extends SceneTree
## T-175: importing a semantic-only tree may not bypass a busy/stale Rust store.

const STRIDE: int = 64
const INK: int = 0xff4268ac
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T175_IMPORT_FAILED: " + description)


func stroke(doc: DrawingDocument, layer: String) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(
		"res://addons/drawing/brushes/hard_round.myb")
	var begun: DrawingResult = session.begin_native_stroke(brush, preset,
		8.0, INK, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not begun.ok:
		session.cancel()
		return begun
	var painted: DrawingResult = session.paint_path_native(PackedVector2Array(
		[Vector2(9, 8), Vector2(19, 8)]), INK, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func native_bytes(store: Object, ink: String) -> PackedByteArray:
	return store.call("read_tile", ink, 0, 0, false).get("bytes", PackedByteArray())


func make_semantic_source() -> Dictionary:
	var donor: DrawingDocument = DrawingDocument.new("t175-donor", STRIDE)
	var group: String = str(donor.create_layer(DrawingLayerNode.GROUP,
		"Semantic bundle", "root", "bundle").value)
	var objects: String = str(donor.create_layer(DrawingLayerNode.OBJECTS,
		"Placed objects", group, "props").value)
	var text: String = str(donor.create_layer(DrawingLayerNode.TEXT,
		"Label", group, "note").value)
	check(donor.add_object(objects, {"position": Vector2(3, 4)}, "marker").ok,
		"donor has a semantic object")
	var element: DrawingTextElement = DrawingTextElement.new()
	element.content = "Imported label"
	element.font_size = 20
	check(donor.commit_text(text, element, donor.revision).ok,
		"donor has editable semantic text")
	var result: DrawingResult = donor.export_subtree(group)
	check(result.ok, "semantic-only subtree export succeeds")
	return {"donor": donor, "snapshot": result.value, "group": group,
		"objects": objects, "text": text}


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required Rust extension loaded")
	var data: Dictionary = make_semantic_source()
	var doc: DrawingDocument = DrawingDocument.new("t175-target", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	check(stroke(doc, ink).ok, "Hokusai stroke attaches native history")
	var store: Object = doc._native_raster_store
	check(store != null, "native tile store is resident")
	if store == null:
		quit(1)
		return
	var rgba: PackedByteArray = native_bytes(store, ink)
	var undo_count: int = int(store.call("stats").get("undo", -1))
	var base: int = doc.revision
	var children: Array[String] = doc.list_children("root")
	var cursor: int = doc.history_position()
	var history_count: int = doc.history_length()
	var untracked: int = doc._untracked_revision
	var dirty: bool = doc.is_dirty()

	var held: Dictionary = store.call("begin_edit", ink, base, false)
	check(bool(held.get("ok", false)), "native stroke transaction held")
	var refused: DrawingResult = doc.import_subtree(data.snapshot, "root", true)
	check(not refused.ok and refused.code == "NATIVE_METADATA",
		"busy native store rejects semantic subtree import")
	check(doc.revision == base and doc.list_children("root") == children and
		not doc.has_node(data.group) and not doc.has_node(data.objects),
		"rejected import installs no nodes and advances no document revision")
	check(doc._untracked_revision == untracked and doc.is_dirty() == dirty and
		doc.history_position() == cursor and doc.history_length() == history_count,
		"rejected import does not alter dirty or history cursors")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == base and
		int(store.call("stats").get("undo", -1)) == undo_count and
		native_bytes(store, ink) == rgba,
		"rejection retains Rust authority and byte-exact paint")
	var transfer: DrawingResult = DrawingDocument.transfer_subtree(data.donor,
		doc, data.group, "root", data.donor.revision, doc.revision, false)
	check(not transfer.ok and doc.list_children("root") == children and
		data.donor.has_node(data.group),
		"standalone Copy refuses busy destination without half-publish")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"native transaction released for retry")

	var added: DrawingResult = doc.import_subtree(data.snapshot, "root", true)
	check(added.ok and str(added.value) == data.group and
		doc.has_node(data.group) and doc.has_node(data.objects) and doc.has_node(data.text),
		"semantic group and all descendants publish atomically")
	check(doc.list_children(data.group) == Array([data.objects, data.text]) and
		(doc.inspect_node(data.objects) as DrawingLayerNode).objects.has("marker") and
		(doc.inspect_node(data.text) as DrawingLayerNode).text_value == "Imported label",
		"semantic values and hierarchy survive import")
	check(doc.revision == base + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == undo_count and
		native_bytes(store, ink) == rgba and doc._native_raster_store == store,
		"successful import preserves native history and source bytes")
	check(data.donor.has_node(data.group) and
		(data.donor.inspect_node(data.text) as DrawingLayerNode).text_value == "Imported label",
		"source tree remains unchanged")
	check(doc.undo().ok and int(store.call("stats").get("revision", -1)) == doc.revision,
		"historical native Brush Undo works after semantic import")
	check(doc.redo().ok and native_bytes(store, ink) == rgba and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"historical native Brush Redo retains exact bytes")
	check(stroke(doc, ink).ok and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"subsequent Hokusai stroke keeps the original Rust store")
	var save_path: String = ProjectSettings.globalize_path(
		"user://t175-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "mixed semantic/native document saves")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and
		(reopened.value as DrawingDocument).has_node(data.group) and
		(reopened.value as DrawingDocument).has_node(data.text) and
		(reopened.value as DrawingDocument).request_chunk(ink, "0,0").ok and
		((reopened.value as DrawingDocument).request_chunk(ink, "0,0").value as DrawingRasterTile).to_rgba8() ==
			(doc.request_chunk(ink, "0,0").value as DrawingRasterTile).to_rgba8(),
		"Save/Open preserves semantic tree and canonical raster")
	DirAccess.remove_absolute(save_path)

	# Native ahead must not detach the store or publish even a semantic-only node.
	var before_ahead: int = doc.revision
	check(bool(store.call("advance_metadata_revision", before_ahead, false)),
		"advance Rust independently for stale-revision control")
	var ahead_undo_count: int = int(store.call("stats").get("undo", -1))
	var ahead_bytes: PackedByteArray = native_bytes(store, ink)
	var stale: DrawingResult = doc.import_subtree(data.snapshot, "root", false)
	check(not stale.ok and stale.code == "STALE_REVISION" and
		doc.revision == before_ahead and doc._native_raster_store == store,
		"native-ahead semantic import fails without detaching Rust")
	check(int(store.call("stats").get("revision", -1)) == before_ahead + 1 and
		int(store.call("stats").get("undo", -1)) == ahead_undo_count and
		native_bytes(store, ink) == ahead_bytes and
		doc.list_children("root") == Array([ink, data.group]),
		"native-ahead failure leaves tree and Rust revision unchanged")

	var plain: DrawingDocument = DrawingDocument.new("t175-plain", STRIDE)
	var plain_import: DrawingResult = plain.import_subtree(data.snapshot, "root", true)
	check(plain_import.ok and plain.has_node(data.group) and
		plain._native_raster_store == null and plain.revision == 1,
		"historical native-absent semantic import still works")
	var retry_target: DrawingDocument = DrawingDocument.new("t175-copy-target", STRIDE)
	var transferred: DrawingResult = DrawingDocument.transfer_subtree(data.donor,
		retry_target, data.group, "root", data.donor.revision,
		retry_target.revision, false)
	check(transferred.ok and retry_target.has_node(str(transferred.value)) and
		data.donor.has_node(data.group),
		"standalone semantic Copy publishes normally when destination is eligible")

	print("T175_SEMANTIC_IMPORT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T175_SEMANTIC_IMPORT_PASSED")
	quit(0 if failures == 0 else 1)
