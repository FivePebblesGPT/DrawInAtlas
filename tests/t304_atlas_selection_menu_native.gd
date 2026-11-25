extends "res://drawing/tests/t304_selection_menu_native.gd"
## Native popup routing in the real Atlas Object Editor.

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
		check(false, "native display and tiles required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1340, 900)
	var folder: String = OS.get_cache_dir().path_join("t304-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t304-object", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-2, 0, 4, 2), 0xff0000ff).ok and edit.commit().ok, "source contains signed seam")
	var created: DrawingResult = library.create_asset(source, "Selection object")
	check(created.ok, "Atlas publishes fixture")
	if not created.ok:
		quit(1)
		return
	var source_id: String = str(created.value)
	var source_path: String = library._absolute(str(library.asset_info(source_id)["path"]))
	var digest: String = FileAccess.get_sha256(source_path)
	var old_undo: bool = editor.edits.can_undo()
	var old_dirty: bool = editor.edits.is_dirty()
	editor._open_object_source(source_id)
	var opened: bool = editor.object_editor_window != null and editor.object_editor_window.visible
	check(opened, "actual Atlas Object Editor window opens source")
	if not opened:
		quit(1)
		return
	var window: AtlasObjectEditorWindow = editor.object_editor_window
	var app: Control = window.workspace
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	await frames(12)
	var top: Control = app.top_bar
	var selection: PopupMenu = top._menus[6].get_popup()
	var direct: PopupMenu = selection.get_item_submenu_node(0) as PopupMenu
	var overflow: PopupMenu = top._radio_submenus[Vector2i(6, 0)][1]
	var draft: DrawingDocument = app.current_document()
	var revision: int = draft.revision
	var history: int = draft.history_length()
	await click(window, app.tool_buttons["Select"].get_global_rect().get_center())
	check(app.active_tool == "Select", "Atlas pointer selects rail tool")
	# The Object Editor may be narrower than the standalone window.
	if top._menus[6].visible:
		await click(window, top._menus[6].get_global_rect().get_center())
		check(selection.visible, "hosted pointer opens Selection")
		selection.set_focused_item(0)
		await popup_key("Right")
		check(direct.visible, "hosted keyboard opens submenu")
		await screenshot("selection-atlas")
		if direct.visible:
			direct.set_focused_item(2)
			await popup_key("Return")
	else:
		var more: PopupMenu = top.more_menu.get_popup()
		var index: int = find_item(more, "Selection › Selection mode")
		check(index >= 0, "hosted More retains Selection mode")
		await click(window, top.more_menu.get_global_rect().get_center())
		check(more.visible, "hosted pointer opens More")
		if index >= 0:
			more.set_focused_item(index)
			await popup_key("Right")
			check(overflow.visible, "hosted keyboard opens overflow submenu")
			await screenshot("selection-atlas")
			if overflow.visible:
				overflow.set_focused_item(2)
				await popup_key("Return")
	check_mode(app, direct, overflow, 2)
	var canvas: Control = app.canvas
	canvas.set_selection_mask(DrawingSelection.new(Rect2i(-2, 0, 4, 2), true))
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-0.5, 0.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(0.5, 1.5)))
	check(canvas.selection_mask.allows(Vector2i(-2, 0)) and not canvas.selection_mask.allows(Vector2i(-1, 0)),
		"hosted Subtract mode affects real signed mask")
	check(draft.revision == revision and draft.history_length() == history and not canvas.snap_to_grid,
		"hosted menu and selection do not change draft content or snapping")
	await key(window, KEY_D, true)
	check(not canvas.selection_mask.enabled, "hosted Ctrl+D routes to selection")
	check(FileAccess.get_sha256(source_path) == digest and editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty,
		"private source and global Atlas history unchanged")
	print("T304_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T304_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	delete_tree(folder)
	quit(1 if failures else 0)
