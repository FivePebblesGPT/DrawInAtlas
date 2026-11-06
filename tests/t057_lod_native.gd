extends SceneTree
## T-057 software-GL renderer witness. post_draw marks frame submission, not scanout.
## This script only measures the existing Atlas 2D camera/composition path.

const FRAMES: int = 21
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T057_NATIVE_FAILED: " + label)


func _stats(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[ceili(float(samples.size()) * 0.95) - 1], 0.001),
		"worst_ms": snappedf(samples.back(), 0.001)}


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires a native software-GL display")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	history.active_map_id = "world"
	var composition: AtlasDrawingComposition = AtlasDrawingComposition.new(history)
	_check(composition.attach_campaign(campaign).ok, "attach shared Drawing composition")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.position = Vector2(24, 24)
	canvas.size = Vector2(736, 540)
	canvas.drawing_composition = composition
	root.add_child(canvas)
	_check(canvas.set_document(campaign.get_map("world"), campaign), "use canonical Atlas map")
	canvas.render_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	for layer: AtlasLayer in canvas.floor.layers:
		layer.visible = false
	canvas.camera_center = Vector2(60, 75)
	canvas.camera_zoom = 8.0
	canvas.brush_color = Color.RED
	canvas.brush_width = 4.0
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	for frame: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	# Active D0 frame has pixels; unpainted D1 must remain transparent
	# independent of camera scale, not synthesize an overview fallback.
	var doc_result: DrawingResult = composition.registry.document_at("world", "ground", 0, true)
	_check(doc_result.ok, "D0 document exists")
	if not doc_result.ok or doc_result.value == null:
		quit(1)
		return
	var version: int = (doc_result.value as DrawingDocument).revision
	var dab: Vector2 = Vector2(320, 250)
	var point: Vector2i = Vector2i(canvas.global_position + dab)
	var screen_before: Color = root.get_texture().get_image().get_pixelv(point)
	var event_down: InputEventMouseButton = InputEventMouseButton.new()
	event_down.button_index = MOUSE_BUTTON_LEFT
	event_down.pressed = true
	event_down.position = canvas.global_position + dab
	event_down.global_position = event_down.position
	root.push_input(event_down, true)
	var event_up: InputEventMouseButton = InputEventMouseButton.new()
	event_up.button_index = MOUSE_BUTTON_LEFT
	event_up.pressed = false
	event_up.position = event_down.position
	event_up.global_position = event_down.position
	root.push_input(event_up, true)
	await RenderingServer.frame_post_draw
	var screen_after: Color = root.get_texture().get_image().get_pixelv(point)
	var edited: DrawingResult = composition.registry.document_at("world", "ground", 0, true)
	_check(edited.ok and (edited.value as DrawingDocument).revision > version,
		"live pointer gesture publishes canonical source revision")
	_check(screen_after.r > screen_before.r + 0.1,
		"live stroke is visible in native framebuffer")
	var first_detail: DrawingResult = composition.registry.ensure_detail("world", "ground", 1)
	_check(first_detail.ok, "create independent authored D1")
	var empty: DrawingResult = composition.render_region("world", "ground", 1,
		Rect2i(0, 0, 64, 64), 0, 0)
	_check(empty.ok, "unpainted D1 bounded render succeeds")
	if empty.ok:
		var blank: PackedByteArray = (empty.value as Image).get_data()
		var all_blank: bool = true
		for value: int in blank:
			if value != 0:
				all_blank = false
				break
		_check(all_blank, "authored D1 must stay blank without D0 fallback")
	_check(canvas.set_presented_detail_level(1), "switch to empty authored detail")
	await RenderingServer.frame_post_draw
	_check(canvas.set_presented_detail_level(0), "return to D0 without changing edit target")
	# Test camera-relative mapping at large signed but float-representable
	# anchors; quantify the float precision limit beyond 2^24.
	canvas.camera_zoom = 4.0
	var signs: Array[float] = [-1048576.0, 1048576.0]
	var camera_deltas: Array[Dictionary] = []
	for anchor: float in signs:
		canvas.camera_center = Vector2(anchor, -anchor)
		var center: Vector2 = canvas.document_to_local(canvas.camera_center)
		var next: Vector2 = canvas.document_to_local(canvas.camera_center + Vector2(8, -4))
		_check(center.distance_to(canvas.size * 0.5) < 0.01,
			"camera-relative origin stable at signed million-scale position")
		_check(absf((next - center).x - 32.0) < 0.01 and absf((next - center).y + 16.0) < 0.01,
			"small translation remains stable near million-scale camera")
		camera_deltas.append({"anchor": anchor, "world_8px_delta_screen": next - center})
	var big: Vector2 = Vector2(16777216.0, -16777216.0)
	var increment: Vector2 = Vector2(16777217.0, -16777217.0)
	var huge_camera_one_unit_distinguishable: bool = big != increment
	# Pan and zoom through a real X11/Mesa draw pipeline. Do not conflate
	# the measured post_draw signal with actual physical presentation.
	var frame_ms: Array[float] = []
	var camera_positions: Array[Vector2] = []
	var static_memory_peak: float = 0.0
	var reported_video_memory_peak: float = 0.0
	var reported_texture_memory_peak: int = 0
	canvas.camera_zoom = 6.0
	for index: int in range(FRAMES):
		var direction: float = -1.0 if index % 2 == 0 else 1.0
		var location: Vector2 = Vector2(60.0 + direction * float(index) * 7.0,
			75.0 + float((index % 5) - 2) * 17.0)
		camera_positions.append(location)
		canvas.camera_zoom = [4.0, 6.0, 8.0][index % 3]
		var start_us: int = Time.get_ticks_usec()
		canvas.camera_center = location
		canvas.queue_redraw()
		await RenderingServer.frame_post_draw
		frame_ms.append(float(Time.get_ticks_usec() - start_us) / 1000.0)
		static_memory_peak = maxf(static_memory_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
		reported_video_memory_peak = maxf(reported_video_memory_peak,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		reported_texture_memory_peak = maxi(reported_texture_memory_peak,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
		_check(frame_ms.back() > 0.0, "frame-post-draw timing %d" % index)
	var memory_monitor: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var vram_monitor: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var result: Dictionary = {"schema": "t057-lod-native-v1", "engine": Engine.get_version_info(),
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"window": [root.size.x, root.size.y], "frames": FRAMES,
		"camera_pan_zoom_frame_post_draw": _stats(frame_ms),
		"static_memory_monitor_bytes": memory_monitor,
		"static_memory_peak_sampled_bytes": static_memory_peak,
		"vram_monitor_bytes": vram_monitor,
		"reported_video_memory_peak_sampled_bytes": reported_video_memory_peak,
		"reported_texture_memory_peak_sampled_bytes": reported_texture_memory_peak,
		"float_camera_distinguishes_2pow24_plus_one": huge_camera_one_unit_distinguishable,
		"signed_camera_probes": camera_deltas,
		"limits": "Mesa/Xvfb post_draw; reported VRAM is a software-renderer accounting estimate, not physical GPU VRAM or photons. Atlas Vector2 1-unit precision eventually fails at huge anchors.",
		"checks": checks, "failures": failures}
	var output: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output = args[index + 1]
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "write native JSON")
		if file != null:
			result["checks"] = checks
			result["failures"] = failures
			file.store_string(JSON.stringify(result, "  ") + "\n")
			file.close()
	root.remove_child(canvas)
	canvas.free()
	print("T057_LOD_NATIVE_%s checks=%d failures=%d frame=%s" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures,
		JSON.stringify(result["camera_pan_zoom_frame_post_draw"])])
	quit(0 if failures == 0 else 1)
