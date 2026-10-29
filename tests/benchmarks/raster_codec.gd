extends SceneTree

## Run each fixture/codec/compression combination in a fresh process. See results doc.
## --script res://tests/benchmarks/raster_codec.gd -- sparse image compressed
const Payload = preload("res://tests/benchmarks/raster_payload.gd")
const DIRECTORY: String = "user://atlas_codec_benchmark"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _benchmark():
		printerr("ATLAS_CODEC_BENCHMARK_FAILED")
		quit(1)
	else:
		quit(0)


func _benchmark() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3:
		return false
	var fixture: String = args[0]
	var codec: String = args[1]
	var compressed: bool = args[2] == "compressed"
	var campaign: AtlasCampaign = _fixture(fixture)
	if campaign == null or DirAccess.make_dir_recursive_absolute(DIRECTORY) != OK:
		return false
	if codec == "store":
		return _store_benchmark(campaign, fixture)
	var path: String = DIRECTORY.path_join("%s-%s-%s.scn" % [fixture, codec, args[2]])
	var initial_memory: int = OS.get_static_memory_usage()
	var expected: Dictionary = campaign.to_dict()
	var start: int = Time.get_ticks_usec()
	var root_node := AtlasCampaignSaveRoot.new()
	root_node.campaign = campaign
	var payloads: Array[Resource] = []
	var raw_bytes: int = 0
	for map: AtlasMapDocument in campaign.maps.values():
		var map_node := AtlasMapSaveNode.new()
		map_node.document = map
		root_node.add_child(map_node, true)
		map_node.owner = root_node
		for floor: AtlasFloor in map.floors:
			for layer: AtlasLayer in floor.layers:
				if layer is AtlasRasterLayer:
					for chunk: AtlasRasterChunk in layer.chunks.values():
						var payload: Resource = Payload.new()
						if not payload.encode(chunk, codec):
							root_node.free()
							return false
						raw_bytes += chunk.width * chunk.height * 4
						payloads.append(payload)
	# The same actual domain graph is embedded in every controlled container.
	# Only raster payload storage differs; these are not production save files.
	root_node.set_meta("raster_payloads", payloads)
	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root_node)
	root_node.free()
	var flags: int = ResourceSaver.FLAG_COMPRESS if compressed else 0
	if pack_error != OK or ResourceSaver.save(packed, path, flags) != OK:
		return false
	var save_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var file_bytes: int = file.get_length()
	file.close()
	packed = null
	payloads.clear()
	var encoded_memory: int = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	var first: Node = _load_verified(path, codec, expected)
	var load_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	var loaded_memory: int = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	var second: Node = _load_verified(path, codec, expected)
	var second_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	if first == null or second == null:
		return false
	var first_payloads: Array = first.get_meta("raster_payloads")
	var second_payloads: Array = second.get_meta("raster_payloads")
	if not first_payloads.is_empty():
		if first_payloads[0] == second_payloads[0]:
			return false
		var pixels: Image = first_payloads[0].get_meta("decoded")
		var other_pixels: Image = second_payloads[0].get_meta("decoded")
		var untouched: PackedByteArray = other_pixels.get_data()
		pixels.set_pixel(0, 0, Color.MAGENTA)
		if other_pixels.get_data() != untouched:
			return false
	print("ATLAS_CODEC_RESULT " + JSON.stringify({
		"fixture": fixture, "codec": codec, "compressed": compressed,
		"bytes": file_bytes, "raw_bytes": raw_bytes, "chunks": first_payloads.size(),
		"save_ms": save_ms, "load_ms": load_ms, "second_load_ms": second_ms,
		"fixture_memory": initial_memory, "encoded_memory": encoded_memory,
		"loaded_memory": loaded_memory, "peak_static": OS.get_static_memory_peak_usage(),
		"exact": true, "isolated": true, "engine": Engine.get_version_info().string
	}))
	first.free()
	second.free()
	DirAccess.remove_absolute(path)
	return true


func _store_benchmark(campaign: AtlasCampaign, fixture: String) -> bool:
	var path: String = DIRECTORY.path_join(fixture + "-store.scn")
	for suffix: String in [".scn", ".bak.scn", ".pending.scn", ".bak.pending.scn"]:
		DirAccess.remove_absolute(path.trim_suffix(".scn") + suffix)
	var start: int = Time.get_ticks_usec()
	if AtlasCampaignStore.save_campaign(campaign, path) != OK:
		return false
	var save_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	if AtlasCampaignStore.save_campaign(campaign, path) != OK:
		return false
	var overwrite_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var first: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
	var load_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var second: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
	var second_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	if first == null or second == null or first == second or first.to_dict() != campaign.to_dict() \
			or second.to_dict() != campaign.to_dict():
		return false
	var working_memory: int = OS.get_static_memory_usage()
	var peak_memory: int = OS.get_static_memory_peak_usage()
	var legacy_assets: Dictionary[String, int] = {}
	for map: AtlasMapDocument in campaign.maps.values():
		for floor: AtlasFloor in map.floors:
			for layer: AtlasLayer in floor.layers:
				if layer is AtlasRasterLayer:
					for key: String in layer.chunks:
						var chunk: AtlasRasterChunk = layer.chunks[key]
						var loaded: AtlasRasterLayer = first.get_map(map.id).floor_by_id(floor.id).layer_by_id(layer.id) as AtlasRasterLayer
						if loaded == null or loaded.chunks[key].image.get_data() != chunk.image.get_data():
							return false
						legacy_assets[chunk.asset_id] = AtlasWebPStore.encode_lossless(chunk.image).size()
	# Historical JSON+unique-WebP primary size for context, not a timing baseline.
	var legacy: Dictionary = campaign.to_dict()
	var normalized: Variant = JSON.parse_string(JSON.stringify(legacy, "", true, true))
	legacy["_checkpoint"] = {"sha256": JSON.stringify(normalized, "", true, true).sha256_text()}
	normalized = JSON.parse_string(JSON.stringify(legacy, "", true, true))
	var legacy_bytes: int = JSON.stringify(normalized, "", true, true).to_utf8_buffer().size()
	for asset_bytes: int in legacy_assets.values():
		legacy_bytes += asset_bytes
	print("ATLAS_STORE_RESULT " + JSON.stringify({
		"fixture": fixture, "bytes": FileAccess.get_file_as_bytes(path).size(),
		"legacy_primary_bytes": legacy_bytes, "save_ms": save_ms, "overwrite_ms": overwrite_ms,
		"load_ms": load_ms, "second_load_ms": second_ms,
		"working_static": working_memory, "peak_static": peak_memory,
		"exact": true, "engine": Engine.get_version_info().string
	}))
	for suffix: String in [".scn", ".bak.scn", ".pending.scn", ".bak.pending.scn"]:
		DirAccess.remove_absolute(path.trim_suffix(".scn") + suffix)
	return true


func _load_verified(path: String, codec: String, expected: Dictionary) -> Node:
	var packed: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return null
	var instance: AtlasCampaignSaveRoot = packed.instantiate() as AtlasCampaignSaveRoot
	if instance == null:
		return null
	instance.campaign.maps.clear()
	for child: Node in instance.get_children():
		instance.campaign.add_map((child as AtlasMapSaveNode).document)
	if instance.campaign.to_dict() != expected:
		instance.free()
		return null
	for payload: Resource in instance.get_meta("raster_payloads"):
		var pixels: Image = payload.decode(codec)
		if pixels == null or pixels.get_width() != payload.width or pixels.get_height() != payload.height \
				or AtlasRasterChunk.image_hash(pixels) != payload.pixel_hash:
			instance.free()
			return null
		# Retain decoded working images, matching the editor's actual working set.
		payload.set_meta("decoded", pixels)
	return instance


func _fixture(kind: String) -> AtlasCampaign:
	var campaign := AtlasCampaign.new()
	campaign.root_map_id = "map-0"
	var map_count: int = 4 if kind == "multi" else 1
	for index: int in range(map_count):
		var map := AtlasMapDocument.new("map-%d" % index, "Benchmark %d" % index)
		campaign.add_map(map)
		var floors: int = 2 if kind == "multi" else 1
		for floor_index: int in range(floors):
			var floor: AtlasFloor = map.floors[0] if floor_index == 0 else AtlasFloor.new()
			if floor_index > 0:
				floor.id = "upper"
				map.floors.append(floor)
			var ink_layers: int = 32 if kind == "ink" else 1
			for layer_index: int in range(ink_layers):
				var ink: AtlasInkLayer = floor.ink_layer() if layer_index == 0 else AtlasInkLayer.new("ink-%d" % layer_index)
				if layer_index > 0:
					floor.layers.append(ink)
				var stroke_count: int = 64 if kind == "ink" else 40
				for stroke_index: int in range(stroke_count):
					ink.strokes.append(AtlasStroke.new(PackedVector2Array([
						Vector2(stroke_index, -stroke_index), Vector2(stroke_index + 0.25, 15.5)])))
			if kind == "ink":
				continue
			var size := Vector2i(769, 513) if kind == "multi" else Vector2i(273, 269)
			if kind == "detail":
				size = Vector2i(2049, 1537)
			var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(_pixels(size, kind, index + floor_index))
			layer.transform = Transform2D(0.31, Vector2(1.25, 0.75), 0.1, Vector2(-53.5, 29.25))
			var chunks: Dictionary[String, AtlasRasterChunk] = {}
			for chunk: AtlasRasterChunk in layer.chunks.values():
				chunk.coord -= Vector2i(2, 1)
				chunk.stored_asset_id = chunk.asset_id
				chunks["%d,%d" % [chunk.coord.x, chunk.coord.y]] = chunk
			layer.chunks = chunks
			floor.layers.append(layer)
	return campaign


func _pixels(size: Vector2i, kind: String, seed_value: int) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	var random := RandomNumberGenerator.new()
	random.seed = 1951 + seed_value
	for index: int in range(size.x * size.y):
		var x: int = index % size.x
		var y: int = index / size.x
		var noise: int = random.randi() & 31
		bytes[index * 4] = (x / 8 + noise) % 256
		bytes[index * 4 + 1] = (y / 8 + noise * 2) % 256
		bytes[index * 4 + 2] = (x / 32 + y / 32 + noise) % 256
		# Include RGB in transparent pixels and all possible alpha values.
		bytes[index * 4 + 3] = 255 if index % 19 != 0 else index % 256
		if kind == "sparse" and x % 32 > 2 and y % 32 > 2:
			bytes[index * 4 + 3] = 0
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
