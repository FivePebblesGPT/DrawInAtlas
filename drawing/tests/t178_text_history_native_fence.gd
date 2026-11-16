extends SceneTree
## T-178: semantic-only text Undo/Redo must acquire Rust before changing Godot.

const STRIDE: int = 64
const COLOR: int = 0xff638ad4
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T178_TEXT_HISTORY_FAILED: " + message)


func draft(value: String) -> DrawingTextElement:
	var text: DrawingTextElement = DrawingTextElement.new()
	text.content = value
	text.font_size = 20
	return text


func paint(doc: DrawingDocument) -> DrawingResult:
	var session: DrawingResult = doc.begin_edit("ink", doc.revision)
	if not session.ok:
		return session
	var edit: DrawingEditSession = session.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = edit.begin_native_stroke(brush, preset, 8.0,
		COLOR, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		edit.cancel()
		return began
	var path: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(9, 9), Vector2(20, 9)]), COLOR, false, null)
	if not path.ok:
		edit.cancel()
		return path
	return edit.commit()


func text_value(doc: DrawingDocument) -> String:
	var node: DrawingLayerNode = doc.inspect_node("label")
	return node.text_value if node != null else "<missing>"


func source_bytes(store: Object) -> PackedByteArray:
	return store.call("read_tile", "ink", 0, 0, false).get("bytes", PackedByteArray())


func make_document(name: String) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok,
		name + " creates Ink")
	var hidden: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	hidden.set_rgba(3, 4, 0x00332211)
	doc._nodes["ink"].tiles["0,0"] = hidden
	check(paint(doc).ok, name + " attaches real Hokusai source")
	check(doc.commit_text("", draft("Alpha"), doc.revision, "root", "label").ok,
		name + " records text creation")
	check(doc.commit_text("label", draft("Bravo"), doc.revision).ok,
		name + " records text edit")
	return doc


func snapshot(doc: DrawingDocument, store: Object) -> Dictionary:
	var stats: Dictionary = store.call("stats")
	var node: DrawingLayerNode = doc.inspect_node("label")
	return {"revision": doc.revision, "native_revision": int(stats.get("revision", -1)),
		"cursor": doc.history_position(), "history": doc.history_length(),
		"untracked": doc._untracked_revision, "dirty": doc.is_dirty(),
		"roots": doc.list_children(), "text": node.text_value if node != null else "<missing>",
		"undo": int(stats.get("undo", -1)), "redo": int(stats.get("redo", -1)),
		"bytes": source_bytes(store)}


func hold_edit(doc: DrawingDocument, store: Object, label: String) -> int:
	var started: Dictionary = store.call("begin_edit", "ink", doc.revision, false)
	check(bool(started.get("ok", false)), label + " begins active native transaction")
	return int(started.get("transaction", 0))


func exercise_busy() -> void:
	var doc: DrawingDocument = make_document("t178-busy")
	var store: Object = doc._native_raster_store
	check(store != null, "busy fixture retains native store")
	if store == null:
		return
	var canonical: PackedByteArray = source_bytes(store)
	var hidden_offset: int = (4 * STRIDE + 3) * 4
	check(canonical.size() == STRIDE * STRIDE * 4 and
		canonical[hidden_offset] == 0x11 and canonical[hidden_offset + 1] == 0x22 and
		canonical[hidden_offset + 2] == 0x33 and canonical[hidden_offset + 3] == 0,
		"canonical Rust source includes transparent hidden RGB")
	var before: Dictionary = snapshot(doc, store)
	var tx: int = hold_edit(doc, store, "edit Undo")
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		"busy native store refuses text edit Undo")
	check(snapshot(doc, store) == before and doc._native_raster_store == store,
		"rejected edit Undo preserves document, cursor, tiles and Rust tokens")
	check(bool(store.call("discard_edit", tx)), "releases edit Undo transaction")
	check(doc.undo().ok and text_value(doc) == "Alpha" and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		doc._native_raster_store == store, "edit Undo retries with same Rust store")
	var after_undo: Dictionary = snapshot(doc, store)
	tx = hold_edit(doc, store, "edit Redo")
	refused = doc.redo()
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		"busy native store refuses text edit Redo")
	check(snapshot(doc, store) == after_undo and doc._native_raster_store == store,
		"rejected edit Redo preserves document and Rust state")
	check(bool(store.call("discard_edit", tx)), "releases edit Redo transaction")
	check(doc.redo().ok and text_value(doc) == "Bravo" and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"edit Redo retries with exact text and native revision")
	check(doc.undo().ok, "rewinds text edit before create Undo")
	var before_create: Dictionary = snapshot(doc, store)
	tx = hold_edit(doc, store, "create Undo")
	refused = doc.undo()
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		"busy native store refuses text creation Undo")
	check(snapshot(doc, store) == before_create and doc.has_node("label"),
		"rejected create Undo preserves layer membership and cursor")
	check(bool(store.call("discard_edit", tx)), "releases create Undo transaction")
	check(doc.undo().ok and not doc.has_node("label") and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"create Undo removes text and advances Rust exactly once")
	var before_redo: Dictionary = snapshot(doc, store)
	tx = hold_edit(doc, store, "create Redo")
	refused = doc.redo()
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		"busy native store refuses text creation Redo")
	check(snapshot(doc, store) == before_redo and not doc.has_node("label"),
		"rejected create Redo preserves missing layer and history")
	check(bool(store.call("discard_edit", tx)), "releases create Redo transaction")
	check(doc.redo().ok and doc.has_node("label") and
		text_value(doc) == "Alpha" and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"create Redo retries without detaching Rust")
	check(doc.redo().ok and text_value(doc) == "Bravo",
		"later text edit Redo remains available")
	check(source_bytes(store) == canonical, "text Undo/Redo preserves native RGBA8")
	check(paint(doc).ok and doc._native_raster_store == store,
		"subsequent Hokusai stroke keeps original native authority")
	var stroke_bytes: PackedByteArray = source_bytes(store)
	check(doc.undo().ok and doc.redo().ok and source_bytes(store) == stroke_bytes,
		"subsequent Hokusai Undo/Redo remains exact")
	var save_path: String = ProjectSettings.globalize_path(
		"user://t178-" + DrawingDocument.new_id() + ".drawing")
	var saved: DrawingResult = DrawingFileIO.save(doc, save_path)
	var opened: DrawingResult = DrawingFileIO.open(save_path)
	check(saved.ok and opened.ok and
		(opened.value as DrawingDocument).has_node("label") and
		text_value(opened.value as DrawingDocument) == "Bravo" and
		(opened.value as DrawingDocument).request_chunk("ink", "0,0").ok and
		((opened.value as DrawingDocument).request_chunk("ink", "0,0").value as DrawingRasterTile).to_rgba8() == stroke_bytes,
		"text history and native source round-trip through .drawing")
	DirAccess.remove_absolute(save_path)


func exercise_ahead() -> void:
	var doc: DrawingDocument = make_document("t178-ahead")
	var store: Object = doc._native_raster_store
	check(store != null, "ahead fixture retains native store")
	if store == null:
		return
	check(bool(store.call("advance_metadata_revision", doc.revision, false)),
		"advances native revision independent of Godot")
	var before: Dictionary = snapshot(doc, store)
	var refused: DrawingResult = doc.undo()
	check(not refused.ok and refused.code == "STALE_REVISION" and
		snapshot(doc, store) == before and doc._native_raster_store == store,
		"native-ahead text edit Undo fails before mutating tree or cursor")


func exercise_native_absent() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t178-plain", STRIDE)
	check(doc.commit_text("", draft("Alpha"), doc.revision, "root", "label").ok and
		doc.commit_text("label", draft("Bravo"), doc.revision).ok,
		"native-absent text create and edit still record history")
	check(doc._native_raster_store == null and doc.undo().ok and
		text_value(doc) == "Alpha" and doc.undo().ok and
		not doc.has_node("label"), "native-absent text Undo stays functional")
	check(doc.redo().ok and doc.redo().ok and
		text_value(doc) == "Bravo" and
		doc._native_raster_store == null, "native-absent text Redo stays functional")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "native extension is loaded")
	exercise_busy()
	exercise_ahead()
	exercise_native_absent()
	print("T178_TEXT_HISTORY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T178_TEXT_HISTORY_PASSED")
	quit(0 if failures == 0 else 1)
