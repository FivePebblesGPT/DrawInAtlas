extends SceneTree
## T-011: native wheel routing through inner LineEdit and spin arrows, plus actual pen drawing.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PEN WIDTH WHEEL VISUAL FAILED: " + label)


func _frames(count: int = 3) -> void:
	for frame: int in range(count):
		await process_frame


func _wheel(point: Vector2, up: bool, pressed: bool = true) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = pressed
	event.factor = 1.0
	root.push_input(event, true)
	await _frames()
	if pressed:
		event.pressed = false
		root.push_input(event, true)
		await _frames()


func _button(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await _frames()


func _hover(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await _frames()


func _motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await _frames()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer required for pointer dispatch")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(10)
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	_check(editor.create_board("Width wheel", grid), "isolated board created")
	var spinner: SpinBox = editor.inspector.brush_width_spinner
	var scroll: ScrollContainer = editor.inspector.get_node("Scroll")
	var canvas: AtlasCanvas = editor.canvas
	var position: Vector2 = spinner.global_position + spinner.size * 0.4
	_check(spinner.get_global_rect().has_point(position), "wheel target lies in width field")
	_check(not spinner.has_focus() and not spinner.get_line_edit().has_focus(), "wheel doesn't need keyboard focus")
	var camera_before: float = canvas.camera_zoom
	var scroll_before: int = scroll.scroll_vertical
	await _wheel(position, true)
	_check(spinner.value == 8.5 and canvas.brush_width == 8.5,
		"real wheel over text field changes width by one half-unit")
	_check(scroll.scroll_vertical == scroll_before and canvas.camera_zoom == camera_before,
		"width wheel neither scrolls the inspector nor zooms the board")
	await _wheel(position, true)
	_check(spinner.value == 9.0 and canvas.brush_width == 9.0, "repeated wheel stays in sync")
	await _wheel(position, false)
	_check(spinner.value == 8.5, "native downward wheel reverses exactly one step")
	var arrows: Vector2 = spinner.global_position + Vector2(spinner.size.x - 7.0, spinner.size.y * 0.5)
	await _wheel(arrows, true)
	_check(spinner.value == 9.0 and canvas.brush_width == 9.0,
		"native wheel over spin arrows changes same width exactly once")
	await _wheel(arrows, true, false)
	_check(spinner.value == 9.0, "wheel release does not cause a second change")
	var input: LineEdit = spinner.get_line_edit()
	input.grab_focus()
	await _frames()
	_check(input.has_focus(), "text editing receives keyboard focus")
	input.text = "17.5"
	spinner.apply()
	_check(spinner.value == 17.5 and canvas.brush_width == 17.5,
		"typed exact width commits to canvas")
	await _wheel(position, true)
	_check(spinner.value == 18.0 and canvas.brush_width == 18.0,
		"wheel works after focusing and typing")
	var board_point: Vector2 = canvas.global_position + Vector2(160, 180)
	await _hover(board_point - Vector2(35, 0))
	await _button(board_point - Vector2(35, 0), true)
	await _motion(board_point + Vector2(35, 0))
	await _button(board_point + Vector2(35, 0), false)
	_check(canvas.floor.strokes.size() == 1 and canvas.floor.strokes[0].width == 18.0,
		"next real pen stroke uses displayed wheel-adjusted width")
	var width_before: float = spinner.value
	await _wheel(board_point, true)
	_check(spinner.value == width_before, "wheel over board never changes pen width")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	position = spinner.global_position + spinner.size * 0.4
	_check(spinner.is_visible_in_tree() and editor.canvas.size.x >= 234,
		"width field remains usable in compact 800×600 layout")
	await _wheel(position, false)
	_check(spinner.value == 17.5 and canvas.brush_width == 17.5,
		"compact-window wheel targets the width control correctly")
	editor._choose_tool(AtlasCanvas.Tool.FILL)
	_check(not spinner.editable, "fill disables width editing")
	await _wheel(position, true)
	_check(spinner.value == 17.5 and canvas.brush_width == 17.5,
		"real wheel cannot change noneditable width")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PEN_WIDTH_WHEEL_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
