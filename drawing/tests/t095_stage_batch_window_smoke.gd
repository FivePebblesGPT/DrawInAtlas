extends SceneTree
## T-095: retain the latest bounded stage-batch timing distribution, not the
## first 4096 batches of an arbitrarily long Brush stroke. Exact lifetime
## count, worst batch, and canonical paint/history must remain unchanged.

const INK: int = 0xb45f37d9
const VIEW: Rect2i = Rect2i(-40, -40, 80, 80)

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_STAGE_BATCH_WINDOW_FAILED: " + label)


func make_canvas() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(350, 260)
	return canvas


func make_document(name: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	return {"document": document, "layer": layer}


func snapshot(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, VIEW, 0, 0,
		VIEW.size.x * VIEW.size.y)
	check(result.ok, "whole drawing render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()


func reset_batch_metrics(canvas: Control) -> void:
	canvas._metrics["stage_batches_us"] = []
	canvas._metrics["stage_batch_total"] = 0
	canvas._metrics["max_stage_batch_us"] = 0
	canvas._batch_latency_write_index = 0


func test_recording() -> void:
	var canvas: Control = make_canvas()
	check(canvas.has_method("_record_stage_batch"),
		"canvas has the bounded stage-batch recorder")
	if not canvas.has_method("_record_stage_batch"):
		canvas.free()
		return
	reset_batch_metrics(canvas)
	for duration: int in [9, -3, 0, 24]:
		canvas._record_stage_batch(duration)
	canvas._finalize_stage_batch_window()
	check((canvas._metrics["stage_batches_us"] as Array) == [9, 0, 0, 24],
		"short strokes preserve complete batch timing and clamp negative input")
	check(int(canvas._metrics["stage_batch_total"]) == 4 and
		int(canvas._metrics["max_stage_batch_us"]) == 24,
		"short stroke count and worst batch are exact")

	reset_batch_metrics(canvas)
	var capacity: int = canvas.MAX_STAGE_BATCH_LATENCIES
	var bounded: bool = true
	for i: int in range(13001):
		# Early worst-case batch must remain observable after eviction.
		canvas._record_stage_batch(900000 if i == 0 else i)
		if (canvas._metrics["stage_batches_us"] as Array).size() > capacity:
			bounded = false
	check(bounded, "batch timing history never exceeds fixed capacity")
	canvas._finalize_stage_batch_window()
	var retained: Array = canvas._metrics["stage_batches_us"] as Array
	check(retained.size() == capacity, "long stroke retains fixed latest window")
	check(int(canvas._metrics["stage_batch_total"]) == 13001 and
		int(canvas._metrics["max_stage_batch_us"]) == 900000,
		"evicted outlier and exact lifetime batch count remain available")
	var ordered: bool = true
	for i: int in range(capacity):
		if int(retained[i]) != 13001 - capacity + i:
			ordered = false
			break
	check(ordered, "latest window is chronological even after multiple wraps")

	reset_batch_metrics(canvas)
	for i: int in range(capacity * 2):
		canvas._record_stage_batch(i)
	canvas._finalize_stage_batch_window()
	retained = canvas._metrics["stage_batches_us"] as Array
	check(retained[0] == capacity and retained[-1] == capacity * 2 - 1,
		"complete ring rotation keeps sample order")
	check(int(canvas._metrics["stage_batch_total"]) == capacity * 2 and
		int(canvas._metrics["max_stage_batch_us"]) == capacity * 2 - 1,
		"complete ring rotation keeps lifetime aggregate metrics")
	canvas.free()


func test_live_brush() -> void:
	var setup: Dictionary = make_document("stage-batch-window")
	var document: DrawingDocument = setup["document"]
	var canvas: Control = make_canvas()
	canvas.document = document
	canvas.layer_id = setup["layer"]
	canvas.brush_width = 5.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var original: PackedByteArray = snapshot(document)
	var previous_revision: int = document.revision
	var points: PackedVector2Array = PackedVector2Array()
	var first: Vector2 = Vector2(-20.5, -12.5)
	points.append(canvas.source_position(canvas.pixel_to_position(first)))
	canvas.start_gesture(canvas.pixel_to_position(first))
	check(canvas.session != null, "pointer-down opens an edit session")
	var last: Vector2 = first
	for i: int in range(96):
		last = Vector2(-20.5 + float(i % 32), -12.5 + float(i / 32) * 8.0)
		var screen: Vector2 = canvas.pixel_to_position(last)
		points.append(canvas.source_position(screen))
		canvas.update_gesture(screen)
	points.append(canvas.source_position(canvas.pixel_to_position(last)))
	canvas.finish_gesture(canvas.pixel_to_position(last))
	canvas.zoom = 8.5
	canvas.camera = Vector2(15, -9)
	var loops: int = 0
	while canvas.session != null and loops < 500:
		canvas._drain_segments(256)
		loops += 1
	check(canvas.session == null and document.revision == previous_revision + 1,
		"released stroke commits once across viewport navigation")
	var metrics: Dictionary = canvas.last_gesture_metrics
	var batches: Array = metrics.get("stage_batches_us", []) as Array
	check(not batches.is_empty() and batches.size() < canvas.MAX_STAGE_BATCH_LATENCIES,
		"normal Brush produces a complete short batch distribution")
	check(int(metrics.get("stage_batch_total", -1)) == batches.size(),
		"actual pointer-drain count matches retained batch timings")
	var sum_us: int = 0
	var worst_us: int = 0
	for value: Variant in batches:
		sum_us += int(value)
		worst_us = maxi(worst_us, int(value))
	check(int(metrics.get("stage_cpu_us", -1)) == sum_us and
		int(metrics.get("max_stage_batch_us", -1)) == worst_us,
		"actual Brush stage CPU sum and exact maximum are preserved")
	var reference_setup: Dictionary = make_document("batch-unsliced")
	var reference: DrawingDocument = reference_setup["document"]
	var edit: DrawingEditSession = reference.begin_edit(reference_setup["layer"],
		reference.revision).value
	check(edit.paint_path(points, INK, 5.0).ok and edit.commit().ok,
		"independent unsliced reference paints successfully")
	var painted: PackedByteArray = snapshot(document)
	check(painted != original and painted == snapshot(reference),
		"staging profiler does not change canonical RGBA8 pixels")
	check(document.undo().ok and reference.undo().ok and
		snapshot(document) == original and snapshot(document) == snapshot(reference),
		"Undo restores source bytes and reference history")
	check(document.redo().ok and reference.redo().ok and
		snapshot(document) == painted and snapshot(document) == snapshot(reference),
		"Redo restores exact painted source bytes")

	# A new gesture must reset both the sample ring position and its counters.
	canvas.start_gesture(canvas.pixel_to_position(Vector2(2.5, 2.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(2.5, 2.5)))
	loops = 0
	while canvas.session != null and loops < 50:
		canvas._drain_segments(256)
		loops += 1
	var second: Dictionary = canvas.last_gesture_metrics
	check(int(second.get("stage_batch_total", -1)) ==
		(second.get("stage_batches_us", []) as Array).size(),
		"next stroke starts with a fresh batch window")
	check(int(second.get("stage_batch_total", 0)) < int(metrics.get("stage_batch_total", -1)),
		"new stroke does not inherit preceding batch totals")
	print("T095_STAGE_BATCH_WINDOW_PROFILE first_batches=%d max_us=%d second_batches=%d" % [
		int(metrics.get("stage_batch_total", -1)), int(metrics.get("max_stage_batch_us", -1)),
		int(second.get("stage_batch_total", -1))])
	canvas.free()


func run() -> void:
	var probe: Control = make_canvas()
	if not probe.has_method("_record_stage_batch"):
		check(false, "long-stroke batch window recorder is installed")
		probe.free()
		print("T095_STAGE_BATCH_WINDOW_PASSED checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	probe.free()
	test_recording()
	await test_live_brush()
	print("T095_STAGE_BATCH_WINDOW_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
