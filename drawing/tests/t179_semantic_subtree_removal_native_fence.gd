extends SceneTree
## T-179: semantic-only subtree removal must obtain native metadata authority
## before deleting Godot nodes, for both local and host-owned history.

const STRIDE: int = 64
const COLOR: int = 0xff638ad4
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T179_SEMANTIC_REMOVE_FAILED: " + message)


func paint(doc: DrawingDocument) -> DrawingResult:
	var began: DrawingResult = doc.begin_edit("ink", doc.revision)
	if not began.ok:
		return began
	var edit: DrawingEditSession = began.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var stroke: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not stroke.ok:
		edit.cancel()
		return stroke
	var samples: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(8, 8), Vector2(22, 8)]), COLOR, false, null)
	if not samples.ok:
		edit.cancel()
		return samples
	return edit.commit()


func make_doc(label: String, host_owned: bool = false) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t179-" + label, STRIDE)
	if host_owned:
		check(doc.set_external_history(true).ok, label + " enables host history")
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok,
		label + " creates native Ink layer")
	check(doc.create_layer(DrawingLayerNode.GROUP, "Bucket", "root", "bucket").ok,
		label + " creates semantic parent")
	check(doc.create_layer(DrawingLayerNode.GROUP, "Nested", "bucket", "nested").ok,
		label + " creates nested semantic group")
	check(doc.create_layer(DrawingLayerNode.OBJECTS, "Objects", "nested", "objects").ok,
		label + " creates nested semantic child")
	var hidden: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	hidden.set_rgba(3, 4, 0x00332211)
	doc._nodes["ink"].tiles["0,0"] = hidden
	var drawn: DrawingResult = paint(doc)
	check(drawn.ok and drawn.delta != null and drawn.delta.native_history_token > 0,
		label + " establishes real Hokusai source/history")
	return doc


func bytes(store: Object) -> PackedByteArray:
	return store.call("read_tile", "ink", 0, 0, false).get("bytes", PackedByteArray())


func snapshot(doc: DrawingDocument, store: Object) -> Dictionary:
	var stats: Dictionary = store.call("stats")
	return {"revision": doc.revision, "native_revision": int(stats.get("revision", -1)),
		"cursor": doc.history_position(), "length": doc.history_length(),
		"dirty": doc.is_dirty(), "untracked": doc._untracked_revision,
		"root": doc.list_children("root"), "bucket": doc.list_children("bucket"),
		"nested": doc.list_children("nested"), "has_bucket": doc.has_node("bucket"),
		"has_objects": doc.has_node("objects"),
		"undo": int(stats.get("undo", -1)), "redo": int(stats.get("redo", -1)),
		"bytes": bytes(store)}


func exercise(record_history: bool, host_owned: bool = false) -> void:
	var label: String = "host" if host_owned else ("recorded" if record_history else "untracked")
	var doc: DrawingDocument = make_doc(label, host_owned)
	var store: Object = doc._native_raster_store
	check(store != null, label + " retains native attachment")
	if store == null:
		return
	var before: Dictionary = snapshot(doc, store)
	var hidden_rgba: PackedByteArray = bytes(store)
	var pixel: int = (4 * STRIDE + 3) * 4
	check(hidden_rgba.size() == STRIDE * STRIDE * 4 and
		hidden_rgba[pixel] == 0x11 and hidden_rgba[pixel + 1] == 0x22 and
		hidden_rgba[pixel + 2] == 0x33 and hidden_rgba[pixel + 3] == 0,
		label + " begins with hidden RGB in Rust")
	var held: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(held.get("ok", false)), label + " holds native transaction")
	if not bool(held.get("ok", false)):
		return
	var rejected: DrawingResult = doc.remove_subtree("bucket", record_history)
	check(not rejected.ok and rejected.code == "NATIVE_METADATA",
		label + " refuses semantic removal while Rust is busy")
	check(snapshot(doc, store) == before and doc._native_raster_store == store,
		label + " rejected removal changes neither tree, source nor histories")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))),
		label + " releases native transaction")
	var accepted: DrawingResult = doc.remove_subtree("bucket", record_history)
	check(accepted.ok and not doc.has_node("bucket") and
		not doc.has_node("nested") and not doc.has_node("objects") and
		doc._native_raster_store == store and doc.revision == before.revision + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		label + " succeeds atomically on retry")
	check(bytes(store) == hidden_rgba and
		int(store.call("stats").get("undo", -1)) == before.undo,
		label + " preserves native pixels and Undo tokens")
	if record_history and not host_owned:
		check(doc.history_length() == before.length + 1 and
			doc.history_position() == before.cursor + 1,
			"recorded removal creates one history event")
		check(doc.undo().ok and doc.has_node("objects") and
			doc.list_children("bucket") == ["nested"] and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			"recorded Undo restores nested semantic tree")
		check(doc.redo().ok and not doc.has_node("bucket") and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			"recorded Redo removes semantic tree with native revision")
	else:
		check(doc.history_length() == before.length and doc.is_dirty(),
			label + " unrecorded/host removal introduces no local history")
	check(paint(doc).ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		label + " subsequent Hokusai paint preserves existing native store")
	if record_history and not host_owned:
		var saved: String = ProjectSettings.globalize_path(
			"user://t179-" + DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(doc, saved).ok, "recorded removal saves")
		var reopened: DrawingResult = DrawingFileIO.open(saved)
		check(reopened.ok and not (reopened.value as DrawingDocument).has_node("bucket") and
			(reopened.value as DrawingDocument).request_chunk("ink", "0,0").ok,
			"recorded removal reopens with Ink but without semantic subtree")
		DirAccess.remove_absolute(saved)


func exercise_native_ahead() -> void:
	var doc: DrawingDocument = make_doc("native-ahead")
	var store: Object = doc._native_raster_store
	if store == null:
		return
	var before: Dictionary = snapshot(doc, store)
	check(bool(store.call("advance_metadata_revision", doc.revision, false)),
		"native-ahead fixture advances only Rust")
	var ahead: Dictionary = snapshot(doc, store)
	var rejected: DrawingResult = doc.remove_subtree("bucket", true)
	check(not rejected.ok and rejected.code == "STALE_REVISION",
		"divergent native revision rejects semantic subtree removal")
	check(snapshot(doc, store) == ahead and doc._native_raster_store == store and
		doc.revision == before.revision and doc.has_node("objects"),
		"divergence leaves both revisions and all source/history state unchanged")


func exercise_native_absent() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t179-absent", STRIDE)
	check(doc.create_layer(DrawingLayerNode.GROUP, "Bucket", "root", "bucket").ok and
		doc.create_layer(DrawingLayerNode.TEXT, "Text", "bucket", "text").ok,
		"native-absent fixture creates semantic subtree")
	check(doc._native_raster_store == null and
		doc.remove_subtree("bucket", true).ok and not doc.has_node("bucket"),
		"native-absent semantic removal works until T-150")
	check(doc.undo().ok and doc.has_node("text") and doc.redo().ok and
		not doc.has_node("bucket"), "native-absent structural Undo/Redo works")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required Rust native classes loaded")
	exercise(true)
	exercise(false)
	exercise(false, true)
	exercise_native_ahead()
	exercise_native_absent()
	print("T179_SEMANTIC_REMOVE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T179_SEMANTIC_REMOVE_PASSED")
	quit(0 if failures == 0 else 1)
