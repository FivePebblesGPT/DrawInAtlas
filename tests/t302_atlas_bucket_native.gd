extends SceneTree
## Verify the real Atlas-hosted Object Editor keeps the fill in its private draft.
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T302_ATLAS_FAILED: " + label)


func frames(count: int = 4) -> void:
	for i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func click(window: Window, position: Vector2) -> void:
	window.warp_mouse(position)
	await frames(3)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		window.push_input(event, true)
		await frames(2)


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
	var folder: String = OS.get_cache_dir().path_join("t302-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t302-object", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = source.begin_edit(layer, source.revision).value
	check(edit.fill_rect(Rect2i(-2, 0, 4, 2), 0xff0000ff).ok and edit.commit().ok, "source contains signed seam")
	var created: DrawingResult = library.create_asset(source, "Bucket object")
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
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 22.0
	app._set_foreground(Color.BLUE)
	await click(window, app.tool_buttons["Bucket"].get_global_rect().get_center())
	await frames()
	check(app.active_tool == "Bucket" and app.top_bar.active_options == "Bucket", "embedded toolbar pointer selects Bucket")
	var draft: DrawingDocument = app.current_document()
	var draft_layer: String = app.current_layer()
	var revision: int = draft.revision
	await click(window, canvas.global_position + canvas.pixel_to_position(Vector2(-0.5, 0.5)))
	await frames()
	check(draft.revision == revision + 1 and int(draft.read_pixel(draft_layer, -1, 0).value) == 0xffff0000 and int(draft.read_pixel(draft_layer, 0, 0).value) == 0xffff0000, "one private signed-seam fill")
	check(app.current_object().is_dirty() and FileAccess.get_sha256(source_path) == digest, "fill never publishes source until explicit save")
	check(editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty, "private fill does not mutate Atlas global history")
	var screenshot: String = OS.get_environment("T302_ATLAS_SCREENSHOT")
	if not screenshot.is_empty():
		await RenderingServer.frame_post_draw
		if window.get_texture().get_image().save_png(screenshot) != OK:
			printerr("OPTIONAL_VISUAL_CAPTURE_FAILED: Atlas Bucket")
	app._undo()
	check(int(draft.read_pixel(draft_layer, 0, 0).value) == 0xff0000ff, "private Undo restores source")
	app._redo()
	check(int(draft.read_pixel(draft_layer, 0, 0).value) == 0xffff0000, "private Redo restores fill")
	print("T302_ATLAS_PASSED checks=%d failures=%d" % [checks, failures])
	root.remove_child(scene)
	scene.free()
	delete_tree(folder)
	quit(0 if failures == 0 else 1)
