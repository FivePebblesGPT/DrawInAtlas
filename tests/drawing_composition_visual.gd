extends SceneTree
## T-055 software framebuffer: canonical raster frame with native Atlas chrome.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T055_NATIVE_FAILED: " + label)

func _frames(amount: int = 6) -> void:
	for i: int in range(amount):
		await process_frame

func _hash() -> String:
	return root.get_texture().get_image().get_data().hex_encode().sha256_text()

func _button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	return event

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires software/native framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(920, 680)
	root.content_scale_size = root.size
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new()
	history.reset(campaign)
	history.active_map_id = "world"
	var comp: AtlasDrawingComposition = AtlasDrawingComposition.new(history)
	_check(comp.attach_campaign(campaign).ok, "canonical registry set up")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.position = Vector2(20, 20)
	canvas.size = Vector2(780, 580)
	canvas.drawing_composition = comp
	root.add_child(canvas)
	_check(canvas.set_document(campaign.get_map("world"), campaign), "native map mounted")
	canvas.render_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	for old: AtlasLayer in canvas.floor.layers:
		old.visible = false
	canvas.camera_center = Vector2(4, 5)
	canvas.camera_zoom = 12.0
	canvas.brush_width = 3.0
	canvas.brush_color = Color.RED
	canvas.choose_tool(AtlasCanvas.Tool.PEN)
	canvas.queue_redraw()
	await _frames(8)
	var baseline: String = _hash()
	var center: Vector2 = canvas.size * 0.5
	canvas._gui_input(_button(center, true))
	canvas._gui_input(_button(center, false))
	await _frames(8)
	var paint_hash: String = _hash()
	_check(baseline != paint_hash, "canonical paint draws visible pixel on native canvas")
	var live: DrawingDocument = comp.registry.document_at("world", "ground", 0).value
	_check(live != null and live.read_pixel(live.list_children()[0], 4, 5).value != 0,
		"native frame reflects same canonical raster document")
	canvas.set_presented_detail_level(1)
	await _frames(8)
	var blank_hash: String = _hash()
	_check(blank_hash != paint_hash, "D1 blank does not inherit D0 rendered artwork")
	canvas.render_grid = true
	canvas.queue_redraw()
	await _frames(8)
	var grid_hash: String = _hash()
	_check(grid_hash != blank_hash, "native Atlas grid still draws on empty D1")
	canvas.render_grid = false
	canvas.queue_redraw()
	await _frames(8)
	_check(_hash() == blank_hash, "removing grid preserves blank D1 appearance")
	canvas.set_presented_detail_level(0)
	await _frames(8)
	_check(_hash() == paint_hash, "return to D0 reproduces committed renderer output")
	_check(history.undo(), "native frame history undo succeeds")
	comp.invalidate()
	canvas._refresh_composition_view()
	await _frames(8)
	_check(_hash() == baseline, "history undo removes the GPU-composited pixels")
	_check(history.redo(), "native history redo succeeds")
	comp.invalidate()
	canvas._refresh_composition_view()
	await _frames(8)
	_check(_hash() == paint_hash, "history redo invalidates GPU frame and restores paint")
	var path: String = OS.get_cache_dir().path_join("drawinatlas-t055-canonical.png")
	_check(root.get_texture().get_image().save_png(path) == OK, "native screenshot written")
	print("T055_NATIVE_SCREENSHOT ", path)
	root.remove_child(canvas)
	canvas.free()
	print("T055_NATIVE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
