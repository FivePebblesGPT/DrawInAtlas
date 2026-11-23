extends SceneTree
## T-292: a legal fill at the view-relative edge must not examine or
## materialize its adjacent, unpublishable lazy-source pixels.

const LIMIT: int = 1073741824
const SOURCE: int = 0x00223344
const PAINT: int = 0xffaabbcc

var checks: int = 0
var failures: int = 0
var fetches: int = 0
var blobs: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T292_FRONTIER_FAILED: " + label)


func _blob(local: Vector2i, outside: Vector2i = Vector2i(-1, -1)) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	for point: Vector2i in [local, outside]:
		if point.x < 0:
			continue
		var offset: int = (point.y * 16 + point.x) * 4
		bytes[offset] = 0x44
		bytes[offset + 1] = 0x33
		bytes[offset + 2] = 0x22
	return bytes


func _fetch(name: String) -> Variant:
	fetches += 1
	return blobs.get(name)


func _scenario(label: String, seed: Vector2i, outside: Vector2i) -> void:
	fetches = 0
	blobs.clear()
	var document: DrawingDocument = DrawingDocument.new("frontier-" + label, 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var start_tile: Vector2i = DrawingDocument.TILES.tile_for_pixel(seed, 16)
	var edge_tile: Vector2i = DrawingDocument.TILES.tile_for_pixel(outside, 16)
	var local: Vector2i = DrawingDocument.TILES.offset_in_tile(seed, 16)
	var outside_local: Vector2i = DrawingDocument.TILES.offset_in_tile(outside, 16)
	var same_tile: bool = start_tile == edge_tile
	var source_bytes: PackedByteArray = _blob(local, outside_local if same_tile else Vector2i(-1, -1))
	blobs["source"] = source_bytes
	_check(document.register_lazy_chunk(layer, start_tile.x, start_tile.y, "source",
		DrawingRasterTile.digest_rgba8(source_bytes, 16),
		Callable(self, "_fetch")).ok, label + ": register lazy boundary source")
	if not same_tile:
		var invalid_bytes: PackedByteArray = _blob(outside_local)
		blobs["invalid"] = invalid_bytes
		_check(document.register_lazy_chunk(layer, edge_tile.x, edge_tile.y, "invalid",
			DrawingRasterTile.digest_rgba8(invalid_bytes, 16),
			Callable(self, "_fetch")).ok,
			label + ": register forbidden neighbor as lazy tile")
	var revision: int = document.revision
	var begun: DrawingResult = document.begin_edit(layer, revision)
	_check(begun.ok, label + ": begin native-backed edit")
	if not begun.ok:
		return
	var session: DrawingEditSession = begun.value as DrawingEditSession
	var filled: DrawingResult = session.flood_fill(seed, PAINT, null, 16)
	_check(filled.ok, label + ": edge seed fills without illegal neighbor error: " + filled.code)
	var source_fence: bool = fetches == 1
	if not same_tile:
		source_fence = source_fence and not session._source_tiles.has(
			"%d,%d" % [edge_tile.x, edge_tile.y])
	_check(source_fence, label + ": forbidden neighbor never invokes lazy source loader")
	_check(session.change_count() == 1 and document.revision == revision,
		label + ": exactly one valid pixel staged; not yet published")
	if not filled.ok:
		session.cancel()
		return
	_check(session.commit().ok and document.revision == revision + 1,
		label + ": commit legal pixel")
	_check(int(document.read_pixel(layer, seed.x, seed.y).value) == PAINT,
		label + ": committed pixel matches exact RGBA8")
	_check(document.undo().ok and int(document.read_pixel(layer, seed.x, seed.y).value) == SOURCE,
		label + ": native Undo restores transparent hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, seed.x, seed.y).value) == PAINT,
		label + ": native Redo replays exact RGBA8")


func _run() -> void:
	_scenario("positive-x", Vector2i(LIMIT - 1, 8), Vector2i(LIMIT, 8))
	_scenario("negative-x", Vector2i(-LIMIT + 1, 8), Vector2i(-LIMIT, 8))
	_scenario("positive-y", Vector2i(8, LIMIT - 1), Vector2i(8, LIMIT))
	_scenario("negative-y", Vector2i(8, -LIMIT + 1), Vector2i(8, -LIMIT))
	print("T292_FRONTIER_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
