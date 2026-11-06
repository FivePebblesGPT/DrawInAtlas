extends SceneTree
## T-087: actual X11/Mesa framebuffer, UI grid snap and unfenced raster.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T087_NATIVE_FAILED: " + label)


func frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func at(canvas: Control, local: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + local)
	if image == null or image.is_empty() or point.x < 0 or point.y < 0 or \
			point.x >= image.get_width() or point.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(point)


func distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func local_delta(before: Image, after: Image, canvas: Control, local: Vector2) -> float:
	var point: Vector2i = Vector2i(canvas.global_position + local)
	var maximum: float = 0.0
	for y: int in range(point.y - 2, point.y + 3):
		for x: int in range(point.x - 2, point.x + 3):
			if x >= 0 and y >= 0 and x < before.get_width() and y < before.get_height():
				maximum = maxf(maximum, distance(before.get_pixel(x, y), after.get_pixel(x, y)))
	return maximum


func patch(doc: DrawingDocument, layer: String, point: Vector2i, rgba: PackedByteArray) -> void:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "start signed off-frame native patch")
	if not started.ok:
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	check(edit.apply_region(Rect2i(point, Vector2i.ONE), rgba).ok and edit.commit().ok,
		"publish signed off-frame pixel without clipping")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real framebuffer required")
		quit(1)
		return
	root.size = Vector2i(560, 460)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(50, 50)
	canvas.size = Vector2(310, 260)
	canvas.zoom = 1.0
	canvas.tool = "Pan"
	canvas.image_bounds = Rect2i(-80, -60, 160, 120)
	var doc: DrawingDocument = DrawingDocument.new("t087-native")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Art").value)
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	await frames()
	check(not canvas.show_grid and not canvas.snap_to_grid,
		"visible frame does not silently turn on grid or snap")
	for scale: float in [0.25, 0.5, 1.0, 2.0]:
		canvas.zoom = scale
		canvas.camera = Vector2.ZERO
		canvas.queue_redraw()
		await frames()
		var frame: Rect2 = Rect2(canvas.pixel_to_position(Vector2(canvas.image_bounds.position)),
			Vector2(canvas.image_bounds.size) * canvas.zoom)
		var view: Rect2 = frame.intersection(Rect2(Vector2.ZERO, canvas.size))
		check(view.has_area(), "signed frame visible at zoom %.2f" % scale)
		var first: Color = at(canvas, view.position + Vector2(7, 7))
		var second: Color = at(canvas, view.position + Vector2(23, 7))
		check(distance(first, second) > 0.08,
			"checker retains 16-screen-pixel cells at zoom %.2f: %s / %s" % [scale, first, second])
		check(first.a >= 0.99 and second.a >= 0.99,
			"checker is an opaque backdrop, not document pixels, at zoom %.2f" % scale)
		check(int(canvas.last_frame_metrics.get("textures_created", 0)) == 0,
			"transparent frame does not allocate raster display textures")
	canvas.zoom = 1.0
	canvas.camera = Vector2(7, -9)
	canvas.queue_redraw()
	await frames()
	var moved: Rect2 = Rect2(canvas.pixel_to_position(Vector2(canvas.image_bounds.position)),
		Vector2(canvas.image_bounds.size) * canvas.zoom)
	check(distance(at(canvas, moved.position + Vector2(7, 7)),
		at(canvas, moved.position + Vector2(23, 7))) > 0.08,
		"panning doesn't stretch checker squares")
	check(distance(at(canvas, moved.position - Vector2(12, 12)),
		Color(0.15, 0.16, 0.18)) < 0.055,
		"workspace outside image extent remains distinguishable")

	canvas.camera = Vector2.ZERO
	canvas.show_grid = false
	canvas.snap_to_grid = false
	canvas.queue_redraw()
	await frames()
	var grid_probe: Vector2 = canvas.pixel_to_position(Vector2(9, 17))
	var hidden: Color = at(canvas, grid_probe)
	var before_grid: Image = root.get_texture().get_image()
	canvas.show_grid = true
	canvas.grid_spacing = 12
	canvas.grid_origin = Vector2i(-3, 5)
	canvas.queue_redraw()
	await frames()
	var shown: Color = at(canvas, grid_probe)
	var after_grid: Image = root.get_texture().get_image()
	check(local_delta(before_grid, after_grid, canvas, grid_probe) > 0.045,
		"Show grid draws world-aligned lines while snap is disabled near: %s / %s" % [hidden, shown])
	var candidate: Vector2 = canvas.pixel_to_position(Vector2(8.3, 8.2))
	check(canvas.position_to_pixel(candidate) == Vector2i(8, 8),
		"visible grid does not alter edit coordinates")
	canvas.snap_to_grid = true
	check(canvas.position_to_pixel(candidate) == Vector2i(9, 5),
		"configured signed grid origin drives snapping")
	canvas.queue_redraw()
	await frames()
	check(distance(at(canvas, grid_probe), shown) < 0.025,
		"snap toggle alone cannot hide or change shown grid")
	canvas.show_grid = false
	canvas.queue_redraw()
	await frames()
	check(distance(at(canvas, grid_probe), hidden) < 0.025 and canvas.snap_to_grid,
		"hiding grid does not disable snap or leave lines painted in document")
	canvas.snap_to_grid = false
	canvas.show_grid = false
	canvas.camera = Vector2(8, 3)
	canvas.zoom = 2.0
	canvas.queue_redraw()
	await frames()
	var translated: Vector2 = canvas.pixel_to_position(Vector2(9, 17))
	var before_transform_grid: Image = root.get_texture().get_image()
	canvas.show_grid = true
	canvas.queue_redraw()
	await frames()
	check(local_delta(before_transform_grid, root.get_texture().get_image(),
		canvas, translated) > 0.045,
		"grid lines follow signed source intersections after pan and zoom")

	# Actual viewport-dispatched stroke honors snap regardless of guide visibility.
	canvas.show_grid = true
	canvas.snap_to_grid = true
	canvas.camera = Vector2.ZERO
	canvas.zoom = 1.0
	canvas.tool = "Brush"
	canvas.brush_width = 1.0
	var tap: Vector2 = canvas.global_position + canvas.pixel_to_position(Vector2(8.3, 8.2))
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = tap
	down.global_position = tap
	root.push_input(down, true)
	await frames(5)
	check(int(doc.read_pixel(layer, 9, 5).value) == 0,
		"real pointer snap preview leaves committed document untouched before release")
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = tap
	up.global_position = tap
	root.push_input(up, true)
	await frames(8)
	check(int(doc.read_pixel(layer, 9, 5).value) != 0 and
		int(doc.read_pixel(layer, 8, 8).value) == 0,
		"native delivered click commits to configured snapped grid intersection")
	check(doc.undo().ok and int(doc.read_pixel(layer, 9, 5).value) == 0,
		"snapped pointer paints one normal reversible edit")
	canvas.tool = "Pan"
	canvas.snap_to_grid = false
	canvas.show_grid = false
	patch(doc, layer, Vector2i(91, 40), PackedByteArray([255, 30, 20, 255]))
	canvas.queue_redraw()
	await frames()
	var painted: Color = at(canvas, canvas.pixel_to_position(Vector2(91.5, 40.5)))
	check(painted.r > 0.85 and painted.g < 0.25,
		"source pixels beyond image frame still render on workspace")
	check(int(doc.read_pixel(layer, 91, 40).value) != 0,
		"image frame never clips sparse raster contents")
	canvas.image_bounds = Rect2i(-15, 11, 22, 40)
	canvas.queue_redraw()
	await frames()
	check(at(canvas, canvas.pixel_to_position(Vector2(91.5, 40.5))).r > 0.85,
		"resizing image guide leaves existing off-frame pixels in framebuffer")
	check(doc.undo().ok and int(doc.read_pixel(layer, 91, 40).value) == 0,
		"normal history works outside guide")
	canvas.queue_redraw()
	await frames()
	check(distance(at(canvas, canvas.pixel_to_position(Vector2(91.5, 40.5))),
		Color(0.15, 0.16, 0.18)) < 0.055,
		"undo returns outside-frame workspace without checker overlay")
	check(canvas.last_frame_metrics.has("draw_cpu_us"), "native frame timing instrumented")
	print("T087_NATIVE: %d checks; %d failed | Godot %s | display %s | viewport %s" % [
		checks, failures, Engine.get_version_info().get("string", "unknown"),
		DisplayServer.get_name(), root.size])
	if failures == 0:
		print("T087_NATIVE_PASSED")
	quit(1 if failures else 0)
