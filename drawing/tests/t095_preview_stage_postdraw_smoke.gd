extends SceneTree
## T-095: changed-preview stage -> Canvas submit -> engine callback correlation.
## These intervals are CPU/Godot observations, NOT physical input-to-photon latency.

const INK: int = 0x9050d7b9
const AREA: Rect2i = Rect2i(-48, -48, 96, 96)
var checks: int = 0
var failures: int = 0


func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_PREVIEW_STAGE_POSTDRAW_FAILED: " + reason)


func make_canvas() -> Control:
	var canvas := Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(500, 360)
	return canvas


func init_metrics(canvas: Control) -> void:
	canvas._metrics.clear()
	canvas._metrics["frame_phases_us"] = []
	canvas._metrics["frame_phase_total"] = 0
	canvas._metrics["frame_post_draw_matches"] = 0
	canvas._metrics["max_frame_end_to_post_draw_us"] = 0
	canvas._metrics["frame_preview_stage_submissions"] = 0
	canvas._metrics["max_frame_preview_stage_to_frame_end_us"] = 0
	canvas._metrics["preview_stage_post_draw_matches"] = 0
	canvas._metrics["max_preview_stage_to_post_draw_us"] = 0


func submit(canvas: Control, frame_end_us: int) -> Dictionary:
	var frame: Dictionary = {"frame_end_us": frame_end_us,
		"full_draw_cpu_us": 10, "pending_input_count": 1}
	canvas._tag_frame_preview_stage(frame, frame_end_us)
	canvas._record_frame_phase(frame)
	return (canvas._metrics["frame_phases_us"] as Array).back() as Dictionary


func test_pairing_and_noop() -> void:
	var canvas: Control = make_canvas()
	check(canvas.has_method("_mark_unsubmitted_preview_stage") and
		canvas.has_method("_tag_frame_preview_stage"),
		"changed-preview stage-to-draw correlation helpers exist")
	if not canvas.has_method("_tag_frame_preview_stage") or \
			not canvas.has_method("_mark_unsubmitted_preview_stage"):
		canvas.free()
		return
	var document := DrawingDocument.new("stage-postdraw", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = document.begin_edit(layer, document.revision).value
	init_metrics(canvas)
	canvas._mark_unsubmitted_preview_stage(1000)
	canvas._mark_unsubmitted_preview_stage(1400)
	var first: Dictionary = submit(canvas, 2000)
	check(int(first.get("preview_stage_completed_us", 0)) == 1000 and
		int(first.get("preview_stage_to_frame_end_us", -1)) == 1000,
		"first changed stage survives additional batches until draw submission")
	canvas._finish_pending_frame_post_draw(2500)
	check(int(first.get("preview_stage_to_post_draw_us", -1)) == 1500 and
		int(canvas._metrics.get("preview_stage_post_draw_matches", -1)) == 1,
		"a matched callback measures stage-to-Godot-callback delay")
	check(int(canvas._metrics.get("max_frame_preview_stage_to_frame_end_us", -1)) == 1000 and
		int(canvas._metrics.get("max_preview_stage_to_post_draw_us", -1)) == 1500,
		"lifetime maxima retain both measured stages")
	canvas._finish_pending_frame_post_draw(2700)
	check(int(canvas._metrics.get("preview_stage_post_draw_matches", -1)) == 1,
		"duplicate callback cannot double-count the changed preview")
	var noop: Dictionary = submit(canvas, 3000)
	canvas._finish_pending_frame_post_draw(3300)
	check(not noop.has("preview_stage_completed_us") and
		not noop.has("preview_stage_to_post_draw_us") and
		int(canvas._metrics.get("frame_preview_stage_submissions", -1)) == 1,
		"cursor-only and unchanged-preview draws do not claim staged pixels")
	canvas._mark_unsubmitted_preview_stage(3400)
	var skipped: Dictionary = submit(canvas, 3500)
	canvas._mark_unsubmitted_preview_stage(3550)
	var replacement: Dictionary = submit(canvas, 3600)
	canvas._finish_pending_frame_post_draw(4000)
	check(not skipped.has("preview_stage_to_post_draw_us") and
		int(replacement.get("preview_stage_to_post_draw_us", -1)) == 450 and
		int(canvas._metrics.get("preview_stage_post_draw_matches", -1)) == 2,
		"only latest submitted changed frame can claim one engine callback")
	canvas._mark_unsubmitted_preview_stage(4200)
	canvas.cancel_gesture()
	canvas.session = document.begin_edit(layer, document.revision).value
	init_metrics(canvas)
	var after_cancel: Dictionary = submit(canvas, 4400)
	check(not after_cancel.has("preview_stage_completed_us") and
		int(canvas._metrics.get("frame_preview_stage_submissions", -1)) == 0,
		"cancelled preview does not leak its stage stamp to a new session")
	canvas.free()


func test_bounded_lifetime_maxima() -> void:
	var canvas: Control = make_canvas()
	if not canvas.has_method("_tag_frame_preview_stage"):
		check(false, "ring test requires stage pairing helper")
		canvas.free()
		return
	var document := DrawingDocument.new("stage-postdraw-ring", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	canvas.session = document.begin_edit(layer, document.revision).value
	init_metrics(canvas)
	var cap: int = canvas.MAX_FRAME_PHASE_SAMPLES
	for i: int in range(cap + 19):
		var stage_at: int = 100000 + i * 5000
		canvas._mark_unsubmitted_preview_stage(stage_at)
		var frame: Dictionary = submit(canvas, stage_at + 100)
		canvas._finish_pending_frame_post_draw(stage_at + (2500 if i == 0 else 250))
	canvas._finalize_frame_phase_window()
	var retained: Array = canvas._metrics["frame_phases_us"] as Array
	check(retained.size() == cap and
		int(canvas._metrics.get("frame_phase_total", -1)) == cap + 19 and
		int(canvas._metrics.get("frame_preview_stage_submissions", -1)) == cap + 19 and
		int(canvas._metrics.get("preview_stage_post_draw_matches", -1)) == cap + 19,
		"bounded history retains exact lifetime submission and callback counts")
	check(int(canvas._metrics.get("max_preview_stage_to_post_draw_us", -1)) == 2500 and
		int(canvas._metrics.get("max_frame_preview_stage_to_frame_end_us", -1)) == 100,
		"all-time stage/callback maxima survive ring eviction")
	var ordered: bool = true
	for j: int in range(cap):
		var f: Dictionary = retained[j] as Dictionary
		var expected_stage: int = 100000 + (j + 19) * 5000
		if int(f.get("preview_stage_completed_us", -1)) != expected_stage or \
			int(f.get("preview_stage_to_frame_end_us", -1)) != 100 or \
			int(f.get("preview_stage_to_post_draw_us", -1)) != 250:
			ordered = false
			break
	check(ordered, "retained source and callback stamps follow exact wraparound order")
	canvas.free()


func snapshot(document: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(document, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(result.ok, "RGBA8 snapshot renders")
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func test_real_brush_and_history() -> void:
	var document := DrawingDocument.new("stage-postdraw-live", 64)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var canvas: Control = make_canvas()
	canvas.document = document
	canvas.layer_id = layer
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	root.add_child(canvas)
	await process_frame
	await process_frame
	var before: PackedByteArray = snapshot(document)
	var a := Vector2(-15.5, -9.5)
	var b := Vector2(18.5, 12.5)
	canvas.start_gesture(canvas.pixel_to_position(a))
	canvas.queue_redraw()
	await process_frame
	canvas._on_frame_post_draw()
	var live: Array = canvas._metrics.get("frame_phases_us", []) as Array
	var match_count: int = 0
	var consistent: bool = true
	for v: Variant in live:
		var f: Dictionary = v as Dictionary
		if f.has("preview_stage_to_post_draw_us"):
			match_count += 1
			if int(f.get("preview_stage_completed_us", 0)) <= 0 or \
				int(f.get("preview_stage_to_frame_end_us", -1)) < 0 or \
				int(f["preview_stage_to_post_draw_us"]) < int(f["preview_stage_to_frame_end_us"]):
				consistent = false
	check(match_count > 0 and consistent,
		"real changed 60px Brush preview has stage/draw/callback timestamps")
	canvas.finish_gesture(canvas.pixel_to_position(b))
	var guard: int = 0
	while canvas.session != null and guard < 400:
		canvas._drain_segments(256)
		guard += 1
	check(canvas.session == null and document.revision == 2,
		"live stroke publishes exactly one transaction")
	var published: Dictionary = canvas.last_gesture_metrics
	check(int(published.get("preview_stage_post_draw_matches", 0)) >= 1,
		"completed gesture retains preview stage/callback evidence")
	var actual: PackedByteArray = snapshot(document)
	var reference := DrawingDocument.new("stage-postdraw-reference", 64)
	var reference_layer: String = String(reference.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root").value)
	var edit: DrawingEditSession = reference.begin_edit(reference_layer,
		reference.revision).value
	check(edit.paint_path(PackedVector2Array([a, b]), INK, 60.0).ok and
		edit.commit().ok, "independent 60px stroke reference commits")
	check(snapshot(reference) == actual,
		"stage-to-callback instrumentation preserves exact RGBA8 pixels")
	check(document.undo().ok and snapshot(document) == before and
		document.redo().ok and snapshot(document) == actual,
		"single-step Undo/Redo preserves original and committed source")
	canvas.queue_free()
	await process_frame


func run() -> void:
	test_pairing_and_noop()
	test_bounded_lifetime_maxima()
	await test_real_brush_and_history()
	print("T095_PREVIEW_STAGE_POSTDRAW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_PREVIEW_STAGE_POSTDRAW_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
