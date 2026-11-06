extends SceneTree
## T-085: real Godot Control mouse routing and live GPU/software framebuffer
## readback with left button still depressed. Offscreen/headless cannot pass.

var checks: int = 0
var failures: int = 0
var first_visible_ms: Array[float] = []
var stage_cpu_ms: Array[float] = []
var input_stage_ms: Array[float] = []


func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T085_NATIVE_FAILED: " + message)


func frames(n: int = 2) -> void:
	for i: int in range(n):
		await process_frame


func button(canvas: Control, pixel: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(pixel)
	event.global_position = event.position
	root.push_input(event, true)


func motion(canvas: Control, pixel: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + canvas.pixel_to_position(pixel)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func color_delta(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func sample(canvas: Control, pixel: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(pixel))
	return image.get_pixelv(point) if image != null and not image.is_empty() and \
			point.x >= 0 and point.y >= 0 and point.x < image.get_width() and point.y < image.get_height() else Color(-1, -1, -1)


func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		verify(false, "native framebuffer requires a display driver")
		quit(1)
		return
	root.size = Vector2i(600, 400)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(40, 40)
	canvas.size = Vector2(210, 162)
	canvas.brush_width = 4.0
	canvas.color_rgba = 0xffffbb44
	root.add_child(canvas)
	await frames(6)
	var baseline_accumulation: bool = Input.use_accumulated_input
	var zoom_levels: Array[float] = [1.0, 0.5, 0.25]
	for zoom_value: float in zoom_levels:
		canvas.zoom = zoom_value
		var document: DrawingDocument = DrawingDocument.new("t085-native")
		var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
		canvas.document = document
		canvas.layer_id = layer
		canvas.tool = "Brush"
		canvas.pointer_known = false
		await frames(3)
		await RenderingServer.frame_post_draw
		var start: Vector2 = Vector2(0.5, 0.5)
		var moved: Vector2 = Vector2(18.5, 13.5)
		var before: Color = sample(canvas, start)
		var revision: int = document.revision
		button(canvas, start, true)
		verify(not Input.use_accumulated_input,
			"zoom %s OS motion coalescing disabled while painting" % zoom_value)
		verify(canvas.session != null and canvas.session.change_count() > 0,
			"zoom %s first stationary dab staged on press" % zoom_value)
		verify(document.revision == revision and document.read_pixel(layer, 0, 0).value == 0,
			"zoom %s no committed pixel before release" % zoom_value)
		motion(canvas, moved)
		await frames(5)
		await RenderingServer.frame_post_draw
		var during: Color = sample(canvas, start)
		verify(during.b > 0.9 and during.g > 0.6 and color_delta(during, before) > 0.1,
			"zoom %s live RGBA framebuffer pixel while mouse still down: %s vs %s" % [zoom_value, during, before])
		verify(canvas.session != null and int(canvas._metrics.get("first_frame_post_draw_us", 0)) > 0,
			"zoom %s preview has a frame_post_draw before button release" % zoom_value)
		for i: int in range(24):
			var t: float = float(i) / 23.0
			motion(canvas, Vector2(18.5 + t * 40.0, 13.5 + sin(t * TAU) * 12.0))
		motion(canvas, Vector2(25.5, 10.5))
		motion(canvas, Vector2(35.5, 25.5))
		motion(canvas, Vector2(25.5, 25.5))
		motion(canvas, Vector2(35.5, 10.5))
		verify(int(canvas._metrics.get("samples_received", 0)) >= 26,
			"zoom %s consecutive raw motion events enqueued without dropping" % zoom_value)
		button(canvas, Vector2(58.5, 13.5), false)
		for attempt: int in range(160):
			if canvas.session == null:
				break
			await frames(1)
		verify(canvas.session == null, "zoom %s released path drains and commits" % zoom_value)
		verify(Input.use_accumulated_input == baseline_accumulation,
			"zoom %s OS motion accumulation restored after publication" % zoom_value)
		verify(document.read_pixel(layer, 0, 0).value != 0 and
			document.read_pixel(layer, 58, 13).value != 0,
			"zoom %s stroke preserves first and final endpoints" % zoom_value)
		verify(document.read_pixel(layer, 28, 25).value != 0 and
			document.read_pixel(layer, 30, 18).value != 0,
			"zoom %s rapid curved and self-crossing samples preserve geometry" % zoom_value)
		verify(document.revision == revision + 1, "zoom %s one history publication" % zoom_value)
		verify(document.undo().ok and document.read_pixel(layer, 0, 0).value == 0 and
			document.read_pixel(layer, 58, 13).value == 0,
			"zoom %s one undo removes entire rapid looping gesture" % zoom_value)
		var recorded: Dictionary = canvas.last_gesture_metrics
		verify((recorded.get("sample_to_stage_us", []) as Array).size() == int(recorded["samples_received"]),
			"zoom %s every delivered time-stamped pointer sample completed staging" % zoom_value)
		verify(int(recorded.get("first_stage_us", 0)) > 0 and
			int(recorded.get("first_preview_submit_us", 0)) > 0 and
			int(recorded.get("commit_us", 0)) >= int(recorded.get("release_us", 0)),
			"zoom %s telemetry contains stage, preview and commit phases" % zoom_value)
		first_visible_ms.append(float(int(recorded.get("first_frame_post_draw_us", 0)) - int(recorded.get("down_us", 0))) / 1000.0)
		stage_cpu_ms.append(float(int(recorded.get("stage_cpu_us", 0))) / 1000.0)
		for arrival_us: Variant in recorded["sample_to_stage_us"]:
			input_stage_ms.append(float(int(arrival_us)) / 1000.0)
		print("T085_NATIVE_ZOOM zoom=%.2f samples=%d max_queued=%d down_to_stage_ms=%.3f down_to_frame_ms=%.3f release_to_commit_ms=%.3f" % [zoom_value,
			int(recorded["samples_received"]), int(recorded["max_pending"]),
			float(int(recorded["first_stage_us"]) - int(recorded["down_us"])) / 1000.0,
			float(int(recorded["first_frame_post_draw_us"]) - int(recorded["down_us"])) / 1000.0,
			float(int(recorded["commit_us"]) - int(recorded["release_us"])) / 1000.0])

	# A draft eraser must expose already-painted document pixels in the frame,
	# not silently wait for mouse-up. Test fully opaque source and cancel.
	canvas.zoom = 1.0
	var image_doc: DrawingDocument = DrawingDocument.new("t085-erase")
	var image_layer: String = String(image_doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	canvas.document = image_doc
	canvas.layer_id = image_layer
	var edit: DrawingEditSession = image_doc.begin_edit(image_layer, image_doc.revision).value as DrawingEditSession
	verify(edit.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]), 0xff10e0ff, 6.0).ok and edit.commit().ok,
		"native eraser has existing painted source")
	canvas.tool = "Eraser"
	await frames(4)
	await RenderingServer.frame_post_draw
	var ink_frame: Color = sample(canvas, Vector2(0.5, 0.5))
	button(canvas, Vector2(0.5, 0.5), true)
	motion(canvas, Vector2(9.5, 9.5))
	await frames(5)
	await RenderingServer.frame_post_draw
	var erased_frame: Color = sample(canvas, Vector2(0.5, 0.5))
	verify(color_delta(ink_frame, erased_frame) > 0.1 and image_doc.read_pixel(image_layer, 0, 0).value != 0,
		"eraser clears framebuffer before canonical paint is removed")
	canvas.cancel_gesture()
	await frames(3)
	await RenderingServer.frame_post_draw
	var restored: Color = sample(canvas, Vector2(0.5, 0.5))
	verify(color_delta(restored, ink_frame) < 0.05 and image_doc.read_pixel(image_layer, 0, 0).value != 0,
		"cancel removes eraser draft with no ghost or history")

	button(canvas, Vector2(12.5, 10.5), true)
	verify(canvas.session != null, "begin new cancellable pointer gesture")
	var saved_revision: int = image_doc.revision
	canvas.tool = "Brush"
	verify(canvas.session == null and image_doc.revision == saved_revision,
		"tool switch cancels draft with no revision")
	verify(Input.use_accumulated_input == baseline_accumulation,
		"tool cancellation restores OS motion accumulation")
	canvas.tool = "Brush"
	button(canvas, Vector2(4.5, 4.5), true)
	verify(canvas.session != null, "begin zoom cancellation witness")
	canvas.zoom = 0.5
	verify(canvas.session == null and image_doc.revision == saved_revision,
		"zoom change cancels pending path without content changes")
	button(canvas, Vector2(4.5, 4.5), true)
	verify(canvas.session != null, "begin layer-switch cancellation witness")
	var replacement_layer: String = String(image_doc.create_layer(DrawingLayerNode.RASTER, "New", "root").value)
	canvas.layer_id = replacement_layer
	verify(canvas.session == null and image_doc.read_pixel(image_layer, 4, 4).value == 0,
		"layer switch drops a transient edit rather than mispublishing")
	canvas.zoom = 1.0
	button(canvas, Vector2(2.5, 2.5), true)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	verify(canvas.session == null, "Escape explicitly cancels a live gesture")
	# The pointer leaves the Control but remains inside the OS window.
	var outside_start_revision: int = image_doc.revision
	button(canvas, Vector2(10.5, 0.5), true)
	motion(canvas, Vector2(350.5, 0.5))
	button(canvas, Vector2(350.5, 0.5), false)
	for attempt: int in range(100):
		if canvas.session == null:
			break
		await frames(1)
	verify(canvas.session == null and image_doc.revision == outside_start_revision + 1 and
		image_doc.read_pixel(replacement_layer, 350, 0).value != 0,
		"leaving canvas and releasing over window background commits full sparse path")
	verify(image_doc.undo().ok and image_doc.read_pixel(replacement_layer, 350, 0).value == 0,
		"outside-canvas path is still a single undo operation")
	print("T085_NATIVE_METRICS ms: preview_frame_p50=%.3f preview_frame_p95=%.3f sample_to_stage_p50=%.3f sample_to_stage_p95=%.3f stage_cpu_p50=%.3f stage_cpu_p95=%.3f" % [
		percentile(first_visible_ms, 0.5), percentile(first_visible_ms, 0.95),
		percentile(input_stage_ms, 0.5), percentile(input_stage_ms, 0.95),
		percentile(stage_cpu_ms, 0.5), percentile(stage_cpu_ms, 0.95)])
	print("T085_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T085_NATIVE_PASSED")
	quit(1 if failures else 0)
