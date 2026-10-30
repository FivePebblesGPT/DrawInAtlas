extends SceneTree
## T-021: actual native pointer events, feedback and one-gesture undo/redo.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ERASER VISUAL FAILED: " + label)


func _frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func _move(canvas: AtlasCanvas, point: Vector2, dragging: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	root.push_input(event, true)
	await _frames()


func _button(canvas: AtlasCanvas, point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.pressed = pressed
	root.push_input(event, true)
	await _frames()


func _sample(image: Image, canvas: AtlasCanvas, point: Vector2) -> Color:
	return image.get_pixelv(Vector2i(canvas.global_position + point))


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
	await _frames(12)
	_check(editor.create_board("Eraser native", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64)),
		"isolated board created")
	var canvas: AtlasCanvas = editor.canvas
	canvas.show_grid = false
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	editor.inspector.brush_width_spinner.value = 40.0
	editor._choose_tool(AtlasCanvas.Tool.ERASER)
	await _frames(5)
	_check(editor.inspector._eraser_hint.visible and editor.inspector.brush_width_spinner.value == 40.0,
		"eraser description and brush diameter are visible")
	var center: Vector2 = canvas.size * Vector2(0.5, 0.48)
	await _move(canvas, center)
	_check(canvas._brush_cursor_inside and canvas.tool == AtlasCanvas.Tool.ERASER,
		"eraser pointer motion produces live cursor")
	await RenderingServer.frame_post_draw
	var frame1: Image = root.get_texture().get_image()
	var ring: Color = _sample(frame1, canvas, center + Vector2(20, 0))
	var background: Color = _sample(frame1, canvas, center + Vector2(30, 0))
	_check(ring.r > background.r + 0.18,
		"eraser cursor ring matches 40-board-unit diameter")
	canvas.camera_zoom = 2.0
	canvas.queue_redraw()
	await _frames(5)
	await RenderingServer.frame_post_draw
	var frame2: Image = root.get_texture().get_image()
	var zoomed: Color = _sample(frame2, canvas, center + Vector2(40, 0))
	var off_ring: Color = _sample(frame2, canvas, center + Vector2(25, 0))
	_check(zoomed.r > off_ring.r + 0.18, "eraser diameter scales with zoom")
	canvas.camera_zoom = 1.0
	# Seed distinct geometry via normal history; pointer erasure must not replace the background.
	var left: Vector2 = Vector2(80, canvas.size.y * 0.65)
	var right: Vector2 = Vector2(canvas.size.x - 80, left.y)
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([
		canvas.local_to_document(left), canvas.local_to_document(right)]),
		Color(1, 1, 1, 0.55), 16.0), false)
	_check(canvas.floor.strokes.size() == 1, "seeded a translucent vector stroke")
	var hit: Vector2 = (left + right) * 0.5
	await _button(canvas, hit + Vector2(0, -45), true)
	await _move(canvas, hit + Vector2(0, 45), true)
	await _button(canvas, hit + Vector2(0, 45), false)
	_check(canvas.floor.strokes.size() == 2, "real mouse drag splits the vector stroke")
	await _move(canvas, center)
	await RenderingServer.frame_post_draw
	var erased: Image = root.get_texture().get_image()
	var gap: Color = _sample(erased, canvas, hit)
	var intact: Color = _sample(erased, canvas, hit + Vector2(-100, 0))
	_check(intact.r > gap.r + 0.14, "real removed gap has no painted background mask")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(erased.save_png("user://validation/eraser-native.png") == OK,
		"saved native eraser witness")
	editor._on_undo()
	_check(canvas.floor.strokes.size() == 1, "one undo restores unsplit ink")
	editor._on_redo()
	_check(canvas.floor.strokes.size() == 2, "redo restores complete pointer erase")
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	_check(not editor.inspector._eraser_hint.visible and editor.inspector.brush_color_picker.visible,
		"switching to Brush restores RGBA controls")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	editor._choose_tool(AtlasCanvas.Tool.ERASER)
	await _frames(8)
	_check(canvas.size.x >= 190.0 and editor.inspector._eraser_hint.visible,
		"compact 800x600 layout keeps canvas usable and eraser guidance visible")
	_check(editor.inspector._eraser_hint.get_global_rect().end.x <= root.size.x,
		"eraser guidance does not overflow compact inspector width")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_ERASER_VISUAL_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
