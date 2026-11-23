extends SceneTree
## Native history must reject a too-large tile envelope before copying buffers
## or invoking lazy sources, and retain exact RGBA8 for small detached replay.

var checks: int = 0
var failures: int = 0
var lazy_calls: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T229_BUDGET_FAILED: " + label)


func fetch_lazy(_reference: String) -> PackedByteArray:
	lazy_calls += 1
	return PackedByteArray()


func tile_bytes(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = document.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real Rust tile store available")
	var wide: DrawingDocument = DrawingDocument.new("wide-budget", 2048)
	var layer: String = str(wide.create_layer(DrawingLayerNode.RASTER, "Wide").value)
	var before: Dictionary[String, PackedByteArray] = {}
	var after: Dictionary[String, PackedByteArray] = {}
	for index: int in range(6):
		var key: String = "%d,0" % index
		before[key] = PackedByteArray()
		after[key] = PackedByteArray()
	check(wide.register_lazy_chunk(layer, 0, 0, "wide-blob", "0".repeat(64),
		Callable(self, "fetch_lazy")).ok, "one wide tile remains pending before preflight")
	var oversize: DrawingDelta = DrawingDelta.from_owned_tile_bytes(layer, 2048, before, after)
	var revision: int = wide.revision
	var rejected: DrawingResult = wide.replay_delta(oversize, false)
	check(not rejected.ok and rejected.code == "HISTORY_TARGET",
		"over-budget detached envelope rejected at document boundary")
	check(wide.revision == revision and wide._native_raster_store == null and
		wide._nodes[layer].tiles.is_empty(),
		"early document rejection changes neither revision, pixels nor native attachment")
	check(lazy_calls == 0 and wide._pending_tiles.has(layer + ":0,0"),
		"budget rejection does not call a lazy provider or consume its reference")
	check(wide._display_changes.is_empty() or
		wide._display_changes.back().get("revision", -1) <= revision,
		"rejected history does not publish a new display revision")

	var native: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(native.call("configure", 2048, 5), "native 2048px tile storage configured")
	var descriptors: Array[Dictionary] = []
	for index: int in range(6):
		descriptors.append({"tile_x": index, "tile_y": 0,
			"expected": PackedByteArray(), "replacement": PackedByteArray()})
	check(native.call("set_layer_editable", "Wide", true), "native layer editable")
	var native_rejected: Dictionary = native.call("replay_detached_history", "Wide", 5, descriptors)
	check(not bool(native_rejected.get("ok", false)) and
		str(native_rejected.get("error", "")).contains("budget"),
		"native detached-history entry rejects budget before byte conversion")
	native_rejected = native.call("replay_history_token", 100, 5, true, "Wide", descriptors)
	check(not bool(native_rejected.get("ok", false)) and
		str(native_rejected.get("error", "")).contains("budget"),
		"native tokenized history entry rejects oversized envelope")
	check(int(native.call("stats").get("revision", -1)) == 5 and
		int(native.call("stats").get("undo", -1)) == 0 and
		int(native.call("stats").get("redo", -1)) == 0,
		"both native refusals preserve revision and history")

	var small: DrawingDocument = DrawingDocument.new("small-budget", 64)
	var small_layer: String = str(small.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var hidden: PackedByteArray = PackedByteArray()
	hidden.resize(64 * 64 * 4)
	hidden.encode_u32(0, 0x00335577)
	small._nodes[small_layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(64, hidden)
	var painted: PackedByteArray = hidden.duplicate()
	painted.encode_u32(4, 0xff3456ab)
	var next_tile: PackedByteArray = PackedByteArray()
	next_tile.resize(64 * 64 * 4)
	next_tile.encode_u32(0, 0x00abc123)
	var normal: DrawingDelta = DrawingDelta.from_owned_tile_bytes(small_layer, 64,
		{"-1,0": hidden, "0,0": PackedByteArray()},
		{"-1,0": painted, "0,0": next_tile})
	var accepted: DrawingResult = small.replay_delta(normal, false)
	check(accepted.ok and small._native_raster_store != null,
		"bounded detached replay bootstraps real Rust authority")
	check(tile_bytes(small, small_layer, "-1,0") == painted and
		tile_bytes(small, small_layer, "0,0") == next_tile,
		"bounded replay preserves exact visible and alpha-zero hidden RGB")
	if accepted.ok:
		var store: Object = small._native_raster_store
		var backing: Dictionary = store.call("read_tile", small_layer, -1, 0, false)
		check(bool(backing.get("ok", false)) and backing.get("bytes") == painted,
			"Rust canonical RGBA8 matches the detached replacement")
		var undone: DrawingResult = small.replay_delta(normal, true)
		check(undone.ok and small._native_raster_store == store and
			tile_bytes(small, small_layer, "-1,0") == hidden and
			tile_bytes(small, small_layer, "0,0").is_empty(),
			"detached Undo restores bytes without rebasing the Rust store")
		check(small.replay_delta(normal, false).ok and
			tile_bytes(small, small_layer, "0,0") == next_tile,
			"detached Redo reuses the native source and hidden RGB")
		var path: String = ProjectSettings.globalize_path("user://t229-" +
			DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(small, path).ok, "native-authorized result saved")
		var loaded: DrawingResult = DrawingFileIO.open(path)
		check(loaded.ok and loaded.value != null and
			tile_bytes(loaded.value, small_layer, "-1,0") == painted and
			tile_bytes(loaded.value, small_layer, "0,0") == next_tile,
			"Save/Open preserves both signed and alpha-zero canonical tiles")
		DirAccess.remove_absolute(path)

	if failures == 0:
		print("T229_HISTORY_BUDGET_PASSED checks=%d failures=0" % checks)
	else:
		print("T229_HISTORY_BUDGET_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
