extends SceneTree
## T-068 targeted X11/Mesa latency witness for nontrivial canonical brush paths.
## This measures synthetic input through frame_post_draw, not physical scan-out.

const TRIALS: int = 5
const CASES: Array[Dictionary] = [
	{"name": "dab_4px", "world_width": 4.0, "path": "dab"},
	{"name": "dab_32px", "world_width": 32.0, "path": "dab"},
	{"name": "dab_64px", "world_width": 64.0, "path": "dab"},
	{"name": "long_4px", "world_width": 4.0, "path": "long"},
	{"name": "cross_4px", "world_width": 4.0, "path": "cross"},
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_STRESS_FAILED: " + label)


func _stats(values: Array[float]) -> Dictionary:
	# Preserve trial order so device evidence can check phase pairing and statistics.
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return {"samples_ms": values.duplicate(),
		"median_ms": snappedf(ordered[ordered.size() / 2], 0.001),
		"p95_ms": snappedf(ordered[ceili(ordered.size() * 0.95) - 1], 0.001)}


func _press(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = canvas.global_position + position
	event.global_position = event.position
	root.push_input(event, true)


func _move(canvas: AtlasCanvas, previous: Vector2, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.relative = position - previous
	root.push_input(event, true)


func _path(kind: String) -> Array[Vector2]:
	match kind:
		"long":
			return [Vector2(220, 340), Vector2(335, 340), Vector2(450, 340),
				Vector2(565, 340), Vector2(680, 340)]
		"cross":
			return [Vector2(450, 340), Vector2(555, 340), Vector2(555, 440),
				Vector2(450, 340), Vector2(345, 340)]
		_:
			return [Vector2(450, 340)]


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires real framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1024, 768)
	root.content_scale_size = root.size
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	history.active_map_id = "world"
	var composition: AtlasDrawingComposition = AtlasDrawingComposition.new(history)
	_check(composition.attach_campaign(campaign).ok, "attach canonical Drawing")
	var target: DrawingResult = composition.registry.document_at("world", "ground", 0, true)
	_check(target.ok and target.value is DrawingDocument, "canonical D0 document")
	if target.ok:
		var measured_document: DrawingDocument = target.value as DrawingDocument
		_check(measured_document.density_numerator == 1 and measured_document.density_denominator == 1,
			"sample D0 has exactly one pixel per world unit")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(900, 680)
	canvas.drawing_composition = composition
	root.add_child(canvas)
	_check(canvas.set_document(campaign.get_map("world"), campaign), "active map")
	canvas.render_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	for layer: AtlasLayer in canvas.floor.layers:
		layer.visible = false
	canvas.camera_center = Vector2(50, 60)
	canvas.camera_zoom = 10.0
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	for unused: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var rows: Array[Dictionary] = []
	var output_path: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg_index: int in range(args.size() - 1):
		if args[arg_index] == "--output":
			output_path = args[arg_index + 1]
	for case_index: int in range(CASES.size()):
		var workload: Dictionary = CASES[case_index]
		canvas.brush_width = float(workload["world_width"])
		var cpu_ms: Array[float] = []
		var frame_ms: Array[float] = []
		var before_revision: int = -1
		var positions: Array[Vector2] = _path(String(workload["path"]))
		for trial: int in range(TRIALS):
			# Alternate fully opaque colors so a repeat stroke must change the framebuffer.
			canvas.brush_color = Color.RED if (trial + case_index) % 2 == 0 else Color.BLUE
			var probe: Vector2i = Vector2i(canvas.global_position + Vector2(450, 340))
			var prior: Color = root.get_texture().get_image().get_pixelv(probe)
			var start_us: int = Time.get_ticks_usec()
			_press(canvas, positions[0], true)
			for point_index: int in range(1, positions.size()):
				_move(canvas, positions[point_index - 1], positions[point_index])
			_press(canvas, positions[positions.size() - 1], false)
			var cpu_done_us: int = Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			var frame_done_us: int = Time.get_ticks_usec()
			var current: Color = root.get_texture().get_image().get_pixelv(probe)
			_check((absf(current.r - prior.r) + absf(current.g - prior.g) + absf(current.b - prior.b)) > 0.15,
				"frame pixel changed for %s trial %d" % [workload["name"], trial])
			var document_result: DrawingResult = composition.registry.document_at("world", "ground", 0)
			_check(document_result.ok, "canonical document")
			if document_result.ok:
				var document: DrawingDocument = document_result.value as DrawingDocument
				_check(document.revision > before_revision,
					"new published revision for %s trial %d" % [workload["name"], trial])
				before_revision = document.revision
			cpu_ms.append(float(cpu_done_us - start_us) / 1000.0)
			frame_ms.append(float(frame_done_us - start_us) / 1000.0)
		rows.append({"name": workload["name"], "world_width": workload["world_width"],
			"synthetic_gestures": TRIALS, "cpu_dispatch": _stats(cpu_ms),
			"event_to_frame_post_draw": _stats(frame_ms)})
		print("T068_STRESS_CASE ", JSON.stringify(rows[rows.size() - 1]))
	_check(history.can_undo(), "gestures have Atlas history")
	var result: Dictionary = {"schema": "t068-native-stress-v1", "renderer": RenderingServer.get_current_rendering_method(),
		"driver": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info(), "rows": rows, "checks": checks, "failures": failures,
		"limitations": "Synthetic X11 Control events; software GL frame_post_draw, not presentation or hardware input"}
	if not output_path.is_empty():
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		_check(file != null, "save stress evidence")
		if file != null:
			result["checks"] = checks
			result["failures"] = failures
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
	print("T068_STRESS_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	root.remove_child(canvas)
	canvas.free()
	quit(0 if failures == 0 else 1)
