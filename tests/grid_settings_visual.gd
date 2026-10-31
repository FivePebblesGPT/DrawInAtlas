extends SceneTree
## T-008 native popup access and compact-window layout checks.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GRID SETTINGS VISUAL FAILED: " + message)


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


# Compare actual framebuffer changes within the popup footprint rather than
# assuming one specific theme color at two hardcoded screen pixels.
func _changed_pixels(before: Image, after: Image, region: Rect2) -> int:
	var rectangle: Rect2i = Rect2i(Vector2i(region.position), Vector2i(region.size))
	rectangle = rectangle.intersection(Rect2i(Vector2i.ZERO, before.get_size()))
	var changed: int = 0
	for y: int in range(rectangle.position.y, rectangle.end.y, 4):
		for x: int in range(rectangle.position.x, rectangle.end.x, 4):
			if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				changed += 1
	return changed


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
	await _frames(12)
	var popup: AtlasGridSettingsPopup = editor.grid_settings_popup
	var button: Button = editor.grid_settings_button
	_check(editor.canvas.size.x >= 394, "no canvas width lost to grid controls")
	_check(button.size.x >= 50 and button.size.y >= 24, "toolbar action has a usable target")
	var closed_frame: Image = root.get_texture().get_image()
	await _click(button)
	_check(popup.visible, "actual mouse click opens grid popup")
	_check(popup.panel.position.y >= 32, "popup opens below top toolbar")
	_check(popup.panel.position.x >= 0 and popup.panel.position.x + popup.panel.size.x <= root.size.x,
		"popup is inside 960-wide window")
	_check(popup.panel.size.y <= root.size.y - popup.panel.position.y, "popup fits the window height")
	var form: AtlasGridControls = editor.grid_controls
	_check(form.shape_picker.is_visible_in_tree() and form.distance_spinner.is_visible_in_tree(),
		"grid geometry and distance form are accessible")
	_check(form.visibility_checkbox.is_visible_in_tree(), "grid overlay visibility belongs to the popup")
	await _frames(12)
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(image.save_png("user://validation/grid-settings-960.png") == OK,
		"960-wide screenshot captured")
	_check(_changed_pixels(closed_frame, image, popup.panel.get_global_rect()) > 25,
		"rendered popup changes framebuffer within its panel")
	await _click(popup.done_button)
	_check(not popup.visible, "Done responds to real mouse input")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(7)
	var compact_closed_frame: Image = root.get_texture().get_image()
	_check(editor.canvas.size.x >= 234, "800-wide canvas retains T-007 compact layout")
	await _click(button)
	_check(popup.visible, "popup reopens from toolbar at 800-wide")
	_check(popup.panel.position.x >= 0 and popup.panel.position.x + popup.panel.size.x <= root.size.x,
		"popup does not extend past 800-wide window")
	_check(popup.panel.position.y + popup.panel.size.y <= root.size.y, "popup remains inside 600-high window")
	_check(form.shape_picker.is_visible_in_tree() and form.unit_picker.is_visible_in_tree(),
		"compact window still presents shape and native units")
	await _frames(12)
	var compact_image: Image = root.get_texture().get_image()
	_check(compact_image.save_png("user://validation/grid-settings-800.png") == OK,
		"800-wide screenshot captured")
	_check(_changed_pixels(compact_closed_frame, compact_image, popup.panel.get_global_rect()) > 25,
		"popup actually renders at 800-wide")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await _frames(3)
	_check(not popup.visible, "Escape dismisses the popover")
	await _click(button)
	_check(popup.visible, "toolbar can reopen popover after Escape")
	var outside: Vector2 = Vector2(550, 140)
	var outside_down: InputEventMouseButton = InputEventMouseButton.new()
	outside_down.position = outside
	outside_down.global_position = outside
	outside_down.button_index = MOUSE_BUTTON_LEFT
	outside_down.pressed = true
	root.push_input(outside_down, true)
	await _frames(3)
	_check(not popup.visible, "outside pointer input dismisses the popover")
	_check(editor.inspector.lock_checkbox.is_visible_in_tree(), "mask remains separately visible when popup closes")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_GRID_SETTINGS_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
