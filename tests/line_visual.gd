extends SceneTree
## T-024 native pointer and framebuffer verification for the Line tool.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LINE VISUAL FAILED: " + reason)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _button(point: Vector2, down: bool, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point
	event.global_position = point
	event.shift_pressed = shift
	event.alt_pressed = alt
	root.push_input(event, true)


func _motion(point: Vector2, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	event.global_position = point
	event.shift_pressed = shift
	event.alt_pressed = alt
	root.push_input(event, true)


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
	_check(editor.create_board("Line native", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 28.0)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	await _frames(7)
	var canvas: AtlasCanvas = editor.canvas
	_check(editor.inspector._line_hint.is_visible_in_tree(), "Line modifier guidance visible")
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.LINE).button_pressed, "Line tool selected in palette")
	var anchor: Vector2 = canvas.camera_center - Vector2(25, 7)
	var pointer: Vector2 = anchor + Vector2(72, 33)
	canvas.camera_center = (anchor + pointer) * 0.5
	canvas.camera_zoom = 1.25
	canvas.brush_width = 9.0
	canvas.brush_color = Color(0.1, 0.8, 0.8, 0.75)
	var start_ui: Vector2 = canvas.global_position + canvas.document_to_local(anchor)
	var end_ui: Vector2 = canvas.global_position + canvas.document_to_local(pointer)
	_button(start_ui, true)
	_motion(end_ui, true, true)
	await _frames(5)
	var expected: PackedVector2Array = AtlasShapes.line_endpoints(anchor, pointer, true, true)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == expected,
		"native Shift+Alt drag produces angle-constrained centered preview")
	var draft_image: Image = root.get_texture().get_image()
	_check(draft_image.get_width() >= 960 and draft_image.get_height() >= 660, "native framebuffer available")
	_button(end_ui, false, true, true)
	await _frames(6)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.strokes.size() == 1 and ink.strokes[0].points == expected,
		"native release commits exact preview geometry")
	var committed_image: Image = root.get_texture().get_image()
	var differences: int = 0
	var origin: Vector2i = Vector2i(canvas.global_position)
	for y: int in range(24, int(canvas.size.y) - 24, 3):
		for x: int in range(14, int(canvas.size.x) - 14, 3):
			if draft_image.get_pixel(origin.x + x, origin.y + y) != committed_image.get_pixel(origin.x + x, origin.y + y):
				differences += 1
	_check(differences < 90, "draft framebuffer closely matches committed line")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(committed_image.save_png("user://validation/line-960.png") == OK, "native 960 screenshot")
	_button(start_ui, true)
	_motion(end_ui, true)
	await _frames(2)
	_check(canvas._draft_stroke != null, "second native preview starts")
	canvas.cancel_edit()
	_button(end_ui, false, true)
	_check(ink.strokes.size() == 1, "Escape cancellation does not create second stroke")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(editor.inspector._line_hint.is_visible_in_tree() and canvas.size.x >= 230.0,
		"Line guidance and canvas remain usable at 800x600")
	_check(root.get_texture().get_image().save_png("user://validation/line-800.png") == OK, "native 800 screenshot")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LINE_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
