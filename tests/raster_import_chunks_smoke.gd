extends SceneTree
## T-030: rectangular chunk import, exact RGBA8 bytes, partial edges and ownership.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("RASTER IMPORT FAILED: " + label)


func _source_image(width: int, height: int) -> Image:
	var rgba: PackedByteArray = PackedByteArray()
	rgba.resize(width * height * 4)
	for y: int in range(height):
		for x: int in range(width):
			var offset: int = (y * width + x) * 4
			rgba[offset] = (x * 17 + y * 3) % 256
			rgba[offset + 1] = (x * 5 + y * 11) % 256
			rgba[offset + 2] = (x + y * 19) % 256
			rgba[offset + 3] = 0 if (x + y) % 3 == 0 else 173
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)


func _byte_exact_chunks() -> void:
	var source: Image = _source_image(513, 257)
	var original: PackedByteArray = source.get_data()
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image_chunks(source, 2.5)
	_check(layer != null and layer.chunks.size() == 6, "one chunk per rectangular region")
	if layer == null:
		return
	_check(layer.pixels_per_unit == 2.5 and layer.transform == Transform2D.IDENTITY,
		"scale saved as metadata; no implicit spatial placement")
	for chunk_y: int in range(2):
		for chunk_x: int in range(3):
			var origin: Vector2i = Vector2i(chunk_x, chunk_y) * AtlasRasterChunk.SIZE
			var size: Vector2i = Vector2i(mini(256, 513 - origin.x), mini(256, 257 - origin.y))
			var key: String = "%d,%d" % [chunk_x, chunk_y]
			var chunk: AtlasRasterChunk = layer.chunks.get(key)
			_check(chunk != null, "imported chunk " + key)
			if chunk == null:
				continue
			_check(chunk.coord == Vector2i(chunk_x, chunk_y) and chunk.width == size.x
				and chunk.height == size.y, "correct extent and coordinate " + key)
			_check(chunk.is_valid(true) and chunk.image.get_data() == source.get_region(
				Rect2i(origin, size)).get_data(), "exact region RGBA8 including hidden RGB " + key)
	_check(source.get_data() == original, "import does not mutate source data")
	var first: AtlasRasterChunk = layer.chunks["0,0"]
	var last: AtlasRasterChunk = layer.chunks["2,1"]
	first.image.set_pixel(0, 0, Color.RED)
	_check(source.get_data() == original, "editing a chunk cannot mutate source")
	var last_bytes: PackedByteArray = last.image.get_data()
	source.fill(Color.GREEN)
	_check(last.image.get_data() == last_bytes, "editing source cannot mutate a chunk")
	_check(last.width == 1 and last.height == 1 and last.image.get_format() == Image.FORMAT_RGBA8,
		"bottom-right partial chunk remains a single pixel")
	_check(AtlasRasterLayer.from_image(source, 2.5) != null,
		"legacy from_image entry point remains supported")


func _source_formats_and_invalid_input() -> void:
	var rgb: Image = Image.create_empty(258, 259, true, Image.FORMAT_RGB8)
	rgb.fill(Color(0.25, 0.5, 0.75))
	var src_bytes: PackedByteArray = rgb.get_data()
	var imported: AtlasRasterLayer = AtlasRasterLayer.from_image_chunks(rgb)
	_check(imported != null and imported.chunks.size() == 4, "mipmapped RGB8 import")
	if imported != null:
		for chunk: AtlasRasterChunk in imported.chunks.values():
			_check(chunk.is_valid(true) and not chunk.image.has_mipmaps()
				and chunk.image.get_format() == Image.FORMAT_RGBA8,
				"each input region normalized to no-mipmap RGBA8")
		_check(imported.chunks["1,1"].width == 2 and imported.chunks["1,1"].height == 3,
			"RGB8 partial edge dimensions")
	_check(rgb.get_data() == src_bytes and rgb.has_mipmaps() and rgb.get_format() == Image.FORMAT_RGB8,
		"RGB8 source format and mipmaps unchanged")
	_check(AtlasRasterLayer.from_image_chunks(null) == null, "reject null image")
	_check(AtlasRasterLayer.from_image_chunks(Image.new()) == null, "reject empty image")
	_check(AtlasRasterLayer.from_image_chunks(rgb, 0.0) == null, "reject zero scale")
	_check(AtlasRasterLayer.from_image_chunks(rgb, -1.0) == null, "reject negative scale")
	_check(AtlasRasterLayer.from_image_chunks(rgb, INF) == null, "reject infinite scale")
	_check(AtlasRasterLayer.pixel_to_chunk(Vector2i(-1, -257)) == Vector2i(-1, -2),
		"negative board coordinates use floor-based chunk addressing")


func _native_save() -> void:
	var source: Image = _source_image(257, 3)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image_chunks(source)
	layer.id = "imported"
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var map: AtlasMapDocument = campaign.get_map(campaign.root_map_id)
	map.floors[0].layers.append(layer)
	var scene: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	_check(scene != null, "native pack accepts imported image chunks")
	if scene == null:
		return
	var unpacked: AtlasCampaign = AtlasNativeScene.unpack_campaign(scene)
	_check(unpacked != null, "native scene unpacks imported image")
	if unpacked == null:
		return
	var restored: AtlasRasterLayer = unpacked.get_map(campaign.root_map_id).floors[0].layer_by_id("imported") as AtlasRasterLayer
	_check(restored != null and restored.chunks.size() == 2, "native scene keeps partial chunks")
	if restored == null:
		return
	for key: String in ["0,0", "1,0"]:
		_check(restored.chunks[key].image.get_data() == layer.chunks[key].image.get_data(),
			"native scene exact RGBA8 " + key)
	var original_bytes: PackedByteArray = layer.chunks["1,0"].image.get_data()
	restored.chunks["1,0"].image.fill(Color.BLUE)
	_check(layer.chunks["1,0"].image.get_data() == original_bytes,
		"loaded raster owns independent pixels")


func _run() -> void:
	_byte_exact_chunks()
	_source_formats_and_invalid_input()
	_native_save()
	print("ATLAS_RASTER_IMPORT_CHUNKS_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
