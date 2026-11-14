extends SceneTree
## T-095: engine-receipt -> changed-preview Canvas draw / post-draw witness.
## This is NOT device-to-photon or OS event latency.

const INK: int = 0x7b4acfd2
const AREA: Rect2i = Rect2i(-48, -48, 96, 96)
var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_PREVIEW_INPUT_POSTDRAW_FAILED: " + message)


func canvas_instance() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(520, 380)
	return canvas


func reset_metrics(canvas: Control) -> void:
	canvas._metrics.clear()
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_phase_total"] = 0
	canvas._metrics["frame_preview_stage_submissions"] = 0
	canvas._metrics["preview_stage_post_draw_matches"] = 0
	canvas._metrics["preview_input_post_draw_matches"] = 0


func submit(canvas: Control, frame_us: int) -> Dictionary:
	var phase: Dictionary = {"frame_end_us": frame_us, "full_draw_cpu_us": 9}
	canvas._tag_frame_preview_stage(phase, frame_us)
	canvas._record_frame_phase(phase)
	return (canvas._metrics["frame_phases_us"] as Array).back() as Dictionary


func test_manual_pairing() -> void:
	var canvas: Control = canvas_instance()
	check(canvas.has_method("_tag_frame_preview_stage") and
		canvas.has_method("_mark_unsubmitted_preview_stage"),
		"receipt pairing has staged/draw entry points")
	var doc: DrawingDocument = DrawingDocument.new("input-correlation", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = doc.begin_edit(layer, doc.revision).value
	reset_metrics(canvas)
	canvas._mark_unsubmitted_preview_stage(1600, 1000)
	canvas._mark_unsubmitted_preview_stage(1800, 1300)
	var first: Dictionary = submit(canvas, 2000)
	check(int(first.get("preview_input_received_us", -1)) == 1000 and
		int(first.get("preview_input_to_frame_end_us", -1)) == 1000,
		"oldest input receipt persists across changed batches until draw")
	check(int(first.get("preview_stage_completed_us", -1)) == 1600 and
		int(first.get("preview_stage_to_frame_end_us", -1)) == 400,
		"receipt witness coexists with stage-to-draw timing")
	canvas._finish_pending_frame_post_draw(2500)
	check(int(first.get("preview_input_to_post_draw_us", -1)) == 1500 and
		int(first.get("preview_stage_to_post_draw_us", -1)) == 900,
		"matching callback timestamps both receipt and stage latency")
	check(int(canvas._metrics.get("preview_input_post_draw_matches", -1)) == 1 and
		int(canvas._metrics.get("max_preview_input_to_frame_end_us", -1)) == 1000 and
		int(canvas._metrics.get("max_preview_input_to_post_draw_us", -1)) == 1500,
		"lifetime callback counts and maxima match observed intervals")
	canvas._finish_pending_frame_post_draw(2600)
	check(int(canvas._metrics.get("preview_input_post_draw_matches", -1)) == 1,
		"repeated callback cannot count the same frame twice")
	var noop: Dictionary = submit(canvas, 3000)
	canvas._finish_pending_frame_post_draw(3100)
	check(not noop.has("preview_input_received_us") and
		not noop.has("preview_input_to_post_draw_us"),
		"unchanged-preview and cursor frames do not claim input receipts")
	canvas._mark_unsubmitted_preview_stage(3400, 3200)
	var unmatched: Dictionary = submit(canvas, 3500)
	canvas._mark_unsubmitted_preview_stage(3600, 3550)
	var latest: Dictionary = submit(canvas, 3700)
	canvas._finish_pending_frame_post_draw(4100)
	check(not unmatched.has("preview_input_to_post_draw_us") and
		int(latest.get("preview_input_to_post_draw_us", -1)) == 550 and
		int(canvas._metrics.get("preview_input_post_draw_matches", -1)) == 2,
		"only latest submitted frame receives a coalesced callback")
	canvas._mark_unsubmitted_preview_stage(4300, 4200)
	canvas.cancel_gesture()
	canvas.session = doc.begin_edit(layer, doc.revision).value
	reset_metrics(canvas)
	var cancelled: Dictionary = submit(canvas, 4500)
	check(not cancelled.has("preview_input_received_us") and
		int(canvas._metrics.get("preview_input_post_draw_matches", -1)) == 0,
		"cancelled input cannot leak into a replacement edit session")
	canvas.free()


func test_bounded_ring() -> void:
	var canvas: Control = canvas_instance()
	var doc: DrawingDocument = DrawingDocument.new("input-correlation-ring", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = doc.begin_edit(layer, doc.revision).value
	reset_metrics(canvas)
	var cap: int = canvas.MAX_FRAME_PHASE_SAMPLES
	for i: int in range(cap + 11):
		var received: int = 200000 + i * 5000
		canvas._mark_unsubmitted_preview_stage(received + 100, received)
		submit(canvas, received + 200)
		canvas._finish_pending_frame_post_draw(received + (2500 if i == 0 else 300))
	canvas._finalize_frame_phase_window()
	var retained: Array = canvas._metrics["frame_phases_us"] as Array
	check(retained.size() == cap and int(canvas._metrics["frame_phase_total"]) == cap + 11,
		"latest-frame history remains bounded with exact lifetime draw count")
	check(int(canvas._metrics.get("preview_input_post_draw_matches", -1)) == cap + 11 and
		int(canvas._metrics.get("max_preview_input_to_post_draw_us", -1)) == 2500,
		"receipt/callback lifetime stats survive eviction of worst old frame")
	var ordered: bool = true
	for i: int in range(cap):
		var item: Dictionary = retained[i] as Dictionary
		if int(item.get("preview_input_received_us", -1)) != 200000 + (i + 11) * 5000 or \
				int(item.get("preview_input_to_frame_end_us", -1)) != 200 or \
				int(item.get("preview_input_to_post_draw_us", -1)) != 300:
			ordered = false
			break
	check(ordered, "retained receipt and callback samples stay chronological")
	canvas.free()


func snapshot(doc: DrawingDocument) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(doc, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(rendered.ok, "RGBA8 source snapshot renders")
	return (rendered.value as Image).get_data() if rendered.ok else PackedByteArray()


func test_live_stroke() -> void:
	var doc: DrawingDocument = DrawingDocument.new("input-correlation-live", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var canvas: Control = canvas_instance()
	canvas.document = doc
	canvas.layer_id = layer
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var before: PackedByteArray = snapshot(doc)
	var a: Vector2 = Vector2(-17.5, -9.5)
	var b: Vector2 = Vector2(18.5, 12.5)
	canvas.start_gesture(canvas.pixel_to_position(a))
	canvas.queue_redraw()
	await process_frame
	canvas._on_frame_post_draw()
	var live_samples: Array = canvas._metrics.get("frame_phases_us", []) as Array
	var live_receipts: int = 0
	var consistent: bool = true
	for v: Variant in live_samples:
		var frame: Dictionary = v as Dictionary
		if frame.has("preview_input_received_us"):
			live_receipts += 1
			if int(frame["preview_input_received_us"]) <= 0 or \
				int(frame["preview_input_received_us"]) > int(frame.get("preview_stage_completed_us", 0)) or \
				int(frame["preview_input_to_frame_end_us"]) < int(frame.get("preview_stage_to_frame_end_us", 0)):
				consistent = false
	check(live_receipts > 0 and consistent,
		"actual 60px input receipt precedes stage and Canvas submission")
	canvas.finish_gesture(canvas.pixel_to_position(b))
	var guard: int = 0
	while canvas.session != null and guard < 400:
		canvas._drain_segments(256)
		guard += 1
	check(canvas.session == null and doc.revision == 2,
		"real mouse-path stroke publishes a single history revision")
	var actual: PackedByteArray = snapshot(doc)
	var reference: DrawingDocument = DrawingDocument.new("input-correlation-reference", 64)
	var ref_layer: String = String(reference.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var edit: DrawingEditSession = reference.begin_edit(ref_layer,
		reference.revision).value
	check(edit.paint_path(PackedVector2Array([a, b]), INK, 60.0).ok and
		edit.commit().ok, "independent legacy coverage oracle stages and commits")
	check(snapshot(reference) == actual, "receipt telemetry leaves exact RGBA8 pixels unchanged")
	check(doc.undo().ok and snapshot(doc) == before and
		doc.redo().ok and snapshot(doc) == actual,
		"telemetry preserves one-step Undo and Redo parity")
	canvas.queue_free()
	await process_frame


func run() -> void:
	test_manual_pairing()
	test_bounded_ring()
	await test_live_stroke()
	print("T095_PREVIEW_INPUT_POSTDRAW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_PREVIEW_INPUT_POSTDRAW_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
