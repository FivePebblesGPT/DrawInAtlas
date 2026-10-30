extends SceneTree
## T-019: native mouse modifiers and visible whole-object selection feedback.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("SELECTION VISUAL FAILED: " + description)


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame


func _click(canvas: AtlasCanvas, local: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		event.alt_pressed = alt
		event.position = canvas.global_position + local
		event.global_position = event.position
		root.push_input(event, true)
		await _frames(2)


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
	editor.create_board("Native selection", AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0))
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	var original_id: String = canvas.active_layer_id
	for local: Vector2 in [Vector2(68, 105), Vector2(200, 105)]:
		var start: Vector2 = canvas.local_to_document(local)
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([start, start + Vector2(24, 0)]), Color.WHITE, 3), false)
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	await _frames(7)
	var image_before: Image = root.get_texture().get_image()
	await _click(canvas, Vector2(80, 105))
	_check(canvas.selection.stroke_indices == [0], "native click selects first active-layer stroke")
	await _frames(4)
	var image_after: Image = root.get_texture().get_image()
	var changes: int = 0
	var origin: Vector2i = Vector2i(canvas.global_position)
	for y: int in range(94, 115):
		for x: int in range(58, 101):
			if image_after.get_pixel(origin.x + x, origin.y + y) != image_before.get_pixel(origin.x + x, origin.y + y):
				changes += 1
	_check(changes > 10, "native framebuffer paints visible selection outline")
	await _click(canvas, Vector2(212, 105), true)
	_check(canvas.selection.stroke_indices == [0, 1], "Ctrl+pointer adds second stroke")
	await _click(canvas, Vector2(80, 105), false, true)
	_check(canvas.selection.stroke_indices == [1], "Alt+pointer subtracts first stroke")
	_check(canvas.active_layer_id == original_id and canvas.map.grid.kind == AtlasGrid.Kind.HEX_POINTY,
		"pointer modifiers do not switch layer or mutate board grid")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(root.get_texture().get_image().save_png("user://validation/selection-interactions-960.png") == OK,
		"capture native selection state")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(canvas.selection.stroke_indices == [1], "compact viewport resize preserves board-coordinate selection")
	_check(root.get_texture().get_image().save_png("user://validation/selection-interactions-800.png") == OK,
		"capture compact selection state")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_SELECTION_INTERACTIONS_VISUAL_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(1 if _failures > 0 else 0)
