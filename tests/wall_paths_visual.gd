extends SceneTree
## T-026: native visible wall path, editable handles, palette, small-window fit.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WALL PATH VISUAL FAILED: " + reason)

func _frames(count: int = 4) -> void:
	for index: int in range(count):
		await process_frame

func _click(canvas: AtlasCanvas, point: Vector2, down: bool, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.shift_pressed = shift
	event.position = canvas.global_position + canvas.document_to_local(point)
	event.global_position = event.position
	root.push_input(event, true)
	await _frames(2)

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
	await _frames(14)
	_check(editor.create_board("Wall path native", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 1.0
	editor._choose_tool(AtlasCanvas.Tool.WALL_PATH)
	editor.sidebar.select_view(&"Tools")
	await _frames()
	_check(editor.tool_palette.button_for(AtlasCanvas.Tool.WALL_PATH).button_pressed and editor.tool_palette.button_for(AtlasCanvas.Tool.WALL_PATH).icon != null,
		"palette button active and icon loaded")
	var a: Vector2 = canvas.local_to_document(Vector2(80, 150))
	var b: Vector2 = canvas.local_to_document(Vector2(170, 150))
	var c: Vector2 = canvas.local_to_document(Vector2(170, 230))
	for point: Vector2 in [a, b, c]:
		await _click(canvas, point, true)
		await _click(canvas, point, false)
	_check(canvas._wall_vertices.size() == 3, "real mouse clicks create three control points")
	var before: Image = root.get_texture().get_image()
	var sample: Vector2i = Vector2i(canvas.global_position) + Vector2i(120, 150)
	_check(before.get_pixelv(sample).a > 0.5, "draft visible in native framebuffer")
	# The saved wall and the confirmed draft edges must use the same renderer.
	# This is a fixed pointer: the style setters alone must invalidate the cache.
	canvas.brush_color = Color(0.12, 0.85, 0.2, 1.0)
	canvas.brush_width = 14.0
	await _frames(5)
	var styled: Color = root.get_texture().get_image().get_pixelv(sample)
	var original: Color = before.get_pixelv(sample)
	_check(styled.g > styled.r and absf(styled.g - original.g) > 0.1,
		"stationary draft visibly updates to green instead of old gold")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	editor._unhandled_key_input(key)
	await _frames(5)
	var ink: AtlasObjectsLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	_check(ink.strokes.size() == 1 and ink.strokes[0].editable_path, "Enter finalizes one editable wall")
	var after: Image = root.get_texture().get_image()
	_check(after.get_pixelv(sample).a > 0.5, "committed wall visible in framebuffer")
	var saved_color: Color = after.get_pixelv(sample)
	_check(absf(saved_color.r - styled.r) + absf(saved_color.g - styled.g)
		+ absf(saved_color.b - styled.b) < 0.05, "draft and committed wall match at a filled stroke pixel")
	await _click(canvas, b, true)
	_check(canvas._wall_drag_vertex == 1, "native hit finds wall vertex")
	var moved: InputEventMouseMotion = InputEventMouseMotion.new()
	moved.position = canvas.global_position + canvas.document_to_local(b + Vector2(20, 20))
	moved.global_position = moved.position
	moved.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(moved, true)
	await _frames(3)
	_check(canvas._wall_preview != null and canvas._wall_preview.points[1].distance_to(b + Vector2(20, 20)) < 0.01,
		"node preview follows real pointer")
	await _click(canvas, b + Vector2(20, 20), false)
	_check(ink.strokes[0].points[1].distance_to(b + Vector2(20, 20)) < 0.01, "release commits position")
	_check(editor.edits.undo() and ink.strokes[0].points[1].distance_to(b) < 0.01, "native drag undo")
	_check(editor.edits.redo() and ink.strokes[0].points[1].distance_to(b + Vector2(20, 20)) < 0.01, "native drag redo")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(root.get_texture().get_image().save_png("user://validation/wall-paths-960.png") == OK, "screenshot 960")
	root.size = Vector2i(800, 600)
	root.content_scale_size = root.size
	await _frames(8)
	_check(canvas.size.x >= 200 and editor.inspector._wall_controls.visible, "800x600 shows wall controls and usable canvas")
	_check(root.get_texture().get_image().save_png("user://validation/wall-paths-800.png") == OK, "screenshot 800")

	# A native pointer draft must disappear when the selected-cell mask changes
	# before Enter. Verify the framebuffer, not just the transient path array.
	editor.apply_grid(AtlasGrid.new(AtlasGrid.Kind.SQUARE, 1000.0))
	canvas.camera_center = Vector2(400, 400)
	canvas.snap_to_grid = false
	editor._on_select(Vector2i.ZERO)
	editor._on_scope_toggled(true)
	await _frames(5)
	var draft_y: float = minf(260.0, canvas.size.y - 35.0)
	var left: Vector2 = canvas.local_to_document(Vector2(80, draft_y))
	var right: Vector2 = canvas.local_to_document(Vector2(180, draft_y))
	var old_count: int = ink.strokes.size()
	var old_history: int = editor.edits._cursor
	await _click(canvas, left, true)
	await _click(canvas, left, false)
	await _click(canvas, right, true)
	await _click(canvas, right, false)
	_check(canvas._wall_draft != null and canvas._wall_vertices.size() == 2,
		"real pointer stages a masked wall draft")
	editor._on_select(Vector2i(1, 0))
	await _frames(4)
	var witness: Vector2i = Vector2i(canvas.global_position) + Vector2i(130, int(draft_y))
	var stale_pixel: Color = root.get_texture().get_image().get_pixelv(witness)
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	editor._unhandled_key_input(key)
	await _frames(5)
	var cleared_pixel: Color = root.get_texture().get_image().get_pixelv(witness)
	_check(ink.strokes.size() == old_count and editor.edits._cursor == old_history,
		"native stale wall does not add artwork or undo history")
	_check(canvas._wall_vertices.is_empty() and canvas._wall_draft == null,
		"native stale wall clears pending draft")
	_check(absf(stale_pixel.r - cleared_pixel.r) + absf(stale_pixel.g - cleared_pixel.g)
		+ absf(stale_pixel.b - cleared_pixel.b) > 0.1,
		"native framebuffer no longer contains the rejected wall preview")
	editor._on_scope_toggled(false)

	root.remove_child(scene)
	scene.free()
	print("ATLAS_WALL_PATHS_VISUAL_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
