extends SceneTree
## T-016 native pointer/visual acceptance for the opt-in grid snapping control.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SNAPPING VISUAL FAILED: " + label)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _button(global_point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = global_point
	event.global_position = global_point
	root.push_input(event, true)


func _move(global_point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = global_point
	event.global_position = global_point
	root.push_input(event, true)


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
	_check(editor.create_board("Native snap", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 28.0)), "create square board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	await _frames(8)
	var canvas: AtlasCanvas = editor.canvas
	var toggle: CheckBox = editor.inspector.snap_checkbox
	_check(toggle.is_visible_in_tree() and toggle.size.x > 90, "snapping visible and readable in inspector")
	_check(not toggle.button_pressed, "free placement is the initial mode")
	var center: Vector2 = toggle.global_position + toggle.size * 0.5
	_button(center, true)
	_button(center, false)
	await _frames(3)
	_check(toggle.button_pressed and canvas.snap_to_grid, "native mouse enables snapping")
	var start: Vector2 = canvas.camera_center - Vector2(22, 16)
	var finish: Vector2 = canvas.camera_center + Vector2(41, 27)
	var snapped_start: Vector2 = AtlasGridSnap.point(canvas.map.grid, start)
	var snapped_finish: Vector2 = AtlasGridSnap.point(canvas.map.grid, finish)
	_button(canvas.global_position + canvas.document_to_local(start), true)
	_move(canvas.global_position + canvas.document_to_local(finish))
	await _frames(5)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == PackedVector2Array([snapped_start, snapped_finish]),
		"native drag shows snapped line endpoints")
	var image_draft: Image = root.get_texture().get_image()
	_button(canvas.global_position + canvas.document_to_local(finish), false)
	await _frames(6)
	var layer: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(layer.strokes.size() == 1 and layer.strokes[0].points == PackedVector2Array([snapped_start, snapped_finish]),
		"native release commits identical line")
	var image_final: Image = root.get_texture().get_image()
	var differences: int = 0
	var origin: Vector2i = Vector2i(canvas.global_position)
	for y: int in range(30, int(canvas.size.y) - 30, 3):
		for x: int in range(15, int(canvas.size.x) - 15, 3):
			if image_draft.get_pixel(origin.x + x, origin.y + y) != image_final.get_pixel(origin.x + x, origin.y + y):
				differences += 1
	_check(differences < 70, "draft framebuffer closely matches committed stroke")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(image_final.save_png("user://validation/snapping-960.png") == OK, "native screenshot 960")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(toggle.is_visible_in_tree() and editor.canvas.size.x >= 234.0, "compact 800x600 layout retains canvas and snap toggle")
	_check(root.get_texture().get_image().save_png("user://validation/snapping-800.png") == OK, "native screenshot 800")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_SNAPPING_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
