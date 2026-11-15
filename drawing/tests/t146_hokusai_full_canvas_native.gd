extends SceneTree
## T-146 full-canvas 96px Hokusai hard-round Brush through actual Godot mouse routing.
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
		printerr("T146_HOKUSAI_FAILED: " + label)


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


## The independent candidate oracle measures every source alpha; it does not
## require Hokusai pigment to match Legacy's exact opaque-red geometry.
## The digest covers all 512*512 RGBA bytes in row-major order.
func scan_source(doc: DrawingDocument, layer: String, label: String) -> Dictionary:
	var tiles: Dictionary = {}
	var keys: Array[String] = doc.tile_keys(layer)
	for key: String in keys:
		check(key in ["0,0", "0,1", "1,0", "1,1"],
			label + ": no paint outside the image frame: " + key)
	for cy: int in range(2):
		for cx: int in range(2):
			var result: DrawingResult = doc.request_chunk_at(layer, cx, cy)
			check(result.ok, label + ": tile read succeeds")
			var bytes: PackedByteArray = PackedByteArray()
			if result.ok and result.value != null:
				bytes = (result.value as DrawingRasterTile).to_rgba8()
			if bytes.is_empty():
				bytes.resize(256 * 256 * 4)
			check(bytes.size() == 256 * 256 * 4, label + ": RGBA8 tile length")
			tiles["%d,%d" % [cx, cy]] = bytes
	var zero: int = 0
	var low: int = 0
	var mid_low: int = 0
	var mid_high: int = 0
	var high: int = 0
	var opaque: int = 0
	var red: int = 0
	var nonred: int = 0
	var first_hole: Vector2i = Vector2i(-1, -1)
	var digest: HashingContext = HashingContext.new()
	check(digest.start(HashingContext.HASH_SHA256) == OK, label + ": SHA init")
	for y: int in range(SIDE):
		var band_y: int = y / 256
		var local_y: int = y % 256
		for cx: int in range(2):
			var bytes: PackedByteArray = tiles["%d,%d" % [cx, band_y]]
			var line: PackedByteArray = bytes.slice((local_y * 256) * 4,
				(local_y * 256 + 256) * 4)
			digest.update(line)
			for local_x: int in range(256):
				var offset: int = local_x * 4
				var alpha: int = line[offset + 3]
				if alpha == 0:
					zero += 1
					if first_hole.x < 0:
						first_hole = Vector2i(cx * 256 + local_x, y)
				elif alpha < 64:
					low += 1
				elif alpha < 128:
					mid_low += 1
				elif alpha < 192:
					mid_high += 1
				elif alpha < 255:
					high += 1
				else:
					opaque += 1
				if alpha > 0:
					if line[offset] > line[offset + 1] and line[offset] > line[offset + 2]:
						red += 1
					else:
						nonred += 1
	var result: Dictionary = {
		"sha256": digest.finish().hex_encode(), "zero": zero,
		"low": low, "mid_low": mid_low, "mid_high": mid_high,
		"high": high, "opaque": opaque, "red": red,
		"nonred": nonred, "first_hole": first_hole,
		"covered": SIDE * SIDE - zero
	}
	print("T146_SOURCE label=%s sha256=%s covered=%d zero=%d " % [
		label, result.sha256, result.covered, zero] +
		"alpha_1_63=%d alpha_64_127=%d alpha_128_191=%d " % [
			low, mid_low, mid_high] +
		"alpha_192_254=%d alpha_255=%d red=%d nonred=%d first_hole=%s " % [
			high, opaque, red, nonred, first_hole] +
		"fills_512=%s" % str(zero == 0))
	return result


func rgb_sample(canvas: Control, framebuffer: Image, pixel: Vector2) -> Color:
	return framebuffer.get_pixelv(Vector2i(canvas.global_position +
		canvas.pixel_to_position(pixel)))


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
	check(backend == "Hokusai", "requires explicit DRAWING_BRUSH_BACKEND=Hokusai")
	check(ClassDB.class_exists("DrawingNativeBrush"), "real native class is registered")
	if failures > 0:
		quit(2)
		return
	var preset_path: String = canvas.BUNDLED_PRESETS["hard"]
	var settings: String = FileAccess.get_file_as_string(preset_path)
	check(not settings.is_empty(), "hard_round.myb settings read")
	var probe: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(probe != null and probe.has_method("begin_stroke") and
		probe.has_method("append_samples") and
		int(probe.call("stroke_abi_version")) == 1,
		"native v1 hard-round stroke API is present")
	if failures == 0:
		var opened: Dictionary = probe.call("begin_stroke", "probe", "Hokusai",
			settings, BRUSH_WIDTH, PAINT_RED, 1, Rect2i())
		check(bool(opened.get("ok", false)), "real hard-round begin_stroke succeeds")
		if bool(opened.get("ok", false)):
			check(bool(probe.call("abort_stroke", opened["handle"])),
				"native probe aborts without modifying document")
	if failures > 0:
		quit(2)
		return
	canvas.brush_backend = "Hokusai"
	canvas.brush_preset = "hard"
	print("T146_IDENTITY backend=Hokusai preset=hard width=96 " +
		"preset_sha256=%s godot=%s native_sha256=%s repo_sha=%s" % [
			FileAccess.get_sha256(preset_path), Engine.get_version_info().get("string", ""),
			OS.get_environment("T146_NATIVE_SHA256"),
			OS.get_environment("T146_REPO_SHA")])
	root.add_child(canvas)
	for initial_frame: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: PackedVector2Array = coverage_path()
	check(path.size() == 99, "99 deterministic serpentine source coordinates")
	var original_accumulation: bool = Input.use_accumulated_input
	var run_count: int = DEFAULT_RUNS
	var requested_runs: String = OS.get_environment("T146_RUNS")
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
		check(canvas._active_brush_backend == "Hokusai" and canvas._native_brush != null,
			"stroke %d selects REAL Hokusai, not fallback" % run_index)
		if failures > 0:
			quit(2)
			return
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
		print("T146_HOKUSAI_RUN index=%d backend=%s source_pixels=%d width_px=96 input_events=100 total_to_postdraw_ms=%.3f release_to_commit_ms=%.3f stage_cpu_ms=%.3f drain_frames=%d max_pending=%d commit_cpu_ms=%.3f compose_cpu_ms=%.3f texture_cpu_ms=%.3f preview_frames=%d segments_staged=%d drain_calls=%d max_batch_ms=%.3f max_drain_ms=%.3f frame_compose_p95_ms=%.3f max_frame_compose_ms=%.3f max_frame_draw_ms=%.3f retained_texture_bytes=%d" % [
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
		var source: Dictionary = scan_source(doc, layer, "stroke-%d" % run_index)
		check(int(source.covered) == SIDE * SIDE and int(source.zero) == 0,
			"hard-round 96px covers every source pixel without transparent holes")
		check(int(source.nonred) == 0, "painted Hokusai pixels retain red hue")
		check(doc.history_length() == 1 and doc.history_position() == 1,
			"one and only one committed raster history event")
		print("T146_FIRST_VISIBLE index=%d first_submit_us=%d first_postdraw_us=%d " % [
			run_index, int(stats.get("first_preview_submit_us", 0)),
			int(stats.get("first_frame_post_draw_us", 0))] +
			"down_us=%d postdraw_matches=%d frame_samples=%d" % [
				int(stats.get("down_us", 0)),
				int(stats.get("frame_post_draw_matches", 0)),
				int(stats.get("frame_phase_total", 0))])
		var hokusai_perf: Dictionary = stats.get("hokusai_perf", {})
		print("T146_NATIVE_PHASE index=%d native_cpu_ms=%.3f native_changed=%s " % [
			run_index, float(hokusai_perf.get("native_us", 0)) / 1000.0,
			str(hokusai_perf.get("pixels", "unavailable"))] +
			"stage_cpu_ms=%.3f perf=%s" % [stage, JSON.stringify(hokusai_perf)])
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
		for position: Vector2 in [Vector2(4.5, 4.5), Vector2(256.5, 256.5),
				Vector2(507.5, 4.5), Vector2(4.5, 507.5), Vector2(507.5, 507.5)]:
			var color: Color = rgb_sample(canvas, framebuffer, position)
			var source_color: int = int(doc.read_pixel(layer, int(position.x), int(position.y)).value)
			print("T146_FRAMEBUFFER index=%d point=%s rgba=%s source_rgba=%08x" % [
				run_index, position, color, source_color])
			check(color.r > color.g + 0.10 and color.r > color.b + 0.10,
				"painted source visibly changes software framebuffer at %s" % position)
		check(doc.undo().ok, "stroke %d can be undone in one step" % run_index)
		check(doc.history_position() == 0, "Undo rewinds exactly one event")
		check(doc.tile_keys(layer).is_empty(), "Undo removes all source tiles")
		check(doc.redo().ok, "stroke %d can be redone in one step" % run_index)
		check(doc.history_position() == 1, "Redo restores exactly one event")
		var redone: Dictionary = scan_source(doc, layer, "redo-%d" % run_index)
		check(redone.sha256 == source.sha256,
			"Redo restores exact Hokusai source RGBA8, including alpha")
		print("T146_FILL_STATUS index=%d full_coverage=%s holes=%d" % [
			run_index, str(int(source.zero) == 0), int(source.zero)])
	# Separate rollback/retry exercise, outside benchmark timings.
	var cancel_doc: DrawingDocument = DrawingDocument.new("t146-cancellation")
	var cancel_layer: String = String(cancel_doc.create_layer(
		DrawingLayerNode.RASTER, "Cancel", "root").value)
	canvas.document = cancel_doc
	canvas.layer_id = cancel_layer
	await process_frame
	var cancel_revision: int = cancel_doc.revision
	mouse_button(canvas, Vector2(256.5, 256.5), true)
	check(canvas._active_brush_backend == "Hokusai", "cancel starts actual Hokusai")
	mouse_motion(canvas, Vector2(260.5, 260.5))
	canvas.cancel_gesture()
	check(cancel_doc.revision == cancel_revision and cancel_doc.history_length() == 0 and
		cancel_doc.tile_keys(cancel_layer).is_empty(), "cancellation keeps source and history pristine")
	mouse_button(canvas, Vector2(256.5, 256.5), true)
	check(canvas._active_brush_backend == "Hokusai", "retry reconfigures actual Hokusai")
	for retry_step: int in range(1, 9):
		mouse_motion(canvas, Vector2(256.5 + float(retry_step) * 4.0, 256.5))
	mouse_button(canvas, Vector2(288.5, 256.5), false)
	for retry_frame: int in range(DRAIN_FRAME_LIMIT):
		if canvas.session == null:
			break
		await process_frame
	check(canvas.session == null and cancel_doc.revision == cancel_revision + 1 and
		cancel_doc.history_length() == 1, "retry publishes exactly one transaction")
	check(int(cancel_doc.read_pixel(cancel_layer, 256, 256).value) != 0,
		"retry paints actual pigment")
	print("T146_CANCEL_RETRY revision=%d base_revision=%d events=%d tiles=%s metrics=%s" % [
		cancel_doc.revision, cancel_revision, cancel_doc.history_length(),
		str(cancel_doc.tile_keys(cancel_layer)), JSON.stringify(canvas.last_gesture_metrics)])
	# Selection/hidden-RGB test is deliberately OUTSIDE timing and does not
	# replace any pixel of the benchmark's brush-created 512x512 source.
	var mask_doc: DrawingDocument = DrawingDocument.new("t146-mask-hidden-rgb")
	var mask_layer: String = String(mask_doc.create_layer(
		DrawingLayerNode.RASTER, "Mask", "root").value)
	var seed_result: DrawingResult = mask_doc.begin_edit(mask_layer, mask_doc.revision)
	check(seed_result.ok, "mask fixture opens normal edit session")
	if seed_result.ok:
		var seed: DrawingEditSession = seed_result.value
		check(seed.apply_region(Rect2i(310, 310, 1, 1),
			PackedByteArray([17, 34, 51, 0])).ok,
			"fixture writes exact hidden RGBA8")
		check(seed.commit().ok, "hidden RGB fixture committed")
	check(int(mask_doc.read_pixel(mask_layer, 310, 310).value) == 0x00332211,
		"hidden RGB bytes persisted before native stroke")
	canvas.document = mask_doc
	canvas.layer_id = mask_layer
	var selection: DrawingSelection = DrawingSelection.new()
	selection.set_rectangle(Rect2i(240, 240, 32, 32))
	canvas.set_selection_mask(selection)
	await process_frame
	var mask_revision: int = mask_doc.revision
	mouse_button(canvas, Vector2(248.5, 256.5), true)
	check(canvas._active_brush_backend == "Hokusai", "masked stroke is actually native")
	for mask_step: int in range(1, 9):
		mouse_motion(canvas, Vector2(248.5 + float(mask_step) * 2.0, 256.5))
	mouse_button(canvas, Vector2(264.5, 256.5), false)
	for mask_frame: int in range(DRAIN_FRAME_LIMIT):
		if canvas.session == null:
			break
		await process_frame
	check(canvas.session == null and mask_doc.revision == mask_revision + 1,
		"masked native stroke commits once")
	check(int(mask_doc.read_pixel(mask_layer, 256, 256).value) != 0,
		"masked native Brush paints inside authorized rectangle")
	check(int(mask_doc.read_pixel(mask_layer, 230, 256).value) == 0,
		"masked native Brush does not paint outside selection")
	check(int(mask_doc.read_pixel(mask_layer, 310, 310).value) == 0x00332211,
		"unselected transparent pixel retains hidden RGB8")
	check(mask_doc.undo().ok and
		int(mask_doc.read_pixel(mask_layer, 256, 256).value) == 0 and
		int(mask_doc.read_pixel(mask_layer, 310, 310).value) == 0x00332211,
		"masked stroke Undo preserves preexisting hidden RGB")
	check(mask_doc.redo().ok and
		int(mask_doc.read_pixel(mask_layer, 256, 256).value) != 0 and
		int(mask_doc.read_pixel(mask_layer, 310, 310).value) == 0x00332211,
		"masked stroke Redo preserves hidden RGB")
	canvas.clear_selection()
	print("T146_MASK_HIDDEN_RGB native=Hokusai rgba=%08x revision=%d" % [
		int(mask_doc.read_pixel(mask_layer, 310, 310).value), mask_doc.revision])
	var p95: float = percentile(elapsed_ms, 0.95)
	var budget: String = OS.get_environment("T146_HOKUSAI_P95_BUDGET_MS")
	if not budget.is_empty():
		check(budget.is_valid_float() and float(budget) > 0.0 and p95 <= float(budget),
			"reference-hardware synthetic input-to-postdraw p95 <= %s ms" % budget)
	print("T146_HOKUSAI_SUMMARY backend=%s runs=%d total_p50_ms=%.3f total_p95_ms=%.3f release_p95_ms=%.3f stage_p95_ms=%.3f proposed_target_ms=100 target_met=%s failures=%d" % [
		canvas.brush_backend, run_count, percentile(elapsed_ms, 0.5), p95,
		percentile(release_ms, 0.95), percentile(stage_ms, 0.95), str(p95 <= 100.0), failures])
	if failures == 0:
		print("T146_HOKUSAI_BENCHMARK_PASSED")
	quit(1 if failures > 0 else 0)
