extends "res://drawing/tests/t306_srgb_native.gd"
## Hosted workspace must use the same SDR framebuffer and native Brush boundary.

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
	var folder: String = OS.get_cache_dir().path_join("t306-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	root.add_child(scene)
	await frames(12)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var source: DrawingDocument = DrawingDocument.new("t306-object", 16)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Swatches").value)
	fill(source, layer, Rect2i(-12, -8, 12, 8), 0xffc08040)
	fill(source, layer, Rect2i(0, -8, 12, 8), 0xff808080)
	var created: DrawingResult = library.create_asset(source, "sRGB object")
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
	check(not root.use_hdr_2d and not window.use_hdr_2d and RenderingServer.get_current_rendering_method() == "gl_compatibility", "Atlas and hosted workspace use SDR framebuffer")
	var session: DrawingObjectEditorSession = app.current_object()
	check(session.set_frame(Vector2i.ZERO, Rect2i(-16, -12, 32, 24)).ok, "finite private object frame")
	var canvas: Control = app.canvas
	canvas.camera = Vector2.ZERO
	canvas.zoom = 16.0
	canvas.show_pixel_grid = false
	canvas.show_grid = false
	canvas.queue_redraw()
	await frames(12)
	check(near_rgb(sample(canvas, Vector2i(-6, -4)), Color8(64, 128, 192)), "hosted source swatch has no display conversion")
	check(near_rgb(sample(canvas, Vector2i(6, -4)), Color8(128, 128, 128)), "hosted gray swatch matches stored RGB")
	app.color_advanced.color = Color8(64, 128, 192)
	app.color_advanced.color_changed.emit(app.color_advanced.color)
	check(canvas.color_rgba == 0xffc08040, "hosted picker routes encoded sRGB")
	app._set_brush_width(4.0)
	app._set_brush_opacity(1.0)
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-7.5, 5.5)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(2.5, 5.5)))
	await frames(6)
	check(canvas.session != null and canvas._active_brush_backend == "Hokusai", "hosted native Brush preview")
	check(near_rgb(sample(canvas, Vector2i(-2, 5)), Color8(64, 128, 192), 2), "hosted detached preview matches picker")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(4.5, 5.5)))
	for i: int in range(120):
		if canvas.session == null:
			break
		await frames(1)
	await frames(8)
	var draft: DrawingDocument = app.current_document()
	check(int(draft.read_pixel(app.current_layer(), -2, 5).value) == 0xffc08040, "hosted Brush committed exact sRGB8")
	check(near_rgb(sample(canvas, Vector2i(-2, 5)), Color8(64, 128, 192)), "hosted committed framebuffer matches source and picker")
	check(FileAccess.get_sha256(source_path) == digest and editor.edits.can_undo() == old_undo and editor.edits.is_dirty() == old_dirty, "color test preserves original object and Atlas history")
	var directory: String = OS.get_environment("T306_SCREENSHOTS")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		window.get_texture().get_image().save_png(directory.path_join("srgb-atlas.png"))
	print("T306_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T306_ATLAS_PASSED")
	root.remove_child(scene)
	scene.free()
	delete_tree(folder)
	quit(1 if failures else 0)
