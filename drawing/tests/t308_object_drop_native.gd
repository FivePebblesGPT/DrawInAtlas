extends "t304_selection_menu_native.gd"

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T308_NATIVE_FAILED: " + description)

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("T308_SCREENSHOTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func mouse(position: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = position
	event.global_position = position
	root.push_input(event, true)
	await frames(4)

func move_held(position: Vector2, relative: Vector2) -> void:
	root.warp_mouse(position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await frames(6)

func drag_to(app: Control, row: int, anchor: Vector2i, cancel: bool = false) -> void:
	var panel: DrawingAssetBrowserPanel = app.asset_browser
	app.inspector.scroll_vertical = int(app.inspector.get_v_scroll_bar().max_value)
	await frames(10)
	var start: Vector2 = panel.assets.get_global_rect().position + panel.assets.get_item_rect(row).get_center()
	var finish: Vector2 = app.canvas.global_position + app.canvas.pixel_to_position(Vector2(anchor) + Vector2(0.5, 0.5))
	root.warp_mouse(start)
	await frames(3)
	await mouse(start, true)
	await move_held(start + Vector2(18, 0), Vector2(18, 0))
	await move_held(finish, finish - start - Vector2(18, 0))
	check(root.gui_is_dragging(), "native browser row starts a GUI drag")
	if not cancel:
		await screenshot("object-drag" + ("-nested" if app.current_object() != null else ""))
	if cancel:
		await key(root, KEY_ESCAPE)
	await mouse(finish, false)
	await frames(8)
	check(not root.gui_is_dragging(), "GUI drag completes or cancels")

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1280, 900)
	var folder: String = OS.get_cache_dir().path_join("t308-" + DrawingDocument.new_id())
	var objects: String = folder.path_join("Objects")
	DirAccess.make_dir_recursive_absolute(objects)
	var path: String = objects.path_join("source.drawing")
	var source: DrawingDocument = DrawingDocument.new("t308-source", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-3, -2, 8, 8), 0xffdc5b1a).ok and edit.commit().ok, "signed source pixels")
	check(DrawingObjectEditorFile.save(source, path, "Copper", Vector2i(-3, -2), Rect2i(-3, -2, 8, 8), 1).ok, "portable source fixture")
	var hash: String = FileAccess.get_sha256(path)
	var original_source: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.initial_asset_browser_root = objects
	root.add_child(app)
	await frames(20)
	check(app.asset_browser.assets.item_count == 1, "visible authorized source")
	var doc: DrawingDocument = app.current_document()
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 4.0
	var anchor: Vector2i = Vector2i(-10, -7)
	var count: int = doc.layer_count()
	var rev: int = doc.revision
	var history: int = doc.history_position()
	await drag_to(app, 0, anchor, true)
	check(doc.layer_count() == count and doc.revision == rev and doc.history_position() == history, "cancel preserves state")
	await drag_to(app, 0, anchor)
	check(doc.layer_count() == count + 1 and doc.revision == rev + 1 and doc.history_position() == history + 1, "one native link transaction")
	if doc.layer_count() != count + 1:
		quit(1)
		return
	var id: String = app.selected_layer_node()
	var records: Array[Dictionary] = doc.layer_links(id)
	check(records.size() == 1 and records[0]["source_id"] == source.id and records[0]["position"] == anchor, "stable source and signed origin")
	var pixels: DrawingResult = DrawingRenderer.render(doc, Rect2i(anchor, Vector2i(8, 8)))
	check(pixels.ok and (pixels.value as Image).get_pixel(4, 4) == Color8(26, 91, 220), "canonical linked pixel render")
	await screenshot("object-placed")
	app._undo()
	check(not doc.has_node(id), "Undo removes link")
	app._redo()
	check(doc.has_node(id) and doc.layer_links(id) == records, "Redo restores link identity")
	var saved: String = folder.path_join("parent.drawing")
	app._save_file(saved)
	app._open_file(saved)
	await frames(12)
	doc = app.current_document()
	check(doc.has_node(id) and doc.layer_links(id) == records, "Save/Open retains stable records")
	pixels = DrawingRenderer.render(doc, Rect2i(anchor, Vector2i(8, 8)))
	check(pixels.ok and (pixels.value as Image).get_pixel(4, 4) == Color8(26, 91, 220), "reopen resolves authorized source")
	check(FileAccess.get_sha256(path) == hash, "source untouched")
	var token: Dictionary = app.asset_browser._drag_entry_for_row(0)
	var target: String = app.selected_layer_node()
	doc.set_locked(target, true)
	check(not app._check_object_drop(token, anchor).has_area(), "locked target rejected")
	doc.set_locked(target, false)
	doc.set_visibility(target, false)
	check(not app._check_object_drop(token, anchor).has_area(), "hidden target rejected")
	doc.set_visibility(target, true)
	app.new_object()
	await frames(12)
	canvas.camera = Vector2.ZERO
	canvas.zoom = 4.0
	canvas.queue_redraw()
	await frames(8)
	check(canvas.object_backdrop, "unbounded local Object checker enabled")
	await screenshot("object-background")
	doc = app.current_document()
	count = doc.layer_count()
	await drag_to(app, 0, anchor)
	check(doc.layer_count() == count + 1, "native drop inside local Object Editor")
	await screenshot("object-nested")
	check(app._check_object_drop(token, anchor).has_area(), "valid source can prepare next drop")
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	stream.seek_end()
	stream.store_string(" ")
	stream.close()
	rev = doc.revision
	app._commit_object_drop(token, anchor)
	check(doc.revision == rev, "stale source rejected before publication")
	stream = FileAccess.open(path, FileAccess.WRITE)
	stream.store_buffer(original_source)
	stream.close()
	app.asset_browser.refresh_assets()
	var nested_path: String = objects.path_join("parent.drawing")
	var parent_id: String = doc.id
	app._save_file(nested_path)
	await frames(12)
	check(FileAccess.file_exists(nested_path) and app.current_object().source_id == parent_id and not app.current_object().is_dirty(), "nested local source saved with same stable ID")
	doc = app.current_document()
	check(doc.linked_records().size() == 1, "nested publication preserves semantic link")
	var parent_entry: Dictionary = {}
	var parent_token: Dictionary = {}
	for i: int in range(app.asset_browser.assets.item_count):
		var offered: Dictionary = app.asset_browser._drag_entry_for_row(i)
		if offered.get("id") == parent_id:
			parent_token = offered
	for entry: Dictionary in app.asset_browser.index.entries:
		if entry["id"] == parent_id:
			parent_entry = entry
	check(not parent_token.is_empty() and not app._check_object_drop(parent_token, anchor).has_area(), "self source rejected in real local Object tab")
	var parent_thumb: DrawingResult = app.asset_browser.thumbnails.preview(app.asset_browser.index, parent_entry)
	check(parent_thumb.ok, "nested source thumbnail resolves graph")
	check(not DrawingAssetBrowserTransfer.export_file(app.asset_browser.index, parent_entry, folder.path_join("copy.drawing")).ok, "nested single-file export fails closed")
	var clone: DrawingDocument = DrawingDocument.new("clone-target")
	var detached: DrawingResult = doc.export_subtree(app.selected_layer_node())
	check(detached.ok and not clone.import_subtree(detached.value, DrawingDocument.ROOT_ID).ok, "unapproved detached link transfer rejected")
	var ordinary: DrawingDocument = DrawingDocument.new("t308-nesting-check")
	var linked: DrawingResult = ordinary.commit_linked_object(parent_token, app.asset_browser.index, Vector2i(5, 6), DrawingDocument.ROOT_ID, 0, ordinary.revision)
	check(linked.ok, "nested graph placement is authorized")
	var nested_pixels: DrawingResult = DrawingRenderer.render(ordinary, Rect2i(anchor + Vector2i(5, 6), Vector2i(8, 8)))
	check(nested_pixels.ok and (nested_pixels.value as Image).get_pixel(4, 4) == Color8(26, 91, 220), "recursive render composes signed origins")
	var unresolved: DrawingResult = DrawingFileIO.open(saved)
	check(unresolved.ok and not DrawingRasterExport.render(unresolved.value, Rect2i(anchor, Vector2i(8, 8))).ok, "reopen without authorization refuses raster export")
	var missing: DrawingResult = DrawingRenderer.render(unresolved.value, Rect2i(anchor - Vector2i(8, 8), Vector2i(16, 16)))
	check(missing.ok and missing.code == "LINK_MISSING", "unresolved link is visible NULL not silent blank")
	# Build a corrupt cycle as external bytes, not via the checked API.
	var cycle_node: String = str(source.create_layer(DrawingLayerNode.OBJECTS, "Corrupt external cycle").value)
	source._nodes[cycle_node].objects["cycle-id"] = {"kind": DrawingDocument.LINK_KIND, "source_id": parent_id, "position": Vector2i.ZERO}
	check(DrawingObjectEditorFile.save(source, path, "Copper", Vector2i(-3, -2), Rect2i(-3, -2, 8, 8), 2).ok, "external cycle fixture")
	app.asset_browser.refresh_assets()
	var rejected: DrawingResult = DrawingLinkedObjects.resolve(ordinary, app.asset_browser.index)
	check(not rejected.ok and rejected.code == "LINK_CYCLE", "transitive cycle rejected")
	check(not app.asset_browser.thumbnails.contains(parent_entry) or not app.asset_browser.thumbnails.preview(app.asset_browser.index, parent_entry).ok, "child change invalidates parent thumbnail")
	stream = FileAccess.open(path, FileAccess.WRITE)
	stream.store_buffer(original_source)
	stream.close()
	app.asset_browser.refresh_assets()
	var forged: Dictionary = token.duplicate(true)
	forged["path"] = folder.path_join("outside.drawing")
	check(DrawingLinkedObjects.entry_for_token(app.asset_browser.index, forged).is_empty(), "forged path rejected")
	var victim: DrawingDocument = DrawingDocument.new("t308-unsafe-check")
	var original_revision: int = victim.revision
	check(not victim.commit_linked_object(forged, app.asset_browser.index, Vector2i.ZERO, DrawingDocument.ROOT_ID, 0, victim.revision).ok and victim.revision == original_revision, "model authorization cannot be bypassed")
	var registry_marker: String = objects.path_join("Test.atlas-object-index.json")
	stream = FileAccess.open(registry_marker, FileAccess.WRITE)
	stream.store_string("{}")
	stream.close()
	check(not victim.commit_linked_object(token, app.asset_browser.index, Vector2i.ZERO, DrawingDocument.ROOT_ID, 0, victim.revision).ok and victim.revision == original_revision, "loose source inside Atlas registry root rejected")
	DirAccess.remove_absolute(registry_marker)
	print("T308_NATIVE: %d passed; %d failed" % [checks - failures, failures])
	if failures == 0:
		print("T308_NATIVE_PASSED")
	quit(1 if failures else 0)
