extends SceneTree
## T-174: semantic document writes must not detach a busy/divergent Rust store.

const STRIDE: int = 64
const INK: int = 0xff638ad4
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T174_SEMANTIC_FAILED: " + label)


func text_element(value: String) -> DrawingTextElement:
	var item: DrawingTextElement = DrawingTextElement.new()
	item.content = value
	item.font_size = 20
	return item


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
	var drawn: DrawingResult = edit.paint_path_native(PackedVector2Array(
		[Vector2(9, 9), Vector2(19, 9)]), INK, false, null)
	if not drawn.ok:
		edit.cancel()
		return drawn
	return edit.commit()


func setup_painted(id: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(id, STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	var objects: String = str(doc.create_layer(DrawingLayerNode.OBJECTS,
		"Objects", "root", "objects").value)
	var label: String = str(doc.create_layer(DrawingLayerNode.TEXT,
		"Label", "root", "label").value)
	check(doc.add_object(objects, {"position": Vector2(1, 2)}, "resident").ok,
		id + " initial object")
	check(doc.commit_text(label, text_element("Original"), doc.revision).ok,
		id + " initial text")
	check(paint(doc, ink).ok, id + " native Hokusai stroke")
	return {"doc": doc, "ink": ink, "objects": objects, "label": label,
		"store": doc._native_raster_store}


func source_bytes(store: Object, ink: String) -> PackedByteArray:
	return store.call("read_tile", ink, 0, 0, false).get("bytes", PackedByteArray())


func rejected_semantic(data: Dictionary, error: String, prefix: String) -> void:
	var doc: DrawingDocument = data["doc"]
	var layer: String = data["objects"]
	var label: String = data["label"]
	var store: Object = data["store"]
	var before_revision: int = doc.revision
	check(doc.commit_text(label, text_element("Original"), doc.revision).ok and
		doc.revision == before_revision,
		prefix + " identical text no-op does not require a native revision")
	var before_untracked: int = doc._untracked_revision
	var before_history: int = doc.history_length()
	var before_cursor: int = doc.history_position()
	var original: PackedByteArray = source_bytes(store, data["ink"])
	var undo_count: int = int(store.call("stats").get("undo", -1))
	var adding: DrawingResult = doc.add_object(layer,
		{"position": Vector2(9, 12)}, "rejected")
	var moving: DrawingResult = doc.move_object(layer, "resident", Vector2(7, 8))
	var editing: DrawingResult = doc.commit_text(label,
		text_element("Changed"), doc.revision)
	var creating: DrawingResult = doc.commit_text("",
		text_element("New label"), doc.revision, "root", "rejected-text")
	check(not adding.ok and adding.code == error, prefix + " rejects add object")
	check(not moving.ok and moving.code == error, prefix + " rejects move object")
	check(not editing.ok and editing.code == error, prefix + " rejects text edit")
	check(not creating.ok and creating.code == error, prefix + " rejects text create")
	check(doc.revision == before_revision and doc._untracked_revision == before_untracked and
		doc.history_length() == before_history and doc.history_position() == before_cursor,
		prefix + " preserves document and host history revisions")
	check(not doc.has_node("rejected-text") and
		not (doc.inspect_node(layer) as DrawingLayerNode).objects.has("rejected") and
		(doc.inspect_node(layer) as DrawingLayerNode).objects["resident"]["position"] == Vector2(1, 2) and
		(doc.inspect_node(label) as DrawingLayerNode).text_value == "Original",
		prefix + " leaves semantic values and node membership unchanged")
	check(doc._native_raster_store == store and
		source_bytes(store, data["ink"]) == original and
		int(store.call("stats").get("undo", -1)) == undo_count,
		prefix + " retains Rust attachment, RGBA8 and native tokens")


func density_boundaries() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t174-density", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	var store: Object = doc._native_store_for_edit(doc.revision)
	check(store != null and doc._native_raster_store == store,
		"density has attached empty native store without committed content")
	if store == null:
		return
	check(store.call("set_layer_editable", ink, true),
		"empty native raster marked editable for density preflight")
	var held: Dictionary = store.call("begin_edit", ink, doc.revision, false)
	check(bool(held.get("ok", false)), "density native transaction held")
	var old: int = doc.revision
	var density_busy: DrawingResult = doc.set_density(3, 2)
	check(not density_busy.ok and density_busy.code == "NATIVE_METADATA" and
		doc.revision == old and doc.density_numerator == 1 and doc.density_denominator == 1 and
		doc._native_raster_store == store, "busy density rejects before changing factors")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"density native transaction released")
	check(doc.set_density(3, 2).ok and doc.revision == old + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		doc.density_numerator == 3, "density retries with shared revision")
	var ahead: int = doc.revision
	check(store.call("advance_metadata_revision", ahead, false),
		"density native store advanced ahead")
	check(doc.set_density(3, 2).ok and doc.revision == ahead,
		"identical density no-op remains legal when native is ahead")
	var stale: DrawingResult = doc.set_density(5, 3)
	check(not stale.ok and stale.code == "STALE_REVISION" and doc.revision == ahead and
		doc.density_numerator == 3 and doc.density_denominator == 2,
		"native-ahead density is failure-atomic")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required native classes loaded")
	var busy: Dictionary = setup_painted("t174-busy")
	var busy_doc: DrawingDocument = busy["doc"]
	var store: Object = busy["store"]
	if store == null:
		quit(1)
		return
	var source: PackedByteArray = source_bytes(store, busy["ink"])
	var token_count: int = int(store.call("stats").get("undo", -1))
	var held: Dictionary = store.call("begin_edit", busy["ink"], busy_doc.revision, false)
	check(bool(held.get("ok", false)), "native edit held")
	rejected_semantic(busy, "NATIVE_METADATA", "busy")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"native edit released")
	check(busy_doc.add_object(busy["objects"], {"position": Vector2(4, 5)}, "rejected").ok,
		"object addition retries")
	check(busy_doc.move_object(busy["objects"], "resident", Vector2(7, 8)).ok,
		"object movement retries")
	check(busy_doc.commit_text(busy["label"],
		text_element("Changed"), busy_doc.revision).ok, "text edit retries")
	check(busy_doc.commit_text("", text_element("New label"),
		busy_doc.revision, "root", "rejected-text").ok, "text creation retries")
	check(busy_doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == busy_doc.revision and
		int(store.call("stats").get("undo", -1)) == token_count and
		source_bytes(store, busy["ink"]) == source,
		"all successful semantic writes retain native history and canonical bytes")
	check(busy_doc.undo().ok and not busy_doc.has_node("rejected-text") and
		int(store.call("stats").get("revision", -1)) == busy_doc.revision,
		"text creation Undo uses shared revision")
	check(busy_doc.redo().ok and busy_doc.has_node("rejected-text") and
		int(store.call("stats").get("revision", -1)) == busy_doc.revision,
		"text creation Redo uses shared revision")
	check(paint(busy_doc, busy["ink"]).ok and busy_doc._native_raster_store == store,
		"later Hokusai edit reuses existing native store")
	var save_path: String = ProjectSettings.globalize_path("user://t174-semantic-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(busy_doc, save_path).ok,
		"native-authored semantic/raster mixture saves")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and (reopened.value as DrawingDocument).has_node("rejected-text") and
		(reopened.value as DrawingDocument).inspect_node(busy["label"]).text_value == "Changed" and
		(reopened.value as DrawingDocument).request_chunk(busy["ink"], "0,0").ok and
		((reopened.value as DrawingDocument).request_chunk(busy["ink"], "0,0").value as DrawingRasterTile).to_rgba8() ==
			(busy_doc.request_chunk(busy["ink"], "0,0").value as DrawingRasterTile).to_rgba8(),
		"Save/Open preserves semantic content and canonical native raster RGBA8")
	DirAccess.remove_absolute(save_path)
	var ahead: Dictionary = setup_painted("t174-ahead")
	var ahead_doc: DrawingDocument = ahead["doc"]
	var ahead_store: Object = ahead["store"]
	var old: int = ahead_doc.revision
	check(ahead_store.call("advance_metadata_revision", old, false),
		"native store advanced ahead of document")
	rejected_semantic(ahead, "STALE_REVISION", "ahead")
	check(int(ahead_store.call("stats").get("revision", -1)) == old + 1 and
		ahead_doc.revision == old and ahead_doc._native_raster_store == ahead_store,
		"native-ahead rejection leaves both revisions untouched")
	density_boundaries()
	var plain: DrawingDocument = DrawingDocument.new("t174-no-native", STRIDE)
	var plain_objects: String = str(plain.create_layer(DrawingLayerNode.OBJECTS, "Objects").value)
	check(plain.add_object(plain_objects, {"position": Vector2.ZERO}, "plain").ok and
		plain.move_object(plain_objects, "plain", Vector2(3, 4)).ok and
		plain.commit_text("", text_element("Plain"), plain.revision).ok and
		plain._native_raster_store == null, "native-absent semantic operations remain available")
	var plain_density: DrawingDocument = DrawingDocument.new("t174-plain-density", STRIDE)
	check(plain_density.set_density(3, 2).ok and plain_density.revision == 1,
		"native-absent density still works")
	print("T174_SEMANTIC_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T174_SEMANTIC_PASSED")
	quit(0 if failures == 0 else 1)
