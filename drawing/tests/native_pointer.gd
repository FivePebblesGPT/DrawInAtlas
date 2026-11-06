extends SceneTree
## T-053: OS-style viewport input routing and real software framebuffer witness.

var checks: int = 0
var failed: int = 0


func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("DRAWING_NATIVE_FAILED: " + label)


func frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func pointer(canvas: Control, pixel: Vector2i, pressed: bool) -> void:
	var input: InputEventMouseButton = InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = pressed
	input.position = canvas.global_position + canvas.pixel_to_position(Vector2(pixel) + Vector2(0.5, 0.5))
	input.global_position = input.position
	root.push_input(input, true)
	await frames(3)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		verify(false, "native framebuffer required")
		quit(1)
		return
	root.size = Vector2i(1080, 700)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var workspace: Control = load("res://main.tscn").instantiate()
	root.add_child(workspace)
	await frames(8)
	var canvas: Control = workspace.canvas
	var document: DrawingDocument = workspace.current_document()
	var raster: String = workspace.current_layer()
	verify(canvas.size.x > 300 and canvas.size.y > 250, "canvas occupies native app window")
	var chosen: Vector2i = Vector2i(5, 7)
	var cursor: Vector2 = canvas.global_position + canvas.pixel_to_position(Vector2(chosen) + Vector2(0.5, 0.5))
	verify(canvas.get_global_rect().has_point(cursor), "pointer target is on visible canvas")
	await pointer(canvas, chosen, true)
	await pointer(canvas, chosen, false)
	var read: DrawingResult = document.read_pixel(raster, chosen.x, chosen.y)
	verify(read.ok and int(read.value) != 0, "viewport-delivered mouse input paints canonical raster")
	await frames(4)
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	verify(frame != null and not frame.is_empty() and frame.get_width() > 500,
		"native framebuffer capture succeeds")
	if frame != null and not frame.is_empty():
		var pixel_on: Vector2i = Vector2i(cursor)
		var pixel_off: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(25, 30)))
		if pixel_on.x >= 0 and pixel_on.y >= 0 and pixel_off.x >= 0 and pixel_off.y >= 0 and \
			pixel_on.x < frame.get_width() and pixel_off.x < frame.get_width() and \
			pixel_on.y < frame.get_height() and pixel_off.y < frame.get_height():
			var on_color: Color = frame.get_pixelv(pixel_on)
			var off_color: Color = frame.get_pixelv(pixel_off)
			verify(Vector3(on_color.r, on_color.g, on_color.b).distance_to(
				Vector3(off_color.r, off_color.g, off_color.b)) > 0.05, "paint visible in native framebuffer")
		else:
			verify(false, "framebuffer sample points in range")
	verify(document.undo().ok and document.read_pixel(raster, chosen.x, chosen.y).value == 0,
		"native pointer stroke is undoable")
	print("DRAWING_NATIVE: %d checks; %d failed" % [checks, failed])
	if failed == 0:
		print("DRAWING_NATIVE_PASSED")
	quit(1 if failed else 0)
