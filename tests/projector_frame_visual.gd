extends SceneTree
## T-013: real native pointer drag and framebuffer witness for GM framing.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PROJECTOR FRAME VISUAL FAILED: " + message)


func _frames(count: int = 3) -> void:
	for step: int in range(count):
		await process_frame


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.pressed = pressed
	root.push_input(event, true)
	await _frames()


func _move(canvas: AtlasCanvas, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
	await _frames()


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
	editor.create_board("Native frame", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	var canvas: AtlasCanvas = editor.canvas
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	var before: Dictionary = editor.campaign.to_dict().duplicate(true)
	var history_entry: AtlasEditCommand = editor.edits.get_undo_command()
	# Use real UI button, rather than setting Canvas state directly.
	# A toggle's action is a real left mouse press/release on its button.
	var ui: Button = editor.projector_frame_button
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = ui.global_position + ui.size * 0.5
	click.global_position = click.position
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await _frames(4)
	_check(canvas.projector_frame_active, "real toolbar input activates frame")
	var rect: Rect2 = canvas.projector_frame.bounds()
	var center: Vector2 = canvas.document_to_local(rect.get_center())
	await _button(canvas, center, true)
	await _move(canvas, center + Vector2(32, 19))
	_check(canvas._frame_drag == AtlasCanvas.FrameDrag.MOVE, "real pointer moves frame draft")
	await _button(canvas, center + Vector2(32, 19), false)
	_check(canvas.projector_frame.center.is_equal_approx(Vector2(32, 19)), "release commits pan in document units")
	var moved: Rect2 = canvas.projector_frame.bounds()
	var handle: Vector2 = canvas.document_to_local(moved.end)
	await _button(canvas, handle, true)
	await _move(canvas, handle + Vector2(20, 12))
	_check(canvas._frame_drag == AtlasCanvas.FrameDrag.RESIZE, "yellow handle begins real resize")
	await _button(canvas, handle + Vector2(20, 12), false)
	_check(canvas.projector_frame.width > moved.size.x and \
		is_equal_approx(canvas.projector_frame.bounds().size.y * canvas.projector_frame.aspect_ratio(), canvas.projector_frame.width),
		"native resize zooms out while preserving aspect")
	_check(canvas.projector_frame.bounds().position.is_equal_approx(moved.position),
		"resize leaves opposite board corner fixed")
	_check(canvas.camera_center == Vector2.ZERO and is_equal_approx(canvas.camera_zoom, 1.0),
		"frame changes never pan or zoom the GM camera")
	var committed_center: Vector2 = canvas.projector_frame.center
	var draft_center: Vector2 = canvas.document_to_local(canvas.projector_frame.center)
	await _button(canvas, draft_center, true)
	await _move(canvas, draft_center + Vector2(18, 9))
	var cancel: InputEventKey = InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	await _frames(3)
	_check(canvas._frame_drag == AtlasCanvas.FrameDrag.NONE \
		and canvas.projector_frame.center.is_equal_approx(committed_center),
		"real Escape cancels a pending frame move and restores prior position")
	# Clicking outside the frame while in frame mode cannot use the Brush tool.
	await _button(canvas, Vector2(12, 12), true)
	await _button(canvas, Vector2(12, 12), false)
	_check(editor.campaign.to_dict() == before, "outside click cannot draw on canonical layers")
	_check(editor.campaign.to_dict() == before and editor.edits.get_undo_command() == history_entry,
		"real frame manipulation never edits artwork or history")
	await _frames(3)
	var image: Image = root.get_texture().get_image()
	var border: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(canvas.projector_frame.bounds().position))
	var pixel: Color = image.get_pixelv(border + Vector2i(30, 0))
	_check(pixel.b > pixel.r, "frame border visibly renders cyan in native framebuffer")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(image.save_png("user://validation/projector-frame-960.png") == OK, "native 960 screenshot saved")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(canvas.size.x >= 234 and ui.visible, "compact layout retains canvas and frame control")
	_check(root.get_texture().get_image().save_png("user://validation/projector-frame-800.png") == OK,
		"native compact screenshot saved")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_PROJECTOR_FRAME_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
