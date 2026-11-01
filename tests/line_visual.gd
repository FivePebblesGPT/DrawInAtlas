extends SceneTree
## T-024 native pointer and framebuffer verification for the Line tool.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LINE VISUAL FAILED: " + reason)


func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


func _button(point: Vector2, down: bool, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point
	event.global_position = point
	event.shift_pressed = shift
	event.alt_pressed = alt
	root.push_input(event, true)


func _motion(point: Vector2, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	event.global_position = point
	event.shift_pressed = shift
	event.alt_pressed = alt
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
	_check(editor.create_board("Line native", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 28.0)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	await _frames(7)
	var canvas: AtlasCanvas = editor.canvas
	_check(editor.inspector._line_hint.is_visible_in_tree(), "Line modifier guidance visible")
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.LINE).button_pressed, "Line tool selected in palette")
	var anchor: Vector2 = canvas.camera_center - Vector2(25, 7)
	var pointer: Vector2 = anchor + Vector2(72, 33)
	canvas.camera_center = (anchor + pointer) * 0.5
	canvas.camera_zoom = 1.25
	canvas.brush_width = 9.0
	canvas.brush_color = Color(0.1, 0.8, 0.8, 0.75)
	var start_ui: Vector2 = canvas.global_position + canvas.document_to_local(anchor)
	var end_ui: Vector2 = canvas.global_position + canvas.document_to_local(pointer)
	_button(start_ui, true)
	_motion(end_ui, true, true)
	await _frames(5)
	var expected: PackedVector2Array = AtlasShapes.line_endpoints(anchor, pointer, true, true)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == expected,
		"native Shift+Alt drag produces angle-constrained centered preview")
	var draft_image: Image = root.get_texture().get_image()
	_check(draft_image.get_width() >= 960 and draft_image.get_height() >= 660, "native framebuffer available")
	_button(end_ui, false, true, true)
	await _frames(6)
	var reference: AtlasFillResult = AtlasRasterBrush.paint(AtlasRasterLayer.paint_layer(), expected, canvas.brush_color, canvas.brush_width, false)
	_check(reference.ok and reference.layer.to_dict() == canvas.floor.raster_layer().to_dict(),
		"native release commits exact preview geometry")
	var committed_image: Image = root.get_texture().get_image()
	var differences: int = 0
	var origin: Vector2i = Vector2i(canvas.global_position)
	for y: int in range(24, int(canvas.size.y) - 24, 3):
		for x: int in range(14, int(canvas.size.x) - 14, 3):
			if draft_image.get_pixel(origin.x + x, origin.y + y) != committed_image.get_pixel(origin.x + x, origin.y + y):
				differences += 1
	_check(differences < 90, "draft framebuffer closely matches committed line")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(committed_image.save_png("user://validation/line-960.png") == OK, "native 960 screenshot")
	_button(start_ui, true)
	_motion(end_ui, true)
	await _frames(2)
	_check(canvas._draft_stroke != null, "second native preview starts")
	canvas.cancel_edit()
	_button(end_ui, false, true)
	_check(reference.layer.to_dict() == canvas.floor.raster_layer().to_dict(), "Escape cancellation does not paint a second stroke")
	# Native-framebuffer contract: inspector styling repaints an in-progress
	# Line without another pointer move, and the released raster matches it.
	_button(start_ui, true)
	_motion(end_ui, true, true)
	await _frames(5)
	var before_restyle_image: Image = root.get_texture().get_image()
	var changed_color: Color = Color(1.0, 0.3, 0.2, 0.95)
	var changed_width: float = 18.0
	editor.inspector.brush_width_spinner.value = changed_width
	editor.inspector.brush_color_picker.color = changed_color
	editor.inspector.brush_color_changed.emit(changed_color)
	await _frames(5)
	var expected_restyle: AtlasFillResult = AtlasRasterBrush.paint(canvas.floor.raster_layer(), expected,
		changed_color, changed_width, false)
	_check(canvas.brush_width == changed_width and canvas.brush_color == changed_color,
		"native inspector forwards restyled Line width and color")
	_check(expected_restyle.ok and canvas._preview_layer != null
		and canvas._preview_layer.to_dict() == expected_restyle.layer.to_dict(),
		"native stationary preview updates its detached raster pixels")
	var restyled_image: Image = root.get_texture().get_image()
	var restyled_pixels: int = 0
	for y: int in range(24, int(canvas.size.y) - 24, 3):
		for x: int in range(14, int(canvas.size.x) - 14, 3):
			if before_restyle_image.get_pixel(origin.x + x, origin.y + y) != restyled_image.get_pixel(origin.x + x, origin.y + y):
				restyled_pixels += 1
	_check(restyled_pixels > 15, "native Line framebuffer changes before release without pointer movement")
	_button(end_ui, false, true, true)
	await _frames(5)
	_check(expected_restyle.ok and canvas.floor.raster_layer().to_dict() == expected_restyle.layer.to_dict(),
		"native release matches restyled preview")
	_check(editor.edits.undo() and canvas.floor.raster_layer().to_dict() == reference.layer.to_dict(),
		"restyled native Line is one undoable raster edit")

	# Native pointer events must not paint a Line whose allowed cell changes
	# after the preview was rendered, even when the pointer is still held.
	canvas.brush_width = 6.0
	var cell: Vector2i = canvas.map.grid.document_to_cell(canvas.camera_center)
	editor._on_select(cell)
	editor._on_scope_toggled(true)
	var center: Vector2 = canvas.map.grid.cell_to_document(cell)
	var cell_start_ui: Vector2 = canvas.global_position + canvas.document_to_local(center - Vector2(4, 0))
	var cell_end_ui: Vector2 = canvas.global_position + canvas.document_to_local(center + Vector2(4, 0))
	var layer_before: Dictionary = canvas.floor.raster_layer().to_dict()
	var history_before: int = editor.edits._cursor
	_button(cell_start_ui, true)
	_motion(cell_end_ui)
	await _frames(5)
	_check(canvas._preview_layer != null and canvas._preview_layer.to_dict() != layer_before,
		"native selected-cell Line preview paints eligible pixels")
	editor._on_select(cell + Vector2i(3, 0))
	_button(cell_end_ui, false)
	await _frames(4)
	_check(canvas.floor.raster_layer().to_dict() == layer_before
		and editor.edits._cursor == history_before,
		"native release rejects a Line preview after its edit cell changes")
	_check(canvas._preview_layer == null and not canvas.is_editing()
		and "edit mask changed" in editor.status_label.text,
		"rejected native Line clears the draft and explains the conflict")
	editor._on_scope_toggled(false)

	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(editor.inspector._line_hint.is_visible_in_tree() and canvas.size.x >= 230.0,
		"Line guidance and canvas remain usable at 800x600")
	_check(root.get_texture().get_image().save_png("user://validation/line-800.png") == OK, "native 800 screenshot")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_LINE_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
