extends SceneTree

const NATIVE_REFERENCE = preload("res://tests/t206_native_queued_reference.gd")
## Released strokes may drain asynchronously without dropping the next
## chronological Brush/Eraser press. Compare both complete source paths with
## a separate same-source/time native Hokusai replay, including undo boundaries.

const AREA: Rect2i = Rect2i(-85, -80, 180, 160)
const FIRST: int = 0xb44183e9
const SECOND: int = 0xffa9421b
## The first press must leave a real backlog even on a fast CPU: a release
## processes at most 256 segments synchronously. With 840 distinct samples,
## the next press always exercises the deferred-gesture path, not an idle edit.
const FIRST_SAMPLES: int = 840
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T124_QUEUED_FAILED: " + label)


func make_target(name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	return {"document": doc, "layer": layer}


func first_path() -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(FIRST_SAMPLES):
		var t: float = float(i) / float(FIRST_SAMPLES - 1)
		path.append(Vector2(-35.5 + 66.0 * t,
			-16.5 + sin(t * TAU * 8.0) * 29.0))
	return path


func second_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-28.5, 28.5), Vector2(-12.5, 22.5),
		Vector2(6.5, 18.5), Vector2(24.5, 27.5), Vector2(36.5, 32.5)])


func capture(canvas: Control, path: PackedVector2Array) -> void:
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


## Store the *accepted* input, not an idealized path reconstructed later.
## Hokusai's stroke clock affects its paint, so the native reference must
## receive exactly the same press, motion, and release timestamps.
func capture_native_receipts(canvas: Control, path: PackedVector2Array) -> Dictionary:
	var points: PackedVector2Array = PackedVector2Array()
	var times: PackedInt64Array = PackedInt64Array()
	var first: Vector2 = canvas.source_position(canvas.pixel_to_position(path[0]))
	var press_us: int = Time.get_ticks_usec()
	canvas.start_gesture(Vector2.ZERO, first, {"press_us": press_us})
	points.append(first)
	times.append(press_us)
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
		points.append(canvas._samples.back())
		times.append(canvas._sample_times_us.back())
	var release_at: int = Time.get_ticks_usec()
	var finish: Vector2 = canvas.source_position(canvas.pixel_to_position(path[-1]))
	canvas.finish_gesture(Vector2.ZERO, finish, release_at)
	points.append(finish)
	times.append(release_at)
	return {"points": points, "times": times}


func captured_deferred(canvas: Control) -> Dictionary:
	return {"points": PackedVector2Array(canvas._deferred_points),
		"times": PackedInt64Array(canvas._deferred_times_us)}


func deferred(canvas: Control) -> Dictionary:
	var value: Variant = canvas.get("_deferred_stroke")
	return value if value is Dictionary else {}


func wait_until_finished(canvas: Control, max_frames: int = 600) -> bool:
	var frame: int = 0
	while (canvas.session != null or not deferred(canvas).is_empty()) and frame < max_frames:
		await process_frame
		frame += 1
	return frame < max_frames


func compare_pixels(a: DrawingDocument, b: DrawingDocument, label: String) -> void:
	var ra: DrawingResult = DrawingRenderer.render(a, AREA)
	var rb: DrawingResult = DrawingRenderer.render(b, AREA)
	check(ra.ok and rb.ok and ra.value.get_data() == rb.value.get_data(), label)


func scenario(release_before_promotion: bool, erase_second: bool = false) -> void:
	var setup: Dictionary = make_target("queued")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	canvas.color_rgba = FIRST
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	var one: PackedVector2Array = first_path()
	var two: PackedVector2Array = second_path() if not erase_second else PackedVector2Array(
		[Vector2(-22.5, -18.5), Vector2(0.5, -14.5), Vector2(19.5, -20.5)])
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-65, -65, 130, 130), true)
	check(mask.combine_rectangle(Rect2i(4, -5, 6, 10), "Subtract"),
		"selection hole prepared for both transactions")
	canvas.set_selection_mask(mask)
	var first_receipts: Dictionary = capture_native_receipts(canvas, one)
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
		"long first stroke leaves an unfinished release backlog")
	canvas.brush_width = 9.0
	canvas.color_rgba = SECOND
	canvas.tool = "Eraser" if erase_second else "Brush"
	canvas.start_gesture(canvas.pixel_to_position(two[0]))
	check(not deferred(canvas).is_empty() and doc.revision == revision,
		"second press is buffered without publishing or replacing the first edit")
	for i: int in range(1, two.size() - 1):
		canvas.update_gesture(canvas.pixel_to_position(two[i]))
	var second_receipts: Dictionary = {}
	if release_before_promotion:
		canvas.finish_gesture(canvas.pixel_to_position(two[two.size() - 1]))
		second_receipts = captured_deferred(canvas)
		check(not bool(deferred(canvas).get("capturing", true)),
			"second mouse-up is retained before the first commit")
		# Navigation and future tool settings must not rewrite either source path.
		canvas.zoom = 3.0
		canvas.camera = Vector2(17, -19)
		canvas.tool = "Pan"
		canvas.brush_width = 2.0
		canvas.color_rgba = 0xff000000
		check(not deferred(canvas).is_empty(),
			"released queued source samples survive zoom, pan and toolbar changes")
	else:
		second_receipts = captured_deferred(canvas)
		var count: int = 0
		while not deferred(canvas).is_empty() and count < 550:
			await process_frame
			count += 1
		check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.CAPTURING,
			"held second press is promoted when first commit finishes")
		canvas.update_gesture(canvas.pixel_to_position(two[two.size() - 1]))
		var delivered_points: PackedVector2Array = second_receipts["points"]
		var delivered_times: PackedInt64Array = second_receipts["times"]
		delivered_points.append(canvas._samples.back())
		delivered_times.append(canvas._sample_times_us.back())
		var finish: Vector2 = canvas.source_position(canvas.pixel_to_position(two[-1]))
		var release_us: int = Time.get_ticks_usec()
		canvas.finish_gesture(Vector2.ZERO, finish, release_us)
		delivered_points.append(finish)
		delivered_times.append(release_us)
		second_receipts = {"points": delivered_points, "times": delivered_times}
	check(await wait_until_finished(canvas), "both strokes drain in bounded frames")
	check(doc.revision == revision + 2, "two independent edits publish chronologically")
	var ref_result: Dictionary = NATIVE_REFERENCE.commit(root, first_receipts,
		second_receipts, FIRST, 40.0, SECOND, 9.0, erase_second, mask)
	var oracle: DrawingDocument = ref_result["document"]
	check(bool(ref_result["ok"]),
		"sequential native reference commits exactly two transactions")
	var captured_first: PackedVector2Array = first_receipts["points"]
	var captured_second: PackedVector2Array = second_receipts["points"]
	check(captured_first.size() == one.size() + 1 and
		captured_second.size() == two.size() + (1 if not release_before_promotion else 0),
		"reference captures every actual press, motion and release without omission")
	check(doc.history_length() == 2 and oracle.history_length() == 2,
		"queued and direct native history each contain two transactions")
	compare_pixels(doc, oracle, "two native paths retain exact canonical bytes")
	var published: DrawingResult = DrawingRenderer.render(doc, AREA)
	if release_before_promotion and not erase_second:
		var divergent: Dictionary = NATIVE_REFERENCE.commit(root, first_receipts,
			second_receipts, FIRST, 40.0, SECOND, 19.0, false, mask)
		var changed: DrawingResult = DrawingRenderer.render(divergent["document"], AREA)
		check(bool(divergent["ok"]) and published.ok and changed.ok and
			published.value.get_data() != changed.value.get_data(),
			"native reference detects a changed queued brush width")
	check(doc.undo().ok and oracle.undo().ok, "first Undo removes only second stroke")
	compare_pixels(doc, oracle, "first Undo leaves first stroke intact")
	var first_only: DrawingResult = DrawingRenderer.render(doc, AREA)
	check(published.ok and first_only.ok and
		published.value.get_data() != first_only.value.get_data(),
		"second %s gesture changes canonical pixels before Undo" % (
			"Eraser" if erase_second else "Brush"))
	check(doc.undo().ok and oracle.undo().ok, "second Undo removes first stroke")
	compare_pixels(doc, oracle, "both Undo transactions match oracle")
	check(doc.redo().ok and oracle.redo().ok and doc.redo().ok and oracle.redo().ok,
		"both Redo transactions restore both strokes")
	compare_pixels(doc, oracle, "both Redo transactions match original pixels")
	canvas.queue_free()
	await process_frame


func overflow_scenario() -> void:
	var setup: Dictionary = make_target("overflow")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	capture(canvas, first_path())
	check(canvas._stroke_phase == canvas.StrokePhase.DRAINING, "overflow guard starts with backlog")
	var errors: Array[String] = []
	canvas.canvas_error.connect(func(message: String) -> void: errors.append(message))
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	for i: int in range(4096):
		canvas.update_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	check(deferred(canvas).is_empty() and not errors.is_empty(),
		"excess input fails visibly and releases bounded capture memory")
	check(await wait_until_finished(canvas), "original released stroke still finishes")
	check(doc.revision == revision + 1, "no overflow fragment becomes an edit")
	canvas.queue_free()
	await process_frame


func failed_predecessor_scenario() -> void:
	var setup: Dictionary = make_target("failed-predecessor")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	capture(canvas, first_path())
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(8.5, 2.5)))
	check(not deferred(canvas).is_empty(), "pending second release held before failed commit")
	var errors: Array[String] = []
	canvas.canvas_error.connect(func(message: String) -> void: errors.append(message))
	if canvas.session == null:
		check(false, "test prerequisite: predecessor remains active for stale-revision fault")
		canvas.queue_free()
		await process_frame
		return
	canvas.session.expected_revision += 1  # Fault injection: stale commit, no document mutation.
	canvas._commit_stroke()
	check(deferred(canvas).is_empty() and canvas.session == null,
		"failed predecessor never promotes or leaks the queued second session")
	check(doc.revision == revision and not errors.is_empty(),
		"failed predecessor reports an error and publishes neither stroke")
	canvas.queue_free()
	await process_frame


func run() -> void:
	await scenario(true)
	await scenario(false)
	await scenario(true, true)
	await scenario(false, true)
	await overflow_scenario()
	await failed_predecessor_scenario()
	if failures == 0:
		print("T124_QUEUED_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T124_QUEUED_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
