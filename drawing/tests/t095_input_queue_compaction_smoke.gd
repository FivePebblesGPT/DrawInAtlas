extends SceneTree
## T-095: sustained pointer backlog must not retain already-dequeued events.
## Compare exact RGBA8 publication against an independent unsliced input path.

const COUNT: int = 1600
const INK: int = 0xb453a5d7
const VIEW: Rect2i = Rect2i(-40, -40, 80, 80)

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_QUEUE_FAILED: " + label)


func new_canvas() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(340, 240)
	return canvas


func make_document(name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name, 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	return {"doc": doc, "layer": layer}


func image_bytes(doc: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, VIEW, 0, 0,
		VIEW.size.x * VIEW.size.y)
	check(result.ok, "bounded layer render is available")
	return result.value.get_data() if result.ok else PackedByteArray()


func test_partial_target() -> void:
	var canvas: Control = new_canvas()
	for i: int in range(600):
		canvas._samples.append(Vector2(i, i * 0.5))
		canvas._sample_times_us.append(10000 + i)
	canvas._sample_index = 310
	canvas._has_segment_target = true
	canvas._segment_target = Vector2(1200, -900)
	canvas._target_arrival_us = 10299
	canvas._metrics["sample_compactions"] = 0
	canvas._compact_sample_queue()
	check(canvas._samples.size() == 290 and canvas._sample_times_us.size() == 290,
		"only consumed input prefix is discarded")
	check(canvas._sample_index == 0 and canvas._samples[0] == Vector2(310, 155) and
		canvas._samples[-1] == Vector2(599, 299.5), "pending source positions retain exact order")
	check(canvas._sample_times_us[0] == 10310 and canvas._sample_times_us[-1] == 10599,
		"pending timestamps retain exact order and values")
	check(canvas._has_segment_target and canvas._segment_target == Vector2(1200, -900) and
		canvas._target_arrival_us == 10299, "partly interpolated target and arrival remain intact")
	check(int(canvas._metrics["sample_compactions"]) == 1,
		"compaction event counted once")
	canvas._compact_sample_queue()
	check(canvas._samples.size() == 290 and int(canvas._metrics["sample_compactions"]) == 1,
		"small pending queue is not repeatedly copied")
	canvas._sample_index = 290
	canvas._compact_sample_queue()
	check(canvas._samples.is_empty() and canvas._sample_times_us.is_empty() and
		canvas._sample_index == 0, "fully consumed queue clears exactly as before")
	canvas.free()


func test_sustained_interleaving() -> void:
	var canvas: Control = new_canvas()
	canvas._metrics["sample_compactions"] = 0
	var max_retained: int = 0
	# The producer remains 300 samples ahead for thousands of events. Never
	# emptying the queue used to retain every consumed point until mouse-up.
	for i: int in range(6000):
		canvas._samples.append(Vector2(i, -i))
		canvas._sample_times_us.append(50000 + i)
		if i >= 300:
			canvas._sample_index += 1
		if i % 47 == 0:
			canvas._compact_sample_queue()
		max_retained = maxi(max_retained, canvas._samples.size())
	check(int(canvas._metrics["sample_compactions"]) >= 10,
		"sustained producer/consumer triggers recurring prefix compaction")
	check(max_retained < 900,
		"unconsumed input pressure stays bounded instead of growing to 6000")
	check(canvas._samples.size() - canvas._sample_index == 300,
		"interleaving keeps all 300 outstanding source samples")
	var correct: bool = true
	for offset: int in range(300):
		var pending: int = canvas._sample_index + offset
		var original: int = 5700 + offset
		if canvas._samples[pending] != Vector2(original, -original) or \
				canvas._sample_times_us[pending] != 50000 + original:
			correct = false
			break
	check(correct, "all outstanding coordinates and timestamps remain ordered")
	canvas.free()


func run() -> void:
	test_partial_target()
	test_sustained_interleaving()
	var setup: Dictionary = make_document("queue-compacted")
	var doc: DrawingDocument = setup["doc"]
	var layer: String = setup["layer"]
	var canvas: Control = new_canvas()
	canvas.document = doc
	canvas.layer_id = layer
	canvas.zoom = 7.86
	canvas.brush_width = 5.0
	canvas.color_rgba = INK
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-30, -30, 60, 60), true)
	check(mask.combine_rectangle(Rect2i(-4, -4, 8, 8), "Subtract"),
		"selection with excluded hole is configured")
	canvas.set_selection_mask(mask)
	root.add_child(canvas)
	await process_frame
	await process_frame
	var initial_revision: int = doc.revision
	var points: PackedVector2Array = PackedVector2Array()
	var first: Vector2 = Vector2(0.5, 12.5)
	points.append(canvas.source_position(canvas.pixel_to_position(first)))
	canvas.start_gesture(canvas.pixel_to_position(first))
	check(canvas.session != null, "actual 5px Brush session owns input")
	var final_point: Vector2 = first
	for i: int in range(COUNT):
		var t: float = float(i) * 0.017
		final_point = Vector2(12.5 * sin(t) + 0.5, 12.5 * cos(t) + 0.5)
		var viewport_point: Vector2 = canvas.pixel_to_position(final_point)
		points.append(canvas.source_position(viewport_point))
		canvas.update_gesture(viewport_point)
	check(canvas._samples.size() >= COUNT and doc.revision == initial_revision,
		"sustained captured waypoints remain detached before drain")
	var drained_before_release: int = 0
	while int(canvas._metrics.get("sample_compactions", 0)) == 0 and drained_before_release < 400:
		canvas._drain_segments(256)
		drained_before_release += 1
	check(int(canvas._metrics.get("sample_compactions", 0)) > 0,
		"long pending capture compacts a consumed prefix")
	check(canvas.session != null and canvas._samples.size() < COUNT and
		canvas._sample_times_us.size() == canvas._samples.size(),
		"compaction retains the pending coordinate/timestamp pairing")
	# Release the source-space path, then navigate before draining finishes.
	points.append(canvas.source_position(canvas.pixel_to_position(final_point)))
	canvas.finish_gesture(canvas.pixel_to_position(final_point))
	check(canvas.session != null and canvas._finish_requested,
		"release keeps a pending transaction after partial drain")
	canvas.zoom = 10.0
	canvas.camera = Vector2(27.0, -19.0)
	canvas.tool = "Pan"
	check(canvas.session != null and doc.revision == initial_revision,
		"post-release zoom/camera/tool changes do not discard the queue")
	var drain_calls: int = 0
	while canvas.session != null and drain_calls < 500:
		canvas._drain_segments(256)
		drain_calls += 1
	check(canvas.session == null and doc.revision == initial_revision + 1,
		"all pending samples finish as one document revision")
	var stats: Dictionary = canvas.last_gesture_metrics
	check(int(stats.get("samples_received", -1)) == COUNT + 2 and
		(stats.get("sample_to_stage_us", []) as Array).size() == COUNT + 2,
		"every captured input including release has a stage completion timestamp")
	check(int(stats.get("sample_compactions", 0)) > 0 and
		int(stats.get("max_sample_buffer", 0)) >= COUNT,
		"sustained input records queue compaction and maximum buffer pressure")
	var reference: Dictionary = make_document("queue-unsliced-oracle")
	var ref_doc: DrawingDocument = reference["doc"]
	var ref_edit: DrawingEditSession = ref_doc.begin_edit(reference["layer"],
		ref_doc.revision).value
	check(ref_edit.paint_path(points, INK, 5.0, false, mask).ok and ref_edit.commit().ok,
		"independent unsliced source-point oracle publishes")
	check(image_bytes(doc) == image_bytes(ref_doc),
		"compacted and unsliced paths produce identical committed RGBA8 pixels")
	check(doc.undo().ok and ref_doc.undo().ok and image_bytes(doc) == image_bytes(ref_doc),
		"one-step Undo returns identical source pixels")
	check(doc.redo().ok and ref_doc.redo().ok and image_bytes(doc) == image_bytes(ref_doc),
		"Redo restores identical canonical pixels")
	canvas.free()
	print("T095_QUEUE_PROFILE compactions=%d drain_calls=%d max_buffer=%d" % [
		int(stats.get("sample_compactions", 0)), drain_calls,
		int(stats.get("max_sample_buffer", 0))])
	print("T095_QUEUE_COMPACTION_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
