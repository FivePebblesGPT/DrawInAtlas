extends SceneTree
## T-096 X11/Mesa real mouse/keyboard, exact contour framebuffer, floating Move.
## Software callback timestamps are diagnostic and are NOT input-to-photon.

var checks: int = 0
var failures: int = 0
var move_ms: Array[float] = []
var receipt_ms: Array[float] = []
var compose_ms: Array[float] = []
var upload_ms: Array[float] = []
var callback_ms: Array[float] = []


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T096_NATIVE_FAILED: " + label)


func frames(count: int = 3) -> void:
	for i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func button(canvas: Control, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(position)
	event.global_position = event.position
	root.push_input(event, true)


func motion(canvas: Control, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + canvas.pixel_to_position(position)
	event.global_position = event.position
	root.push_input(event, true)


func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)


func sample(canvas: Control, at: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var location: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(at))
	if location.x < 0 or location.y < 0 or location.x >= image.get_width() or location.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(location)


func distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func pixel(doc: DrawingDocument, layer: String, at: Vector2i) -> int:
	var result: DrawingResult = doc.read_pixel(layer, at.x, at.y)
	return int(result.value) if result.ok else -1


func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	root.size = Vector2i(1100, 820)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(40, 35)
	canvas.size = Vector2(990, 740)
	canvas.zoom = 4.0
	canvas.show_grid = false
	canvas.show_pixel_grid = false
	canvas.tool = "Select"
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t096-native", 16)
	var under: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Under").value)
	var active: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Active").value)
	canvas.document = doc
	canvas.layer_id = active
	var underneath: DrawingEditSession = doc.begin_edit(under, doc.revision).value as DrawingEditSession
	check(underneath._stage(-31, -25, 0xff22ee11).ok and underneath.commit().ok,
		"lower-layer byte seeded")
	var seed: DrawingEditSession = doc.begin_edit(active, doc.revision).value as DrawingEditSession
	for y: int in range(-27, 39):
		for x: int in range(-36, 41):
			if (x + y * 7) % 6 == 0:
				seed._stage(x, y, 0xffbb2288)
	check(seed._stage(-31, -25, 0xffd03020).ok and seed.commit().ok,
		"seed actual 5000px+ region including signed seams")
	await frames(6)

	# Create the main 5k+ selection by real marquee mouse events.
	button(canvas, Vector2(-36.5, -27.5), true)
	motion(canvas, Vector2(40.5, 38.5))
	await frames(2)
	check(canvas.selecting and canvas._marquee_dragged, "active marquee before release")
	button(canvas, Vector2(40.5, 38.5), false)
	check(canvas.selected.size.x * canvas.selected.size.y > 4096,
		"persistent selected region exceeds old bounding-box shortcut")
	canvas.selection_mode = "Subtract"
	button(canvas, Vector2(-7.5, -7.5), true)
	motion(canvas, Vector2(8.5, 11.5))
	button(canvas, Vector2(8.5, 11.5), false)
	canvas.selection_mode = "Add"
	button(canvas, Vector2(47.5, -8.5), true)
	motion(canvas, Vector2(61.5, 15.5))
	button(canvas, Vector2(61.5, 15.5), false)
	canvas.selection_mode = "Replace"
	check(not canvas.selection_mask.allows(Vector2i(-2, 2)) and
		canvas.selection_mask.allows(Vector2i(53, 0)) and
		canvas.selection_mask.allows(Vector2i(-31, -25)),
		"pointer gestures produced a real hole and disjoint island")
	await frames()
	var hole_edge: Vector2 = Vector2(-8.0, 2.0)
	var island_edge: Vector2 = Vector2(47.0, -2.0)
	var main_edge: Vector2 = Vector2(-37.0, -15.0)
	var false_bounding_edge: Vector2 = Vector2(53.0, -27.0)
	var selected_colors: Array[Color] = [sample(canvas, hole_edge), sample(canvas, island_edge),
		sample(canvas, main_edge), sample(canvas, false_bounding_edge)]
	var original: DrawingSelection = canvas.selection_mask.detached_copy()
	canvas.set_selection_mask(null, false)
	await frames()
	var background_colors: Array[Color] = [sample(canvas, hole_edge), sample(canvas, island_edge),
		sample(canvas, main_edge), sample(canvas, false_bounding_edge)]
	check(distance(selected_colors[0], background_colors[0]) > 0.08,
		"real framebuffer shows internal subtracted hole boundary")
	check(distance(selected_colors[1], background_colors[1]) > 0.08,
		"real framebuffer shows distant added island contour")
	check(distance(selected_colors[2], background_colors[2]) > 0.08,
		"real framebuffer shows main region boundary")
	check(distance(selected_colors[3], background_colors[3]) < 0.08,
		"no false enclosing-bounds outline in gap between islands")
	canvas.set_selection_mask(original, false)
	await frames()

	var revision: int = doc.revision
	var history: int = doc.history_length()
	var original_pixel: int = pixel(doc, active, Vector2i(-31, -25))
	canvas.tool = "Move"
	var source: Vector2 = Vector2(-31.5, -25.5)
	var destination: Vector2 = Vector2(-19.5, -30.5)
	var sample_destination: Vector2 = Vector2(-18.5, -29.5)
	var dest_before: Color = sample(canvas, sample_destination)
	button(canvas, source, true)
	var first_capture: DrawingClipboard = canvas._move_capture
	check(first_capture != null and canvas._floating_source_revision == revision,
		"first pointer-down captures source once at pinned revision")
	for i: int in range(1, 9):
		var position: Vector2 = source + Vector2(i * 1.5, -5.0)
		var pointer_at: int = Time.get_ticks_usec()
		motion(canvas, position)
		await frames(2)
		callback_ms.append(float(Time.get_ticks_usec() - pointer_at) / 1000.0)
		var sample_metrics: Dictionary = canvas.last_move_metrics
		move_ms.append(float(sample_metrics.get("motion_to_preview_submit_us", 0)) / 1000.0)
		receipt_ms.append(float(sample_metrics.get("input_to_preview_submit_us", 0)) / 1000.0)
		compose_ms.append(float(canvas.last_frame_metrics.get("compose_cpu_us", 0)) / 1000.0)
		upload_ms.append(float(canvas.last_frame_metrics.get("texture_cpu_us", 0)) / 1000.0)
		check(canvas._move_capture == first_capture and doc.revision == revision,
			"motion %d reuses identical capture and detached revision" % i)
	check(canvas._move_preview != null and canvas._move_preview_offset == Vector2i(12, -5),
		"native motion delivered latest 12px/5px displacement")
	check(distance(sample(canvas, sample_destination), dest_before) > 0.08,
		"held-button floating content becomes visible at destination")
	button(canvas, destination, false)
	await frames(3)
	check(canvas.has_floating_move() and doc.revision == revision and
		doc.history_length() == history, "release retains uncommitted floating content")
	var new_pointer: Vector2 = Vector2(-24.5, -30.5)
	button(canvas, destination, true)
	motion(canvas, new_pointer)
	await frames(3)
	button(canvas, new_pointer, false)
	await frames(2)
	check(canvas._move_preview_offset == Vector2i(7, -5) and canvas.has_floating_move() and
		canvas._move_capture == first_capture,
		"second drag accumulates and reuses the original capture")
	key(KEY_ESCAPE)
	await frames()
	check(not canvas.has_floating_move() and canvas._move_capture == null and
		pixel(doc, active, Vector2i(-31, -25)) == original_pixel and
		doc.revision == revision and doc.history_length() == history,
		"Escape cancels all floating drags without history/bytes")

	# A fresh gesture and outside-click drop must publish ONE history step.
	button(canvas, source, true)
	motion(canvas, destination)
	await frames(3)
	button(canvas, destination, false)
	await frames(3)
	var drop_start: int = Time.get_ticks_usec()
	button(canvas, Vector2(95.5, 58.5), true)
	await frames(2)
	var drop_ms: float = float(Time.get_ticks_usec() - drop_start) / 1000.0
	var drop_cpu_ms: float = float(canvas.last_move_metrics.get("drop_cpu_us", 0)) / 1000.0
	check(doc.revision == revision + 1 and doc.history_length() == history + 1 and
		not canvas.has_floating_move() and canvas._move_capture == null,
		"outside click drops one edit, no floating resources retained")
	check(pixel(doc, active, Vector2i(-31, -25)) == 0 and
		pixel(doc, active, Vector2i(-19, -30)) == original_pixel and
		pixel(doc, under, Vector2i(-31, -25)) == 0xff22ee11,
		"source clears, destination pastes exact RGBA and lower layer unchanged")
	check(doc.undo().ok and pixel(doc, active, Vector2i(-31, -25)) == original_pixel and
		doc.redo().ok and pixel(doc, active, Vector2i(-31, -25)) == 0,
		"one-step Undo/Redo restores exact original and destination")

	check(doc.undo().ok and pixel(doc, active, Vector2i(-31, -25)) == original_pixel,
		"restore source for separate 25% and 786% pointer runs")

	# Cold 25% viewport draws selection without scanning an entire 5000px mask.
	canvas.zoom = 0.25
	canvas.set_selection_mask(original, false)
	var cold_start: int = Time.get_ticks_usec()
	canvas.queue_redraw()
	await frames()
	var cold_ms: float = float(Time.get_ticks_usec() - cold_start) / 1000.0
	var cold_outline: float = float(canvas.last_frame_metrics.get("selection_outline_cpu_us", 0)) / 1000.0
	var cold_compose: float = float(canvas.last_frame_metrics.get("compose_cpu_us", 0)) / 1000.0
	canvas.queue_redraw()
	await frames()
	var warm_compose: float = float(canvas.last_frame_metrics.get("compose_cpu_us", 0)) / 1000.0
	check(canvas.selection_mask.allows(Vector2i(53, 0)) and
		canvas.selection_mask.bounds.has_area(), "zoom-out preserves truth of island mask")
	# Native low- and high-zoom Move input, including real Escape and Enter.
	canvas.tool = "Move"
	var again_rev: int = doc.revision
	button(canvas, source, true)
	button(canvas, source, false)
	check(not canvas.has_floating_move() and canvas._move_capture == null and
		doc.revision == again_rev, "stationary Move click frees immutable payload")
	button(canvas, source, true)
	for i: int in range(1, 7):
		motion(canvas, source + Vector2(i * 4.0, i * 1.33333))
		await frames(2)
	button(canvas, source + Vector2(24.0, 8.0), false)
	await frames(2)
	check(canvas.has_floating_move() and canvas._move_preview_offset == Vector2i(24, 8) and
		canvas.last_move_metrics.get("input_to_preview_submit_us", -1) >= 0,
		"25% pointer batches show detached move and capture receipt-to-stage latency")
	key(KEY_ESCAPE)
	await frames()
	check(doc.revision == again_rev and not canvas.has_floating_move(),
		"25% Move Escape leaves no history")
	canvas.zoom = 7.86
	canvas.set_selection_mask(original, false)
	await frames()
	button(canvas, source, true)
	motion(canvas, source + Vector2(7.0, 1.0))
	await frames(2)
	button(canvas, source + Vector2(7.0, 1.0), false)
	await frames(2)
	check(canvas.has_floating_move() and canvas._move_preview_offset == Vector2i(7, 1),
		"786% native Move leaves one floating preview before Enter")
	key(KEY_ENTER)
	await frames(3)
	check(not canvas.has_floating_move() and doc.revision == again_rev + 1 and
		pixel(doc, active, Vector2i(-24, -24)) == original_pixel,
		"786% Enter publishes one exact selected-pixel transaction")
	check(doc.undo().ok and doc.revision == again_rev + 2,
		"786% Move Undo restores prior content")
	print("T096_NATIVE_TIMING: capture_ms=%.3f motion_stage_p50_ms=%.3f motion_stage_p95_ms=%.3f receipt_to_submit_p50_ms=%.3f receipt_to_submit_p95_ms=%.3f callback_p50_ms=%.3f callback_p95_ms=%.3f compose_p95_ms=%.3f upload_p95_ms=%.3f drop_callback_ms=%.3f drop_cpu_ms=%.3f cold_frame_callback_ms=%.3f cold_compose_ms=%.3f warm_compose_ms=%.3f cold_outline_ms=%.3f" % [
		float(canvas.last_move_metrics.get("capture_us", 0)) / 1000.0,
		percentile(move_ms, 0.5), percentile(move_ms, 0.95),
		percentile(receipt_ms, 0.5), percentile(receipt_ms, 0.95),
		percentile(callback_ms, 0.5), percentile(callback_ms, 0.95),
		percentile(compose_ms, 0.95), percentile(upload_ms, 0.95),
		drop_ms, drop_cpu_ms, cold_ms, cold_compose, warm_compose, cold_outline])
	print("T096_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T096_NATIVE_PASSED")
	quit(0 if failures == 0 else 1)
