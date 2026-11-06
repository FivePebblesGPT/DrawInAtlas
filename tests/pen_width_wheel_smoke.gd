extends SceneTree
## T-011: width wheel step, bounds, editor synchronization and non-wheel editing.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PEN WIDTH WHEEL FAILED: " + label)


func _wheel(up: bool, pressed: bool = true) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = pressed
	event.factor = 1.0
	return event


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var spinner: SpinBox = editor.inspector.brush_width_spinner
	var line_edit: LineEdit = spinner.get_line_edit()
	_check(spinner.is_visible_in_tree() and spinner.editable, "pen width shown and editable")
	_check(spinner.step == 0.5 and spinner.min_value == 0.5 and spinner.max_value == 256.0,
		"half-unit wheel steps with explicit lower/upper limits")
	_check(spinner.tooltip_text.contains("0.5") and spinner.tooltip_text.contains("256"),
		"width tooltip explains wheel step and bounds")
	_check(is_equal_approx(spinner.value, 8.0) and is_equal_approx(editor.canvas.brush_width, 8.0),
		"display and brush agree initially")
	line_edit.gui_input.emit(_wheel(true))
	_check(spinner.value == 8.5 and editor.canvas.brush_width == 8.5,
		"inner text field accepts hovered up-wheel without separate focus")
	spinner.gui_input.emit(_wheel(false))
	_check(spinner.value == 8.0 and editor.canvas.brush_width == 8.0,
		"outer spinner region accepts down-wheel exactly once")
	spinner.gui_input.emit(_wheel(true, false))
	_check(spinner.value == 8.0, "wheel release never doubles the adjustment")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	line_edit.gui_input.emit(click)
	_check(spinner.value == 8.0, "non-wheel buttons leave the width alone")
	spinner.value = 255.5
	line_edit.gui_input.emit(_wheel(true))
	line_edit.gui_input.emit(_wheel(true))
	_check(spinner.value == 256.0 and editor.canvas.brush_width == 256.0,
		"upper bound clamps without overshoot")
	spinner.value = 0.5
	line_edit.gui_input.emit(_wheel(false))
	_check(spinner.value == 0.5 and editor.canvas.brush_width == 0.5,
		"lower bound clamps without going to zero")
	spinner.value = 13.5
	_check(editor.canvas.brush_width == 13.5, "direct numeric editing still updates the brush")
	editor._choose_tool(AtlasCanvas.Tool.FILL)
	_check(not spinner.editable, "fill keeps width read-only")
	line_edit.gui_input.emit(_wheel(true))
	_check(spinner.value == 13.5 and editor.canvas.brush_width == 13.5,
		"disabled width cannot change on wheel")
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	_check(spinner.editable and spinner.value == 13.5, "pen restores width editing without resetting value")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PEN_WIDTH_WHEEL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
