extends SceneTree
## T-095: correlate bounded Canvas frame CPU phases with pending pointer age.

const INK: int = 0x9050d7b9
const AREA: Rect2i = Rect2i(-48, -48, 96, 96)

var checks: int = 0
var failures: int = 0


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_FRAME_BACKLOG_FAILED: " + reason)


func make_canvas() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(500, 360)
	return canvas


func test_pending_age_and_interpolation() -> void:
	var canvas: Control = make_canvas()
	check(canvas.has_method("_frame_input_backlog"),
		"frame backlog sampler is available")
	if not canvas.has_method("_frame_input_backlog"):
		canvas.free()
		return
	var at_us: int = 1000000
	var empty: Dictionary = canvas._frame_input_backlog(at_us)
	check(int(empty.get("pending_input_count", -1)) == 0 and
		int(empty.get("oldest_pending_age_us", -1)) == 0,
		"idle frame has no pending samples or positive age")
	canvas._sample_times_us.append_array([at_us - 350, at_us - 150, at_us - 50])
	canvas._sample_index = 1
	var queued: Dictionary = canvas._frame_input_backlog(at_us)
	check(int(queued.get("pending_input_count", -1)) == 2 and
		int(queued.get("oldest_pending_age_us", -1)) == 150,
		"consumed prefix is ignored and oldest unconsumed sample is timed")
	canvas._has_segment_target = true
	canvas._target_arrival_us = at_us - 500
	var in_progress: Dictionary = canvas._frame_input_backlog(at_us)
	check(int(in_progress.get("pending_input_count", -1)) == 3 and
		int(in_progress.get("oldest_pending_age_us", -1)) == 500,
		"interpolated in-flight target is counted exactly once and takes oldest timestamp")
	canvas._target_arrival_us = at_us - 20
	var newer_target: Dictionary = canvas._frame_input_backlog(at_us)
	check(int(newer_target.get("pending_input_count", -1)) == 3 and
		int(newer_target.get("oldest_pending_age_us", -1)) == 150,
		"queued input predating interpolated target still determines age")
	canvas._sample_index = canvas._sample_times_us.size()
	var only_target: Dictionary = canvas._frame_input_backlog(at_us)
	check(int(only_target.get("pending_input_count", -1)) == 1 and
		int(only_target.get("oldest_pending_age_us", -1)) == 20,
		"partially interpolated target survives an exhausted sample buffer")
	canvas._target_arrival_us = at_us + 100
	check(int(canvas._frame_input_backlog(at_us).get("oldest_pending_age_us", -1)) == 0,
		"clock skew never yields negative pending age")
	canvas._has_segment_target = false
	canvas._sample_times_us.clear()
	canvas._sample_index = 0
	check(int(canvas._frame_input_backlog(at_us).get("pending_input_count", -1)) == 0,
		"cancelled or fully drained input clears the queue snapshot")
	# A long stroke compacts only consumed samples. Its oldest *remaining*
	# receipt time must not move when the consumed prefix is discarded.
	for i: int in range(600):
		canvas._samples.append(Vector2(float(i), 0))
		canvas._sample_times_us.append(at_us - 600 + i)
	canvas._sample_index = 350
	canvas._metrics["sample_compactions"] = 0
	canvas._has_segment_target = true
	canvas._target_arrival_us = at_us - 400
	var before_compaction: Dictionary = canvas._frame_input_backlog(at_us)
	canvas._compact_sample_queue()
	var after_compaction: Dictionary = canvas._frame_input_backlog(at_us)
	check(before_compaction == after_compaction and
		canvas._sample_index == 0 and canvas._sample_times_us.size() == 250,
		"queue compaction does not change pending age or count, including the in-flight target")
	canvas.free()


func test_bounded_frame_alignment() -> void:
	var canvas: Control = make_canvas()
	canvas._metrics.clear()
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_phase_total"] = 0
	canvas._frame_phase_write_index = 0
	var cap: int = canvas.MAX_FRAME_PHASE_SAMPLES
	for i: int in range(2 * cap + 23):
		var sample: Dictionary = {"full_draw_cpu_us": i + 10,
			"compose_cpu_us": i, "frame_end_us": 2000000 + i * 17,
			"pending_input_count": i % 9,
			"oldest_pending_age_us": i * 3}
		if i == 0:
			sample["oldest_pending_age_us"] = 900000
		canvas._record_frame_phase(sample)
	canvas._finalize_frame_phase_window()
	var frames: Array = canvas._metrics["frame_phases_us"] as Array
	check(frames.size() == cap and
		int(canvas._metrics.get("frame_phase_total", -1)) == 2 * cap + 23,
		"bounded frame ring retains latest samples and exact lifetime count")
	check(int(canvas._metrics.get("max_frame_oldest_pending_age_us", -1)) == 900000 and
		int(canvas._metrics.get("max_frame_pending_input_count", -1)) == 8,
		"all-time queue maxima survive eviction of an early stall")
	var ordered: bool = true
	for j: int in range(frames.size()):
		var expected: int = cap + 23 + j
		var frame: Dictionary = frames[j] as Dictionary
		if int(frame.get("frame_end_us", -1)) != 2000000 + expected * 17 or \
			int(frame.get("pending_input_count", -1)) != expected % 9 or \
			int(frame.get("oldest_pending_age_us", -1)) != expected * 3 or \
			int(frame.get("full_draw_cpu_us", -1)) != expected + 10:
			ordered = false
			break
	check(ordered, "frame timestamp, backlog and CPU phases retain exact joint order")
	canvas.free()


func snapshot(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(result.ok, "source snapshot renders")
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func test_live_brush_frames() -> void:
	var document: DrawingDocument = DrawingDocument.new("frame-backlog-live", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var canvas: Control = make_canvas()
	if not canvas.has_method("_frame_input_backlog"):
		check(false, "live Canvas exposes the backlog sampler")
		canvas.free()
		return
	canvas.document = document
	canvas.layer_id = layer
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var original: PackedByteArray = snapshot(document)
	var first: Vector2 = Vector2(-15.5, -9.5)
	var last: Vector2 = Vector2(18.5, 12.5)
	canvas.start_gesture(canvas.pixel_to_position(first))
	canvas.paint_to(Vector2i(18, 12))
	var probe_us: int = Time.get_ticks_usec()
	var pending: Dictionary = canvas._frame_input_backlog(probe_us)
	check(int(pending.get("pending_input_count", -1)) >= 1 and
		int(pending.get("oldest_pending_age_us", -1)) >= 0,
		"live 60px Brush samples are visible to the backlog sampler")
	canvas.queue_redraw()
	await process_frame
	await process_frame
	var frame_history: Array = canvas._metrics.get("frame_phases_us", []) as Array
	var fields_ok: bool = not frame_history.is_empty()
	var last_at_us: int = 0
	for item: Variant in frame_history:
		var frame: Dictionary = item as Dictionary
		for key: String in ["frame_end_us", "pending_input_count", "oldest_pending_age_us",
				"full_draw_cpu_us", "compose_cpu_us", "texture_cpu_us"]:
			if not frame.has(key) or int(frame[key]) < 0:
				fields_ok = false
		if int(frame.get("frame_end_us", 0)) < last_at_us:
			fields_ok = false
		last_at_us = int(frame.get("frame_end_us", 0))
	check(fields_ok and last_at_us > 0,
		"real Canvas frames align monotonic timestamps, pending age/depth and CPU phases")
	canvas.finish_gesture(canvas.pixel_to_position(last))
	var guard: int = 0
	while canvas.session != null and guard < 500:
		canvas._drain_segments(256)
		guard += 1
	check(canvas.session == null and document.revision == 2,
		"live 60px Brush commits exactly once")
	var published: Dictionary = canvas.last_gesture_metrics
	var completed: Array = published.get("frame_phases_us", []) as Array
	check(completed.size() >= frame_history.size() and
		int(published.get("frame_phase_total", -1)) == completed.size(),
		"committed profile retains every short-gesture frame")
	var committed: PackedByteArray = snapshot(document)
	var reference: DrawingDocument = DrawingDocument.new("frame-backlog-control", 64)
	var reference_layer: String = String(reference.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var edit: DrawingEditSession = reference.begin_edit(reference_layer,
		reference.revision).value
	var source_first: Vector2 = canvas.source_position(canvas.pixel_to_position(first))
	var source_last: Vector2 = canvas.source_position(canvas.pixel_to_position(last))
	check(edit.paint_path(PackedVector2Array([source_first, source_last]),
		INK, 60.0).ok and edit.commit().ok,
		"independent reference Brush stroke commits")
	check(committed == snapshot(reference),
		"queue profiling does not mutate RGBA8 Brush output")
	check(document.undo().ok and snapshot(document) == original and
		document.redo().ok and snapshot(document) == committed,
		"queue profiling preserves single-step Undo/Redo")
	canvas.queue_free()
	await process_frame


func run() -> void:
	test_pending_age_and_interpolation()
	test_bounded_frame_alignment()
	await test_live_brush_frames()
	print("T095_FRAME_BACKLOG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_FRAME_BACKLOG_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
