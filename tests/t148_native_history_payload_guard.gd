extends SceneTree
## T-148: a caller's detached full-tile history payload must agree with
## Rust's tokenized event before Undo/Redo can consume a native token.

const STRIDE: int = 64
const INK: int = 0xff3456ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_HISTORY_PAYLOAD_FAILED: " + label)


func source(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var result: DrawingResult = document.request_chunk(layer, key)
	if not result.ok or result.value == null:
		return PackedByteArray()
	return (result.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real compiled Rust engine is available")
	var document: DrawingDocument = DrawingDocument.new("native-history-payload", STRIDE)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var seed: PackedByteArray = PackedByteArray()
	seed.resize(STRIDE * STRIDE * 4)
	seed.encode_u32(0, 0x00123456) # transparent hidden RGB in signed tile
	document._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, seed)
	var opened: DrawingResult = document.begin_edit(layer, document.revision)
	check(opened.ok, "editable native session opened")
	if not opened.ok:
		quit(1)
		return
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"), 8.0, INK, CLIP, true).ok,
		"real Hokusai Hard Round stroke started")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-20.5, 10.5), Vector2(12.5, 10.5)]), INK, false, null).ok,
		"stroke crosses negative-to-positive storage tile seam")
	var committed: DrawingResult = session.commit()
	check(committed.ok and committed.delta != null, "native gesture committed")
	if not committed.ok:
		quit(1)
		return
	var delta: DrawingDelta = committed.delta
	check(delta.native_history_token > 0 and delta.tile_stride == STRIDE and
		delta.after_tiles.size() == 2, "two whole-tile snapshots have a native token")
	var store: Object = document._native_raster_store
	var original_revision: int = document.revision
	var after_signed: PackedByteArray = source(document, layer, "-1,0")
	var after_positive: PackedByteArray = source(document, layer, "0,0")
	check(after_signed.size() == STRIDE * STRIDE * 4 and
		after_positive.size() == STRIDE * STRIDE * 4 and
		after_signed.decode_u32(0) == 0x00123456,
		"signed tile retains untouched transparent hidden RGB")
	check(int(store.call("stats").get("undo", -1)) == 1 and document.can_undo(),
		"token is the top of native and local Undo histories")
	# Each replacement still has the correct size and the source image still
	# matches. Without native payload validation this would diverge Rust/Godot.
	var before_signed: PackedByteArray = delta.before_tiles["-1,0"].duplicate()
	var modified: PackedByteArray = before_signed.duplicate()
	modified.encode_u32(0, 0x00fefdfc)
	delta.before_tiles["-1,0"] = modified
	var rejected: DrawingResult = document.undo()
	check(not rejected.ok and rejected.code == "NATIVE_HISTORY",
		"mutated Undo replacement is rejected by Rust before token consumption")
	check(document.revision == original_revision and
		int(store.call("stats").get("revision", -1)) == original_revision and
		int(store.call("stats").get("undo", -1)) == 1 and
		int(store.call("stats").get("redo", -1)) == 0 and document.can_undo(),
		"rejected Undo retains both revisions and history cursor")
	check(source(document, layer, "-1,0") == after_signed and
		source(document, layer, "0,0") == after_positive,
		"no tile is published by rejected Undo")
	delta.before_tiles["-1,0"] = before_signed
	check(document.undo().ok, "valid Undo can consume the original token")
	check(source(document, layer, "-1,0") == seed and
		source(document, layer, "0,0").is_empty(),
		"Undo restores exact before state on both storage tiles")
	check(int(store.call("stats").get("redo", -1)) == 1,
		"Rust preserved the Redo token")
	var original_after: PackedByteArray = delta.after_tiles["0,0"].duplicate()
	modified = original_after.duplicate()
	modified.encode_u32(4, 0xffabcdef)
	delta.after_tiles["0,0"] = modified
	var redo_revision: int = document.revision
	rejected = document.redo()
	check(not rejected.ok and rejected.code == "NATIVE_HISTORY",
		"mutated Redo replacement rejected atomically")
	check(document.revision == redo_revision and
		int(store.call("stats").get("revision", -1)) == redo_revision and
		int(store.call("stats").get("redo", -1)) == 1 and document.can_redo(),
		"rejected Redo retains native token and local cursor")
	check(source(document, layer, "-1,0") == seed and
		source(document, layer, "0,0").is_empty(),
		"rejected Redo leaves exact Undo state")
	delta.after_tiles["0,0"] = original_after
	check(document.redo().ok, "valid Redo succeeds after restoring detached payload")
	check(source(document, layer, "-1,0") == after_signed and
		source(document, layer, "0,0") == after_positive,
		"Redo restores exact committed bytes with native source parity")
	check(int(store.call("stats").get("revision", -1)) == document.revision and
		int(store.call("stats").get("undo", -1)) == 1,
		"single authority and live history survive failed retries")
	if failures == 0:
		print("T148_HISTORY_PAYLOAD_PASSED checks=%d failures=0" % checks)
	else:
		print("T148_HISTORY_PAYLOAD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
