extends SceneTree
## T-073: verify current shortcut dispatch through a native Godot viewport.
## Deliberately does not assert proposed T-063 Save As/overflow UX as implemented.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T073_KEYBOARD_FAILED: " + description)


func frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func shortcut(code: Key, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = shift
	root.push_input(event, true)
	await frames()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)
	await frames()


func pointer(canvas: Control, point: Vector2i, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(
		Vector2(point) + Vector2(0.5, 0.5))
	event.global_position = event.position
	root.push_input(event, true)
	await frames()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native viewport required")
		quit(1)
		return
	root.size = Vector2i(1080, 700)
	root.mode = Window.MODE_WINDOWED
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	root.add_child(app)
	await frames(8)
	check(app.tabs.size() == 1, "one ordinary document at startup")
	await shortcut(KEY_N)
	check(app.tabs.size() == 2 and app.active_tab == 1,
		"Ctrl+N creates a second ordinary document")
	var doc: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var canvas: Control = app.canvas
	var target: Vector2i = Vector2i(5, 6)
	await pointer(canvas, target, true)
	await pointer(canvas, target, false)
	var pixel: DrawingResult = doc.read_pixel(layer, target.x, target.y)
	check(pixel.ok and int(pixel.value) != 0, "native pointer produces a committed stroke")
	var painted: int = int(pixel.value) if pixel.ok else 0
	await shortcut(KEY_Z)
	check(doc.read_pixel(layer, target.x, target.y).value == 0,
		"Ctrl+Z undoes a real canvas gesture")
	await shortcut(KEY_Y)
	check(doc.read_pixel(layer, target.x, target.y).value == painted,
		"Ctrl+Y redoes the gesture")
	await shortcut(KEY_Z)
	await shortcut(KEY_Z, true)
	check(doc.read_pixel(layer, target.x, target.y).value == painted,
		"Ctrl+Shift+Z is a current redo alias")
	await shortcut(KEY_W)
	check(app.tabs.size() == 2 and app.close_dialog.visible,
		"Ctrl+W on modified tab opens unsaved-close prompt")
	app.close_dialog.hide()
	app._cancel_pending_close()
	await frames()
	check(app.tabs.size() == 2 and doc.read_pixel(layer, target.x, target.y).value == painted,
		"Cancel preserves the modified tab and raster data")
	print("T073_KEYBOARD: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T073_KEYBOARD_PASSED")
	quit(1 if failures else 0)
