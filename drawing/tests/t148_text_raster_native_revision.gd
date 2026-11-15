extends SceneTree
## T-148: text/raster kind transitions preserve unrelated Rust ownership only
## when the converted layer ID has never held native source or history.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_TEXT_RASTER_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String, center: Vector2) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var opened: DrawingResult = session.begin_native_stroke(brush, "NativeHard", "",
		8.0, 0xff5599cc, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not opened.ok:
		session.cancel()
		return opened
	var painted: DrawingResult = session.paint_path_native(
		PackedVector2Array([center, center + Vector2(10, 0)]), 0xff5599cc, false, null)
	if not painted.ok:
		session.cancel()
		return painted
	return session.commit()


func text_element() -> DrawingTextElement:
	var element: DrawingTextElement = DrawingTextElement.new()
	element.content = "Rust + Text"
	element.position = Vector2i(-18, -17)
	element.font_size = 20
	return element


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native store registered")
	var doc: DrawingDocument = DrawingDocument.new("text-raster-owner", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(stroke(doc, ink, Vector2(9, 10)).ok, "first native Brush creates history")
	var store: Object = doc._native_raster_store
	var original: PackedByteArray = (doc.request_chunk(ink, "0,0").value as DrawingRasterTile).to_rgba8()
	var original_undo: int = int(store.call("stats").get("undo", -1))
	var imported: int = int(store.call("stats").get("bytes_imported", -1))
	var created: DrawingResult = doc.commit_text("", text_element(), doc.revision,
		"root", "text-unowned")
	check(created.ok and String(created.value) == "text-unowned", "semantic text committed")
	if not created.ok:
		print("T148_TEXT_RASTER_FAILED (font source unavailable)")
		quit(1)
		return
	var text_id: String = String(created.value)
	var view: Rect2i = Rect2i(-32, -32, 160, 128)
	var preview: DrawingResult = DrawingRenderer.render(doc, view)
	check(preview.ok, "semantic source renders")
	var before_revision: int = doc.revision
	var converted: DrawingResult = doc.rasterize_text(text_id, doc.revision)
	check(converted.ok and doc.revision == before_revision + 1 and
		doc.inspect_node(text_id).kind == DrawingLayerNode.RASTER,
		"text converts to RGBA8 raster in one document revision")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == original_undo,
		"unreferenced rasterization preserves unrelated Rust history")
	check(int(store.call("stats").get("bytes_imported", -1)) == imported,
		"text rasterization does not reimport unrelated native source")
	var post: DrawingResult = DrawingRenderer.render(doc, view)
	check(post.ok and preview.ok and
		(post.value as Image).get_data() == (preview.value as Image).get_data(),
		"semantic and rasterized preview are byte-identical")
	check(stroke(doc, ink, Vector2(37, 38)).ok and doc._native_raster_store == store,
		"second Brush uses persistent Rust owner")
	check(int(store.call("stats").get("undo", -1)) == original_undo + 1 and
		int(store.call("stats").get("bytes_imported", -1)) == imported,
		"second Brush adds native token without source reload")
	check(doc.undo().ok, "Undo newest Brush")
	check(doc.undo().ok and doc.inspect_node(text_id).kind == DrawingLayerNode.TEXT,
		"Undo rasterization restores semantic layer")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == original_undo,
		"raster/text Undo preserves earlier Rust history")
	check(doc.undo().ok and not doc.has_node(text_id), "Undo text creation")
	check(doc.undo().ok and doc.has_node(ink), "Undo original native Brush across text edits")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 0,
		"Rust and document revisions stay synchronized after multiple Undo")
	check(doc.redo().ok and doc.redo().ok and doc.redo().ok and doc.redo().ok and
		doc.inspect_node(text_id).kind == DrawingLayerNode.RASTER,
		"Redo Brush, text creation, rasterization and Brush")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == original_undo + 1,
		"native history tokens survive complete Undo/Redo replay")
	# The newly rasterized layer was not imported at conversion time. Its
	# first native Brush must import the real text RGBA8 before painting it.
	var text_tile: String = "0,0"
	var before_text_paint: DrawingResult = doc.request_chunk(text_id, text_tile)
	check(before_text_paint.ok and before_text_paint.value != null,
		"rasterized text exposes signed-tile RGBA8 source")
	var original_text_bytes: PackedByteArray = (before_text_paint.value as DrawingRasterTile).to_rgba8()
	check(stroke(doc, text_id, Vector2(28, 28)).ok and doc._native_raster_store == store,
		"first native Brush of rasterized text keeps persistent store")
	var changed_text_bytes: PackedByteArray = (doc.request_chunk(text_id, text_tile).value as DrawingRasterTile).to_rgba8()
	check(changed_text_bytes != original_text_bytes and
		int(store.call("stats").get("bytes_imported", -1)) > imported,
		"first text Brush imports glyph tiles and changes source RGBA8")
	check(doc.undo().ok and
		(doc.request_chunk(text_id, text_tile).value as DrawingRasterTile).to_rgba8() == original_text_bytes,
		"text-derived native Brush Undo restores exact glyph bytes")
	check(doc.redo().ok and
		(doc.request_chunk(text_id, text_tile).value as DrawingRasterTile).to_rgba8() == changed_text_bytes,
		"text-derived native Brush Redo restores exact painted bytes")
	var save_path: String = ProjectSettings.globalize_path("user://t148-text-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "mixed text/native document saves")
	var loaded: DrawingResult = DrawingFileIO.open(save_path)
	check(loaded.ok, "saved document opens")
	if loaded.ok:
		var opened_doc: DrawingDocument = loaded.value as DrawingDocument
		check(opened_doc.inspect_node(text_id).kind == DrawingLayerNode.RASTER and
			(opened_doc.request_chunk(ink, "0,0").value as DrawingRasterTile).to_rgba8() ==
				(doc.request_chunk(ink, "0,0").value as DrawingRasterTile).to_rgba8() and
			(opened_doc.request_chunk(text_id, text_tile).value as DrawingRasterTile).to_rgba8() ==
				changed_text_bytes,
			"Save/Open preserves text glyph bytes and both native paint sources")
	DirAccess.remove_absolute(save_path)

	# Once text-derived raster source enters Rust, the inverse kind change
	# cannot pretend that layer is unreferenced. Checked rebase is required.
	var guarded: DrawingDocument = DrawingDocument.new("text-native-history", STRIDE)
	var base: String = str(guarded.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(stroke(guarded, base, Vector2(9, 10)).ok, "negative control owns a raster source")
	var guard_store: Object = guarded._native_raster_store
	var label: String = str(guarded.commit_text("", text_element(), guarded.revision).value)
	check(guarded.rasterize_text(label, guarded.revision).ok and
		stroke(guarded, label, Vector2(35, 35)).ok,
		"text-derived raster is explicitly imported on first native paint")
	check(guarded.undo().ok and guarded.inspect_node(label).kind == DrawingLayerNode.RASTER,
		"Undo text-derived native Brush")
	check(guarded.undo().ok and guarded.inspect_node(label).kind == DrawingLayerNode.TEXT and
		int(guard_store.call("stats").get("revision", -1)) < guarded.revision,
		"previously native-owned layer correctly rejects unreferenced replay")
	check(stroke(guarded, base, Vector2(36, 37)).ok and
		guarded._native_raster_store == guard_store and
		int(guard_store.call("stats").get("revision", -1)) == guarded.revision and
		int(guard_store.call("stats").get("undo", -1)) == 1,
		"next Brush rebases stale source and clears retired native history")
	check(not guarded.can_redo(), "new Brush invalidates detached text-raster Redo")
	print("T148_TEXT_RASTER_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
