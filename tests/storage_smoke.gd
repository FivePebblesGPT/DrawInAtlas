extends SceneTree

## Godot 4.8-beta1: --headless --path . --script res://tests/storage_smoke.gd
## Tests native file roundtrips, exact pixels, backup recovery and injected IO faults.
const SLOT: String = "user://atlas_native_storage_smoke/checkpoint.scn"
const MEMORY_SLOT: String = "user://injected/checkpoint.scn"

class MemoryIO extends AtlasStoreIO:
	var files: Dictionary[String, PackedByteArray] = {}
	var operations: Array[String] = []
	var fail_at: int = -1
	var torn: bool = false
	var deny_directory: bool = false
	var expected_corruption: Array[PackedByteArray] = []

	func decode_scene(bytes: PackedByteArray) -> PackedScene:
		# Silence only deliberately corrupt fixtures, never ordinary load failures.
		var printed_errors: bool = Engine.print_error_messages
		if expected_corruption.has(bytes):
			Engine.print_error_messages = false
		var scene: PackedScene = super.decode_scene(bytes)
		Engine.print_error_messages = printed_errors
		return scene

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
		printerr("NATIVE STORAGE FAILED: " + description)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] in ["write-portable", "read-portable"]:
		_check(_portable_fixture(args[0], args[1]), "fresh-process portable campaign " + args[0])
		print("ATLAS_PORTABILITY_%s" % ["PASSED" if failures == 0 else "FAILED"])
		quit(0 if failures == 0 else 1)
		return
	var default_existed: bool = FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH)
	var default_bytes: PackedByteArray = FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH) if default_existed else PackedByteArray()
	for phase: String in ["_roundtrip", "_recovery", "_format_validation", "_injected_failures", "_invalid"]:
		_check(call(phase) == true, phase + " completes without a runtime error")
	_check(FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH) == default_existed,
		"tests never create the default campaign slot")
	if default_existed:
		_check(FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH) == default_bytes,
			"tests never modify the default campaign slot")
	print("ATLAS_STORAGE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _portable_fixture(mode: String, path: String) -> bool:
	var expected: AtlasCampaign = _campaign(41)
	if mode == "write-portable":
		return AtlasCampaignStore.save_campaign(expected, path) == OK
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(path)
	if result.campaign == null or result.recovered or result.campaign.to_dict() != expected.to_dict():
		return false
	var expected_raster: AtlasRasterLayer = _raster(expected)
	var actual: AtlasRasterLayer = _raster(result.campaign)
	for key: String in expected_raster.chunks:
		if actual.chunks[key].image.get_data() != expected_raster.chunks[key].image.get_data():
			return false
	return true


func _pixels() -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(273 * 269 * 4)
	for pixel: int in range(273 * 269):
		bytes[pixel * 4] = (pixel * 3 + 17) % 256
		bytes[pixel * 4 + 1] = (pixel * 5 + 29) % 256
		bytes[pixel * 4 + 2] = (pixel * 7 + 31) % 256
		bytes[pixel * 4 + 3] = pixel % 256 # Includes hidden, nonzero RGB.
	return Image.create_from_data(273, 269, false, Image.FORMAT_RGBA8, bytes)


func _campaign(seed: int = 0) -> AtlasCampaign:
	var result: AtlasCampaign = AtlasCampaign.sample()
	result.display_name = "Native Generation %d" % seed
	var map: AtlasMapDocument = result.get_map("world")
	map.tags.append("native")
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	upper.display_name = "Upper floor"
	upper.strokes.append(AtlasStroke.new(PackedVector2Array([
		Vector2(-3.125, 0.25), Vector2(17.75, -40.5)]), Color(0.25, 0.5, 0.75, 0.5), 1.2345678901234567))
	map.floors.append(upper)
	map.default_floor_id = upper.id
	var reverse: AtlasMapLink = AtlasMapLink.from_dict(result.links[0].to_dict())
	reverse.id = "cycle"
	reverse.source_map_id = "greyhaven"
	reverse.target_map_id = "world"
	reverse.target_floor_id = upper.id
	result.links.append(reverse)
	var placement: AtlasPlacement = AtlasPlacement.new()
	placement.id = "native-placement"
	placement.parent_map_id = "world"
	placement.child_map_id = "greyhaven"
	placement.origin = Vector2(-53.25, 17.5)
	placement.rotation = 0.12345678901234567
	result.placements.append(placement)
	var extra: AtlasMapLink = AtlasMapLink.from_dict(result.links[0].to_dict())
	extra.id = "second-entrance"
	extra.source_floor_id = upper.id
	extra.placement_id = placement.id
	result.links.append(extra)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(_pixels(), 1.2345678901234567)
	raster.id = "native-raster"
	raster.transform = Transform2D(0.31, Vector2(1.25, 0.75), 0.1, Vector2(-53.5, 29.25))
	var shifted: Dictionary[String, AtlasRasterChunk] = {}
	for chunk: AtlasRasterChunk in raster.chunks.values():
		chunk.coord -= Vector2i(2, 1)
		shifted["%d,%d" % [chunk.coord.x, chunk.coord.y]] = chunk
	raster.chunks = shifted
	map.floors[0].layers.append(raster)
	return result


func _raster(campaign: AtlasCampaign) -> AtlasRasterLayer:
	return campaign.get_map("world").floors[0].layer_by_id("native-raster") as AtlasRasterLayer


func _roundtrip() -> bool:
	var original: AtlasCampaign = _campaign()
	var saved: Error = AtlasCampaignStore.save_campaign(original, SLOT)
	_check(saved == OK, "real native .scn file save: " + error_string(saved))
	if saved != OK:
		return false
	var result: AtlasStoreResult = AtlasCampaignStore.load_result(SLOT)
	_check(result.error == OK and result.campaign != null and not result.recovered,
		"native scene reload: " + result.message)
	if result.campaign == null:
		return false
	_check(original.maps.keys() != result.campaign.maps.keys(), "fixture exercises reordered map registry")
	_check(original.to_dict() == result.campaign.to_dict(),
		"semantic graph and metadata roundtrip independent of map registry order")
	_check(result.campaign.maps.size() == 2 and result.campaign.links.size() == 3
		and result.campaign.placements.size() == 1,
		"independent cyclic map graph and multiple entrances embedded in one file")
	var expected: AtlasRasterLayer = _raster(original)
	var actual: AtlasRasterLayer = _raster(result.campaign)
	_check(actual != null and actual.chunks.size() == 4, "four raster chunks incl. edges")
	if actual != null:
		for key: String in expected.chunks:
			_check(actual.chunks.has(key) and actual.chunks[key].image != null
				and actual.chunks[key].image.get_data() == expected.chunks[key].image.get_data(),
				"exact RGBA8 chunk " + key)
	# A second load must not alias editable domain Resources from the first one.
	var second: AtlasCampaign = AtlasCampaignStore.load_campaign(SLOT)
	_check(second != null and second != result.campaign, "fresh Resource root")
	if second != null:
		second.get_map("world").display_name = "mutated"
		_check(result.campaign.get_map("world").display_name != "mutated",
			"loaded mutable Resources do not alias")
		second.get_map("world").floors[1].strokes[0].width = 99.0
		_check(result.campaign.get_map("world").floors[1].strokes[0].width != 99.0,
			"nested floor/stroke Resources do not alias")
		_raster(second).chunks["-2,-1"].image.set_pixel(0, 0, Color.MAGENTA)
		_check(actual.chunks["-2,-1"].image.get_data() == expected.chunks["-2,-1"].image.get_data(),
			"decoded raster Images do not alias across loads or the source")
	_check(not DirAccess.dir_exists_absolute(SLOT + ".assets") and not FileAccess.file_exists(SLOT.trim_suffix(".scn") + ".webp"),
		"no raster sidecars")
	_check(AtlasCampaignStore.save_campaign(_campaign(1), SLOT) == OK,
		"real filesystem replaces an existing head")
	_check(AtlasCampaignStore.save_campaign(_campaign(2), SLOT) == OK,
		"real filesystem replaces an existing adjacent backup")
	var backup: AtlasCampaign = AtlasCampaignStore.load_campaign(SLOT.trim_suffix(".scn") + ".bak.scn")
	_check(backup != null and backup.display_name == "Native Generation 1",
		"real filesystem retains the previous validated generation")
	for suffix: String in [".scn", ".bak.scn", ".pending.scn", ".bak.pending.scn"]:
		DirAccess.remove_absolute(SLOT.trim_suffix(".scn") + suffix)
	return true


func _recovery() -> bool:
	var io: MemoryIO = MemoryIO.new()
	_check(AtlasCampaignStore.save_campaign(_campaign(1), MEMORY_SLOT, io) == OK, "first generation")
	_check(AtlasCampaignStore.save_campaign(_campaign(2), MEMORY_SLOT, io) == OK, "backup generation")
	var head: PackedByteArray = io.files[MEMORY_SLOT]
	var backup_path: String = MEMORY_SLOT.trim_suffix(".scn") + ".bak.scn"
	_check(io.files.has(backup_path), "adjacent backup exists")
	io.files[MEMORY_SLOT] = head.slice(0, 23)
	io.expected_corruption.append(io.files[MEMORY_SLOT])
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
	_check(loaded.error == OK and loaded.recovered and loaded.campaign.display_name == "Native Generation 1",
		"corrupt head recovers validated backup")
	var previous_backup: PackedByteArray = io.files[backup_path]
	_check(AtlasCampaignStore.save_campaign(_campaign(3), MEMORY_SLOT, io) == OK,
		"saving after corrupt head")
	_check(io.files[backup_path] == previous_backup, "corrupt head cannot replace healthy backup")
	io.files[MEMORY_SLOT] = PackedByteArray([1, 2, 3])
	io.files[backup_path] = PackedByteArray([3, 2, 1])
	io.expected_corruption.append_array([io.files[MEMORY_SLOT], io.files[backup_path]])
	loaded = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
	_check(loaded.campaign == null and loaded.error != OK and loaded.message.contains("backup:"),
		"two invalid generations return actionable error")
	return true


func _format_validation() -> bool:
	var storage: MemoryIO = MemoryIO.new()
	var base: PackedScene = AtlasNativeScene.pack_campaign(_campaign())
	_check(base != null, "native fixture scene can be packed")
	if base == null:
		return false
	for damage: String in ["version", "digest", "external-asset", "raster"]:
		var root: AtlasCampaignSaveRoot = base.instantiate() as AtlasCampaignSaveRoot
		if root == null:
			_check(false, "test fixture scene root type")
			return false
		match damage:
			"version":
				root.native_version = 99
			"digest":
				root.semantic_digest = "invalid-digest"
			"external-asset":
				root.set_meta("sidecar", load("res://img/icon.svg"))
			"raster":
				for child: Node in root.get_children():
					var map_node: AtlasMapSaveNode = child as AtlasMapSaveNode
					if map_node != null and map_node.document.id == "world":
						var raster: AtlasRasterLayer = map_node.document.floors[0].layer_by_id("native-raster") as AtlasRasterLayer
						var chunk: AtlasRasterChunk = raster.chunks.values()[0]
						chunk.encoded_webp = PackedByteArray([1, 2, 3])
		var changed: PackedScene = PackedScene.new()
		_check(changed.pack(root) == OK, "modified native fixture can be packed")
		root.free()
		var bytes: PackedByteArray = storage.encode_scene(changed)
		_check(not bytes.is_empty(), "modified native fixture can be encoded")
		storage.files[MEMORY_SLOT] = bytes
		var restored: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, storage)
		_check(restored.campaign == null, "corrupt native %s rejected" % damage)
	return true


func _injected_failures() -> bool:
	var seed: MemoryIO = MemoryIO.new()
	_check(AtlasCampaignStore.save_campaign(_campaign(0), MEMORY_SLOT, seed) == OK,
		"failure fixture initial checkpoint")
	_check(AtlasCampaignStore.save_campaign(_campaign(1), MEMORY_SLOT, seed) == OK,
		"failure fixture second checkpoint")
	var next: AtlasCampaign = _campaign(2)
	var baseline: MemoryIO = MemoryIO.new()
	baseline.files = seed.files.duplicate(true)
	_check(AtlasCampaignStore.save_campaign(next, MEMORY_SLOT, baseline) == OK,
		"baseline successful operation trace")
	var backup_path: String = MEMORY_SLOT.trim_suffix(".scn") + ".bak.scn"
	for torn: bool in [false, true]:
		for step: int in range(1, baseline.operations.size() + 1):
			var io: MemoryIO = MemoryIO.new()
			io.files = seed.files.duplicate(true)
			io.fail_at = step
			io.torn = torn
			var error: Error = AtlasCampaignStore.save_campaign(next, MEMORY_SLOT, io)
			_check(error != OK, "fault injected %d torn=%s" % [step, torn])
			var restored: AtlasStoreResult = AtlasCampaignStore.load_result(MEMORY_SLOT, io)
			_check(restored.error == OK and restored.campaign != null,
				"fault %d retains a valid generation" % step)
			_check(io.files.has(backup_path), "backup remains after failure")
	return true


func _invalid() -> bool:
	var io: MemoryIO = MemoryIO.new()
	_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).error == ERR_FILE_NOT_FOUND,
		"missing head and backup")
	_check(AtlasCampaignStore.save_campaign(_campaign(), "user://wrong.json", io) == ERR_INVALID_PARAMETER,
		"legacy JSON save extension rejected")
	var invalid: AtlasCampaign = _campaign()
	_raster(invalid).pixels_per_unit = NAN
	_check(AtlasCampaignStore.save_campaign(invalid, MEMORY_SLOT, io) != OK,
		"nonfinite raster settings rejected")
	var denied: MemoryIO = MemoryIO.new()
	denied.deny_directory = true
	_check(AtlasCampaignStore.save_campaign(_campaign(), MEMORY_SLOT, denied) != OK,
		"directory creation failure")
	# A stale staged file is never a load candidate.
	io.files[MEMORY_SLOT.trim_suffix(".scn") + ".pending.scn"] = PackedByteArray([1, 2])
	_check(AtlasCampaignStore.load_result(MEMORY_SLOT, io).campaign == null,
		"stale pending ignored")
	return true
