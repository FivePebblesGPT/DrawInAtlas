extends SceneTree

const NATIVE_REFERENCE = preload("res://tests/t206_native_queued_reference.gd")
## Real X11 canvas pointer dispatch and framebuffer readback. This checks the
## new press is not discarded during the preceding released Brush backlog;
## all dimensions and colors are source-space canonical, not GPU timing data.

const FIRST: int = 0xe64378ff
const SECOND: int = 0xff9ad045
const VIEW: Rect2i = Rect2i(-100, -90, 200, 180)
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T124_NATIVE_FAILED: " + label)


func button(canvas: Control, source: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func move(canvas: Control, source: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func first_path() -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	# The current 256-segment mouse-up drain finishes 190 short samples
	# synchronously. A longer real-event burst must still exercise the
	# intentionally deferred second pointer-down and its atomic promotion.
	for i: int in range(840):
		var t: float = float(i) / 839.0
		path.append(Vector2(-40.5 + 75.0 * t, -30.5 + 18.0 * sin(t * TAU * 8.0)))
	return path


func render_bytes(doc: DrawingDocument) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(doc, VIEW)
	check(rendered.ok, "canonical software renderer succeeds")
	return (rendered.value as Image).get_data() if rendered.ok else PackedByteArray()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display is mandatory")
		quit(2)
		return
	root.size = Vector2i(1000, 800)
	var doc: DrawingDocument = DrawingDocument.new("t124-native")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(650, 540)
	canvas.position = Vector2(25, 25)
	canvas.document = doc
	canvas.layer_id = layer
	canvas.zoom = 2.0
	canvas.brush_width = 30.0
	canvas.color_rgba = FIRST
	root.add_child(canvas)
	await process_frame
	await RenderingServer.frame_post_draw
	var revision: int = doc.revision
	var path: PackedVector2Array = first_path()
	var accepted_first: PackedVector2Array = PackedVector2Array()
	var first_times: PackedInt64Array = PackedInt64Array()
	button(canvas, path[0], true)
	if canvas.session == null:
		check(false, "first routed pointer-down starts a native edit")
		quit(1)
		return
	accepted_first.append(canvas._staged_position)
	first_times.append(int(canvas._metrics.get("down_us", 0)))
	var routed_ok: bool = true
	for i: int in range(1, path.size()):
		move(canvas, path[i])
		if int(canvas._metrics.get("samples_received", 0)) != i + 1:
			routed_ok = false
			break
		accepted_first.append(canvas._samples.back())
		first_times.append(canvas._sample_times_us.back())
	check(routed_ok, "every raw first-stroke mouse event reaches the native queue")
	if not routed_ok:
		canvas.cancel_gesture()
		quit(1)
		return
	button(canvas, path[-1], false)
	if canvas.session == null:
		check(false, "first pointer release retains native backlog")
		quit(1)
		return
	accepted_first.append(canvas._samples.back())
	first_times.append(canvas._sample_times_us.back())
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
		"first pointer-released stroke has queued input")
	canvas.color_rgba = SECOND
	canvas.brush_width = 9.0
	var sample_screen: Vector2 = canvas.global_position + canvas.pixel_to_position(Vector2(-12.5, 49.5))
	var before: Color = root.get_texture().get_image().get_pixelv(Vector2i(sample_screen))
	var next: PackedVector2Array = PackedVector2Array([Vector2(-25.5, 48.5),
		Vector2(-12.5, 49.5), Vector2(2.5, 48.5), Vector2(20.5, 49.5)])
	button(canvas, next[0], true)
	for i: int in range(1, next.size()):
		move(canvas, next[i])
	button(canvas, next[next.size() - 1], false)
	var captured_second: Dictionary = {"points": PackedVector2Array(canvas._deferred_points),
		"times": PackedInt64Array(canvas._deferred_times_us)}
	var reference_first: Dictionary = {"points": accepted_first, "times": first_times}
	# Godot may send a final routed motion before the button release; the
	# actual deferred arrays, not the synthetic target count, are the oracle.
	var second_size: int = (captured_second["points"] as PackedVector2Array).size()
	check(accepted_first.size() == path.size() + 1 and
		second_size >= next.size() and second_size <= next.size() + 1 and
		(captured_second["times"] as PackedInt64Array).size() == second_size,
		"reference retains every raw press/motion/release sample and timestamp")
	check(doc.revision == revision and not canvas._deferred_stroke.is_empty(),
		"second complete GUI pointer stroke is retained before first publishes")
	var frames: int = 0
	while (canvas.session != null or not canvas._deferred_stroke.is_empty()) and frames < 500:
		await process_frame
		frames += 1
	check(frames < 500 and doc.revision == revision + 2,
		"two real-input strokes publish in order, each with one revision")
	var reference: Dictionary = NATIVE_REFERENCE.commit(root, reference_first,
		captured_second, FIRST, 30.0, SECOND, 9.0)
	var oracle: DrawingDocument = reference["document"]
	check(bool(reference["ok"]) and oracle.history_length() == 2,
		"separate timestamp-identical native Hokusai control commits two strokes")
	check(render_bytes(doc) == render_bytes(oracle),
		"real pointer queue matches canonical native reference bytes")
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot: Image = root.get_texture().get_image()
	var pixel: Color = snapshot.get_pixelv(Vector2i(sample_screen))
	var source: int = int(doc.read_pixel(layer, -12, 49).value)
	check(source != 0 and Vector3(pixel.r, pixel.g, pixel.b).distance_to(
			Vector3(before.r, before.g, before.b)) > 0.1,
		"software GL framebuffer displays changed second-stroke pigment")
	check(doc.undo().ok and oracle.undo().ok and render_bytes(doc) == render_bytes(oracle),
		"first Undo removes only the second pointer stroke")
	check(doc.undo().ok and oracle.undo().ok and render_bytes(doc) == render_bytes(oracle),
		"second Undo removes the first pointer stroke")
	check(doc.redo().ok and oracle.redo().ok and doc.redo().ok and oracle.redo().ok,
		"independent Redo steps restore both transactions")
	check(render_bytes(doc) == render_bytes(oracle), "Redo matches byte-exact reference")
	print("T124_NATIVE_RESULT checks=%d failures=%d frames=%d" % [checks, failures, frames])
	if failures == 0:
		print("T124_NATIVE_PASSED checks=%d failures=0" % checks)
	canvas.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
