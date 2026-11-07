extends SceneTree
## T-095: actual mouse-down/motion/up 60px Brush with compositor and framebuffer readback.

const REPEATS: int = 5
const MOTIONS: int = 120
const BRUSH_WIDTH: float = 60.0
const ZOOM: float = 7.86

var failures: int = 0
var stage_ms: Array[float] = []
var release_ms: Array[float] = []
var compose_ms: Array[float] = []
var upload_ms: Array[float] = []
var preview_index_ms: Array[float] = []
var input_stage_ms: Array[float] = []
var batch_ms: Array[float] = []
var commit_ms: Array[float] = []
var post_draw_ms: Array[float] = []
var pending: Array[float] = []


func verify(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("T095_NATIVE_FAILED: " + message)


func frames(count: int = 1) -> void:
	for i: int in range(count):
		await process_frame


func button(canvas: Control, source: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func motion(canvas: Control, source: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func point(index: int, run: int) -> Vector2:
	var t: float = float(index) / float(MOTIONS)
	return Vector2(256.5 + 37.0 * sin(t * TAU * 2.0 + run * 0.21),
		256.5 + 24.0 * sin(t * TAU * 7.0 + run * 0.13))


func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]


func record_frame(canvas: Control) -> void:
	var frame_stats: Dictionary = canvas.last_frame_metrics
	compose_ms.append(float(frame_stats.get("compose_cpu_us", 0)) / 1000.0)
	upload_ms.append(float(frame_stats.get("texture_cpu_us", 0)) / 1000.0)
	preview_index_ms.append(float(frame_stats.get("preview_index_cpu_us", 0)) / 1000.0)


func sample(canvas: Control, source: Vector2) -> Color:
	var screenshot: Image = root.get_texture().get_image()
	var point_on_screen: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(source))
	return screenshot.get_pixelv(point_on_screen)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		verify(false, "requires a graphical framebuffer")
		quit(1)
		return
	root.size = Vector2i(1100, 820)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(40, 40)
	canvas.size = Vector2(980, 700)
	canvas.zoom = ZOOM
	canvas.camera = Vector2(256, 256)
	canvas.brush_width = BRUSH_WIDTH
	canvas.color_rgba = 0xa060bfee
	canvas.image_bounds = Rect2i(0, 0, 512, 512)
	canvas.clip_strokes_to_image_frame = true
	canvas.tool = "Brush"
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t095-native")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	canvas.document = doc
	canvas.layer_id = layer
	await frames(5)
	await RenderingServer.frame_post_draw
	var base_accumulation: bool = Input.use_accumulated_input
	for run_index: int in range(REPEATS):
		var before_revision: int = doc.revision
		var source_start: Vector2 = point(0, run_index)
		var before_color: Color = sample(canvas, source_start)
		button(canvas, source_start, true)
		verify(canvas.session != null and not Input.use_accumulated_input,
			"stroke %d: real pointer down starts detached Brush" % run_index)
		var saw_preview: bool = false
		var changed_framebuffer_while_held: bool = false
		for i: int in range(1, MOTIONS + 1):
			motion(canvas, point(i, run_index))
			if i % 4 == 0:
				await frames()
				await RenderingServer.frame_post_draw
				record_frame(canvas)
				if int(canvas._metrics.get("first_frame_post_draw_us", 0)) > 0:
					saw_preview = true
				if run_index == 0 and i == 4:
					var after_color: Color = sample(canvas, source_start)
					changed_framebuffer_while_held = Vector3(before_color.r, before_color.g,
						before_color.b).distance_to(Vector3(after_color.r, after_color.g,
						after_color.b)) > 0.10
		verify(saw_preview, "stroke %d: rendered a preview while mouse held" % run_index)
		if run_index == 0:
			verify(changed_framebuffer_while_held,
				"RGBA framebuffer changed visibly while primary mouse button remains held")
		verify(doc.revision == before_revision,
			"stroke %d: no premature document changes" % run_index)
		button(canvas, point(MOTIONS, run_index), false)
		var drain_frames: int = 0
		while canvas.session != null and drain_frames < 180:
			await frames()
			await RenderingServer.frame_post_draw
			record_frame(canvas)
			drain_frames += 1
		verify(canvas.session == null, "stroke %d: release drained" % run_index)
		verify(doc.revision == before_revision + 1, "stroke %d: committed once" % run_index)
		var stats: Dictionary = canvas.last_gesture_metrics
		var stage: float = float(stats.get("stage_cpu_us", 0)) / 1000.0
		var release: float = float(int(stats.get("commit_us", 0)) - int(stats.get("release_us", 0))) / 1000.0
		stage_ms.append(stage)
		release_ms.append(release)
		pending.append(float(stats.get("max_pending", 0)))
		commit_ms.append(float(stats.get("commit_cpu_us", 0)) / 1000.0)
		post_draw_ms.append(float(int(stats.get("first_frame_post_draw_us", 0)) -
			int(stats.get("down_us", 0))) / 1000.0)
		for microseconds: Variant in stats.get("sample_to_stage_us", []):
			input_stage_ms.append(float(microseconds) / 1000.0)
		for microseconds: Variant in stats.get("stage_batches_us", []):
			batch_ms.append(float(microseconds) / 1000.0)
		verify(int(stats.get("samples_received", 0)) == MOTIONS + 2,
			"stroke %d: received all mouse samples" % run_index)
		verify((stats.get("sample_to_stage_us", []) as Array).size() == MOTIONS + 2,
			"stroke %d: staged every input sample" % run_index)
		verify(doc.read_pixel(layer, floori(source_start.x), floori(source_start.y)).value != 0,
			"stroke %d: source RGBA8 was published after framebuffer witness" % run_index)
		print("T095_NATIVE_RUN run=%d zoom=%.2f width=%.1f stage_ms=%.3f release_ms=%.3f max_pending=%d max_drain_ms=%.3f commit_ms=%.3f compose_sum_ms=%.3f upload_sum_ms=%.3f index_sum_ms=%.3f preview_frames=%d uploaded_bytes=%d drains=%d" % [
			run_index, canvas.zoom, canvas.brush_width, stage, release,
			int(stats.get("max_pending", 0)), float(stats.get("max_drain_cpu_us", 0)) / 1000.0,
			float(stats.get("commit_cpu_us", 0)) / 1000.0,
			float(stats.get("compose_cpu_us", 0)) / 1000.0,
			float(stats.get("texture_cpu_us", 0)) / 1000.0,
			float(stats.get("preview_index_cpu_us", 0)) / 1000.0,
			int(stats.get("preview_frames", 0)), int(stats.get("bytes_uploaded", 0)),
			int(stats.get("drain_calls", 0))])
	verify(Input.use_accumulated_input == base_accumulation, "input accumulation restored")
	var image: Image = root.get_texture().get_image()
	verify(image != null and not image.is_empty(), "native framebuffer captured")
	verify(doc.read_pixel(layer, 256, 256).ok, "source pixel accessible")
	verify(doc.undo().ok and doc.redo().ok, "one-step Undo/Redo still work")
	# Reference-machine timing gates are opt-in. CI machines and LLVMPipe have
	# widely different wall clocks; the baseline above is always emitted.
	var release_budget: String = OS.get_environment("T095_RELEASE_P95_BUDGET_MS")
	if not release_budget.is_empty():
		verify(release_budget.is_valid_float() and float(release_budget) > 0.0 and
			percentile(release_ms, 0.95) <= float(release_budget),
			"reference-machine release p95 <= %s ms" % release_budget)
	var input_budget: String = OS.get_environment("T095_INPUT_STAGE_P95_BUDGET_MS")
	if not input_budget.is_empty():
		verify(input_budget.is_valid_float() and float(input_budget) > 0.0 and
			percentile(input_stage_ms, 0.95) <= float(input_budget),
			"reference-machine input-to-stage p95 <= %s ms" % input_budget)
	print("T095_NATIVE_SUMMARY repetitions=%d motions_per_stroke=%d stage_p50_ms=%.3f stage_p95_ms=%.3f release_p50_ms=%.3f release_p95_ms=%.3f batch_p50_ms=%.3f batch_p95_ms=%.3f input_stage_p50_ms=%.3f input_stage_p95_ms=%.3f compose_p50_ms=%.3f compose_p95_ms=%.3f upload_p50_ms=%.3f upload_p95_ms=%.3f preview_index_p95_ms=%.3f commit_p50_ms=%.3f commit_p95_ms=%.3f first_postdraw_p95_ms=%.3f max_pending=%d failures=%d" % [
		REPEATS, MOTIONS, percentile(stage_ms, 0.5), percentile(stage_ms, 0.95),
		percentile(release_ms, 0.5), percentile(release_ms, 0.95),
		percentile(batch_ms, 0.5), percentile(batch_ms, 0.95),
		percentile(input_stage_ms, 0.5), percentile(input_stage_ms, 0.95),
		percentile(compose_ms, 0.5), percentile(compose_ms, 0.95),
		percentile(upload_ms, 0.5), percentile(upload_ms, 0.95),
		percentile(preview_index_ms, 0.95), percentile(commit_ms, 0.5),
		percentile(commit_ms, 0.95), percentile(post_draw_ms, 0.95),
		int(pending.max()), failures])
	if failures == 0:
		print("T095_NATIVE_PASSED")
	quit(1 if failures > 0 else 0)
