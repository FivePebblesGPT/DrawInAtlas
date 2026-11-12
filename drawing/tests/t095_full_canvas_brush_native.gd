extends SceneTree
## T-095 full-canvas 96px hard Brush through real Godot mouse routing.
## Events are injected as one rapid, continuous drag for throughput comparison.
## A virtual pointer and engine post-draw callback are NOT physical input-to-photon.

const SIDE: int = 512
const BRUSH_WIDTH: float = 96.0
const PAINT_RED: int = 0xff0000ff
const DEFAULT_RUNS: int = 1
## SHA-256 of 256*256 repetitions of independent RGBA bytes ff,00,00,ff.
const RED_TILE_SHA256: String = "b8b9b478324141d9331328a2150e74ec5feb266a743a51cab73d903247247ea4"
const DRAIN_FRAME_LIMIT: int = 360

var failures: int = 0
var elapsed_ms: Array[float] = []
var release_ms: Array[float] = []
var stage_ms: Array[float] = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("T095_FULL_CANVAS_FAILED: " + label)


func frame_compose_p95_ms(stats: Dictionary) -> float:
	var values: Array[float] = []
	for phase: Dictionary in (stats.get("frame_phases_us", []) as Array):
		values.append(float(phase.get("compose_cpu_us", 0)) / 1000.0)
	return percentile(values, 0.95)


func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func frame_metric_p_ms(stats: Dictionary, key: String, fraction: float) -> float:
	var values: Array[float] = []
	for sample: Dictionary in (stats.get("frame_phases_us", []) as Array):
		if sample.has(key):
			values.append(float(sample[key]) / 1000.0)
	return percentile(values, fraction)


func frame_depth_p(stats: Dictionary, fraction: float) -> float:
	var values: Array[float] = []
	for sample: Dictionary in (stats.get("frame_phases_us", []) as Array):
		values.append(float(sample.get("pending_input_count", 0)))
	return percentile(values, fraction)


## Nine 64px-spaced, alternating horizontal sweeps. At every source pixel
## center there is a point on a sweep within 32px, less than the 48px radius.
## This is a SINGLE Brush gesture, not a rectangle/fill API substitution.
func coverage_path() -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	for row: int in range(9):
		var y: float = minf(511.5, 0.5 + float(row) * 64.0)
		for col: int in range(11):
			var step: int = col if row % 2 == 0 else 10 - col
			path.append(Vector2(0.5 + 511.0 * float(step) / 10.0, y))
	return path


func mouse_button(canvas: Control, source: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func mouse_motion(canvas: Control, source: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func check_all_red(doc: DrawingDocument, layer: String, label: String) -> void:
	var keys: Array[String] = doc.tile_keys(layer)
	check(keys == ["0,0", "0,1", "1,0", "1,1"],
		label + ": exactly four 256px source tiles, no out-of-frame paint")
	for cy: int in range(2):
		for cx: int in range(2):
			var result: DrawingResult = doc.request_chunk_at(layer, cx, cy)
			check(result.ok and result.value != null,
				label + ": canonical source tile %d,%d is readable" % [cx, cy])
			if not result.ok or result.value == null:
				continue
			var tile: DrawingRasterTile = result.value as DrawingRasterTile
			check(tile.pixel_count() == 256 * 256,
				label + ": tile %d,%d contains every pixel" % [cx, cy])
			var bytes: PackedByteArray = tile.to_rgba8()
			var digest: HashingContext = HashingContext.new()
			check(digest.start(HashingContext.HASH_SHA256) == OK,
				label + ": SHA-256 initialized")
			digest.update(bytes)
			check(digest.finish().hex_encode() == RED_TILE_SHA256,
				label + ": tile %d,%d matches independent all-red RGBA8 bytes" % [cx, cy])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires actual graphical viewport under X11/Windows/macOS")
		quit(1)
		return
	root.size = Vector2i(900, 820)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(30.0, 30.0)
	canvas.size = Vector2(700.0, 700.0)
	canvas.zoom = 1.0
	canvas.camera = Vector2(256.0, 256.0)
	canvas.brush_width = BRUSH_WIDTH
	canvas.color_rgba = PAINT_RED
	canvas.image_bounds = Rect2i(0, 0, SIDE, SIDE)
	canvas.clip_strokes_to_image_frame = true
	canvas.tool = "Brush"
	var backend: String = OS.get_environment("DRAWING_BRUSH_BACKEND")
	if not backend.is_empty():
		check(backend in ["Legacy", "NativeHard"], "supported hard Brush backend")
		if backend not in ["Legacy", "NativeHard"]:
			quit(2)
			return
		if backend == "NativeHard" and not ClassDB.class_exists("DrawingNativeBrush"):
			check(false, "NativeHard requested without an installed GDExtension")
			quit(2)
			return
		canvas.brush_backend = backend
	root.add_child(canvas)
	for initial_frame: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: PackedVector2Array = coverage_path()
	check(path.size() == 99, "99 deterministic serpentine source coordinates")
	var original_accumulation: bool = Input.use_accumulated_input
	var run_count: int = DEFAULT_RUNS
	var requested_runs: String = OS.get_environment("T095_FULL_CANVAS_RUNS")
	if not requested_runs.is_empty():
		check(requested_runs.is_valid_int() and int(requested_runs) >= 1 and
			int(requested_runs) <= 3, "run count must be 1..3")
		if failures > 0:
			quit(2)
			return
		run_count = int(requested_runs)
	for run_index: int in range(run_count):
		var doc: DrawingDocument = DrawingDocument.new("full-canvas-%d" % run_index)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Red", "root").value)
		canvas.document = doc
		canvas.layer_id = layer
		await process_frame
		var previous_revision: int = doc.revision
		var memory_before: int = OS.get_static_memory_usage()
		var peak_before: int = OS.get_static_memory_peak_usage()
		var begin_us: int = Time.get_ticks_usec()
		mouse_button(canvas, path[0], true)
		check(canvas.session != null, "stroke %d begins via pointer down" % run_index)
		for i: int in range(1, path.size()):
			mouse_motion(canvas, path[i])
		check(doc.revision == previous_revision,
			"stroke %d is still an uncommitted gesture at release" % run_index)
		mouse_button(canvas, path[path.size() - 1], false)
		var drained_frames: int = 0
		while canvas.session != null and drained_frames < DRAIN_FRAME_LIMIT:
			await process_frame
			drained_frames += 1
		check(canvas.session == null, "stroke %d drains its queued input" % run_index)
		await RenderingServer.frame_post_draw
		var complete_us: int = Time.get_ticks_usec()
		var stats: Dictionary = canvas.last_gesture_metrics
		var elapsed: float = float(complete_us - begin_us) / 1000.0
		var release: float = float(int(stats.get("commit_us", 0)) -
			int(stats.get("release_us", 0))) / 1000.0
		var stage: float = float(stats.get("stage_cpu_us", 0)) / 1000.0
		elapsed_ms.append(elapsed)
		release_ms.append(release)
		stage_ms.append(stage)
		check(doc.revision == previous_revision + 1, "stroke %d commits once" % run_index)
		check(int(stats.get("samples_received", 0)) == path.size() + 1,
			"stroke %d received every 100 pointer event" % run_index)
		check(int(stats.get("commit_us", 0)) > int(stats.get("release_us", 0)),
			"stroke %d has actual commit timestamps" % run_index)
		var max_previews: String = OS.get_environment("T099_MAX_PREVIEW_FRAMES")
		if not max_previews.is_empty():
			check(max_previews.is_valid_int() and int(max_previews) > 0,
				"T-099 changed-preview threshold is valid")
			if max_previews.is_valid_int():
				check(int(stats.get("preview_frames", 0)) <= int(max_previews),
					"T-099 drains all input with at most %d changed preview redraws (got %d)" % [
						int(max_previews), int(stats.get("preview_frames", 0))])
		check(Input.use_accumulated_input == original_accumulation,
			"stroke %d restores engine input accumulation" % run_index)
		print("T095_FULL_CANVAS_RUN index=%d backend=%s source_pixels=%d width_px=96 input_events=100 total_to_postdraw_ms=%.3f release_to_commit_ms=%.3f stage_cpu_ms=%.3f drain_frames=%d max_pending=%d commit_cpu_ms=%.3f compose_cpu_ms=%.3f texture_cpu_ms=%.3f preview_frames=%d segments_staged=%d drain_calls=%d max_batch_ms=%.3f max_drain_ms=%.3f frame_compose_p95_ms=%.3f max_frame_compose_ms=%.3f max_frame_draw_ms=%.3f retained_texture_bytes=%d" % [
			run_index, canvas.brush_backend, SIDE * SIDE, elapsed, release, stage,
			drained_frames, int(stats.get("max_pending", 0)),
			float(stats.get("commit_cpu_us", 0)) / 1000.0,
			float(stats.get("compose_cpu_us", 0)) / 1000.0,
			float(stats.get("texture_cpu_us", 0)) / 1000.0,
			int(stats.get("preview_frames", 0)), int(stats.get("segments_staged", 0)),
			int(stats.get("drain_calls", 0)),
			float(stats.get("max_stage_batch_us", 0)) / 1000.0,
			float(stats.get("max_drain_cpu_us", 0)) / 1000.0,
			frame_compose_p95_ms(stats),
			float(stats.get("max_frame_compose_cpu_us", 0)) / 1000.0,
			float(stats.get("max_frame_full_draw_cpu_us", 0)) / 1000.0,
			canvas._display_tiles.size() * canvas.DISPLAY_TILE_SIZE *
			canvas.DISPLAY_TILE_SIZE * 4])
		print("T100_POINTER_MEMORY index=%d static_before_bytes=%d " % [
			run_index, memory_before] +
			"static_after_bytes=%d peak_before_bytes=%d peak_after_bytes=%d" % [
			OS.get_static_memory_usage(), peak_before, OS.get_static_memory_peak_usage()])
		print("T099_FRAME_METRICS index=%d input_draw_p50_ms=%.3f input_draw_p95_ms=%.3f input_draw_max_ms=%.3f input_callback_p50_ms=%.3f input_callback_p95_ms=%.3f input_callback_max_ms=%.3f pending_depth_p95=%.0f pending_depth_max=%d pending_age_p95_ms=%.3f pending_age_max_ms=%.3f preview_draws=%d drain_calls=%d max_drain_ms=%.3f" % [
			run_index,
			frame_metric_p_ms(stats, "preview_input_to_frame_end_us", 0.5),
			frame_metric_p_ms(stats, "preview_input_to_frame_end_us", 0.95),
			float(stats.get("max_preview_input_to_frame_end_us", 0)) / 1000.0,
			frame_metric_p_ms(stats, "preview_input_to_post_draw_us", 0.5),
			frame_metric_p_ms(stats, "preview_input_to_post_draw_us", 0.95),
			float(stats.get("max_preview_input_to_post_draw_us", 0)) / 1000.0,
			frame_depth_p(stats, 0.95),
			int(stats.get("max_frame_pending_input_count", 0)),
			frame_metric_p_ms(stats, "oldest_pending_age_us", 0.95),
			float(stats.get("max_frame_oldest_pending_age_us", 0)) / 1000.0,
			int(stats.get("preview_frames", 0)),
			int(stats.get("drain_calls", 0)),
			float(stats.get("max_drain_cpu_us", 0)) / 1000.0])
		check_all_red(doc, layer, "stroke %d" % run_index)
		# T-102 intentionally populates missing display tiles over successive
		# frames. The first post-draw callback certifies frame submission, not
		# that every cold corner has reached the framebuffer.
		var settle_frames: int = 0
		while settle_frames < 40 and (canvas._cold_population_pending or
				int(canvas.last_frame_metrics.get("cold_tiles_deferred", 0)) > 0):
			await process_frame
			await RenderingServer.frame_post_draw
			settle_frames += 1
		check(not canvas._cold_population_pending and
			int(canvas.last_frame_metrics.get("cold_tiles_deferred", 0)) == 0,
			"stroke %d finishes progressive display population" % run_index)
		print("T104_DISPLAY_SETTLE index=%d backend=%s extra_frames=%d" % [
			run_index, canvas.brush_backend, settle_frames])
		var framebuffer: Image = root.get_texture().get_image()
		var screen_point: Vector2i = Vector2i(canvas.global_position +
			canvas.pixel_to_position(Vector2(256.5, 256.5)))
		var screen_color: Color = framebuffer.get_pixelv(screen_point)
		check(screen_color.r > 0.95 and screen_color.g < 0.05 and screen_color.b < 0.05,
			"stroke %d is visibly red at center in software framebuffer" % run_index)
		for corner: Vector2 in [Vector2(4.5, 4.5), Vector2(507.5, 4.5),
				Vector2(4.5, 507.5), Vector2(507.5, 507.5)]:
			var screen: Vector2i = Vector2i(canvas.global_position +
				canvas.pixel_to_position(corner))
			var color: Color = framebuffer.get_pixelv(screen)
			check(color.r > 0.95 and color.g < 0.05 and color.b < 0.05,
				"stroke %d framebuffer corner %s is red" % [run_index, corner])
		check(doc.undo().ok, "stroke %d can be undone in one step" % run_index)
		check(int(doc.read_pixel(layer, 256, 256).value) == 0,
			"stroke %d undo clears its canonical pixel" % run_index)
		check(doc.redo().ok, "stroke %d can be redone in one step" % run_index)
		check(int(doc.read_pixel(layer, 256, 256).value) == PAINT_RED,
			"stroke %d redo restores the opaque red pixel" % run_index)
	var p95: float = percentile(elapsed_ms, 0.95)
	var budget: String = OS.get_environment("T095_FULL_CANVAS_P95_BUDGET_MS")
	if not budget.is_empty():
		check(budget.is_valid_float() and float(budget) > 0.0 and p95 <= float(budget),
			"reference-hardware synthetic input-to-postdraw p95 <= %s ms" % budget)
	print("T095_FULL_CANVAS_SUMMARY backend=%s runs=%d total_p50_ms=%.3f total_p95_ms=%.3f release_p95_ms=%.3f stage_p95_ms=%.3f proposed_target_ms=100 target_met=%s failures=%d" % [
		canvas.brush_backend, run_count, percentile(elapsed_ms, 0.5), p95,
		percentile(release_ms, 0.95), percentile(stage_ms, 0.95), str(p95 <= 100.0), failures])
	if failures == 0:
		print("T095_FULL_CANVAS_PASSED")
	quit(1 if failures > 0 else 0)
