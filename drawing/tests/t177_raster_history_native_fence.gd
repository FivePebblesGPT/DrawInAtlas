extends SceneTree
## T-177: raster create/remove structural Undo/Redo must acquire native authority first.

const STRIDE: int = 64
const COLOR: int = 0xff608edb
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, context: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T177_RASTER_FAILED: " + context)


func paint(doc: DrawingDocument, layer_id: String) -> DrawingResult:
	var start: DrawingResult = doc.begin_edit(layer_id, doc.revision)
	if not start.ok:
		return start
	var edit: DrawingEditSession = start.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		edit.cancel()
		return begun
	var drawn: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(9, 9), Vector2(20, 9)]), COLOR, false, null)
	if not drawn.ok:
		edit.cancel()
		return drawn
	return edit.commit()


func make_doc(context: String, parked: bool) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t177-" + context, STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok,
		context + " creates Ink")
	var hidden: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	hidden.set_rgba(3, 4, 0x00332211)
	doc._nodes["ink"].tiles["0,0"] = hidden
	check(paint(doc, "ink").ok, context + " creates live Hokusai source")
	if parked:
		check(doc.create_layer(DrawingLayerNode.GROUP, "Group", "root", "group").ok,
			context + " creates group")
		check(doc.create_layer(DrawingLayerNode.RASTER, "Victim", "group", "victim").ok,
			context + " creates victim")
		var victim_tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
		victim_tile.set_rgba(3, 4, 0x00224466)
		doc._nodes["victim"].tiles["0,0"] = victim_tile
		check(paint(doc, "victim").ok, context + " authorizes victim source")
	return doc


func record(doc: DrawingDocument, operation: String) -> DrawingResult:
	match operation:
		"create":
			return doc.create_layer(DrawingLayerNode.RASTER, "New raster",
				"root", "newraster", -1, true)
		"remove_unreferenced":
			var group: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP,
				"Group", "root", "group")
			if not group.ok:
				return group
			var child: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER,
				"Deferred", "group", "deferred")
			if not child.ok:
				return child
			return doc.remove_subtree("group", true)
		"remove_parked":
			return doc.remove_subtree("group", true)
	return DrawingResult.failure("TEST", "Unknown raster structural operation")


func native_tile(store: Object, layer_id: String) -> PackedByteArray:
	return store.call("read_tile", layer_id, 0, 0, false).get(
		"bytes", PackedByteArray())


func snapshot(doc: DrawingDocument, store: Object) -> Dictionary:
	var stats: Dictionary = store.call("stats")
	return {"revision": doc.revision, "cursor": doc.history_position(),
		"length": doc.history_length(), "dirty": doc.is_dirty(),
		"untracked": doc._untracked_revision,
		"roots": doc.list_children(), "children": doc.list_children("group"),
		"new": doc.node_metadata("newraster"),
		"group": doc.node_metadata("group"), "deferred": doc.node_metadata("deferred"),
		"victim": doc.node_metadata("victim"), "ink": native_tile(store, "ink"),
		"native_revision": int(stats.get("revision", -1)),
		"native_undo": int(stats.get("undo", -1)),
		"native_redo": int(stats.get("redo", -1)),
		"parked": bool(store.call("is_layer_parked", "victim"))}


func same_replayed_projection(before: Dictionary, after: Dictionary) -> bool:
	# Structural Undo/Redo advances monotonic revisions even when it restores
	# the identical tree and content; compare those revisions separately.
	var expected: Dictionary = before.duplicate(true)
	var actual: Dictionary = after.duplicate(true)
	expected.erase("revision")
	expected.erase("native_revision")
	actual.erase("revision")
	actual.erase("native_revision")
	return expected == actual


func exercise(operation: String) -> void:
	var doc: DrawingDocument = make_doc(operation, operation == "remove_parked")
	var store: Object = doc._native_raster_store
	check(store != null, operation + " retains canonical tile store")
	if store == null:
		return
	var recorded: DrawingResult = record(doc, operation)
	check(recorded.ok, operation + " records raster structural change")
	if not recorded.ok:
		return
	var event: Dictionary = doc._events[doc._cursor - 1]
	check(bool(event.get("native_parked", false)) == (operation == "remove_parked"),
		operation + " records correct parked authority")
	var before: Dictionary = snapshot(doc, store)
	var held: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(held.get("ok", false)), operation + " opens native transaction")
	if not bool(held.get("ok", false)):
		return
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "NATIVE_STRUCTURE",
		operation + " busy Rust rejects structural Undo")
	check(snapshot(doc, store) == before and doc._native_raster_store == store,
		operation + " rejected Undo is byte/history/tree atomic")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))),
		operation + " releases native transaction")
	var undone_result: DrawingResult = doc.undo()
	check(undone_result.ok and doc.history_position() == before.cursor - 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		doc._native_raster_store == store,
		operation + " Undo retries with synchronized native revision")
	var undone: Dictionary = snapshot(doc, store)
	var redo_held: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(redo_held.get("ok", false)), operation + " opens native Redo transaction")
	if not bool(redo_held.get("ok", false)):
		return
	var refused_redo: DrawingResult = doc.redo()
	check(not refused_redo.ok and refused_redo.code == "NATIVE_STRUCTURE",
		operation + " busy Rust rejects structural Redo")
	check(snapshot(doc, store) == undone and doc._native_raster_store == store,
		operation + " rejected Redo is byte/history/tree atomic")
	check(bool(store.call("discard_edit", int(redo_held.get("transaction", 0)))),
		operation + " releases native Redo transaction")
	var redone: DrawingResult = doc.redo()
	check(redone.ok and same_replayed_projection(before, snapshot(doc, store)) and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		operation + " Redo retries and restores exact tree/bytes with matching revision")
	var ink: PackedByteArray = native_tile(store, "ink")
	var hidden_offset: int = (4 * STRIDE + 3) * 4
	check(ink.size() == STRIDE * STRIDE * 4 and
		ink[hidden_offset] == 0x11 and ink[hidden_offset + 1] == 0x22 and
		ink[hidden_offset + 2] == 0x33 and ink[hidden_offset + 3] == 0,
		operation + " preserves transparent hidden RGB")
	if operation == "remove_parked":
		check(not doc.has_node("victim") and bool(store.call("is_layer_parked", "victim")),
			"parked replay leaves victim reserved until Undo")
		check(doc.undo().ok and doc.has_node("victim") and
			(not bool(store.call("is_layer_parked", "victim"))) and doc.redo().ok,
			"parked native raster Undo/Redo remains reversible")
	if operation == "create":
		check(paint(doc, "ink").ok and doc._native_raster_store == store,
			"native Brush remains attached after raster structural history")
		var stroke_bytes: PackedByteArray = native_tile(store, "ink")
		check(doc.undo().ok and doc.redo().ok and
			native_tile(store, "ink") == stroke_bytes,
			"later native Brush Undo/Redo remains byte exact")
		var save_path: String = ProjectSettings.globalize_path(
			"user://t177-" + DrawingDocument.new_id() + ".drawing")
		var saved: DrawingResult = DrawingFileIO.save(doc, save_path)
		var opened: DrawingResult = DrawingFileIO.open(save_path)
		check(saved.ok and opened.ok and
			(opened.value as DrawingDocument).has_node("newraster") and
			(opened.value as DrawingDocument).request_chunk("ink", "0,0").ok and
			((opened.value as DrawingDocument).request_chunk("ink", "0,0").value as DrawingRasterTile).to_rgba8() == stroke_bytes,
			"raster structural replay persists in .drawing Save/Open")
		DirAccess.remove_absolute(save_path)


func exercise_ahead(operation: String) -> void:
	var doc: DrawingDocument = make_doc("ahead-" + operation,
		operation == "remove_parked")
	var store: Object = doc._native_raster_store
	check(record(doc, operation).ok, operation + " records native-ahead fixture")
	var current: int = doc.revision
	check(bool(store.call("advance_metadata_revision", current, false)),
		operation + " advances native revision independently")
	var before: Dictionary = snapshot(doc, store)
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "STALE_REVISION" and
		doc._native_raster_store == store and snapshot(doc, store) == before,
		operation + " native-ahead rejects without tree/history mutation")


func exercise_corrupt_parked() -> void:
	var doc: DrawingDocument = make_doc("corrupt-parked", true)
	var store: Object = doc._native_raster_store
	check(doc.remove_subtree("group", true).ok,
		"parked snapshot corruption fixture records removal")
	var event: Dictionary = doc._events[doc._cursor - 1]
	var tile: DrawingRasterTile = event["nodes"]["victim"].tiles["0,0"]
	var canonical: int = tile.get_rgba(3, 4)
	tile.set_rgba(3, 4, 0x00887766)
	var before: Dictionary = snapshot(doc, store)
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "STALE_PIXEL" and
		snapshot(doc, store) == before,
		"mutated parked history snapshot rejects before native unpark")
	tile.set_rgba(3, 4, canonical)
	check(doc.undo().ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"restored parked snapshot retries without clearing native history")


func exercise_owned_create_refusal() -> void:
	var doc: DrawingDocument = make_doc("owned-create", false)
	var store: Object = doc._native_raster_store
	check(record(doc, "create").ok and paint(doc, "newraster").ok,
		"recorded new raster receives real Hokusai source")
	check(doc.undo().ok, "created raster Brush Undo succeeds")
	var before: Dictionary = snapshot(doc, store)
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "NATIVE_STRUCTURE" and
		doc._native_raster_store == store and snapshot(doc, store) == before,
		"previously authorized raster create cannot be undone via unreferenced bridge")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "native extension available")
	for operation: String in ["create", "remove_unreferenced", "remove_parked"]:
		exercise(operation)
		exercise_ahead(operation)
	exercise_corrupt_parked()
	exercise_owned_create_refusal()
	var plain: DrawingDocument = DrawingDocument.new("t177-plain", STRIDE)
	check(plain.create_layer(DrawingLayerNode.RASTER, "Plain", "root",
		"plain", -1, true).ok and plain.undo().ok and
		not plain.has_node("plain") and plain.redo().ok and
		plain.has_node("plain") and plain._native_raster_store == null,
		"native-absent historical raster create Undo/Redo remains valid")
	print("T177_RASTER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T177_RASTER_PASSED")
	quit(0 if failures == 0 else 1)
