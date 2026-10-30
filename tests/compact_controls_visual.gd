extends SceneTree
## T-007 native layout and pointer acceptance, including measured board clearance.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("COMPACT CONTROLS VISUAL FAILED: " + message)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame


func _click(button: Button) -> void:
	var point: Vector2 = button.global_position + button.size / 2.0
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.position = point
	down.global_position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down, true)
	await _frames(2)
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.position = point
	up.global_position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up, true)
	await _frames(2)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer is required")
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
	editor.sidebar.select_view(&"Layers")
	await _frames(5)
	var actions: HBoxContainer = editor.layer_panel.get_node("Order")
	var floor_actions: HBoxContainer = editor.inspector.get_node("Scroll/Margin/Sections/FloorSection/FloorActions")
	_check(editor.canvas.size.x >= 394.0, "960-wide canvas gains at least 26 pixels over 368-pixel baseline")
	_check(editor.inspector.size.x <= 235.0, "inspector is narrower than 252-pixel baseline")
	_check(editor.layer_panel.size.y <= 558.0, "layer panel saves at least 86 pixels in height")
	_check(floor_actions.size.y <= 36.0, "floor action buttons fit one 36-pixel row")
	var sidebar_right: float = editor.canvas.global_position.x
	for child: Node in actions.get_children():
		var button: Button = child as Button
		_check(button.size.x >= 32.0 and button.size.y >= 34.0,
			"%s remains a usable click target" % button.name)
		_check(button.global_position.x + button.size.x <= sidebar_right,
			"%s stays in the sidebar" % button.name)
	var floor: AtlasFloor = editor.canvas.floor
	var starting_layers: int = floor.layers.size()
	await _click(actions.get_node("NewInkButton"))
	_check(floor.layers.size() == starting_layers + 1, "native pointer triggers add ink")
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	var path: String = "user://validation/compact-controls-960.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(image.save_png(path) == OK, "native screenshot saved")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(editor.canvas.size.x >= 234.0, "800-wide canvas gains at least 26 pixels over 208-pixel baseline")
	_check(actions.size.x <= editor.sidebar.size.x and floor_actions.size.x <= editor.inspector.size.x,
		"compact controls fit both panels")
	_check(root.get_texture().get_image().save_png("user://validation/compact-controls-800.png") == OK,
		"compact window screenshot saved")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_COMPACT_CONTROLS_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
