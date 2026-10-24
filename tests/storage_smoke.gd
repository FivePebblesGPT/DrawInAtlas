extends SceneTree

## Run with Godot 4.8: --headless --path . --script res://tests/storage_smoke.gd
const SLOT: String = "user://atlas_storage_smoke/checkpoint.json"
const MEMORY_SLOT: String = "user://injected/checkpoint.json"

class MemoryIO extends AtlasStoreIO:
	var files: Dictionary[String, PackedByteArray] = {}
	var operations: Array[String] = []
	var fail_at: int = -1
	var torn: bool = false
	var deny_directory: bool = false

	func exists(path: String) -> bool:
		return files.has(path)

	func read_bytes(path: String) -> PackedByteArray:
		return files.get(path, PackedByteArray())

	func write_bytes(path: String, bytes: PackedByteArray) -> Error:
		operations.append("write " + path)
		if operations.size() == fail_at:
			if torn:
				files[path] = bytes.slice(0, bytes.size() / 2)
				return OK
			return ERR_FILE_CANT_WRITE
		files[path] = bytes.duplicate()
		return OK

	func rename(from_path: String, to_path: String) -> Error:
		operations.append("rename " + to_path)
		if operations.size() == fail_at:
			return ERR_FILE_CANT_WRITE
		if not files.has(from_path):
			return ERR_FILE_NOT_FOUND
		files[to_path] = files[from_path]
		files.erase(from_path)
		return OK

	func make_dir(_path: String) -> Error:
		return ERR_CANT_CREATE if deny_directory else OK


var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("STORAGE FAILED: " + description)


func _run() -> void:
	var default_before: PackedByteArray = FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH) \
		if FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH) else PackedByteArray()
	var default_existed: bool = FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH)
	_codec()
	_roundtrip()
	_failures()
	_recovery()
	_invalid()
	_check(FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH) == default_existed,
		"suite does not create the default slot")
	if default_existed:
		_check(FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH) == default_before,
			"suite does not modify the default slot")
	print("ATLAS_STORAGE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _pixels(width: int, height: int, seed: int = 0, hidden_rgb: bool = false) -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(width * height * 4)
	for index: int in range(width * height):
		var alpha: int = (index + seed) % 256
		for channel: int in range(3):
			bytes[index * 4 + channel] = ((index * (channel + 3) + seed + 17) % 256) \
				if alpha != 0 or hidden_rgb else 0
		bytes[index * 4 + 3] = alpha
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)


func _campaign(seed: int = 0) -> AtlasCampaign:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = "Generation %d" % seed
	var map: AtlasMapDocument = AtlasMapDocument.new("world", "Storage")
	campaign.add_map(map)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(_pixels(273, 269, seed), 1.2345678901234567)
	# Shift the multichunk image across zero while retaining edge dimensions.
	var moved: Dictionary[String, AtlasRasterChunk] = {}
	for chunk: AtlasRasterChunk in layer.chunks.values():
		chunk.coord -= Vector2i(2, 1)
		moved["%d,%d" % [chunk.coord.x, chunk.coord.y]] = chunk
	layer.chunks = moved
	map.floors[0].layers.append(layer)
	return campaign


func _raster(campaign: AtlasCampaign) -> AtlasRasterLayer:
	for layer: AtlasLayer in campaign.get_map("world").floors[0].layers:
		if layer is AtlasRasterLayer:
			return layer as AtlasRasterLayer
	return null


func _codec() -> void:
	for hidden: bool in [false, true]:
		var image: Image = _pixels(41, 37, 13, hidden)
		var bytes: PackedByteArray = AtlasWebPStore.encode_lossless(image)
		_check(not bytes.is_empty(), "codec preserves varied RGBA, hidden RGB=%s" % hidden)
		if not bytes.is_empty():
			var decoded: Image = AtlasWebPStore.decode(bytes)
			_check(decoded != null and decoded.get_format() == Image.FORMAT_RGBA8
				and decoded.get_data() == image.get_data(), "exact canonical pixel roundtrip")
			_check(AtlasWebPStore.decode_lossless(bytes, 40, 37) == null,
				"canonical decode rejects incorrect dimensions")
	var lossy: PackedByteArray = _pixels(41, 37).save_webp_to_buffer(true)
	_check(AtlasWebPStore.decode_lossless(lossy, 41, 37) == null, "canonical decode rejects lossy WebP")


func _roundtrip() -> void:
	var campaign: AtlasCampaign = _campaign()
	var saved: Error = AtlasCampaignStore.save_campaign(campaign, SLOT)
	_check(saved == OK, "real filesystem multichunk save: " + error_string(saved))
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(SLOT)
	_check(result.error == OK and result.campaign != null and not result.recovered, "real filesystem load: " + result.message)
	if result.campaign != null:
		_check(JSON.stringify(result.campaign.to_dict(), "", true, true)
			== JSON.stringify(campaign.to_dict(), "", true, true), "full precision metadata roundtrip")
		var restored: AtlasRasterLayer = _raster(result.campaign)
		var original: AtlasRasterLayer = _raster(campaign)
		_check(restored.chunks.size() == 4, "four chunks including partial edges")
		for key: String in original.chunks:
			_check(restored.chunks.has(key) and restored.chunks[key].image != null
				and restored.chunks[key].image.get_data() == original.chunks[key].image.get_data(),
				"negative-coordinate chunk pixels: " + key)
	var io: MemoryIO = MemoryIO.new()
	saved = AtlasCampaignStore.save_campaign(campaign, MEMORY_SLOT, io)
	_check(saved == OK, "injectable first save: " + error_string(saved))
	if saved != OK:
		return
	io.operations.clear()
	_check(AtlasCampaignStore.save_campaign(campaign, MEMORY_SLOT, io) == OK, "unchanged save")
	for operation: String in io.operations:
		_check(not operation.contains(".assets/"), "unchanged asset is reused without writes or renames")


func _failures() -> void:
	var seed_io: MemoryIO = MemoryIO.new()
	var old: AtlasCampaign = _campaign(1)
	var next: AtlasCampaign = _campaign(2)
	_check(AtlasCampaignStore.save_campaign(_campaign(), MEMORY_SLOT, seed_io) == OK, "older backup fixture")
	var saved: Error = AtlasCampaignStore.save_campaign(old, MEMORY_SLOT, seed_io)
	_check(saved == OK, "failure fixture: " + error_string(saved))
	if saved != OK:
		return
	var baseline: MemoryIO = MemoryIO.new()
	baseline.files = seed_io.files.duplicate(true)
	_check(AtlasCampaignStore.save_campaign(next, MEMORY_SLOT, baseline) == OK, "successful operation trace")
	for torn: bool in [false, true]:
		for step: int in range(1, baseline.operations.size() + 1):
			var io: MemoryIO = MemoryIO.new()
			io.files = seed_io.files.duplicate(true)
			io.fail_at = step
			io.torn = torn
			var error: Error = AtlasCampaignStore.save_campaign(next, MEMORY_SLOT, io)
			_check(error != OK, "failure detected at %d, torn=%s" % [step, torn])
			_check(io.files[MEMORY_SLOT] == seed_io.files[MEMORY_SLOT], "failed save preserves head bytes")
			var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
			_check(loaded.error == OK and loaded.campaign.display_name == old.display_name,
				"failed save retains usable previous generation")
	var denied: MemoryIO = MemoryIO.new()
	denied.files = seed_io.files.duplicate(true)
	denied.deny_directory = true
	_check(AtlasCampaignStore.save_campaign(next, MEMORY_SLOT, denied) != OK
		and denied.files[MEMORY_SLOT] == seed_io.files[MEMORY_SLOT], "directory failure preserves head")


func _recovery() -> void:
	var io: MemoryIO = MemoryIO.new()
	_check(AtlasCampaignStore.save_campaign(_campaign(1), MEMORY_SLOT, io) == OK, "recovery old generation")
	_check(AtlasCampaignStore.save_campaign(_campaign(2), MEMORY_SLOT, io) == OK, "recovery new generation")
	if not io.files.has(MEMORY_SLOT):
		return
	var good_files: Dictionary[String, PackedByteArray] = io.files.duplicate(true)
	var asset: String = MEMORY_SLOT + ".assets/" + _raster(_campaign(2)).chunks.values()[0].asset_id + ".webp"
	for damage: String in ["head", "missing", "chunk", "truncated", "backup"]:
		io.files = good_files.duplicate(true)
		if damage == "head":
			var changed: Dictionary = JSON.parse_string(io.files[MEMORY_SLOT].get_string_from_utf8())
			changed["name"] = "undetected without checksum"
			io.files[MEMORY_SLOT] = JSON.stringify(changed, "", true, true).to_utf8_buffer()
		elif damage == "missing":
			io.files.erase(asset)
		elif damage == "chunk":
			io.files[asset] = AtlasWebPStore.encode_lossless(_pixels(256, 256, 77))
		elif damage == "truncated":
			io.files[asset] = io.files[asset].slice(0, 23)
		else:
			io.files[MEMORY_SLOT + ".bak"] = "broken".to_utf8_buffer()
		var result: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
		_check(result.error == OK and result.campaign != null, "usable generation after " + damage)
		_check(result.recovered == (damage != "backup"), "recovery flag after " + damage)
		if damage != "backup":
			_check(result.source_path == MEMORY_SLOT + ".bak" and not result.message.is_empty()
				and result.campaign.display_name == "Generation 1", "recovery provenance and diagnostic")
	io.files = good_files.duplicate(true)
	io.files[MEMORY_SLOT] = "broken".to_utf8_buffer()
	var backup_before: PackedByteArray = io.files[MEMORY_SLOT + ".bak"]
	_check(AtlasCampaignStore.save_campaign(_campaign(3), MEMORY_SLOT, io) == OK
		and io.files[MEMORY_SLOT + ".bak"] == backup_before, "save preserves valid backup of corrupt head")
	io.files[MEMORY_SLOT] = "broken".to_utf8_buffer()
	io.files[MEMORY_SLOT + ".bak"] = "broken".to_utf8_buffer()
	var invalid: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
	_check(invalid.campaign == null and invalid.error != OK and invalid.message.contains("backup:"),
		"both invalid produce structured diagnostic")
	io.files = good_files.duplicate(true)
	io.files[MEMORY_SLOT] = "broken".to_utf8_buffer()
	io.fail_at = io.operations.size() + 1
	_check(AtlasCampaignStore.save_campaign(_campaign(3), MEMORY_SLOT, io) != OK
		and AtlasCampaignStore.load_result(MEMORY_SLOT, io).recovered,
		"failed save over corrupt head retains usable backup")


func _invalid() -> void:
	var io: MemoryIO = MemoryIO.new()
	_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).error == ERR_FILE_NOT_FOUND, "missing slot")
	for raw: String in ["{", "[]", "null", '{"schema_version":99}', '{"schema_version":4}']:
		io.files[MEMORY_SLOT] = raw.to_utf8_buffer()
		var result: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
		_check(result.campaign == null and result.error != OK and not result.message.is_empty(),
			"malformed or unknown schema: " + raw)
	var saved: Error = AtlasCampaignStore.save_campaign(_campaign(), MEMORY_SLOT, io)
	_check(saved == OK, "invalid-save fixture: " + error_string(saved))
	if saved != OK:
		return
	var before: PackedByteArray = io.files[MEMORY_SLOT]
	var unloaded: AtlasCampaign = AtlasCampaign.from_dict(_campaign().to_dict())
	_check(AtlasCampaignStore.save_campaign(unloaded, "user://missing/chunks.json", io) != OK
		and not io.exists("user://missing/chunks.json"), "missing source assets prevent a save")
	_check(AtlasCampaignStore.save_campaign(unloaded, MEMORY_SLOT, io) == OK,
		"metadata-only candidate verifies existing chunks")
	before = io.files[MEMORY_SLOT]
	var campaign: AtlasCampaign = _campaign()
	_raster(campaign).pixels_per_unit = NAN
	_check(AtlasCampaignStore.save_campaign(campaign, MEMORY_SLOT, io) != OK
		and io.files[MEMORY_SLOT] == before, "invalid candidate cannot replace head")
	io.files.erase(MEMORY_SLOT)
	io.files.erase(MEMORY_SLOT + ".bak")
	io.files[MEMORY_SLOT + ".pending"] = before
	_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).campaign == null, "pending generation is ignored")
	io.files.clear()
	for version: int in [1, 2, 3]:
		var legacy: Dictionary = {"schema_version": version, "root_map_id": "world", "maps": [
			{"id": "world", "name": "Legacy", "grid": {}, "floors": [
				{"id": "ground", "name": "Ground", "terrain": {"-1,2": 3}}]}]}
		io.files[MEMORY_SLOT] = JSON.stringify(legacy).to_utf8_buffer()
		_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).error == OK,
			"legacy schema %d loads without checkpoint" % version)
		legacy["_checkpoint"] = null
		io.files[MEMORY_SLOT] = JSON.stringify(legacy).to_utf8_buffer()
		_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).campaign == null,
			"present but malformed legacy checkpoint is rejected")
