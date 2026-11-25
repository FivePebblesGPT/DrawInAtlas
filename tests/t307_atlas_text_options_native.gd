extends "res://drawing/tests/t307_text_options_native.gd"
## Hosted text authoring shares detached preview and private object history.

func delete_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for folder: String in dir.get_directories():
		delete_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "actual display and mandatory native tiles required")
		quit(1)
		return
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t307-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t307-object", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Ground").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-80, -48, 160, 96), 0xffdce8f5).ok and edit.commit().ok, "ground fixture")
	var created: DrawingResult = library.create_asset(source, "Map sign")
	check(created.ok, "source fixture published")
	if not created.ok:
		quit(1)
		return
	var source_id: String = str(created.value)
	var source_path: String = library._absolute(str(library.asset_info(source_id)["path"]))
	var digest: String = FileAccess.get_sha256(source_path)
	var old_undo: bool = editor.edits.can_undo()
	var old_dirty: bool = editor.edits.is_dirty()
	editor._open_object_source(source_id)
	var window: AtlasObjectEditorWindow = editor.object_editor_window
	check(window != null and window.visible, "actual Atlas Object Editor opens")
	if window == null or not window.visible:
		quit(1)
		return
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	var session: DrawingObjectEditorSession = app.current_object()
	check(session.set_frame(Vector2i.ZERO, Rect2i(-80, -48, 160, 96)).ok, "finite private object frame")
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 2.0
	canvas.show_pixel_grid = false
	canvas.show_grid = false
	canvas.queue_redraw()
	await frames(8)
	var doc: DrawingDocument = app.current_document()
	var count: int = doc.layer_count()
	var rev: int = doc.revision
	var history: int = doc.history_position()
	await click(window, app.tool_buttons["Text"].get_global_rect().get_center())
	await click(window, canvas.global_position + canvas.pixel_to_position(Vector2(-52.5, -27.5)))
	await frames(10)
	check(app.text_panel.is_visible_in_tree() and app.text_edit.editable and app.text_edit.has_focus(), "hosted Text pointer opens focused panel")
	if not app.text_edit.editable:
		quit(1)
		return
	set_content(app, "North Gate")
	app.text_size.value = 21
	app.text_color.color = Color8(42, 74, 130)
	app.text_color.color_changed.emit(app.text_color.color)
	app._text_style_from_menu("Bold")
	await frames(10)
	var view: Rect2i = Rect2i(-80, -48, 160, 96)
	var preview: PackedByteArray = render_bytes(app, view, true)
	check(render_bytes(app, view, false) != preview, "hosted detached glyph preview")
	check(doc.revision == rev and doc.layer_count() == count and doc.history_position() == history, "draft preserves native history")
	var displayed: PackedByteArray = frame_bytes(app, view)
	var directory: String = OS.get_environment("T307_SCREENSHOTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		window.get_texture().get_image().save_png(directory.path_join("text-atlas.png"))
	await click(window, app.text_apply.get_global_rect().get_center())
	await frames(8)
	check(doc.layer_count() == count + 1 and doc.revision == rev + 1 and doc.history_position() == history + 1, "hosted Apply one edit")
	var id: String = app.current_layer()
	var node: DrawingLayerNode = doc.inspect_node(id)
	check(node != null and node.kind == DrawingLayerNode.TEXT and node.text_element.content == "North Gate" and node.text_element.font_id == "lato-bold-v1", "hosted semantic text")
	check(render_bytes(app, view, false) == preview and frame_bytes(app, view) == displayed, "hosted preview matches commit and framebuffer")
	app._edit_selected_text()
	set_content(app, "Other gate")
	await frames(5)
	await click(window, app.text_cancel.get_global_rect().get_center())
	await frames(5)
	check(canvas.text_preview.is_empty() and render_bytes(app, view, false) == preview, "hosted Cancel restores committed text")
	app._undo()
	check(not doc.has_node(id), "hosted Undo removes text")
	app._redo()
	check(doc.has_node(id), "hosted Redo restores text")
	check(FileAccess.get_sha256(source_path) == digest and editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty, "private text edit preserves source and Atlas history")
	print("T307_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T307_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	delete_tree(folder)
	quit(1 if failures else 0)
