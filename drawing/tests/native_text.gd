extends SceneTree
## Native-window witness: Text click opens editor, published glyphs appear in framebuffer.

var checks: int = 0
var failures: int = 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("DRAWING_TEXT_NATIVE_FAILED: " + description)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame

func pointer(canvas: Control, pixel: Vector2i, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(Vector2(pixel) + Vector2(0.5, 0.5))
	event.global_position = event.position
	root.push_input(event, true)
	await frames()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "Native framebuffer required")
		quit(1)
		return
	root.size = Vector2i(1100, 720)
	root.mode = Window.MODE_WINDOWED
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(8)
	var canvas: Control = app.canvas
	app._change_tool("Text")
	var target: Vector2i = Vector2i(-20, -18)
	await pointer(canvas, target, true)
	await pointer(canvas, target, false)
	check(app.text_dialog.visible, "Native pointer opens text editor")
	var doc: DrawingDocument = app.current_document()
	var count_before: int = doc.layer_count()
	app.text_dialog.hide()
	check(doc.layer_count() == count_before, "Cancelling native editor is nonmutating")
	app._edit_text_at(target)
	app.text_edit.text = "Native Label"
	app.text_color.color = Color.WHITE
	app._commit_text_dialog()
	app.text_dialog.hide()
	var label_id: String = app.current_layer()
	check(doc.inspect_node(label_id).kind == DrawingLayerNode.TEXT, "Native text saves semantic element")
	canvas.queue_redraw()
	await frames(6)
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	check(frame != null and not frame.is_empty(), "Native framebuffer available")
	var bright_pixels: int = 0
	if frame != null and not frame.is_empty():
		var visible: Rect2i = DrawingTextRaster.bounds(doc.inspect_node(label_id).text_element).value
		var screen_start: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(visible.position)))
		var screen_end: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(visible.end)))
		for y: int in range(maxi(0, screen_start.y), mini(frame.get_height(), screen_end.y)):
			for x: int in range(maxi(0, screen_start.x), mini(frame.get_width(), screen_end.x)):
				var pixel: Color = frame.get_pixel(x, y)
				if pixel.r > 0.75 and pixel.g > 0.75 and pixel.b > 0.75:
					bright_pixels += 1
	check(bright_pixels > 30, "Text glyph coverage visible in native framebuffer")
	app._rasterize_text()
	check(doc.inspect_node(label_id).kind == DrawingLayerNode.RASTER, "Native UI rasterization enabled")
	app._undo()
	check(doc.inspect_node(label_id).kind == DrawingLayerNode.TEXT, "Native undo restores editable text")
	print("DRAWING_TEXT_NATIVE_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
