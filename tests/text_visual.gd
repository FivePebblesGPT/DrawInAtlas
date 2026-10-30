extends SceneTree
## T-027: native text editing and screen-space visibility at compact windows.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEXT VISUAL FAILED: " + reason)

func _frames(n: int = 4) -> void:
	for frame: int in range(n):
		await process_frame

func _click(canvas: AtlasCanvas, world: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = canvas.global_position + canvas.document_to_local(world)
	event.global_position = event.position
	root.push_input(event, true)

func _sample_ink(canvas: AtlasCanvas, frame: Image) -> int:
	var pixels: int = 0
	var center: Vector2i = Vector2i(canvas.global_position + canvas.size * 0.5)
	for y: int in range(center.y - 35, center.y + 35):
		for x: int in range(center.x - 110, center.x + 110):
			if x < 0 or y < 0 or x >= frame.get_width() or y >= frame.get_height():
				continue
			var color: Color = frame.get_pixel(x, y)
			if color.r > 0.7 and color.g > 0.7 and color.b > 0.7:
				pixels += 1
	return pixels

func _run() -> void:
	if DisplayServer.get_name() == "headless":
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
	_check(editor.create_board("Text native", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)), "new board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	editor.sidebar.select_view(&"Tools")
	await _frames()
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.TEXT).button_pressed and
		editor.tool_palette.button_for(AtlasCanvas.Tool.TEXT).icon != null, "text palette and icon")
	var anchor: Vector2 = canvas.camera_center - Vector2(88, 12)
	_click(canvas, anchor, true)
	_click(canvas, anchor, false)
	await _frames()
	_check(editor.text_editor.visible and editor.text_editor.text_input.has_focus(), "native pointer opens text editor")
	editor.text_editor.text_input.text = "Greyhaven East Gate"
	editor.text_editor.size_input.value = 20
	editor.text_editor.color_picker.color = Color(1, 1, 1, 1)
	await _frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(root.get_texture().get_image().save_png("user://validation/text-editor-960.png") == OK, "editor modal screenshot")
	editor.text_editor.confirm_text()
	await _frames(5)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.strokes.size() == 1 and ink.strokes[0].is_text(), "native placement and editable metadata")
	canvas.camera_center = anchor + Vector2(80, 6)
	canvas.camera_zoom = 0.4
	canvas.queue_redraw()
	await _frames(7)
	var hidden: int = _sample_ink(canvas, root.get_texture().get_image())
	canvas.camera_zoom = 0.5
	canvas.queue_redraw()
	await _frames(7)
	var shown: int = _sample_ink(canvas, root.get_texture().get_image())
	_check(shown > hidden + 20, "text appears at 10 px but is culled at 8 px; content unchanged")
	_check(ink.strokes[0].text == "Greyhaven East Gate" and ink.strokes[0].width == 20,
		"screen culling never modifies text")
	canvas.camera_zoom = 1.5
	canvas.queue_redraw()
	await _frames(5)
	_check(root.get_texture().get_image().save_png("user://validation/text-native-960.png") == OK, "readable text screenshot")
	# Independently authored detail uses the same font-space readability rule.
	editor.layer_panel.view_detail_spinner.value = 1
	editor.layer_panel._add_ink()
	var local_layer: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(local_layer != null and local_layer.detail_level == 1, "D1 text layer")
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	canvas._begin_text_edit(anchor)
	editor.text_editor.text_input.text = "D1 · Street details"
	editor.text_editor.size_input.value = 14
	editor.text_editor.color_picker.color = Color(0.15, 0.95, 0.95)
	editor.text_editor.confirm_text()
	canvas.queue_redraw()
	await _frames(5)
	_check(local_layer.strokes.size() == 1 and AtlasTextLayout.readable(local_layer.strokes[0], canvas.camera_zoom),
		"authored D1 text is readable at high zoom")
	_check(root.get_texture().get_image().save_png("user://validation/text-native-d1.png") == OK,
		"D1 text screenshot")
	editor.layer_panel.view_detail_spinner.value = 0
	_check(local_layer.strokes.size() == 1 and local_layer.strokes[0].is_text() and
		canvas.presented_detail_level == 0, "hidden D1 does not discard text")
	editor.select_layer(local_layer.id)
	_check(canvas.presented_detail_level == 1 and canvas.editing_target_is_presented(),
		"return to D1 keeps text editable")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(9)
	_check(canvas.size.x >= 200, "compact window retains drawing space")
	_check(root.get_texture().get_image().save_png("user://validation/text-native-800.png") == OK, "compact screenshot")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_TEXT_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures else 0)
