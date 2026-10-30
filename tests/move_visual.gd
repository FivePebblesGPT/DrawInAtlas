extends SceneTree
## T-022: native Move shortcut/pointer interaction and live visual feedback.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MOVE VISUAL FAILED: " + description)


func _frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func _button(canvas: AtlasCanvas, local: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.global_position + local
	event.global_position = event.position
	event.pressed = pressed
	root.push_input(event, true)
	await _frames()


func _move(canvas: AtlasCanvas, local: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + local
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
	editor.create_board("Native move", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	var start: Vector2 = canvas.local_to_document(Vector2(100, 110))
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([start, start + Vector2(35, 0)]), Color.WHITE, 7), false)
	var ink_id: String = canvas.active_layer_id
	var before: Dictionary = (canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).to_dict().duplicate(true)
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.keycode = KEY_M
	shortcut.pressed = true
	editor._unhandled_key_input(shortcut)
	await _frames(5)
	_check(canvas.tool == AtlasCanvas.Tool.MOVE and editor.tool_palette.button_for(AtlasCanvas.Tool.MOVE).button_pressed,
		"M activates dedicated move tool and palette")
	_check(editor.inspector.selection_label.visible, "selection feedback remains visible")
	await _button(canvas, Vector2(112, 110), true)
	await _move(canvas, Vector2(153, 131))
	_check(canvas._preview_layer != null and canvas.selection.stroke_indices == [0],
		"native pointer picks artwork and displays drag preview")
	var draft: Image = root.get_texture().get_image()
	await _button(canvas, Vector2(153, 131), false)
	await _frames(6)
	var moved: AtlasInkLayer = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(moved.strokes[0].points[0].distance_to(start + Vector2(41, 21)) < 0.01,
		"release commits same pointer movement")
	_check(editor.edits.undo() and (canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).to_dict() == before,
		"native move undo restores exact original")
	_check(editor.edits.redo(), "native move redo")
	editor.sidebar.select_view(&"Tools")
	await _frames(3)
	var after: Image = root.get_texture().get_image()
	var origin: Vector2i = Vector2i(canvas.global_position)
	var draft_color: Color = draft.get_pixelv(origin + Vector2i(153, 131))
	var final_color: Color = after.get_pixelv(origin + Vector2i(153, 131))
	_check(draft_color != Color.TRANSPARENT and final_color != Color.TRANSPARENT,
		"drag preview and committed ink appear in framebuffer")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(after.save_png("user://validation/move-960.png") == OK, "capture native move 960")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(7)
	_check(canvas.size.x >= 234 and editor.tool_palette.button_for(AtlasCanvas.Tool.MOVE).icon != null,
		"compact editor retains canvas width and Move icon")
	_check(root.get_texture().get_image().save_png("user://validation/move-800.png") == OK,
		"capture native move 800")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_MOVE_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
