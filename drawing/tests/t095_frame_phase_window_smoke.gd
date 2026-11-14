extends SceneTree
## T-095: owner-device profiling must retain bounded chronological per-frame
## CPU phase samples, including late stalls, without changing Brush pixels.

const INK: int = 0x9d43a1d7
const AREA: Rect2i = Rect2i(-35, -35, 70, 70)

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_FRAME_PHASE_FAILED: " + description)


func make_canvas() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(480, 320)
	return canvas


func reset_frame_metrics(canvas: Control) -> void:
	canvas._metrics.clear()
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_phase_total"] = 0
	canvas._frame_phase_write_index = 0


func frame_sample(i: int) -> Dictionary:
	return {"full_draw_cpu_us": 100 + i, "compose_cpu_us": i,
		"texture_cpu_us": i * 2, "preview_index_cpu_us": i * 3,
		"selection_outline_cpu_us": i * 4}


func test_bounded_recorder() -> void:
	var canvas: Control = make_canvas()
	check(canvas.has_method("_record_frame_phase") and
		canvas.has_method("_finalize_frame_phase_window"),
		"Canvas exposes per-frame recorder and chronological finalizer")
	if not canvas.has_method("_record_frame_phase"):
		canvas.free()
		return
	reset_frame_metrics(canvas)
	canvas._record_frame_phase({"full_draw_cpu_us": -5,
		"compose_cpu_us": -2, "texture_cpu_us": 12})
	canvas._record_frame_phase(frame_sample(2))
	canvas._finalize_frame_phase_window()
	var samples: Array = canvas._metrics["frame_phases_us"] as Array
	check(samples.size() == 2 and int(samples[0]["full_draw_cpu_us"]) == 0
		and int(samples[0]["compose_cpu_us"]) == 0 and
		int(samples[0]["texture_cpu_us"]) == 12 and
		int(samples[1]["full_draw_cpu_us"]) == 102,
		"short stroke retains every phase and clamps invalid negative samples")
	check(int(canvas._metrics["frame_phase_total"]) == 2 and
		int(canvas._metrics["max_frame_texture_cpu_us"]) == 12,
		"short window keeps exact count and worst upload cost")

	reset_frame_metrics(canvas)
	var cap: int = canvas.MAX_FRAME_PHASE_SAMPLES
	var within_limit: bool = true
	for i: int in range(3 * cap + 71):
		var sample: Dictionary = frame_sample(i)
		if i == 0:
			sample["compose_cpu_us"] = 990000
		canvas._record_frame_phase(sample)
		if (canvas._metrics["frame_phases_us"] as Array).size() > cap:
			within_limit = false
	check(within_limit, "long capture never retains more than the fixed frame budget")
	canvas._finalize_frame_phase_window()
	samples = canvas._metrics["frame_phases_us"] as Array
	check(samples.size() == cap and
		int(canvas._metrics["frame_phase_total"]) == 3 * cap + 71 and
		int(canvas._metrics["max_frame_compose_cpu_us"]) == 990000,
		"evicted early compositor stall stays in all-time maximum and count")
	var ordered: bool = true
	for i: int in range(cap):
		var expected: int = 3 * cap + 71 - cap + i
		var sample: Dictionary = samples[i] as Dictionary
		if (int(sample.get("compose_cpu_us", -1)) != expected or
			int(sample.get("full_draw_cpu_us", -1)) != expected + 100 or
			int(sample.get("texture_cpu_us", -1)) != expected * 2 or
			int(sample.get("preview_index_cpu_us", -1)) != expected * 3):
			ordered = false
			break
	check(ordered, "every retained phase has correct order after multiple ring wraps")

	reset_frame_metrics(canvas)
	for i: int in range(cap * 2):
		canvas._record_frame_phase(frame_sample(i))
	canvas._finalize_frame_phase_window()
	samples = canvas._metrics["frame_phases_us"] as Array
	check(int(samples[0]["compose_cpu_us"]) == cap and
		int(samples[-1]["compose_cpu_us"]) == cap * 2 - 1,
		"complete ring rotation preserves chronological ordering")
	canvas.free()


func snapshot(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(result.ok, "source snapshot renders")
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func test_live_preview() -> void:
	var document: DrawingDocument = DrawingDocument.new("frame-phase-live", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var canvas: Control = make_canvas()
	canvas.document = document
	canvas.layer_id = layer
	canvas.brush_width = 12.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var original: PackedByteArray = snapshot(document)
	var start: Vector2 = Vector2(-12.5, -5.5)
	var end: Vector2 = Vector2(14.5, 8.5)
	canvas.start_gesture(canvas.pixel_to_position(start))
	await process_frame
	await process_frame
	canvas.paint_to(Vector2i(14, 8))
	canvas._drain_segments(256)
	canvas.queue_redraw()
	await process_frame
	await process_frame
	var actual_frames: int = int(canvas._metrics.get("frame_phase_total", 0))
	check(actual_frames >= 1 and
		actual_frames == int(canvas._metrics.get("preview_frames", -1)),
		"actual Canvas draw callbacks record one phase sample per preview frame")
	var samples: Array = canvas._metrics.get("frame_phases_us", []) as Array
	var valid: bool = not samples.is_empty()
	for sample_variant: Variant in samples:
		var sample: Dictionary = sample_variant as Dictionary
		for key: String in ["full_draw_cpu_us", "compose_cpu_us", "texture_cpu_us",
				"preview_index_cpu_us", "selection_outline_cpu_us"]:
			if not sample.has(key) or int(sample[key]) < 0:
				valid = false
	check(valid, "every real preview frame reports all nonnegative CPU phases")
	canvas.finish_gesture(canvas.pixel_to_position(end))
	var guard: int = 0
	while canvas.session != null and guard < 300:
		canvas._drain_segments(256)
		guard += 1
	check(canvas.session == null and document.revision == 2,
		"real pointer gesture commits once after bounded drain")
	var published: Dictionary = canvas.last_gesture_metrics
	print("T095_FRAME_PHASE_LIVE frames=%d max_draw_us=%d max_compose_us=%d max_upload_us=%d" % [
		int(published.get("frame_phase_total", -1)),
		int(published.get("max_frame_full_draw_cpu_us", -1)),
		int(published.get("max_frame_compose_cpu_us", -1)),
		int(published.get("max_frame_texture_cpu_us", -1))])
	check(int(published.get("frame_phase_total", -1)) ==
		(published.get("frame_phases_us", []) as Array).size() and
		int(published.get("frame_phase_total", -1)) >= actual_frames,
		"final snapshot retains the real short-stroke chronological distribution")
	var committed: PackedByteArray = snapshot(document)
	var reference: DrawingDocument = DrawingDocument.new("frame-phase-control", 64)
	var reference_layer: String = String(reference.create_layer(
		DrawingLayerNode.RASTER, "Paint", "root").value)
	var reference_edit: DrawingEditSession = reference.begin_edit(reference_layer,
		reference.revision).value
	var source_start: Vector2 = canvas.source_position(canvas.pixel_to_position(start))
	var source_end: Vector2 = canvas.source_position(canvas.pixel_to_position(end))
	check(reference_edit.paint_path(PackedVector2Array([source_start, source_end]),
		INK, 12.0).ok and reference_edit.commit().ok,
		"independent Brush reference stroke commits")
	check(committed == snapshot(reference),
		"profiling does not alter the RGBA8 rendered Brush result")
	check(document.undo().ok and snapshot(document) == original and
		document.redo().ok and snapshot(document) == committed,
		"profiling preserves one-step Undo and Redo")
	canvas.queue_free()
	await process_frame


func run() -> void:
	test_bounded_recorder()
	await test_live_preview()
	print("T095_FRAME_PHASE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_FRAME_PHASE_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
