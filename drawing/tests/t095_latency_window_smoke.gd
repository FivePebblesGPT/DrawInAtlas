extends SceneTree
## T-095: a continuous Brush stroke must not retain unlimited profiling data.
## Short stroke metrics remain complete; long metrics hold the latest samples
## chronologically with an exact all-time count and maximum age.

const COUNT: int = 4600
const INK: int = 0xa46a35dd
const VIEW: Rect2i = Rect2i(-32, -32, 64, 64)

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_LATENCY_WINDOW_FAILED: " + label)


func make_canvas() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(340, 240)
	return canvas


func make_document(name: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	return {"document": document, "layer": layer}


func image_bytes(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, VIEW, 0, 0,
		VIEW.size.x * VIEW.size.y)
	check(result.ok, "bounded document render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()


func test_metrics_recorder() -> void:
	var canvas: Control = make_canvas()
	canvas._metrics.clear()
	canvas._metrics["sample_to_stage_us"] = []
	canvas._metrics["sample_to_stage_total"] = 0
	canvas._metrics["max_sample_to_stage_us"] = 0
	for age: int in [9, -20, 7, 0, 12]:
		canvas._record_stage_latency(age)
	canvas._finalize_stage_latency_window()
	check((canvas._metrics["sample_to_stage_us"] as Array) == [9, 0, 7, 0, 12],
		"small gestures retain every latency and clamp negatives")
	check(int(canvas._metrics["sample_to_stage_total"]) == 5 and
		int(canvas._metrics["max_sample_to_stage_us"]) == 12,
		"short-stroke count and maximum stay exact")
	canvas._metrics.clear()
	canvas._metrics["sample_to_stage_us"] = []
	canvas._metrics["sample_to_stage_total"] = 0
	canvas._metrics["max_sample_to_stage_us"] = 0
	canvas._sample_latency_write_index = 0
	var capacity: int = canvas.MAX_SAMPLE_STAGE_LATENCIES
	var bounded: bool = true
	for i: int in range(15000):
		# First sample has the worst age; it must survive in the all-time max
		# even after falling out of the newest bounded window.
		canvas._record_stage_latency(900000 if i == 0 else i)
		if (canvas._metrics["sample_to_stage_us"] as Array).size() > capacity:
			bounded = false
	check(bounded, "sample latency history never exceeds fixed capacity")
	canvas._finalize_stage_latency_window()
	var retained: Array = canvas._metrics["sample_to_stage_us"] as Array
	check(retained.size() == capacity, "long history has fixed capacity")
	check(int(canvas._metrics["sample_to_stage_total"]) == 15000 and
		int(canvas._metrics["max_sample_to_stage_us"]) == 900000,
		"evicted worst latency and all completed samples remain counted")
	var order_ok: bool = true
	for i: int in range(capacity):
		if int(retained[i]) != 15000 - capacity + i:
			order_ok = false
			break
	check(order_ok, "long history returns the latest samples in chronological order")
	# Exact multiple of the capacity: next write position is zero; no rotation.
	canvas._metrics.clear()
	canvas._metrics["sample_to_stage_us"] = []
	canvas._metrics["sample_to_stage_total"] = 0
	canvas._metrics["max_sample_to_stage_us"] = 0
	canvas._sample_latency_write_index = 0
	for i: int in range(capacity * 2):
		canvas._record_stage_latency(i)
	canvas._finalize_stage_latency_window()
	retained = canvas._metrics["sample_to_stage_us"] as Array
	check(int(retained[0]) == capacity and int(retained[-1]) == capacity * 2 - 1,
		"complete ring wraps retain chronological ordering")
	canvas.free()


func run() -> void:
	test_metrics_recorder()
	var setup: Dictionary = make_document("latency-window")
	var document: DrawingDocument = setup["document"]
	var canvas: Control = make_canvas()
	canvas.document = document
	canvas.layer_id = setup["layer"]
	canvas.brush_width = 3.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var revision_before: int = document.revision
	var points: PackedVector2Array = PackedVector2Array()
	var first: Vector2 = Vector2(0.5, 8.5)
	points.append(canvas.source_position(canvas.pixel_to_position(first)))
	canvas.start_gesture(canvas.pixel_to_position(first))
	check(canvas.session != null, "Brush pointer-down owns a detached transaction")
	var last: Vector2 = first
	for i: int in range(COUNT):
		var phase: float = float(i) * 0.021
		last = Vector2(8.5 * sin(phase) + 0.5, 8.5 * cos(phase) + 0.5)
		var screen: Vector2 = canvas.pixel_to_position(last)
		points.append(canvas.source_position(screen))
		canvas.update_gesture(screen)
	check(document.revision == revision_before,
		"queued source-space samples have not published a partial stroke")
	points.append(canvas.source_position(canvas.pixel_to_position(last)))
	canvas.finish_gesture(canvas.pixel_to_position(last))
	canvas.zoom = 9.0
	canvas.camera = Vector2(24, -11)
	canvas.tool = "Pan"
	var drains: int = 0
	while canvas.session != null and drains < 800:
		canvas._drain_segments(256)
		drains += 1
	check(canvas.session == null and document.revision == revision_before + 1,
		"long stroke commits exactly once despite post-release navigation")
	var metrics: Dictionary = canvas.last_gesture_metrics
	check(int(metrics.get("samples_received", -1)) == COUNT + 2 and
		int(metrics.get("sample_to_stage_total", -1)) == COUNT + 2,
		"all received samples were staged even after metric window rollover")
	check((metrics.get("sample_to_stage_us", []) as Array).size() == 4096 and
		int(metrics.get("max_sample_to_stage_us", -1)) >= 0,
		"real long Brush metrics are bounded and retain maximum age")
	var reference_setup: Dictionary = make_document("unsliced")
	var reference: DrawingDocument = reference_setup["document"]
	var edit: DrawingEditSession = reference.begin_edit(reference_setup["layer"],
		reference.revision).value
	check(edit.paint_path(points, INK, 3.0, false).ok and edit.commit().ok,
		"independent unsliced reference stroke commits")
	check(image_bytes(document) == image_bytes(reference),
		"bounded telemetry does not change canonical committed pixels")
	check(document.undo().ok and reference.undo().ok and
		image_bytes(document) == image_bytes(reference),
		"Undo parity survives rolling latency history")
	check(document.redo().ok and reference.redo().ok and
		image_bytes(document) == image_bytes(reference),
		"Redo parity survives rolling latency history")
	print("T095_LATENCY_WINDOW_PROFILE input=%d retained=%d max_age_us=%d drains=%d" % [
		int(metrics.get("sample_to_stage_total", -1)),
		(metrics.get("sample_to_stage_us", []) as Array).size(),
		int(metrics.get("max_sample_to_stage_us", -1)), drains])
	canvas.free()
	print("T095_LATENCY_WINDOW_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
