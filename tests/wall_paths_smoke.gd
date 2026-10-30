extends SceneTree
## T-026: explicitly editable wall-path schema, tools, masks, history and saves.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WALL PATH FAILED: " + reason)

func _mouse(canvas: AtlasCanvas, location: Vector2, down: bool, shift: bool = false, alt: bool = false, twice: bool = false, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.position = canvas.document_to_local(location)
	event.pressed = down
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.double_click = twice
	canvas._gui_input(event)

func _click(canvas: AtlasCanvas, location: Vector2, shift: bool = false, alt: bool = false) -> void:
	_mouse(canvas, location, true, shift, alt)
	_mouse(canvas, location, false, shift, alt)

func _key(canvas: AtlasCanvas, code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	canvas._gui_input(event)

func _run() -> void:
	var a: Vector2 = Vector2(12, 10)
	var b: Vector2 = Vector2(72, 10)
	var c: Vector2 = Vector2(72, 65)
	var vertices: PackedVector2Array = PackedVector2Array([a, b, c])
	var open: AtlasStroke = AtlasEditablePath.make(vertices, Color(0.4, 0.5, 0.8, 0.55), 4, false)
	var closed: AtlasStroke = AtlasEditablePath.make(vertices, Color.WHITE, 4, true)
	_check(open != null and closed != null and open.editable_path and not open.closed_path and closed.closed_path, "typed open and closed resource")
	_check(not open.filled and not closed.filled and closed.points.size() == 3, "closed path never becomes solid polygon")
	_check(AtlasEditablePath.render_points(closed).size() == 4 and AtlasEditablePath.render_points(closed)[-1] == a, "closure only added for rendering")
	_check(AtlasEditablePath.make(PackedVector2Array([a]), Color.WHITE, 4) == null, "reject one vertex")
	_check(AtlasEditablePath.make(PackedVector2Array([a, b]), Color.WHITE, 4, true) == null, "reject two vertex enclosure")
	_check(AtlasEditablePath.make(PackedVector2Array([a, a, b]), Color.WHITE, 4) == null, "reject duplicate edge")
	_check(AtlasEditablePath.make(PackedVector2Array([a, Vector2.INF, b]), Color.WHITE, 4) == null, "reject invalid coordinate")
	_check(AtlasEditablePath.make(PackedVector2Array([a, b, Vector2(132, 10)]), Color.WHITE, 4, true) == null, "reject zero area closure")
	_check(AtlasStroke.from_dict(open.to_dict()) != null and AtlasStroke.from_dict(open.to_dict()).editable_path, "dictionary compatibility")
	_check(AtlasStroke.from_dict(closed.to_dict()).closed_path, "persist closed mode")
	var invalid: Dictionary = open.to_dict().duplicate(true)
	invalid["closed_path"] = "true"
	_check(AtlasStroke.from_dict(invalid) == null, "malformed closed flag denied")
	_check(AtlasStroke.from_dict({"points": [[0, 0], [1, 1]], "color": [1, 1, 1, 1], "width": 2}) != null, "old save remains readable")
	_check(not AtlasStroke.same_artwork([open], [closed]), "history sees closure difference")
	_check(open.copy().editable_path and closed.copy().closed_path, "cloning retains editability")
	_check(AtlasEditablePath.vertex_at(open, a + Vector2(2, 0), 4) == 0, "vertex hit")
	_check(AtlasEditablePath.segment_at(closed, Vector2(42, 37.5), 4) == 2, "closed edge hit")
	_check(AtlasEditablePath.moved_vertex(open, 1, Vector2(75, 15)).points[1] == Vector2(75, 15), "move vertex")
	_check(AtlasEditablePath.inserted_vertex(open, 0, Vector2(32, 10)).points.size() == 4, "insert vertex")
	_check(AtlasEditablePath.deleted_vertex(open, 1).points.size() == 2, "delete vertex")
	_check(AtlasEditablePath.deleted_vertex(closed, 1) == null, "cannot delete below closed minimum")
	_check(AtlasEditablePath.restyled(open, Color.RED, 9).width == 9 and AtlasEditablePath.restyled(open, Color.RED, 9).color == Color.RED, "restyle keeps geometry")
	var ink: AtlasInkLayer = AtlasInkLayer.new()
	ink.strokes.append(closed)
	_check(AtlasSelectionGeometry.select_point(ink, Vector2(42, 37.5), 2).stroke_indices == [0], "closed edge selection")
	_check(AtlasStrokeEraser.erase([closed], PackedVector2Array([Vector2(42, 37.5)]), 8).is_empty(), "eraser removes entire wall rather than uneditable fragments")
	_check(AtlasStrokeEraser.erase([closed], PackedVector2Array([Vector2(300, 300)]), 8)[0].closed_path, "eraser misses retain path")
	var copied: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_ink([closed], [0], a))
	_check(copied != null and copied.strokes[0].editable_path and copied.strokes[0].closed_path, "clipboard keeps wall schema")

	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	var folder: String = "user://wall-paths-%d" % Time.get_ticks_usec()
	editor.save_path = folder + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Path test", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 35)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.WALL_PATH)
	var canvas: AtlasCanvas = editor.canvas
	canvas.camera_zoom = 1.4
	canvas.camera_center = Vector2(35, 30)
	var live: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(live != null and editor.inspector._wall_controls.visible, "tool has ink inspector options")
	_click(canvas, a)
	_click(canvas, b)
	_check(live.strokes.is_empty() and canvas.is_editing(), "unfinished path never changes document")
	_key(canvas, KEY_ENTER)
	_check(live.strokes.size() == 1 and live.strokes[0].editable_path and not live.strokes[0].closed_path, "Enter finishes open wall in one command")
	_check(editor.edits.undo() and live.strokes.is_empty(), "open creation undo")
	_check(editor.edits.redo() and live.strokes.size() == 1, "open creation redo")
	_check(editor.edits.undo(), "clear path before closed test")
	_click(canvas, a)
	_click(canvas, b)
	_click(canvas, c)
	_mouse(canvas, c, true, false, false, false, MOUSE_BUTTON_RIGHT)
	_check(live.strokes.size() == 1 and live.strokes[0].closed_path, "right-click closes wall")
	_check(not live.strokes[0].filled and live.strokes[0].points.size() == 3 and live.strokes[0].points[0].distance_to(a) < 0.001 and live.strokes[0].points[1].distance_to(b) < 0.001, "stored vertices are editable, not a filled polygon")
	_check(editor.edits.undo() and live.strokes.is_empty(), "closed creation undo")
	_check(editor.edits.redo() and live.strokes.size() == 1, "closed redo")
	# Vertex moves are previewed without modifying the source until release.
	_mouse(canvas, b, true)
	_check(canvas._wall_drag_vertex == 1, "click node begins drag")
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = canvas.document_to_local(Vector2(85, 20))
	canvas._gui_input(move)
	_check(live.strokes[0].points[1].distance_to(b) < 0.001 and canvas._wall_preview != null and canvas._wall_preview.points[1] == Vector2(85, 20), "drag preview leaves source intact")
	_mouse(canvas, Vector2(85, 20), false)
	_check(live.strokes[0].points[1] == Vector2(85, 20), "release commits moved node")
	_check(editor.edits.undo() and live.strokes[0].points[1].distance_to(b) < 0.001, "drag undo")
	_check(editor.edits.redo() and live.strokes[0].points[1] == Vector2(85, 20), "drag redo")
	# Shift+click a segment inserts; Alt+click a vertex deletes.
	_click(canvas, Vector2(42, 10), true)
	_check(live.strokes[0].points.size() == 4, "Shift edge inserts vertex")
	_click(canvas, Vector2(42, 10), false, true)
	_check(live.strokes[0].points.size() == 3, "Alt vertex deletes vertex")
	_check(editor.edits.undo() and live.strokes[0].points.size() == 4, "delete undo")
	_check(editor.edits.redo() and live.strokes[0].points.size() == 3, "delete redo")
	canvas.brush_color = Color.RED
	canvas.brush_width = 11
	canvas.restyle_selected_wall()
	_check(live.strokes[0].color == Color.RED and live.strokes[0].width == 11, "explicit restyle action changes style only")
	_check(editor.edits.undo() and live.strokes[0].width != 11, "style undo")
	_check(editor.edits.redo() and live.strokes[0].width == 11, "style redo")
	var stored: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._on_save()
	var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(restored != null and restored.to_dict() == stored, "native save round-trip retains path edits")
	# Cancellation, layer protections and scope denial must not create history.
	canvas.cancel_edit()
	_click(canvas, Vector2(-40, -20))
	_key(canvas, KEY_ESCAPE)
	_check(live.strokes.size() == 1, "Escape cancels construction")
	live.locked = true
	_click(canvas, Vector2(-40, -20)); _click(canvas, Vector2(-10, -20)); _key(canvas, KEY_ENTER)
	_check(live.strokes.size() == 1, "locked ink denies new paths")
	live.locked = false
	_check(canvas.set_presented_detail_level(1), "hide editing target")
	_click(canvas, Vector2(-40, -20)); _click(canvas, Vector2(-10, -20)); _key(canvas, KEY_ENTER)
	_check(live.strokes.size() == 1, "hidden detail denies paths")
	_check(canvas.set_presented_detail_level(0), "restore presented layer")
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(100, 100)
	editor._on_scope_toggled(true)
	_click(canvas, Vector2(-40, -20)); _click(canvas, Vector2(-10, -20)); _key(canvas, KEY_ENTER)
	_check(live.strokes.size() == 1, "cell mask denies out-of-bounds creation")
	_mouse(canvas, a, true)
	_mouse(canvas, Vector2(25, 25), false)
	_check(live.strokes[0].points[0].distance_to(a) < 0.001, "mask blocks vertex movement")
	editor._on_scope_toggled(false)
	# Merely picking an off-grid vertex with snapping on must not move it.
	var rotated: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)
	rotated.rotation = deg_to_rad(24)
	rotated.origin = Vector2(4, -7)
	editor.apply_grid(rotated)
	editor.inspector.snap_checkbox.button_pressed = true
	var untouched: Vector2 = live.strokes[0].points[1]
	_mouse(canvas, untouched, true)
	_mouse(canvas, untouched, false)
	_check(live.strokes[0].points[1] == untouched, "snapping never moves a vertex on selection-only click")
	var snap_target: Vector2 = Vector2(140, 95)
	_mouse(canvas, untouched, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = canvas.document_to_local(snap_target)
	canvas._gui_input(motion)
	_mouse(canvas, snap_target, false)
	_check(live.strokes[0].points[1].distance_to(AtlasGridSnap.point(rotated, snap_target)) < 0.001,
		"dragging vertex respects rotated-grid snapping")
	_check(editor.edits.undo() and live.strokes[0].points[1] == untouched, "snapped move undo restores original")

	root.remove_child(scene)
	scene.free()
	_remove(folder)
	print("ATLAS_WALL_PATHS_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)

func _remove(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		for name: String in DirAccess.get_files_at(absolute):
			DirAccess.remove_absolute(absolute.path_join(name))
		DirAccess.remove_absolute(absolute)
