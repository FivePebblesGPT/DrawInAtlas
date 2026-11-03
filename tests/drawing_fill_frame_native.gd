extends SceneTree
## T-068 targeted native witness: canonical Drawing flood-fill on a GUI-input
## release, followed by DrawingCanvas rendering and software frame submission.
## This is a test adapter, NOT a claim that DrawingCanvas exposes a Bucket tool.

const CANVAS_SCRIPT: Script = preload("res://addons/drawing/canvas.gd")
const DEFAULT_TRIALS: int = 5
const MAX_TRIALS: int = 40
const SIZES: Array[int] = [32, 64, 96]
const SOURCE_RGBA: int = 0xff321e0a
const TARGET_RGBA: int = 0xff2088e8

var checks: int = 0
var failures: int = 0
var _canvas: Control
var _document: DrawingDocument
var _layer: String = ""
var _budget: int = 0
var _started: bool = false
var _last_result: DrawingResult
var _dispatch_count: int = 0
var _trials: int = DEFAULT_TRIALS


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_FILL_FRAME_FAILED: " + label)


func _stats(source: Array[float]) -> Dictionary:
	var samples: Array[float] = source.duplicate()
	samples.sort()
	return {"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[ceili(float(samples.size()) * 0.95) - 1], 0.001),
		"min_ms": snappedf(samples.front(), 0.001),
		"max_ms": snappedf(samples.back(), 0.001), "samples_ms": samples}


func _click(local_position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = _canvas.global_position + local_position
		event.global_position = event.position
		root.push_input(event, true)


func _fill_on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_started = true
		return
	if not _started:
		return
	_started = false
	_dispatch_count += 1
	var pixel: Vector2i = _canvas.position_to_pixel(button.position)
	var opened: DrawingResult = _document.begin_edit(_layer, _document.revision)
	if not opened.ok:
		_last_result = opened
		return
	var session: DrawingEditSession = opened.value as DrawingEditSession
	var staged: DrawingResult = session.flood_fill(pixel, TARGET_RGBA, null, _budget)
	if staged.ok:
		_last_result = session.commit()
	else:
		session.cancel()
		_last_result = staged
	if _last_result.ok:
		_canvas.queue_redraw()


func _seed(size: int) -> bool:
	_document = DrawingDocument.new("native-bucket-%d" % size, 128)
	var layer_result: DrawingResult = _document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not layer_result.ok:
		return false
	_layer = String(layer_result.value)
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(size * size * 4)
	for index: int in range(size * size):
		payload[index * 4] = SOURCE_RGBA & 255
		payload[index * 4 + 1] = (SOURCE_RGBA >> 8) & 255
		payload[index * 4 + 2] = (SOURCE_RGBA >> 16) & 255
		payload[index * 4 + 3] = (SOURCE_RGBA >> 24) & 255
	var edit: DrawingResult = _document.begin_edit(_layer, _document.revision)
	if not edit.ok:
		return false
	var transaction: DrawingEditSession = edit.value as DrawingEditSession
	var populated: DrawingResult = transaction.apply_region(
		Rect2i(-size / 2, -size / 2, size, size), payload)
	if not populated.ok:
		transaction.cancel()
		return false
	if not transaction.commit().ok:
		return false
	_canvas.document = _document
	_canvas.layer_id = _layer
	_canvas.tool = "Fill"  # Harness handles release; it is not a production canvas tool.
	_canvas.queue_redraw()
	_budget = size * size * 6
	_last_result = null
	_started = false
	return true


func _frame_color() -> Color:
	var position: Vector2i = Vector2i(_canvas.global_position + _canvas.size * 0.5 + Vector2(2, 2))
	return root.get_texture().get_image().get_pixelv(position)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var ready_file: String = ""
	for arg_index: int in range(args.size() - 1):
		if args[arg_index] == "--trials":
			var parsed_trials: String = args[arg_index + 1]
			if not parsed_trials.is_valid_int() or int(parsed_trials) < DEFAULT_TRIALS \
					or int(parsed_trials) > MAX_TRIALS:
				_check(false, "trials must be in [5, 40]")
				quit(1)
				return
			_trials = int(parsed_trials)
		elif args[arg_index] == "--ready-file":
			ready_file = args[arg_index + 1]
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(900, 720)
	root.content_scale_size = root.size
	_canvas = CANVAS_SCRIPT.new() as Control
	_canvas.position = Vector2(45, 35)
	_canvas.size = Vector2(800, 640)
	_canvas.zoom = 4.0
	_canvas.camera = Vector2.ZERO
	root.add_child(_canvas)
	_canvas.gui_input.connect(Callable(self, "_fill_on_gui_input"))
	for unused: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	if not ready_file.is_empty():
		var ready: FileAccess = FileAccess.open(ready_file, FileAccess.WRITE)
		_check(ready != null, "write host sampler readiness marker")
		if ready == null:
			quit(1)
			return
		ready.store_string("ready\n")
		ready.close()

	var cases: Array[Dictionary] = []
	var memory_peak: float = 0.0
	var vram_peak: float = 0.0
	var textures_peak: int = 0
	for size: int in SIZES:
		var cpu_ms: Array[float] = []
		var frame_ms: Array[float] = []
		for trial: int in range(_trials):
			_check(_seed(size), "prepare %d trial %d" % [size, trial])
			await RenderingServer.frame_post_draw
			var previous: Color = _frame_color()
			var revision: int = _document.revision
			var before_dispatch: int = _dispatch_count
			var start_us: int = Time.get_ticks_usec()
			_click(_canvas.size * 0.5 + Vector2(2, 2))
			var cpu_done_us: int = Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			var frame_done_us: int = Time.get_ticks_usec()
			var visible: Color = _frame_color()
			_check(absf(previous.r - 10.0 / 255.0) < 0.06 and
				absf(previous.g - 30.0 / 255.0) < 0.06,
				"seed source is visible before input %d/%d" % [size, trial])
			_check(_dispatch_count == before_dispatch + 1 and _last_result != null
				and _last_result.ok, "native release commits once %d/%d" % [size, trial])
			_check(_document.revision == revision + 1 and _last_result != null
				and _last_result.delta != null and _last_result.delta.after.size() == size * size,
				"exact canonical fill coverage %d/%d" % [size, trial])
			_check(int(_document.read_pixel(_layer, 0, 0).value) == TARGET_RGBA,
				"source RGBA8 updated %d/%d" % [size, trial])
			_check(visible.r > previous.r + 0.35 and visible.g > previous.g + 0.25,
				"framebuffer visible after fill %d/%d" % [size, trial])
			cpu_ms.append(float(cpu_done_us - start_us) / 1000.0)
			frame_ms.append(float(frame_done_us - start_us) / 1000.0)
			memory_peak = maxf(memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
			vram_peak = maxf(vram_peak, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			textures_peak = maxi(textures_peak,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
		cases.append({"size": size, "pixels": size * size, "trials": _trials,
			"cpu_dispatch": _stats(cpu_ms), "event_to_frame_post_draw": _stats(frame_ms)})
		print("T068_FILL_FRAME_CASE ", JSON.stringify(cases.back()))

	# Save the successfully filled 96px frame, not the subsequent rejection case.
	var output_path: String = ""
	var screenshot_path: String = ""
	for arg_index: int in range(args.size() - 1):
		if args[arg_index] == "--output":
			output_path = args[arg_index + 1]
		elif args[arg_index] == "--screenshot":
			screenshot_path = args[arg_index + 1]
	if not screenshot_path.is_empty():
		_check(root.get_texture().get_image().save_png(screenshot_path) == OK,
			"write successfully filled native framebuffer screenshot")

	# A failed gesture must never publish, even when it starts with valid pixels.
	_check(_seed(32), "prepare rejected-gesture fixture")
	await RenderingServer.frame_post_draw
	_budget = 1
	var prior_revision: int = _document.revision
	var before_rejected: Color = _frame_color()
	_click(_canvas.size * 0.5 + Vector2(2, 2))
	await RenderingServer.frame_post_draw
	_check(_last_result != null and not _last_result.ok and _last_result.code == "FILL_LIMIT",
		"bounded input fill reports budget cancellation")
	_check(_document.revision == prior_revision and _frame_color() == before_rejected,
		"rejected input does not publish or alter framebuffer")
	_check(int(_document.read_pixel(_layer, 0, 0).value) == SOURCE_RGBA,
		"cancelled fill retains byte-exact source")

	var result: Dictionary = {"schema": "t068-bucket-frame-v1", "engine": Engine.get_version_info(),
		"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"configured_trials_per_size": _trials,
		"cases": cases, "checks": checks, "failures": failures,
		"sampled_static_memory_peak_bytes": memory_peak,
		"sampled_render_video_memory_peak_bytes": vram_peak,
		"sampled_texture_memory_peak_bytes": textures_peak,
		"limits": "Synthetic X11 GUI release mapped by a test adapter to canonical DrawingEditSession; not production Bucket UI, physical pointer, scan-out, or GPU VRAM. Memory monitors are sampled/renderer-dependent."}
	if not output_path.is_empty():
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		_check(file != null, "write diagnostic JSON")
		if file != null:
			result["checks"] = checks
			result["failures"] = failures
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
	print("T068_FILL_FRAME_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	root.remove_child(_canvas)
	_canvas.free()
	quit(0 if failures == 0 else 1)
