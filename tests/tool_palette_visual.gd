extends SceneTree
## T-006: X11 pointer, keyboard and compact layout witness.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TOOL PALETTE VISUAL FAILED: " + label)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native X11 framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(8)
	editor.sidebar.select_view(&"Tools")
	await _frames(4)
	var palette: AtlasToolPalette = editor.tool_palette
	_check(palette.is_visible_in_tree(), "categorised Tools tab is visible")
	_check(editor.canvas.size.x > 200 and editor.canvas.size.y > 500,
		"960-pixel window preserves useful board area")
	await _click(palette.button_for(AtlasCanvas.Tool.LINE))
	_check(editor.canvas.tool == AtlasCanvas.Tool.LINE and palette.button_for(AtlasCanvas.Tool.LINE).button_pressed,
		"pointer click activates Line and its pressed icon")
	await _key(KEY_E)
	_check(editor.canvas.tool == AtlasCanvas.Tool.ERASER and palette.button_for(AtlasCanvas.Tool.ERASER).button_pressed
		and not palette.button_for(AtlasCanvas.Tool.LINE).button_pressed,
		"native E shortcut switches canvas and highlighted tool")
	await _click(palette.button_for(AtlasCanvas.Tool.PEN))
	_check(editor.canvas.tool == AtlasCanvas.Tool.PEN, "pointer switches back to Pen")
	await _save("tool-palette-expanded.png")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(6)
	_check(editor.canvas.size.x >= 160 and editor.canvas.size.y >= 400,
		"compact window retains minimum board for drawing")
	var rightmost: float = 0.0
	for category: Dictionary in AtlasToolPalette.CATEGORIES:
		for definition: Dictionary in category["tools"]:
			var button: Button = palette.button_for(definition["id"])
			_check(button.is_visible_in_tree() and button.size.x >= 40.0,
				"compact layout keeps %s accessible" % definition["name"])
			rightmost = maxf(rightmost, button.global_position.x + button.size.x)
	_check(rightmost < editor.canvas.global_position.x, "palette fits left of the drawing board")
	await _save("tool-palette-compact.png")
	editor.sidebar.set_panel_expanded(false)
	await _frames(4)
	_check(editor.canvas.size.x > 300, "collapsing sidebar frees board width")
	await _save("tool-palette-collapsed.png")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_TOOL_PALETTE_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)


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


func _key(code: Key) -> void:
	var down: InputEventKey = InputEventKey.new()
	down.keycode = code
	down.pressed = true
	root.push_input(down, true)
	await _frames(2)
	var up: InputEventKey = InputEventKey.new()
	up.keycode = code
	up.pressed = false
	root.push_input(up, true)
	await _frames(2)


func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://validation/" + filename
	DirAccess.make_dir_recursive_absolute("user://validation")
	_check(root.get_texture().get_image().save_png(path) == OK, "saved " + filename)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame
