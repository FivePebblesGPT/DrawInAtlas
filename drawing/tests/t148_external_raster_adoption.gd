extends SceneTree
## A real Brush gesture followed by ordinary (non-brush) multi-tile raster
## publication, using one Rust history and source-revision timeline.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_EXTERNAL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func stroke(doc: DrawingDocument, layer: String,
		start_at: Vector2 = Vector2(12.5, 12.5)) -> DrawingResult:
	var start: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not start.ok:
		return start
	var session: DrawingEditSession = start.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var opened: DrawingResult = session.begin_native_stroke(brush, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, 0xff3322bb, Rect2i(0, 0, 64, 64), true)
	if not opened.ok:
		session.cancel()
		return opened
	var painted: DrawingResult = session.paint_path_native(
		PackedVector2Array([start_at, start_at + Vector2(8.0, 0.0)]),
		0xff3322bb, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func packed(doc: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var resolved: DrawingResult = doc.request_chunk(layer, key)
	if not resolved.ok or resolved.value == null:
		return PackedByteArray()
	return (resolved.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native store available")
	var doc: DrawingDocument = DrawingDocument.new("external-raster-mixed", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var first: DrawingResult = stroke(doc, layer)
	check(first.ok and first.delta.native_history_token > 0, "brush creates native history")
	if not first.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var brush_bytes: PackedByteArray = packed(doc, layer, "0,0")
	var brush_revision: int = doc.revision
	var imported_before: int = int(store.call("stats").get("bytes_imported", -1))
	var external: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": int(doc.read_pixel(layer, 0, 0).value), "-2,3": 0},
		{"0,0": 0x00cdef12, "-2,3": 0xff884422})
	check(external.ok and external.delta.tile_stride == STRIDE and
		external.delta.native_history_token > 0, "external edit joins native tile history")
	check(doc.revision == brush_revision + 1 and doc._native_raster_store == store,
		"one source revision, same native owner")
	check(int(store.call("stats").get("undo", -1)) == 2 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"brush and external tool share ordered Rust history")
	check(int(doc.read_pixel(layer, 0, 0).value) == 0x00cdef12 and
		int(doc.read_pixel(layer, -2, 3).value) == 0xff884422,
		"signed tile seam and alpha-zero hidden RGB survive publication")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported_before and
		int(store.call("stats").get("external_bytes_received", 0)) ==
			2 * STRIDE * STRIDE * 4 * 2 - STRIDE * STRIDE * 4,
		"external tile transfer counted separately, no brush-source reimport")
	var native_negative: Dictionary = store.call("read_tile", layer, -1, 0, false)
	check(native_negative.get("ok", false) and
		(native_negative.get("bytes") as PackedByteArray).decode_u32((3 * STRIDE + 62) * 4) == 0xff884422,
		"native source contains signed external tile")
	var final_main: PackedByteArray = packed(doc, layer, "0,0")
	var final_negative: PackedByteArray = packed(doc, layer, "-1,0")
	var saved_path: String = ProjectSettings.globalize_path("user://t148-external-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, saved_path).ok, "mixed source saved as real .drawing")
	var reopened: DrawingResult = DrawingFileIO.open(saved_path)
	check(reopened.ok, "real .drawing reload succeeds")
	if reopened.ok:
		var reopened_doc: DrawingDocument = reopened.value
		check(packed(reopened_doc, layer, "0,0") == final_main and
			packed(reopened_doc, layer, "-1,0") == final_negative,
			"reloaded source equals mixed native canonical bytes")
	DirAccess.remove_absolute(saved_path)
	check(doc.undo().ok and doc.revision == brush_revision + 2,
		"external raster edit undoes via native history")
	check(packed(doc, layer, "0,0") == brush_bytes and
		int(doc.read_pixel(layer, -2, 3).value) == 0,
		"native external Undo restores byte-exact brush source")
	check(int(store.call("stats").get("undo", -1)) == 1 and
		int(store.call("stats").get("redo", -1)) == 1,
		"Rust retains brush token beneath external Undo")
	check(doc.undo().ok and int(store.call("stats").get("undo", -1)) == 0,
		"older brush gesture also undoes using same stack")
	check(doc.redo().ok and doc.redo().ok, "redo both gesture and external raster edit")
	check(packed(doc, layer, "0,0") == final_main and
		packed(doc, layer, "-1,0") == final_negative and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"redo restores exact tile bytes and unified revision")
	var continued: DrawingResult = stroke(doc, layer, Vector2(35.5, 40.5))
	check(continued.ok and doc._native_raster_store == store and
		int(store.call("stats").get("undo", -1)) == 3,
		"next brush gesture preserves external-edit history in same Rust store")
	var three_changes: PackedByteArray = packed(doc, layer, "0,0")
	check(three_changes != final_main and doc.undo().ok and
		packed(doc, layer, "0,0") == final_main,
		"next brush gesture undoes without reverting external pixels")
	check(doc.redo().ok and packed(doc, layer, "0,0") == three_changes,
		"redo after mixed edits restores third native brush output")
	# Rejected Rust multi-tile import is failure-atomic, even when the first
	# tile is valid. This direct negative control must not change the document.
	var before_invalid_revision: int = doc.revision
	var undo_before: int = int(store.call("stats").get("undo", -1))
	var before_main: PackedByteArray = packed(doc, layer, "0,0")
	var next_main: PackedByteArray = before_main.duplicate()
	next_main.encode_u32(0, 0xff339955)
	var invalid_batch: Array[Dictionary] = [
		{"tile_x": 0, "tile_y": 0, "before": before_main, "after": next_main},
		{"tile_x": -2, "tile_y": 0, "before": PackedByteArray(),
			"after": PackedByteArray([1, 2, 3])}
	]
	check(not bool(store.call("adopt_external_edit", layer, doc.revision,
		invalid_batch).get("ok", true)), "invalid second tile rejects whole Rust batch")
	check(doc.revision == before_invalid_revision and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == undo_before and
		packed(doc, layer, "0,0") == before_main,
		"atomic rejection preserves both Rust and Godot authority")
	var stale_batch: Array[Dictionary] = [invalid_batch[0]]
	check(not bool(store.call("adopt_external_edit", layer, doc.revision - 1,
		stale_batch).get("ok", true)), "stale external revision rejected")
	# Direct source-object substitution without a revision is invalid even if
	# the replacement has byte-identical pixels.
	doc._nodes[layer].tiles["0,0"] = (doc._nodes[layer].tiles["0,0"] as DrawingRasterTile).detached_copy()
	var substitution: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": 0x00cdef12}, {"0,0": 0x00cdef13})
	check(not substitution.ok and doc.revision == before_invalid_revision and
		int(store.call("stats").get("undo", -1)) == undo_before,
		"source-object substitution cannot advance either history")
	# Independently cover two raster layers sharing the same signed tile ID.
	# Layer metadata is assembled before Rust owns the document revision.
	var multi: DrawingDocument = DrawingDocument.new("external-multilayer", STRIDE)
	var bottom: String = str(multi.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var top: String = str(multi.create_layer(DrawingLayerNode.RASTER, "Top").value)
	check(stroke(multi, bottom).ok, "first layer opens shared native store")
	var second_layer_edit: DrawingResult = multi._publish_edit(top, multi.revision,
		{"0,0": 0}, {"0,0": 0xffaa3399})
	check(second_layer_edit.ok and second_layer_edit.delta.native_history_token > 0 and
		int(multi._native_raster_store.call("stats").get("undo", -1)) == 2,
		"second layer raster event joins first layer native history")
	check(multi.undo().ok and int(multi.read_pixel(top, 0, 0).value) == 0 and
		int(multi.read_pixel(bottom, 12, 12).value) != 0,
		"second-layer Undo does not affect first-layer brush bytes")
	check(multi.redo().ok and int(multi.read_pixel(top, 0, 0).value) == 0xffaa3399,
		"second-layer Redo restores its own canonical tile")
	print("T148_EXTERNAL_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
