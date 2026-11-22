extends SceneTree
## T-240: reject whole malformed native history/adoption batches before
## copying any full-tile payload or accounting those bytes as transferred.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T240_FFI_PREFLIGHT_FAILED: " + label)


func tile() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STRIDE * STRIDE * 4)
	bytes.encode_u32(0, HIDDEN)
	return bytes


func descriptors(entries: Array) -> Array[Dictionary]:
	var packed: Array[Dictionary] = []
	for entry: Dictionary in entries:
		packed.append(entry)
	return packed


func store() -> Object:
	var owner: Object = ClassDB.instantiate("DrawingNativeTiles")
	check(owner != null and owner.call("configure", STRIDE, 0) and
		owner.call("set_layer_editable", "Ink", true),
		"real native tile store initialized")
	return owner


func same_state(owner: Object, revision: int, undo_count: int, label: String) -> void:
	var stats: Dictionary = owner.call("stats")
	check(int(stats.get("revision", -1)) == revision and
		int(stats.get("undo", -1)) == undo_count and
		int(stats.get("redo", -1)) == 0,
		label + " preserves native revision and history")


func test_adoption(method: String) -> void:
	var owner: Object = store()
	var existing: PackedByteArray = tile()
	var malformed: PackedByteArray = PackedByteArray([1, 2, 3])
	var first: Dictionary = {"tile_x": -1, "tile_y": 0,
		"before": PackedByteArray(), "after": existing}
	var bad: Dictionary = {"tile_x": 1, "tile_y": 0,
		"before": PackedByteArray(), "after": malformed}
	var result: Dictionary = owner.call(method, "Ink", 0, descriptors([first, bad]))
	check(not bool(result.get("ok", false)), method + " rejects later malformed tile")
	same_state(owner, 0, 0, method + " rejected batch")
	check(int(owner.call("stats").get("external_bytes_received", -1)) == 0,
		method + " validates all lengths before copying/accounting earlier tiles")
	check(owner.call("import_source", "Ink", -1, 0, 0, PackedByteArray()),
		method + " imports valid blank source")
	result = owner.call(method, "Ink", 0, descriptors([first]))
	check(bool(result.get("ok", false)) and int(result.get("revision", -1)) == 1,
		method + " accepts valid packed RGBA8 after rejection")
	var native: Dictionary = owner.call("read_tile", "Ink", -1, 0, false)
	check(bool(native.get("ok", false)) and
		(native.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32(0) == HIDDEN,
		method + " preserves alpha-zero hidden RGB")
	check(int(owner.call("stats").get("undo", -1)) == (1 if method == "adopt_external_edit" else 0),
		method + " retains expected recorded/untracked history semantics")


func test_detached() -> void:
	var owner: Object = store()
	var first: Dictionary = {"tile_x": 0, "tile_y": 0,
		"expected": PackedByteArray(), "replacement": tile()}
	var bad: Dictionary = {"tile_x": 1, "tile_y": 0,
		"expected": PackedByteArray([1, 2, 3]), "replacement": PackedByteArray()}
	var rejected: Dictionary = owner.call("replay_detached_history", "Ink", 0, descriptors([first, bad]))
	check(not bool(rejected.get("ok", false)), "detached replay rejects later malformed tile")
	same_state(owner, 0, 0, "detached malformed replay")
	check(int(owner.call("stats").get("external_bytes_received", -1)) == 0,
		"detached replay validates all lengths before copying/accounting earlier tiles")
	check(owner.call("import_source", "Ink", 0, 0, 0, PackedByteArray()),
		"detached replay imports valid blank source")
	var result: Dictionary = owner.call("replay_detached_history", "Ink", 0, descriptors([first]))
	check(bool(result.get("ok", false)) and int(result.get("revision", -1)) == 1,
		"detached replay accepts the same valid tile")
	var native: Dictionary = owner.call("read_tile", "Ink", 0, 0, false)
	check(bool(native.get("ok", false)) and
		(native.get("bytes", PackedByteArray()) as PackedByteArray).decode_u32(0) == HIDDEN,
		"detached replay publishes exact hidden RGB")


func test_tokenized() -> void:
	var owner: Object = store()
	check(owner.call("import_source", "Ink", 0, 0, 0, PackedByteArray()),
		"tokenized history source imported")
	var accepted: Dictionary = owner.call("adopt_external_edit", "Ink", 0,
		descriptors([{"tile_x": 0, "tile_y": 0, "before": PackedByteArray(), "after": tile()}]))
	var token: int = int(accepted.get("history_token", 0))
	check(bool(accepted.get("ok", false)) and token > 0,
		"recorded native transaction returns history token")
	var valid: Dictionary = {"tile_x": 0, "tile_y": 0,
		"expected": tile(), "replacement": PackedByteArray()}
	var malformed: Dictionary = {"tile_x": 1, "tile_y": 0,
		"expected": PackedByteArray([1, 2, 3]), "replacement": PackedByteArray()}
	var refused: Dictionary = owner.call("replay_history_token", token, 1, true,
		"Ink", descriptors([valid, malformed]))
	check(not bool(refused.get("ok", false)) and
		str(refused.get("error", "")).contains("descriptor"),
		"tokenized replay rejects malformed batch before comparing history snapshots")
	same_state(owner, 1, 1, "tokenized malformed replay")
	check(bool(owner.call("has_history_token", token, 1, true)),
		"malformed token replay leaves Undo event available")
	var undone: Dictionary = owner.call("replay_history_token", token, 1, true, "Ink", descriptors([valid]))
	check(bool(undone.get("ok", false)) and int(undone.get("revision", -1)) == 2,
		"valid token Undo succeeds after rejected request")
	var redone: Dictionary = owner.call("replay_history_token", token, 2, false,
		"Ink", descriptors([{"tile_x": 0, "tile_y": 0,
		"expected": PackedByteArray(), "replacement": tile()}]))
	check(bool(redone.get("ok", false)) and int(redone.get("revision", -1)) == 3,
		"valid token Redo preserves native history lifecycle")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension loaded")
	test_adoption("adopt_external_edit")
	test_adoption("adopt_untracked_edit")
	test_detached()
	test_tokenized()
	if failures == 0:
		print("T240_FFI_PREFLIGHT_PASSED checks=%d failures=0" % checks)
	else:
		print("T240_FFI_PREFLIGHT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
