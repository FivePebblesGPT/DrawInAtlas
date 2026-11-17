extends SceneTree
## Full standalone Drawing workspace timing witness. Virtual X11 mouse input,
## software GL renderer and engine callback timestamps are not physical scanout.

const WIDTH: float = 96.0
const BOUNDS: Rect2i = Rect2i(-256, -256, 512, 512)
const HOLD_FRAMES: int = 8
const MAX_DRAIN_FRAMES: int = 360

var failures: int = 0
var cases: int = 0
var postdraw_timestamps: Array[int] = []
var process_timestamps: Array[int] = []


func check(valid: bool, label: String) -> void:
	if not valid:
		failures += 1
		printerr("T185_FAILED: " + label)


func on_postdraw() -> void:
	postdraw_timestamps.append(Time.get_ticks_usec())


func on_process() -> void:
	process_timestamps.append(Time.get_ticks_usec())


func intervals(timestamps: Array[int], start_us: int, end_us: int) -> Array[int]:
	var result: Array[int] = []
	var previous: int = 0
	for timestamp: int in timestamps:
		if timestamp < start_us or timestamp > end_us:
			continue
		if previous > 0:
			result.append(timestamp - previous)
		previous = timestamp
	return result


func mouse(canvas: Control, source: Vector2, down: bool, button: bool) -> void:
	if button:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = canvas.global_position + canvas.pixel_to_position(source)
		event.global_position = event.position
		root.push_input(event, true)
	else:
		var move: InputEventMouseMotion = InputEventMouseMotion.new()
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		move.position = canvas.global_position + canvas.pixel_to_position(source)
		move.global_position = move.position
		root.push_input(move, true)


func path() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-190, -190), Vector2(190, -190),
		Vector2(190, -120), Vector2(-190, -120),
		Vector2(-190, -50), Vector2(190, -50),
		Vector2(190, 20), Vector2(-190, 20),
		Vector2(-190, 90), Vector2(190, 90),
		Vector2(190, 160), Vector2(-190, 160),
		Vector2(-190, 190)])


func source_sha(document: DrawingDocument) -> Dictionary:
	var rendered: DrawingResult = DrawingRenderer.render(document, BOUNDS)
	if not rendered.ok:
		return {"ok": false}
	var bytes: PackedByteArray = (rendered.value as Image).get_data()
	var sha: HashingContext = HashingContext.new()
	if sha.start(HashingContext.HASH_SHA256) != OK:
		return {"ok": false}
	sha.update(bytes)
	var covered: int = 0
	var opacity: int = 0
	for i: int in range(3, bytes.size(), 4):
		if bytes[i] > 0:
			covered += 1
		opacity += bytes[i]
	return {"ok": bytes.size() == 512 * 512 * 4, "sha256": sha.finish().hex_encode(),
		"covered": covered, "alpha_sum": opacity}


func stroke(app: Control, zoom_value: float, kind: String, index: int) -> void:
	var canvas: Control = app.canvas
	var document: DrawingDocument = app.current_document()
	var revision: int = document.revision
	var before_cache: int = canvas._display_tiles.size()
	var before_digest: Dictionary = source_sha(document)
	canvas.tool = "Eraser" if kind == "eraser" else "Brush"
	await process_frame
	var started: int = Time.get_ticks_usec()
	var gesture: PackedVector2Array = path()
	var delivered: Array[int] = []
	mouse(canvas, gesture[0], true, true)
	check(canvas.session != null and canvas._native_brush != null and
		canvas.session._native_tiles != null, "%s: native workspace stroke started" % kind)
	if canvas.session == null:
		return
	for i: int in range(1, gesture.size()):
		await create_timer(0.016).timeout
		delivered.append(Time.get_ticks_usec())
		mouse(canvas, gesture[i], true, false)
	check(document.revision == revision, "%s: moving preview is uncommitted" % kind)
	var held_us: int = Time.get_ticks_usec()
	for i: int in range(HOLD_FRAMES):
		await create_timer(0.016).timeout
	check(canvas.session != null and document.revision == revision,
		"%s: held pointer remains unpublished" % kind)
	var release_start: int = Time.get_ticks_usec()
	mouse(canvas, gesture[gesture.size() - 1], false, true)
	var drained: int = 0
	while canvas.session != null and drained < MAX_DRAIN_FRAMES:
		await process_frame
		drained += 1
	check(canvas.session == null, "%s: bounded native queue drains" % kind)
	if canvas.session != null:
		canvas.cancel_gesture()
		return
	var committed: int = Time.get_ticks_usec()
	var stats: Dictionary = canvas.last_gesture_metrics
	var settle: int = 0
	while settle < 40:
		await process_frame
		settle += 1
		if not canvas._cold_population_pending and \
				int(canvas.last_frame_metrics.get("cold_tiles_deferred", 0)) == 0 and \
				int(canvas.last_frame_metrics.get("post_draw_us", 0)) >= committed:
			break
	var settled: int = Time.get_ticks_usec()
	check(settle < 40 and not canvas._cold_population_pending,
		"%s: bounded preview/commit framebuffer settlement" % kind)
	var after_digest: Dictionary = source_sha(document)
	check(document.revision == revision + 1 and
			before_digest.get("ok", false) and after_digest.get("ok", false) and
			before_digest.get("sha256") != after_digest.get("sha256"),
		"%s: one native source revision with changed RGBA8" % kind)
	if kind == "eraser":
		check(int(after_digest.get("alpha_sum", 0)) < int(before_digest.get("alpha_sum", 0)),
			"native Eraser decreases already painted opacity")
	else:
		check(int(after_digest.get("covered", 0)) > 0, "Brush paints source")
	check(int(stats.get("samples_received", -1)) == gesture.size() + 1,
		"%s: every down/move/up input event recorded" % kind)
	check(int(stats.get("first_preview_submit_us", 0)) >= started and
		int(stats.get("first_frame_post_draw_us", 0)) > 0,
		"%s: first preview submission and postdraw observed" % kind)
	check(int(stats.get("t185_native_stage", {}).get("batch_calls", 0)) > 0,
		"%s: measured actual native staging" % kind)
	var active_process: Array[int] = intervals(process_timestamps, started, settled)
	var active_draw: Array[int] = intervals(postdraw_timestamps, started, settled)
	check(active_process.size() >= 3 and active_draw.size() >= 2,
		"%s: process and rendered-frame intervals captured" % kind)
	var phase: Array = stats.get("frame_phases_us", []) as Array
	var raw: Dictionary = {"zoom": zoom_value, "case": kind, "index": index,
		"cadence_requested_ms": 16.0, "hold_requested_frames": HOLD_FRAMES,
		"tool": canvas.tool, "preset": canvas.brush_preset,
		"width_px": canvas.brush_width, "opacity": canvas.brush_opacity,
		"hardness": canvas.brush_hardness, "native_backend": "Hokusai",
		"document_bounds": [BOUNDS.position.x, BOUNDS.position.y, 512, 512],
		"canvas_px": [roundi(canvas.size.x), roundi(canvas.size.y)],
		"display_tiles_before": before_cache, "display_tiles_after": canvas._display_tiles.size(),
		"input_events": gesture.size() + 1, "drain_frames": drained,
		"commit_revision_delta": document.revision - revision,
		"coverage": after_digest.get("covered", -1),
		"before_sha256": before_digest.get("sha256", ""),
		"after_sha256": after_digest.get("sha256", ""),
		"first_submit_ms": float(int(stats.get("first_preview_submit_us", 0)) -
			int(stats.get("down_us", 0))) / 1000.0,
		"first_postdraw_ms": float(int(stats.get("first_frame_post_draw_us", 0)) -
			int(stats.get("down_us", 0))) / 1000.0,
		"release_to_commit_ms": float(int(stats.get("commit_us", 0)) -
			int(stats.get("release_us", 0))) / 1000.0,
		"release_to_settled_ms": float(settled - release_start) / 1000.0,
		"total_to_settled_ms": float(settled - started) / 1000.0,
		"held_ms": float(release_start - held_us) / 1000.0,
		"input_delivery_intervals_us": intervals(delivered, started, release_start),
		"process_frame_intervals_us": active_process,
		"post_draw_intervals_us": active_draw,
		"frame_phases_us": phase,
		"stage_cpu_us": stats.get("stage_cpu_us", 0),
		"compose_cpu_us": stats.get("compose_cpu_us", 0),
		"texture_cpu_us": stats.get("texture_cpu_us", 0),
		"preview_index_cpu_us": stats.get("preview_index_cpu_us", 0),
		"commit_cpu_us": stats.get("commit_cpu_us", 0),
		"bytes_uploaded": stats.get("bytes_uploaded", 0),
		"max_pending": stats.get("max_pending", 0),
		"release_pending_samples": stats.get("release_pending_samples", 0),
		"post_release_deferred_calls": stats.get("post_release_deferred_calls", 0),
		"native_ffi_stats": stats.get("native_ffi_stats", {}),
		"native_stage": stats.get("t185_native_stage", {}),
		"engine_godot": Engine.get_version_info().get("string", "")}
	print("T185_RUN " + JSON.stringify(raw))
	cases += 1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	check(DisplayServer.get_name() != "headless" and
		ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"graphical workspace with both native classes")
	if failures:
		quit(1)
		return
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	RenderingServer.frame_post_draw.connect(on_postdraw)
	process_frame.connect(on_process)
	var app: Control = load("res://main.tscn").instantiate()
	app.preferences_persistence_enabled = false
	app.layout_persistence_enabled = false
	root.add_child(app)
	for i: int in range(12):
		await process_frame
	check(app.canvas != null and app.brush_panel != null and app.current_document() != null,
		"real Drawing shell, brush panel and document")
	if failures:
		quit(1)
		return
	for zoom_value: float in [0.54, 1.0]:
		app.new_drawing()
		var canvas: Control = app.canvas
		canvas.zoom = zoom_value
		canvas.camera = Vector2.ZERO
		canvas.image_bounds = BOUNDS
		canvas.clip_strokes_to_image_frame = true
		app._select_brush_preset("hard")
		app._set_brush_width(WIDTH)
		app._set_brush_opacity(1.0)
		for i: int in range(10):
			await process_frame
		for kind: String in ["cold_brush", "warm_overlap", "held_brush", "eraser"]:
			await stroke(app, zoom_value, kind, cases)
			if failures:
				break
		if failures:
			break
	print("T185_RESULT cases=%d failures=%d" % [cases, failures])
	if failures == 0 and cases == 8:
		print("T185_PROFILE_PASSED cases=8 failures=0")
	quit(0 if failures == 0 and cases == 8 else 1)
