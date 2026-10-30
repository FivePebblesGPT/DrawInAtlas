extends SceneTree
## T-025 native pointer and framebuffer check for vertex-based outline/filled polygons.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLYGON VISUAL FAILED: " + description)


func _frames(count: int = 4) -> void:
	for index: int in range(count):
		await process_frame


func _click(canvas: AtlasCanvas, document_point: Vector2) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = canvas.global_position + canvas.document_to_local(document_point)
		event.global_position = event.position
		root.push_input(event, true)
		await _frames(2)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(12)
	_check(editor.create_board("Polygon native", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	editor.inspector.polygon_fill_checkbox.button_pressed = true
	await _frames(7)
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.POLYGON).button_pressed and
		editor.inspector._polygon_hint.is_visible_in_tree(), "polygon icon and guidance visible")
	var triangle: PackedVector2Array = PackedVector2Array([Vector2(-65, -55), Vector2(80, -55), Vector2(10, 75)])
	var interior: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(Vector2(10, -10)))
	var before: Color = root.get_texture().get_image().get_pixelv(interior)
	for point: Vector2 in triangle:
		await _click(canvas, point)
	await _frames(5)
	_check(canvas._polygon_vertices.size() == 3, "three native pointer clicks fix vertices")
	var draft: Color = root.get_texture().get_image().get_pixelv(interior)
	_check(draft != before, "preview renders transparent filled polygon interior")
	await _click(canvas, triangle[0])
	await _frames(6)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.strokes.size() == 1 and ink.strokes[0].filled and not canvas.is_editing(), "native close click commits fill")
	var after: Image = root.get_texture().get_image()
	var committed: Color = after.get_pixelv(interior)
	_check(draft.is_equal_approx(committed), "filled preview and committed interior match")
	editor.sidebar.select_view(&"Tools")
	var inspector_scroll: ScrollContainer = editor.inspector.get_node("Scroll") as ScrollContainer
	inspector_scroll.scroll_vertical = 190
	await _frames(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(root.get_texture().get_image().save_png("user://validation/polygon-960.png") == OK, "native 960 screenshot")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(canvas.size.x >= 230.0 and editor.inspector.polygon_fill_checkbox.is_visible_in_tree(),
		"polygon remains usable at 800x600")
	_check(root.get_texture().get_image().save_png("user://validation/polygon-800.png") == OK, "native 800 screenshot")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_POLYGON_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
