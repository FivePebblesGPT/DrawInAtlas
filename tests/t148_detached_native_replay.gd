extends SceneTree
## T-148: a detached history entry must still update current Rust canonical
## tiles atomically, without fabricating a history token outside this timeline.

const STRIDE: int = 64
const INK: int = 0xff3456ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_DETACHED_FAILED: " + label)


func source(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = document.request_chunk(layer, key)
	if not result.ok or result.value == null:
		return PackedByteArray()
	return (result.value as DrawingRasterTile).to_rgba8()


func stroke(document: DrawingDocument, layer: String, y: float) -> DrawingResult:
	var opened: DrawingResult = document.begin_edit(layer, document.revision)
	if not opened.ok:
		return opened
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var begun: DrawingResult = session.begin_native_stroke(
		brush, "NativeHard", "", 8.0, INK, CLIP, true)
	if not begun.ok:
		return begun
	var painted: DrawingResult = session.paint_path_native(PackedVector2Array([
		Vector2(-20.5, y), Vector2(12.5, y)]), INK, false, null)
	if not painted.ok:
		return painted
	return session.commit()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "real compiled Rust engine available")
	var document: DrawingDocument = DrawingDocument.new("detached-replay", STRIDE)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var seed: PackedByteArray = PackedByteArray()
	seed.resize(STRIDE * STRIDE * 4)
	seed.encode_u32(0, 0x00123456)
	document._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, seed)
	var first: DrawingResult = stroke(document, layer, 10.5)
	check(first.ok and first.delta != null, "first real native brush edit committed")
	if not first.ok:
		quit(1)
		return
	var after_first_negative: PackedByteArray = source(document, layer, "-1,0")
	var after_first_positive: PackedByteArray = source(document, layer, "0,0")
	var second: DrawingResult = stroke(document, layer, 24.5)
	check(second.ok and second.delta != null, "second real native brush edit committed")
	if not second.ok:
		quit(1)
		return
	var after_second_negative: PackedByteArray = source(document, layer, "-1,0")
	var after_second_positive: PackedByteArray = source(document, layer, "0,0")
	var store: Object = document._native_raster_store
	check(int(store.call("stats").get("undo", -1)) == 2, "two native history tokens exist")
	check(document.undo().ok, "second edit replays through live native token")
	check(source(document, layer, "-1,0") == after_first_negative and
		source(document, layer, "0,0") == after_first_positive,
		"first edit restored byte-exactly")
	# Simulate eviction of the older event's Rust token without changing
	# canonical bytes; the host still owns its complete detached snapshots.
	var old: DrawingDelta = document._events[0]["delta"]
	old.native_history_token = 9223372036854000000 # token no longer resident
	var base_revision: int = document.revision
	var bad: Array[Dictionary] = [
		{"tile_x": -1, "tile_y": 0, "expected": PackedByteArray([1, 2]),
			"replacement": old.before_tiles["-1,0"]}]
	var rejected: Dictionary = store.call("replay_detached_history", layer, base_revision, bad)
	check(not bool(rejected.get("ok", false)), "malformed buffer rejected by native replay")
	check(document.revision == base_revision and
		int(store.call("stats").get("revision", -1)) == base_revision,
		"rejected FFI call changes neither revision")
	check(document.undo().ok, "older detached history successfully replays through Rust")
	check(document._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == document.revision,
		"detached Undo retains the same canonical native store and revision")
	check(int(store.call("stats").get("undo", -1)) == 0 and
		int(store.call("stats").get("redo", -1)) == 0,
		"unpaired native tokens retired rather than silently retained")
	check(source(document, layer, "-1,0") == seed and
		source(document, layer, "0,0").is_empty(),
		"detached Undo restored initial hidden RGB and blank positive tile")
	var canonical: Dictionary = store.call("read_tile", layer, -1, 0, false)
	check(bool(canonical.get("ok", false)) and (canonical.get("bytes") as PackedByteArray) == seed,
		"Rust canonical RGBA8 equals Godot's Undo projection")
	check(document.redo().ok and document._native_raster_store == store,
		"detached Redo replays in the same Rust store")
	check(source(document, layer, "-1,0") == after_first_negative and
		source(document, layer, "0,0") == after_first_positive,
		"first Redo restores exact pixels")
	check(document.redo().ok and document._native_raster_store == store,
		"newer invalidated token safely replays as detached bytes")
	check(source(document, layer, "-1,0") == after_second_negative and
		source(document, layer, "0,0") == after_second_positive,
		"final Redo restores second native stroke source")
	check(int(store.call("stats").get("revision", -1)) == document.revision,
		"native revision remains authoritative across all Undo/Redo")
	var third: DrawingResult = stroke(document, layer, 40.5)
	check(third.ok and third.delta != null and third.delta.native_history_token > 0,
		"new real native stroke follows detached history without source reimport")
	check(document._native_raster_store == store and
		int(store.call("stats").get("undo", -1)) == 1,
		"fresh stroke owns a new native history token")
	check(document.undo().ok and document.redo().ok,
		"new native history Undo/Redo is exact")
	if failures == 0:
		print("T148_DETACHED_PASSED checks=%d failures=0" % checks)
	else:
		print("T148_DETACHED_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
