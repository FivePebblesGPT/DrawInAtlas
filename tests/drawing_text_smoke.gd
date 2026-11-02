extends SceneTree
## T-058 isolated semantic text, renderer, undo/redo, rasterization and codec.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, what: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T-058 FAILED: " + what)


func _run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("text-test", 64)
	var group: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP, "Labels")
	var parent_id: String = group.value
	var original: int = doc.layer_count()
	var empty: DrawingTextElement = DrawingTextElement.new()
	_check(not doc.commit_text("", empty, doc.revision, parent_id).ok, "Empty content rejected")
	_check(doc.layer_count() == original, "Empty commit never creates layer")
	var element: DrawingTextElement = DrawingTextElement.new()
	element.content = "Hello\nCanvas"
	element.position = Vector2i(-35, -29)
	element.font_size = 20
	var bounds: DrawingResult = DrawingTextRaster.bounds(element)
	_check(bounds.ok, "Bundled font shapes")
	if not bounds.ok:
		print("DRAWING_TEXT_FAILED: " + bounds.message)
		quit(1)
		return
	var layer_result: DrawingResult = doc.commit_text("", element, doc.revision, parent_id, "text-label-1")
	_check(layer_result.ok, "Text commits once")
	var layer_id: String = String(layer_result.value)
	_check(doc.layer_count() == original + 1 and doc.history_length() == 1, "Single layer and undo event")
	_check(doc.inspect_node(layer_id).text_element.content == element.content, "One semantic element")
	var area: Rect2i = Rect2i(Vector2i(-64, -64), Vector2i(180, 120))
	var rendered: DrawingResult = DrawingRenderer.render(doc, area)
	_check(rendered.ok, "Text compositor renders viewport")
	if not rendered.ok:
		print("DRAWING_TEXT_FAILED: " + rendered.message)
		quit(1)
		return
	var image: Image = rendered.value
	var present: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.01:
				present += 1
	_check(present > 20, "Glyphs yield visible nonblank alpha")
	var conversion: DrawingResult = doc.rasterize_text(layer_id, doc.revision)
	_check(conversion.ok, "Explicit rasterization succeeded")
	if not conversion.ok:
		print("DRAWING_TEXT_FAILED: " + conversion.message)
		quit(1)
		return
	_check(doc.inspect_node(layer_id).kind == DrawingLayerNode.RASTER, "Converted content is ordinary raster")
	var raster_preview: DrawingResult = DrawingRenderer.render(doc, area)
	_check(raster_preview.ok, "Raster renders")
	if raster_preview.ok:
		_check(image.get_data() == (raster_preview.value as Image).get_data(), "Editable/rasterized composite exact equality")
	_check(doc.undo().ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.TEXT, "Undo restores editability")
	_check(doc.redo().ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.RASTER, "Redo restores pixels")
	_check(doc.undo().ok and doc.undo().ok and not doc.has_node(layer_id), "Undo initial commit removes layer")
	_check(doc.redo().ok and doc.has_node(layer_id), "Redo uses stable text ID")
	var saved: String = OS.get_cache_dir().path_join("drawing-text-t058.drawing")
	var write: DrawingResult = DrawingFileIO.save(doc, saved)
	_check(write.ok, "Text save succeeds")
	var reopened: DrawingResult = DrawingFileIO.open(saved)
	_check(reopened.ok, "Text reopen succeeds")
	if reopened.ok:
		var reloaded: DrawingDocument = reopened.value
		_check(reloaded.inspect_node(layer_id).text_element.content == element.content, "Reopen retains text content")
		_check(reloaded.inspect_node(layer_id).text_element.position == element.position, "Reopen retains signed position")
	var unknown: DrawingTextElement = element.detached_copy()
	unknown.font_id = "nonexistent-system-font"
	_check(not doc.commit_text("", unknown, doc.revision, parent_id).ok, "Unknown font blocks mutation")
	DirAccess.remove_absolute(saved)
	_edge_cases()
	print("DRAWING_TEXT_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _edge_cases() -> void:
	var doc: DrawingDocument = DrawingDocument.new("edge-text", 32)
	var base: DrawingTextElement = DrawingTextElement.new()
	base.content = "Label A"
	base.position = Vector2i(-250, 90)
	var created: DrawingResult = doc.commit_text("", base, doc.revision)
	_check(created.ok and doc.is_dirty(), "New semantic commit dirties an initially clean document")
	var layer_id: String = String(created.value)
	var copied_out: DrawingResult = doc.export_subtree(layer_id)
	_check(copied_out.ok, "Export text subtree")
	var target: DrawingDocument = DrawingDocument.new("copy-text", 32)
	var copied_in: DrawingResult = target.import_subtree(copied_out.value, DrawingDocument.ROOT_ID)
	_check(copied_in.ok and copied_in.value != layer_id, "Copy mints different layer ID")
	_check(target.inspect_node(String(copied_in.value)).text_element.to_record() == base.to_record(),
		"Copied label is semantically and geometrically identical")
	var modified: DrawingTextElement = base.detached_copy()
	modified.content = "Label B"
	modified.font_id = "lato-bold-v1"
	modified.font_size = 30
	modified.color_rgba = 0x8800ff00
	modified.alignment = "right"
	modified.angle = 0.2
	modified.scale = Vector2(1.25, 1.1)
	_check(doc.commit_text(layer_id, modified, doc.revision).ok, "Style, layout and transform edit")
	_check(doc.inspect_node(layer_id).text_element.font_id == "lato-bold-v1", "Bold selected by stable font identity")
	_check(doc.inspect_node(layer_id).text_element.content == "Label B", "Content edit replaces element")
	_check(target.inspect_node(String(copied_in.value)).text_element.content == "Label A", "Copy remains detached")
	var pre_revision: int = doc.revision
	_check(doc.commit_text(layer_id, modified, doc.revision).ok and doc.revision == pre_revision,
		"Repeated identical edit makes no history entry")
	var bad_revision: DrawingResult = doc.commit_text(layer_id, base, doc.revision - 1)
	_check(not bad_revision.ok and bad_revision.code == "STALE_REVISION", "Concurrent edit is rejected")
	_check(doc.undo().ok and doc.inspect_node(layer_id).text_element.content == "Label A", "Undo text edit restores text and style")
	_check(doc.redo().ok and doc.inspect_node(layer_id).text_element.font_id == "lato-bold-v1", "Redo restores font style")
	var rotated: DrawingResult = DrawingTextRaster.bounds(modified)
	_check(rotated.ok and rotated.value.has_area(), "Rotated and scaled text has bounds")
	var view: DrawingResult = DrawingRenderer.render(doc, Rect2i(Vector2i(-440, 0), Vector2i(240, 170)))
	_check(view.ok, "Rotated text rasterizes onto bounded viewport")
	var invisible: DrawingResult = DrawingRenderer.render(doc, Rect2i(Vector2i(1000, 1000), Vector2i(32, 32)))
	_check(invisible.ok and (invisible.value as Image).get_pixel(0, 0).a == 0.0,
		"Distant viewport culls text cleanly")
	_check(doc.set_locked(layer_id, true).ok, "Lock text layer")
	pre_revision = doc.revision
	var locked: DrawingResult = doc.commit_text(layer_id, base, doc.revision)
	_check(not locked.ok and doc.revision == pre_revision, "Locked text rejects edits without mutation")
	_check(not doc.rasterize_text(layer_id, doc.revision).ok, "Locked text rejects rasterization")
	_check(doc.set_locked(layer_id, false).ok, "Unlock text layer")
	_check(doc.rename_layer(layer_id, "Chapter label").ok and doc.inspect_node(layer_id).name == "Chapter label", "Rename reuses stable ID")
	var raster: DrawingResult = doc.rasterize_text(layer_id, doc.revision)
	_check(raster.ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.RASTER, "Rotated text rasterized")
	var pixels: int = 0
	for key: String in doc.tile_keys(layer_id):
		var coords: PackedStringArray = key.split(",")
		var tile: DrawingResult = doc.request_chunk_at(layer_id, int(coords[0]), int(coords[1]))
		if tile.ok:
			for y: int in range(doc.tile_stride):
				for x: int in range(doc.tile_stride):
					if ((tile.value as DrawingRasterTile).get_rgba(x, y) >> 24) != 0:
						pixels += 1
	_check(pixels > 0, "Raster pixels are materialized across signed tiles")
	var paint: DrawingResult = doc.begin_edit(layer_id, doc.revision)
	_check(paint.ok, "Rasterized layer supports normal raster edits")
	if paint.ok:
		var edit: DrawingEditSession = paint.value
		_check(edit.apply_region(Rect2i(-1, -1, 1, 1), PackedByteArray([1, 2, 3, 255])).ok and edit.commit().ok,
			"Paint rasterized layer through generic edit API")
	_check(doc.undo().ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.RASTER, "Undo raster edit independently")
	_check(doc.undo().ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.TEXT,
		"Undo text rasterization restores semantic element")
	_check(doc.redo().ok and doc.inspect_node(layer_id).kind == DrawingLayerNode.RASTER, "Redo rasterization from saved bytes")
	# Font glyph coverage is explicit; an unsupported code point never becomes invisible data.
	var no_glyph: DrawingTextElement = DrawingTextElement.new()
	no_glyph.content = "命"
	var missing: DrawingResult = DrawingTextRaster.bounds(no_glyph)
	_check(missing.ok and missing.code == "GLYPH_FALLBACK" and missing.message.contains("U+"),
		"Unsupported glyph visibly substituted with explicit warning")
	var huge: DrawingDocument = DrawingDocument.new("huge-text", 32)
	var long_label: DrawingTextElement = DrawingTextElement.new()
	long_label.content = "W".repeat(12000)
	long_label.font_size = 256
	var pending: DrawingResult = huge.commit_text("", long_label, huge.revision)
	_check(pending.ok, "Large text can remain editable without raster allocation")
	if pending.ok:
		var attempt: DrawingResult = huge.rasterize_text(String(pending.value), huge.revision)
		_check(not attempt.ok and attempt.code == "RASTER_LIMIT", "Large rasterization rejects unsafe allocation")
		_check(huge.inspect_node(String(pending.value)).kind == DrawingLayerNode.TEXT, "Rasterization failure leaves source editable")
	var style_doc: DrawingDocument = DrawingDocument.new("style-text", 32)
	var italic: DrawingTextElement = DrawingTextElement.new()
	italic.content = "Italic words"
	italic.font_id = "lato-italic-v1"
	var inserted: DrawingResult = style_doc.commit_text("", italic, style_doc.revision)
	_check(inserted.ok, "Italic has licensed bundled font")
	var payload: DrawingResult = DrawingFileIO.encode(style_doc)
	_check(payload.ok, "Portable codec embeds selected font")
	if payload.ok:
		var record: Dictionary = payload.value
		_check(record["font_assets"].has("lato-italic-v1") and 			(record["font_assets"]["lato-italic-v1"] as Dictionary).has("license"),
			"Font bytes and license included in portable save")
		var opened: DrawingResult = DrawingFileIO.decode(record)
		_check(opened.ok and (opened.value as DrawingDocument).inspect_node(String(inserted.value)).text_element.font_id == "lato-italic-v1",
			"Portable font style survives round trip")
		var tampered: Dictionary = record.duplicate(true)
		tampered["font_assets"]["lato-italic-v1"]["sha256"] = "0".repeat(64)
		_check(DrawingFileIO.decode(tampered).code == "FONT_CORRUPT", "Tampered font digest rejected")
		var missing_license: Dictionary = record.duplicate(true)
		missing_license["font_assets"]["lato-italic-v1"].erase("license")
		_check(DrawingFileIO.decode(missing_license).code == "FONT_LICENSE", "Font missing redistribution license rejected")
		var missing_asset: Dictionary = record.duplicate(true)
		missing_asset["font_assets"].clear()
		_check(DrawingFileIO.decode(missing_asset).code == "FONT_MISSING", "Missing referenced font rejected")
	_check(huge.undo().ok and not huge.has_node(String(pending.value)), "Large text can undo normally")
