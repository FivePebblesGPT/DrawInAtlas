extends SceneTree
## T-010: native pointer and framebuffer witness for round, uniform-opacity pen turns.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PEN TURNS VISUAL FAILED: " + label)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await _frames(2)


func _motion(canvas: AtlasCanvas, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await _frames(2)


func _trace(canvas: AtlasCanvas, points: PackedVector2Array) -> void:
	await _button(canvas, points[0], true)
	for index: int in range(1, points.size()):
		await _motion(canvas, points[index])
	await _button(canvas, points[-1], false)
	await _frames(2)


func _sample(image: Image, canvas: AtlasCanvas, local: Vector2) -> Color:
	return image.get_pixelv(Vector2i(canvas.global_position + local))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 800)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	await _frames(10)
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	grid.distance_unit = "tiles"
	_check(editor.create_board("Turns witness", grid), "new empty board")
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.brush_color = Color(1, 1, 1, 0.45)
	canvas.brush_width = 24.0
	canvas.camera_zoom = 1.0
	canvas.camera_center = Vector2.ZERO
	editor.artwork.choose_tool(AtlasCanvas.Tool.PEN)
	await _frames(6)
	print("canvas size: ", canvas.size)
	var slow: PackedVector2Array = PackedVector2Array([
		Vector2(80, 160), Vector2(105, 160), Vector2(130, 160), Vector2(155, 160),
		Vector2(180, 160), Vector2(205, 160), Vector2(230, 160), Vector2(255, 160),
		Vector2(260, 155), Vector2(260, 130), Vector2(260, 105), Vector2(260, 80)
	])
	var quick: PackedVector2Array = PackedVector2Array([
		Vector2(80, 370), Vector2(260, 370), Vector2(260, 285)])
	var hairpin: PackedVector2Array = PackedVector2Array([
		Vector2(80, 520), Vector2(245, 520), Vector2(245, 550), Vector2(80, 550)])
	await _trace(canvas, slow)
	await _trace(canvas, quick)
	await _trace(canvas, hairpin)
	await _trace(canvas, PackedVector2Array([Vector2(420, 500)]))
	_check(canvas.floor.strokes.size() == 4, "slow, fast, tight U-turn and tap gestures committed")
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var s_straight: Color = _sample(image, canvas, Vector2(140, 160))
	var s_turn: Color = _sample(image, canvas, Vector2(260, 160))
	var q_straight: Color = _sample(image, canvas, Vector2(150, 370))
	var q_turn: Color = _sample(image, canvas, Vector2(260, 370))
	var hairpin_straight: Color = _sample(image, canvas, Vector2(150, 520))
	var hairpin_turn: Color = _sample(image, canvas, Vector2(245, 520))
	var dot: Color = _sample(image, canvas, Vector2(420, 500))
	print("slow straight/turn: ", s_straight, " / ", s_turn, " quick: ", q_straight, " / ", q_turn)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(image.save_png("user://validation/pen-turns-native.png") == OK, "screenshot")
	_check(absf(s_straight.r - s_turn.r) < 0.07, "slow turn matches stroke opacity")
	_check(absf(q_straight.r - q_turn.r) < 0.07, "fast turn matches stroke opacity")
	_check(absf(s_straight.r - q_straight.r) < 0.07,
		"sample density does not increase translucent pen opacity")
	_check(absf(hairpin_straight.r - hairpin_turn.r) < 0.07,
		"tight U-turn has no dark or sharp corner")
	_check(absf(dot.r - s_straight.r) < 0.07, "single pointer tap has correct opacity")
	var saved_path: PackedVector2Array = canvas.floor.strokes[0].points.duplicate()
	var saved_color: Color = canvas.floor.strokes[0].color
	editor._on_undo()
	_check(canvas.floor.strokes.size() == 3, "single tap undo is one transaction")
	editor._on_undo()
	_check(canvas.floor.strokes.size() == 2, "tight U-turn undo is one transaction")
	editor._on_redo()
	editor._on_redo()
	_check(canvas.floor.strokes.size() == 4 and canvas.floor.strokes[0].points == saved_path
		and canvas.floor.strokes[0].color == saved_color,
		"redo restores exact sampled path and transparency")
	# A closed shape must keep its hollow center; offset outlines may contain holes.
	var rect: PackedVector2Array = PackedVector2Array([
		Vector2(375, 240), Vector2(470, 240), Vector2(470, 330),
		Vector2(375, 330), Vector2(375, 240)])
	editor._on_stroke(AtlasStroke.new(rect, Color.WHITE, 14.0), false)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var closed_image: Image = root.get_texture().get_image()
	_check(_sample(closed_image, canvas, Vector2(420, 285)).is_equal_approx(AtlasCanvas.EMPTY_COLOR),
		"closed outlines retain their hollow center")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PEN_TURNS_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
