extends SceneTree
## T-176: local semantic structural Undo/Redo must not outpace Rust.

const STRIDE: int = 64
const COLOR: int = 0xff628cda
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T176_STRUCTURAL_FAILED: " + message)


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var edit: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		edit.cancel()
		return begun
	var drawn: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(9, 9), Vector2(22, 9)]), COLOR, false, null)
	if not drawn.ok:
		edit.cancel()
		return drawn
	return edit.commit()


func native_bytes(store: Object) -> PackedByteArray:
	return store.call("read_tile", "ink", 0, 0, false).get("bytes", PackedByteArray())


func snapshot(doc: DrawingDocument, store: Object) -> Dictionary:
	var metadata: Dictionary = {}
	for node_id: String in ["ink", "props", "target", "created", "bucket", "kid"]:
		metadata[node_id] = doc.node_metadata(node_id)
	return {"revision": doc.revision, "cursor": doc.history_position(),
		"count": doc.history_length(), "dirty": doc.is_dirty(),
		"untracked": doc._untracked_revision, "root": doc.list_children("root"),
		"target_children": doc.list_children("target"),
		"bucket_children": doc.list_children("bucket"), "metadata": metadata,
		"native_revision": int(store.call("stats").get("revision", -1)),
		"native_undo": int(store.call("stats").get("undo", -1)),
		"native_redo": int(store.call("stats").get("redo", -1)),
		"bytes": native_bytes(store)}


func make_doc(suffix: String) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t176-" + suffix, STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").ok, suffix + " creates raster")
	check(doc.create_layer(DrawingLayerNode.GROUP,
		"Target", "root", "target").ok, suffix + " creates destination group")
	check(doc.create_layer(DrawingLayerNode.OBJECTS,
		"Properties", "root", "props").ok, suffix + " creates semantic layer")
	var initial_tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	initial_tile.set_rgba(3, 4, 0x00332211)
	doc._nodes["ink"].tiles["0,0"] = initial_tile
	check(paint(doc, "ink").ok, suffix + " paints native Hokusai source")
	return doc


func record_operation(doc: DrawingDocument, operation: String) -> DrawingResult:
	match operation:
		"rename":
			return doc.rename_layer("props", "Updated", true)
		"visibility":
			return doc.set_visibility("props", false, true)
		"lock":
			return doc.set_locked("props", true, true)
		"reorder":
			return doc.reorder("props", "target", 0, true)
		"create":
			return doc.create_layer(DrawingLayerNode.OBJECTS,
				"Created", "root", "created", -1, true)
		"remove":
			var group: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP,
				"Bucket", "root", "bucket")
			if not group.ok:
				return group
			var child: DrawingResult = doc.create_layer(DrawingLayerNode.OBJECTS,
				"Kid", "bucket", "kid")
			if not child.ok:
				return child
			return doc.remove_subtree("bucket", true)
	return DrawingResult.failure("TEST", "Unknown operation")


func exercise(operation: String) -> void:
	var doc: DrawingDocument = make_doc(operation)
	var store: Object = doc._native_raster_store
	check(store != null, operation + " has resident Rust history")
	if store == null:
		return
	check(record_operation(doc, operation).ok, operation + " records structural change")
	var initial: Dictionary = snapshot(doc, store)
	var held: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(held.get("ok", false)), operation + " holds Rust transaction")
	if not bool(held.get("ok", false)):
		return
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		operation + " busy native source rejects Undo")
	check(doc._native_raster_store == store and snapshot(doc, store) == initial,
		operation + " rejected Undo changes neither tree nor history/source")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))),
		operation + " releases transaction")
	check(doc.undo().ok and doc.history_position() == initial.cursor - 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		native_bytes(store) == initial.bytes,
		operation + " Undo retries with shared native revision")
	var undone: Dictionary = snapshot(doc, store)
	var held_redo: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(held_redo.get("ok", false)), operation + " holds Redo transaction")
	if not bool(held_redo.get("ok", false)):
		return
	var refused_redo: DrawingResult = doc.redo()
	check(not refused_redo.ok and refused_redo.code == "NATIVE_METADATA",
		operation + " busy native source rejects Redo")
	check(doc._native_raster_store == store and snapshot(doc, store) == undone,
		operation + " rejected Redo preserves cursor and native source")
	check(bool(store.call("discard_edit", int(held_redo.get("transaction", 0)))),
		operation + " releases Redo transaction")
	check(doc.redo().ok and doc.history_position() == initial.cursor and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		(doc.node_metadata("props") == initial.metadata.props) and
		doc.list_children("root") == initial.root and
		doc.list_children("target") == initial.target_children and
		native_bytes(store) == initial.bytes,
		operation + " Redo retries and restores structural projection")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("undo", -1)) == initial.native_undo,
		operation + " keeps previous native brush history")
	var rgba: PackedByteArray = native_bytes(store)
	var hidden: int = (4 * STRIDE + 3) * 4
	check(rgba.size() == STRIDE * STRIDE * 4 and
		rgba[hidden] == 0x11 and rgba[hidden + 1] == 0x22 and
		rgba[hidden + 2] == 0x33 and rgba[hidden + 3] == 0,
		operation + " keeps transparent hidden RGB across structural replay")
	if operation == "rename":
		check(paint(doc, "ink").ok and doc._native_raster_store == store and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			"subsequent native Hokusai Brush uses the retained store")
		var post_stroke: PackedByteArray = native_bytes(store)
		check(doc.undo().ok and doc.redo().ok and
			native_bytes(store) == post_stroke and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			"subsequent Brush Undo/Redo recovers exact native bytes")
		var save_path: String = ProjectSettings.globalize_path(
			"user://t176-" + DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(doc, save_path).ok, "replayed semantic/native document saves")
		var reopened: DrawingResult = DrawingFileIO.open(save_path)
		var source_chunk: DrawingResult = doc.request_chunk("ink", "0,0")
		check(reopened.ok and source_chunk.ok and
			(reopened.value as DrawingDocument).node_metadata("props").get("name") == "Updated" and
			(reopened.value as DrawingDocument).request_chunk("ink", "0,0").ok and
			((reopened.value as DrawingDocument).request_chunk("ink", "0,0").value as DrawingRasterTile).to_rgba8() ==
			(source_chunk.value as DrawingRasterTile).to_rgba8(),
			"Save/Open preserves structural state and canonical RGBA8")
		DirAccess.remove_absolute(save_path)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required native classes loaded")
	for operation: String in ["rename", "visibility", "lock", "reorder", "create", "remove"]:
		exercise(operation)
	var ahead: DrawingDocument = make_doc("ahead")
	var store: Object = ahead._native_raster_store
	check(ahead.rename_layer("props", "Changed", true).ok,
		"native-ahead case creates recorded rename")
	var previous: int = ahead.revision
	check(store.call("advance_metadata_revision", previous, false),
		"native store advanced ahead independently")
	var before: Dictionary = snapshot(ahead, store)
	var rejected: DrawingResult = ahead.undo()
	check(not rejected.ok and rejected.code == "STALE_REVISION" and
		ahead._native_raster_store == store and snapshot(ahead, store) == before,
		"native-ahead structural replay rejects without detaching Rust")
	var plain: DrawingDocument = DrawingDocument.new("t176-plain", STRIDE)
	check(plain.create_layer(DrawingLayerNode.OBJECTS,
		"Plain", "root", "plain", -1, true).ok and
		plain.rename_layer("plain", "Changed", true).ok and plain.undo().ok and
		plain.node_metadata("plain").get("name") == "Plain" and
		plain.redo().ok and plain.node_metadata("plain").get("name") == "Changed" and
		plain._native_raster_store == null,
		"native-absent historical structural replay remains valid")
	print("T176_STRUCTURAL_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T176_STRUCTURAL_PASSED")
	quit(0 if failures == 0 else 1)
