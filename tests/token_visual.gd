extends SceneTree
## T-041: native CanvasGroup token placement, drag preview and committed pixels.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TOKEN VISUAL FAILED: " + label)


func _frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func _mouse(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	canvas._gui_input(event)


func _pixel(canvas: AtlasCanvas, board: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(board))
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		return Color.TRANSPARENT
	return image.get_pixelv(point)


func _red(pixel: Color) -> bool:
	return pixel.r > 0.7 and pixel.g < 0.35 and pixel.b < 0.35


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "native framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(10)
	editor.create_board("Token screenshot", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	editor._choose_tool(AtlasCanvas.Tool.TOKEN)
	var canvas: AtlasCanvas = editor.canvas
	canvas.snap_to_grid = false
	canvas.brush_color = Color.RED
	canvas.token_label = "Ranger"
	canvas.token_radius = 19.0
	var start: Vector2 = canvas.camera_center + Vector2(-65, -28)
	var end: Vector2 = start + Vector2(93, 48)
	var start_local: Vector2 = canvas.document_to_local(start)
	var end_local: Vector2 = canvas.document_to_local(end)
	_check(canvas.size.x >= 240 and canvas.size.y >= 400, "rendering canvas is visible")
	_mouse(canvas, start_local, true)
	_mouse(canvas, start_local, false)
	await _frames()
	_check(_red(_pixel(canvas, start)), "new token is visibly rendered on native board")
	var layer: AtlasTokenLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	_check(layer != null and layer.tokens.size() == 1, "native placement creates one semantic token")
	_mouse(canvas, start_local, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = end_local
	motion.relative = end_local - start_local
	canvas._gui_input(motion)
	await _frames()
	_check(layer.tokens[0].position == start and _red(_pixel(canvas, end)),
		"moving preview visibly follows cursor but does not edit stored position")
	_mouse(canvas, end_local, false)
	await _frames()
	layer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	_check(layer.tokens[0].position == end and _red(_pixel(canvas, end)),
		"release commits same visible position")
	_check(not _red(_pixel(canvas, start)), "old position has no residual painted token")
	# A real pointer preview must disappear from the framebuffer when another
	# edit cell becomes selected before release. The original token stays put.
	editor.apply_grid(AtlasGrid.new(AtlasGrid.Kind.SQUARE, 1000.0))
	canvas.camera_center = Vector2(450, 450)
	var guarded_start: Vector2 = canvas.local_to_document(Vector2(115, 140))
	var guarded_end: Vector2 = guarded_start + Vector2(75, 0)
	var guarded_start_local: Vector2 = canvas.document_to_local(guarded_start)
	var guarded_end_local: Vector2 = canvas.document_to_local(guarded_end)
	canvas.token_label = "Native guard"
	canvas.token_radius = 16.0
	editor._on_select(Vector2i.ZERO)
	editor._on_scope_toggled(true)
	_mouse(canvas, guarded_start_local, true)
	_mouse(canvas, guarded_start_local, false)
	await _frames()
	layer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	var guard_id: String = layer.tokens[-1].id
	var history_before: int = editor.edits._cursor
	_mouse(canvas, guarded_start_local, true)
	var drag: InputEventMouseMotion = InputEventMouseMotion.new()
	drag.position = guarded_end_local
	drag.relative = guarded_end_local - guarded_start_local
	canvas._gui_input(drag)
	await _frames()
	_check(_red(_pixel(canvas, guarded_end)) and layer.token_by_id(guard_id).position == guarded_start,
		"pending token drag visibly previews its target without moving the source")
	editor._on_select(Vector2i(1, 0))
	canvas._gui_input(drag)
	await _frames()
	_check(canvas._token_drag_preview == null and not _red(_pixel(canvas, guarded_end)),
		"invalidated token preview disappears from native framebuffer")
	_mouse(canvas, guarded_end_local, false)
	await _frames()
	_check(layer.token_by_id(guard_id).position == guarded_start and _red(_pixel(canvas, guarded_start))
		and editor.edits._cursor == history_before,
		"stale pointer release leaves token pixels and history unchanged")
	editor._on_scope_toggled(false)
	var path: String = "user://validation/token-gm-native.png"
	DirAccess.make_dir_recursive_absolute("user://validation")
	_check(root.get_texture().get_image().save_png(path) == OK, "native proof screenshot saved")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_TOKEN_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
