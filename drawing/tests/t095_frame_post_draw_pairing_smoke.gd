extends SceneTree
## T-095: per-frame Godot post-draw callbacks must not be confused with photon latency.

const INK: int = 0x9050d7b9
const AREA: Rect2i = Rect2i(-48, -48, 96, 96)
var checks: int = 0
var failures: int = 0


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_POSTDRAW_PAIR_FAILED: " + reason)


func canvas_new() -> Control:
	var canvas := Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(500, 360)
	return canvas


func snapshot(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(result.ok, "RGBA8 snapshot renders")
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func test_exact_callback_matching() -> void:
	var canvas: Control = canvas_new()
	check(canvas.has_method("_finish_pending_frame_post_draw"),
		"post-draw correlation helper exists")
	if not canvas.has_method("_finish_pending_frame_post_draw"):
		canvas.free()
		return
	var document := DrawingDocument.new("callback-synthetic", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = document.begin_edit(layer, document.revision).value
	canvas._metrics.clear()
	canvas._metrics["frame_phase_total"] = 0
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_post_draw_matches"] = 0
	canvas._metrics["max_frame_end_to_post_draw_us"] = 0
	canvas._record_frame_phase({"frame_end_us": 1000, "full_draw_cpu_us": 100,
		"pending_input_count": 2, "oldest_pending_age_us": 300})
	canvas._finish_pending_frame_post_draw(1500)
	var sample: Dictionary = (canvas._metrics["frame_phases_us"] as Array)[0] as Dictionary
	check(int(sample.get("frame_post_draw_callback_us", 0)) == 1500 and
		int(sample.get("frame_end_to_post_draw_us", -1)) == 500,
		"callback timestamp and nonnegative delay belong to the exact submitted frame")
	check(int(canvas._metrics.get("frame_post_draw_matches", -1)) == 1 and
		int(canvas._metrics.get("max_frame_end_to_post_draw_us", -1)) == 500,
		"lifetime matched callback count and worst delay are recorded")
	canvas._finish_pending_frame_post_draw(1700)
	check(int(canvas._metrics.get("frame_post_draw_matches", -1)) == 1 and
		int(sample.get("frame_post_draw_callback_us", 0)) == 1500,
		"a second callback cannot be counted against an already matched draw")
	canvas._record_frame_phase({"frame_end_us": 2000, "full_draw_cpu_us": 120})
	canvas._finish_pending_frame_post_draw(1900)
	var second: Dictionary = (canvas._metrics["frame_phases_us"] as Array)[1] as Dictionary
	check(int(second.get("frame_end_to_post_draw_us", -1)) == 0 and
		int(second.get("frame_post_draw_callback_us", -1)) == 2000,
		"out-of-order callback clocks clamp delay and timestamp")
	check(int(canvas._metrics.get("frame_post_draw_matches", -1)) == 2 and
		int(canvas._metrics.get("max_frame_end_to_post_draw_us", -1)) == 500,
		"negative delays cannot decrease the all-time maximum")
	# If two Canvas draws occur before a callback, only the latest submitted
	# draw may claim it. The first remains explicitly unmatched.
	canvas._record_frame_phase({"frame_end_us": 2500, "full_draw_cpu_us": 130})
	canvas._record_frame_phase({"frame_end_us": 2600, "full_draw_cpu_us": 140})
	canvas._finish_pending_frame_post_draw(2900)
	var preceding: Dictionary = (canvas._metrics["frame_phases_us"] as Array)[2] as Dictionary
	var latest: Dictionary = (canvas._metrics["frame_phases_us"] as Array)[3] as Dictionary
	check(not preceding.has("frame_post_draw_callback_us") and
		int(latest.get("frame_end_to_post_draw_us", -1)) == 300 and
		int(canvas._metrics.get("frame_post_draw_matches", -1)) == 3,
		"callback is paired with the latest submitted draw, never duplicated")
	canvas._record_frame_phase({"frame_end_us": 3000, "full_draw_cpu_us": 80})
	canvas.session = null
	canvas._finish_pending_frame_post_draw(3300)
	var abandoned: Dictionary = (canvas._metrics["frame_phases_us"] as Array)[4] as Dictionary
	check(not abandoned.has("frame_post_draw_callback_us") and
		int(canvas._metrics.get("frame_post_draw_matches", -1)) == 3,
		"post-commit callbacks never update a discarded session")
	canvas.free()


func test_bounded_callback_history() -> void:
	var canvas: Control = canvas_new()
	if not canvas.has_method("_finish_pending_frame_post_draw"):
		check(false, "ring callback helper exists")
		canvas.free()
		return
	var document := DrawingDocument.new("callback-ring", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = document.begin_edit(layer, document.revision).value
	canvas._metrics.clear()
	canvas._metrics["frame_phase_total"] = 0
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_post_draw_matches"] = 0
	canvas._metrics["max_frame_end_to_post_draw_us"] = 0
	var cap: int = canvas.MAX_FRAME_PHASE_SAMPLES
	for i: int in range(cap + 37):
		var submitted_at: int = 100000 + i * 2000
		canvas._record_frame_phase({"frame_end_us": submitted_at,
			"full_draw_cpu_us": 33})
		canvas._finish_pending_frame_post_draw(submitted_at + (700 if i == 0 else 9))
	canvas._finalize_frame_phase_window()
	var retained: Array = canvas._metrics["frame_phases_us"] as Array
	check(retained.size() == cap and
		int(canvas._metrics.get("frame_phase_total", -1)) == cap + 37 and
		int(canvas._metrics.get("frame_post_draw_matches", -1)) == cap + 37,
		"bounded ring retains latest frames but exact lifetime callback count")
	check(int(canvas._metrics.get("max_frame_end_to_post_draw_us", -1)) == 700,
		"lifetime worst post-draw delay survives eviction")
	var ordered: bool = true
	for j: int in range(cap):
		var frame: Dictionary = retained[j] as Dictionary
		var expected: int = 100000 + (j + 37) * 2000
		if int(frame.get("frame_end_us", -1)) != expected or \
			int(frame.get("frame_post_draw_callback_us", -1)) != expected + 9 or \
			int(frame.get("frame_end_to_post_draw_us", -1)) != 9:
			ordered = false
			break
	check(ordered, "callback delay and timestamp preserve chronological ring pairing")
	canvas.free()


func test_live_brush() -> void:
	var document := DrawingDocument.new("callback-live", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var canvas: Control = canvas_new()
	canvas.document = document
	canvas.layer_id = layer
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var before: PackedByteArray = snapshot(document)
	var a: Vector2 = Vector2(-15.5, -9.5)
	var b: Vector2 = Vector2(18.5, 12.5)
	canvas.start_gesture(canvas.pixel_to_position(a))
	canvas.paint_to(Vector2i(18, 12))
	canvas.queue_redraw()
	await process_frame
	canvas._on_frame_post_draw()
	var frames: Array = canvas._metrics.get("frame_phases_us", []) as Array
	var matched: int = 0
	var aligned: bool = true
	for v: Variant in frames:
		var frame: Dictionary = v as Dictionary
		if frame.has("frame_post_draw_callback_us"):
			matched += 1
			if int(frame["frame_post_draw_callback_us"]) < int(frame.get("frame_end_us", 0)) or \
				int(frame.get("frame_end_to_post_draw_us", -1)) < 0:
				aligned = false
	check(matched > 0 and aligned,
		"actual Canvas draw receives a paired monotonic post-draw callback")
	check(int(canvas._metrics.get("frame_post_draw_matches", -1)) == matched,
		"live callback count matches paired retained frame samples")
	canvas.finish_gesture(canvas.pixel_to_position(b))
	var attempts: int = 0
	while canvas.session != null and attempts < 400:
		canvas._drain_segments(256)
		attempts += 1
	check(canvas.session == null and document.revision == 2,
		"60px Brush still publishes one atomic stroke")
	var published: Dictionary = canvas.last_gesture_metrics
	check(int(published.get("frame_post_draw_matches", -1)) >= 1,
		"completed gesture retains callback matching evidence")
	var after: PackedByteArray = snapshot(document)
	var reference := DrawingDocument.new("callback-reference", 64)
	var reference_layer: String = String(reference.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var edit: DrawingEditSession = reference.begin_edit(reference_layer,
		reference.revision).value
	check(edit.paint_path(PackedVector2Array([a, b]), INK, 60.0).ok and edit.commit().ok,
		"independent Brush reference commits")
	check(snapshot(reference) == after, "postdraw timing does not alter RGBA8 pixels")
	check(document.undo().ok and snapshot(document) == before and
		document.redo().ok and snapshot(document) == after,
		"single-step Undo/Redo retains exact source pixels")
	canvas.queue_free()
	await process_frame


func run() -> void:
	test_exact_callback_matching()
	test_bounded_callback_history()
	await test_live_brush()
	print("T095_POSTDRAW_PAIR_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_POSTDRAW_PAIR_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
