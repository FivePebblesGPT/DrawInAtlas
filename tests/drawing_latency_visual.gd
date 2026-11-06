extends SceneTree
## T-068: actual X11 input dispatch -> CPU commit -> framebuffer submission witness.
## frame_post_draw is *not* a physical display or scan-out measurement.

const TRIALS: int = 21
var checks: int = 0
var failures: int = 0
var cpu_ms: Array[float] = []
var frame_ms: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_LATENCY_FAILED: " + label)

func _quantiles(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median_ms": snappedf(values[values.size() / 2], 0.001),
		"p95_ms": snappedf(values[ceili(float(values.size()) * 0.95) - 1], 0.001)}

func _push_button(local: Vector2, canvas: AtlasCanvas, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + local
	event.global_position = event.position
	root.push_input(event, true)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires actual GL framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1024, 768)
	root.content_scale_size = root.size
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	history.active_map_id = "world"
	var composed: AtlasDrawingComposition = AtlasDrawingComposition.new(history)
	_check(composed.attach_campaign(campaign).ok, "attach canonical Drawing document registry")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(900, 680)
	canvas.drawing_composition = composed
	root.add_child(canvas)
	_check(canvas.set_document(campaign.get_map("world"), campaign), "set live Atlas map")
	canvas.render_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	for layer: AtlasLayer in canvas.floor.layers:
		layer.visible = false
	canvas.camera_center = Vector2(50, 60)
	canvas.camera_zoom = 10.0
	canvas.brush_color = Color.RED
	canvas.brush_width = 2.0
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	canvas.queue_redraw()
	for frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var sample_zero: Color = root.get_texture().get_image().get_pixelv(
		Vector2i(canvas.global_position + Vector2(80, 340)))
	var first_revision: int = 0
	for trial: int in range(TRIALS):
		var local: Vector2 = Vector2(80.0 + float(trial) * 33.0, 340.0)
		var frame_point: Vector2i = Vector2i(canvas.global_position + local)
		var before: Color = root.get_texture().get_image().get_pixelv(frame_point)
		var start_us: int = Time.get_ticks_usec()
		_push_button(local, canvas, true)
		_push_button(local, canvas, false)
		var cpu_complete: int = Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var frame_complete: int = Time.get_ticks_usec()
		var after: Color = root.get_texture().get_image().get_pixelv(frame_point)
		_check(after.r > before.r + 0.15, "new stroke visibly reaches native framebuffer %d" % trial)
		var document_result: DrawingResult = composed.registry.document_at("world", "ground", 0)
		_check(document_result.ok, "canonical document available")
		if document_result.ok:
			var document: DrawingDocument = document_result.value as DrawingDocument
			_check(document.revision > first_revision, "native input committed Drawing revision %d" % trial)
			first_revision = document.revision
		cpu_ms.append(float(cpu_complete - start_us) / 1000.0)
		frame_ms.append(float(frame_complete - start_us) / 1000.0)
	_check(sample_zero != Color.RED, "first probe starts without red paint")
	_check(history.can_undo(), "native gesture integrated into global history")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_path: String = ""
	for i: int in range(args.size() - 1):
		if args[i] == "--output":
			output_path = args[i + 1]
	var file: FileAccess = null
	if not output_path.is_empty():
		file = FileAccess.open(output_path, FileAccess.WRITE)
		_check(file != null, "open evidence output")
	var results: Dictionary = {"schema": "t068-native-frame-v1", "driver": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "trials": TRIALS,
		"cpu_input_dispatch": _quantiles(cpu_ms), "input_to_frame_post_draw": _quantiles(frame_ms),
		"limitations": "X11 synthetic events; post_draw submission, not photons, hardware GPU or OS mouse latency",
		"checks": checks, "failures": failures}
	print("T068_NATIVE_FRAME_RESULTS ", JSON.stringify(results))
	if file != null:
		file.store_string(JSON.stringify(results, "  ") + "\n")
		file.close()
	root.remove_child(canvas)
	canvas.free()
	print("T068_NATIVE_FRAME_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
