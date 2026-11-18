extends RefCounted
## Historical paint_path does not share Hokusai's raster algorithm. Replay the
## same native transaction without Canvas draws or post-draw instrumentation to
## test that measured rendering callbacks do not mutate its canonical output.


static func commit_without_frame_callbacks(host: Window, area: Rect2i,
		points: PackedVector2Array, receipt_us: PackedInt64Array,
		color: int, width: float) -> Dictionary:
	if points.size() < 2 or points.size() != receipt_us.size():
		return {"ok": false}
	var document: DrawingDocument = DrawingDocument.new("native-profiler-control", 64)
	var result: DrawingResult = document.create_layer(DrawingLayerNode.RASTER,
		"Paint", "root")
	if not result.ok:
		return {"ok": false}
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(500, 360)
	canvas.visible = false
	canvas.document = document
	canvas.layer_id = str(result.value)
	canvas.brush_preset = "hard"
	host.add_child(canvas)
	if RenderingServer.frame_post_draw.is_connected(canvas._on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(canvas._on_frame_post_draw)
	canvas.start_gesture(Vector2.ZERO, points[0], {"press_us": receipt_us[0],
		"tool": "Brush", "preset": "hard", "width": width, "color": color})
	var native_started: bool = canvas.session != null and \
		canvas._native_brush != null and canvas._active_brush_backend == "Hokusai"
	if native_started:
		for i: int in range(1, points.size() - 1):
			canvas._enqueue_sample_at_time(points[i], receipt_us[i])
		canvas.finish_gesture(Vector2.ZERO, points[-1], receipt_us[-1])
		var attempts: int = 0
		while canvas.session != null and attempts < 400:
			canvas._drain_segments(256)
			attempts += 1
	var committed: bool = native_started and canvas.session == null and \
		document.revision == 2 and document.history_length() == 1
	var pixels: PackedByteArray = PackedByteArray()
	if committed:
		var rendered: DrawingResult = DrawingRenderer.render(document, area, 0, 0,
			area.size.x * area.size.y)
		if rendered.ok:
			pixels = (rendered.value as Image).get_data()
		else:
			committed = false
	var reference: Dictionary = {"ok": committed, "pixels": pixels,
		"frame_phase_total": int(canvas.last_gesture_metrics.get("frame_phase_total", 0)),
		"post_draw_matches": int(canvas.last_gesture_metrics.get("frame_post_draw_matches", 0))}
	canvas.queue_free()
	return reference
