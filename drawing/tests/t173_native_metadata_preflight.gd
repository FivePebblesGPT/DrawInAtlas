extends SceneTree
## T-173: public layer metadata/tree commands must reject a busy or divergent
## attached Rust store before changing the Godot tree or history cursor.

const STRIDE: int = 64
const INK: int = 0xff638ad4
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T173_METADATA_FAILED: " + description)


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		edit.cancel()
		return begun
	var path: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(8, 8), Vector2(20, 8)]), INK, false, null)
	if not path.ok:
		edit.cancel()
		return path
	return edit.commit()


func bytes(store: Object, layer: String) -> PackedByteArray:
	return store.call("read_tile", layer, 0, 0, false).get("bytes", PackedByteArray())


func attempt_changes(doc: DrawingDocument, layer: String, group: String,
		expected_code: String, tag: String) -> void:
	var revision_before: int = doc.revision
	var root_before: Array[String] = doc.list_children("root")
	var ink_before: Dictionary = doc.node_metadata(layer)
	var created: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP,
		"Rejected group", "root", "t173-rejected", -1, true)
	var renamed: DrawingResult = doc.rename_layer(layer, "Rejected name", true)
	var hidden: DrawingResult = doc.set_visibility(layer, false, true)
	var locked: DrawingResult = doc.set_locked(layer, true, true)
	var moved: DrawingResult = doc.reorder(layer, group, 0, true)
	check(not created.ok and created.code == expected_code,
		tag + " rejects group creation")
	check(not renamed.ok and renamed.code == expected_code,
		tag + " rejects rename")
	check(not hidden.ok and hidden.code == expected_code,
		tag + " rejects visibility")
	check(not locked.ok and locked.code == expected_code,
		tag + " rejects locking")
	check(not moved.ok and moved.code == expected_code,
		tag + " rejects reorder")
	check(doc.revision == revision_before and
		doc.list_children("root") == root_before and
		doc.node_metadata(layer) == ink_before and not doc.has_node("t173-rejected"),
		tag + " leaves metadata, tree, and revision unchanged")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required Rust classes loaded")
	var doc: DrawingDocument = DrawingDocument.new("t173-native", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP,
		"Target group", "root", "target").value)
	var drawn: DrawingResult = paint(doc, layer)
	check(drawn.ok and drawn.delta.native_history_token > 0,
		"native Hokusai stroke established canonical source and history")
	if not drawn.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var rgba: PackedByteArray = bytes(store, layer)
	var undo_count: int = int(store.call("stats").get("undo", -1))
	var begin_revision: int = doc.revision
	var held: Dictionary = store.call("begin_edit", layer, doc.revision, false)
	check(bool(held.get("ok", false)), "active native transaction held")
	attempt_changes(doc, layer, group, "NATIVE_METADATA", "busy native")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == begin_revision and
		int(store.call("stats").get("undo", -1)) == undo_count and
		bytes(store, layer) == rgba,
		"busy rejection leaves attached native source, bytes and tokens intact")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"active transaction discarded for retry")
	# A retry of the exact refused commands is now legal and advances one
	# revision per operation, without reimporting or invalidating source bytes.
	check(doc.create_layer(DrawingLayerNode.GROUP,
		"New group", "root", "t173-rejected", -1, true).ok,
		"create retries after native unblocks")
	check(doc.rename_layer(layer, "New name", true).ok,
		"rename retries after native unblocks")
	check(doc.reorder(layer, group, 0, true).ok,
		"reorder retries after native unblocks")
	check(doc.set_locked(layer, true, true).ok and
		doc.set_locked(layer, false, true).ok,
		"lock and unlock retry after native unblocks")
	check(doc.set_visibility(layer, false, true).ok and
		doc.set_visibility(layer, true, true).ok,
		"hide and show retry after native unblocks")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == undo_count and
		bytes(store, layer) == rgba,
		"successful commands preserve native bytes and history through revisions")
	var after_metadata: int = doc.revision
	check(doc.rename_layer(layer, "New name", true).ok and
		doc.revision == after_metadata,
		"no-op metadata call does not advance revision")
	check(doc.undo().ok and doc.node_metadata(layer).get("visible") == false and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"metadata Undo preserves native timeline")
	check(doc.redo().ok and doc.node_metadata(layer).get("visible") == true and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"metadata Redo preserves native timeline")
	check(paint(doc, layer).ok and doc._native_raster_store == store,
		"later native paint reuses the same store")
	# Native-ahead store is not busy, but must still fail atomically.
	var stale_doc: DrawingDocument = DrawingDocument.new("t173-ahead", STRIDE)
	var stale_layer: String = str(stale_doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	var stale_group: String = str(stale_doc.create_layer(DrawingLayerNode.GROUP,
		"Target", "root", "target").value)
	check(paint(stale_doc, stale_layer).ok, "native-ahead case begins with real Brush")
	var stale_store: Object = stale_doc._native_raster_store
	var stale_revision: int = stale_doc.revision
	var stale_bytes: PackedByteArray = bytes(stale_store, stale_layer)
	var stale_undo: int = int(stale_store.call("stats").get("undo", -1))
	check(stale_store.call("advance_metadata_revision", stale_revision, false),
		"manually advance native store ahead of Godot")
	attempt_changes(stale_doc, stale_layer, stale_group, "STALE_REVISION", "native ahead")
	check(stale_doc._native_raster_store == stale_store and
		stale_doc.revision == stale_revision and
		int(stale_store.call("stats").get("revision", -1)) == stale_revision + 1 and
		int(stale_store.call("stats").get("undo", -1)) == stale_undo and
		bytes(stale_store, stale_layer) == stale_bytes,
		"stale rejection keeps native attachment and canonical source")
	# No native store still uses the historical metadata path until T-150.
	var plain: DrawingDocument = DrawingDocument.new("t173-plain", STRIDE)
	var plain_layer: String = str(plain.create_layer(DrawingLayerNode.RASTER,
		"Plain", "root", "plain").value)
	check(plain._native_raster_store == null and
		plain.rename_layer(plain_layer, "Renamed", true).ok and
		plain.set_visibility(plain_layer, false, true).ok and
		plain.revision == 3,
		"native-absent metadata remains available until Legacy retirement")
	print("T173_METADATA_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T173_METADATA_PASSED")
	quit(0 if failures == 0 else 1)
