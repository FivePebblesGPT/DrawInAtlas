extends SceneTree
## T-025: point-authored polygons, closed shape modes, protections and persistence.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("POLYGON FAILED: " + description)


func _mouse(canvas: AtlasCanvas, document_point: Vector2, down: bool, twice: bool = false, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.double_click = twice
	event.position = canvas.document_to_local(document_point)
	canvas._gui_input(event)


func _vertex(canvas: AtlasCanvas, position: Vector2) -> void:
	_mouse(canvas, position, true)
	_mouse(canvas, position, false)


func _key(canvas: AtlasCanvas, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	canvas._gui_input(event)


func _run() -> void:
	var triangle: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(90, 0), Vector2(30, 70)])
	var filled: AtlasStroke = AtlasShapes.polygon(triangle, Color(0.3, 0.7, 0.2, 0.5), 6.0, true)
	_check(filled != null and filled.filled and filled.points.size() == 4 and filled.points[0] == filled.points[-1], "closed filled polygon is one stroke")
	_check(AtlasShapes.polygon(triangle, Color.WHITE, 5, false) != null, "same vertices support outline-only mode")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2.ZERO, Vector2.RIGHT]), Color.WHITE, 5, true) == null, "two vertices rejected")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2(2, 0)]), Color.WHITE, 5, false) == null, "collinear vertices rejected")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2.ZERO, Vector2(10, 10), Vector2(0, 10), Vector2(10, 0)]), Color.WHITE, 5, true) == null, "crossing polygon rejected")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(2, 2)]), Color.WHITE, 5, true) == null, "duplicate neighboring points rejected")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2.INF, Vector2.ZERO, Vector2(2, 2)]), Color.WHITE, 5, true) == null, "nonfinite input rejected")
	_check(AtlasShapes.polygon(PackedVector2Array([Vector2(0, 0), Vector2(80, 0), Vector2(80, 80), Vector2(40, 30), Vector2(0, 80)]), Color.WHITE, 5, true) != null,
		"concave but simple polygon is accepted")
	var too_many: PackedVector2Array = PackedVector2Array()
	for index: int in range(AtlasShapes.MAX_POLYGON_VERTICES + 1):
		too_many.append(Vector2.from_angle(float(index) * TAU / float(AtlasShapes.MAX_POLYGON_VERTICES + 1)) * 100.0)
	_check(AtlasShapes.polygon(too_many, Color.WHITE, 5, false) == null, "bounded vertex count avoids quadratic frame stalls")
	_check(AtlasStroke.from_dict(filled.to_dict()) != null and AtlasStroke.from_dict(filled.to_dict()).filled, "filled style survives source dictionary")
	_check(AtlasStroke.from_dict({"points": filled.to_dict()["points"], "color": filled.to_dict()["color"], "width": 6.0}) != null, "legacy stroke without filled flag survives")
	_check(AtlasStroke.from_dict({"points": filled.to_dict()["points"], "color": filled.to_dict()["color"], "width": 6.0, "filled": "yes"}) == null, "malformed style rejected")
	_check(not AtlasStroke.same_artwork([filled], [AtlasShapes.polygon(triangle, filled.color, 6, false)]), "history distinguishes fill mode")
	_check(AtlasSelectionGeometry.select_point(_ink_with(filled), Vector2(30, 20), 1).stroke_indices == [0], "filled interior is selectable")
	_check(AtlasStrokeEraser.erase([filled], PackedVector2Array([Vector2(25, 20)]), 5).is_empty(), "eraser removes touched solid shape without open fragments")

	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	var folder: String = "user://polygon-%d" % Time.get_ticks_usec()
	editor.save_path = folder + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Polygon test", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 35)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	var canvas: AtlasCanvas = editor.canvas
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink != null and editor.inspector.polygon_fill_checkbox.visible, "polygon picker and inspector controls")
	canvas.camera_center = Vector2(30, 25)
	canvas.camera_zoom = 1.5
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_check(canvas.is_editing() and ink.strokes.is_empty(), "multiple clicks leave source unchanged")
	_check(canvas._draft_stroke != null or canvas._polygon_vertices.size() == 3, "draft is held outside history")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = canvas.document_to_local(Vector2(70, 60))
	canvas._gui_input(motion)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == AtlasShapes.polygon(triangle, canvas.brush_color, canvas.brush_width, false).points,
		"pending fourth vertex never changes the Enter-to-commit preview")
	_key(canvas, KEY_ENTER)
	_check(not canvas.is_editing() and ink.strokes.size() == 1, "Enter commits one closed polygon")
	_check(not ink.strokes[0].filled and ink.strokes[0].points[0] == ink.strokes[0].points[-1], "default outline persisted")
	_check(editor.edits.undo() and ink.strokes.is_empty(), "outline is one undo")
	_check(editor.edits.redo() and ink.strokes.size() == 1, "outline redo")
	_check(editor.edits.undo(), "clear before next test")

	# Fill control is wired to the canvas and stored in one shape, not a raster island.
	editor.inspector.polygon_fill_checkbox.button_pressed = true
	_check(canvas.polygon_solid_fill, "inspector fill mode connects to input")
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_mouse(canvas, triangle[0], true)
	_mouse(canvas, triangle[0], false)
	_check(ink.strokes.size() == 1 and ink.strokes[0].filled and not canvas.is_editing(), "close by first vertex")
	_check(AtlasSelectionGeometry.select_point(ink, Vector2(30, 20), 1).stroke_indices == [0], "interior hit test on live ink")
	var saved: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._on_save()
	var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(loaded != null and loaded.to_dict() == saved, "filled polygon native-save round-trip")
	var stored: AtlasInkLayer = loaded.get_map(canvas.map.id).floor_by_id(canvas.floor.id).layer_by_id(ink.id) as AtlasInkLayer if loaded != null else null
	_check(stored != null and stored.strokes.size() == 1 and stored.strokes[0].filled, "native file keeps filled style")
	_check(editor.edits.undo() and ink.strokes.is_empty(), "filled polygon one undo")

	# Esc, Backspace and failed geometry produce no partial history commands.
	_vertex(canvas, triangle[0])
	_vertex(canvas, triangle[1])
	_key(canvas, KEY_ENTER)
	_check(ink.strokes.is_empty(), "invalid two-point shape cannot commit")
	_vertex(canvas, triangle[0])
	_vertex(canvas, triangle[1]); _vertex(canvas, triangle[2])
	_key(canvas, KEY_BACKSPACE)
	_check(canvas._polygon_vertices.size() == 2, "Backspace removes last vertex")
	_key(canvas, KEY_ESCAPE)
	_check(not canvas.is_editing() and ink.strokes.is_empty(), "Escape cancels without mutation")

	ink.locked = true
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(ink.strokes.is_empty(), "locked target blocks every vertex")
	ink.locked = false
	_check(canvas.set_presented_detail_level(1), "hide editing detail")
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(ink.strokes.is_empty(), "hidden detail blocks polygons")
	_check(canvas.set_presented_detail_level(0), "show editing detail")

	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(100, 100)
	editor._on_scope_toggled(true)
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(ink.strokes.is_empty(), "cell mask rejects filled polygon outside mask")
	editor._on_scope_toggled(false)
	# Clicking twice on final vertex should not create a duplicate invalid edge.
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_mouse(canvas, triangle[2], true, true)
	_check(ink.strokes.size() == 1, "double click finishes without duplicated vertex")
	_check(editor.edits.undo(), "double click shape undo")

	# A rotated board grid snaps every new vertex and freezes the snap choice
	# for the complete multi-click gesture.
	var rotated: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 22.0)
	rotated.origin = Vector2(8, -13)
	rotated.rotation = deg_to_rad(29.0)
	editor.apply_grid(rotated)
	_check(canvas.map.grid.rotation == rotated.rotation, "set rotated grid")
	editor.inspector.snap_checkbox.button_pressed = true
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	var snapped: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in triangle:
		snapped.append(AtlasGridSnap.point(rotated, point))
	_check(canvas._polygon_vertices == snapped, "vertices snap in rotated board-space grid")
	editor.inspector.snap_checkbox.button_pressed = false
	_check(canvas._gesture_snap and canvas._polygon_vertices == snapped, "gesture keeps its snap mode while controls change")
	_key(canvas, KEY_ENTER)
	_check(ink.strokes.size() == 1 and ink.strokes[-1].points[0] == snapped[0], "snapped polygon stored without shifting earlier vertices")
	_check(editor.edits.undo(), "snapped polygon undo")

	root.remove_child(scene)
	scene.free()
	_remove(folder)
	print("ATLAS_POLYGON_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)


func _ink_with(stroke: AtlasStroke) -> AtlasInkLayer:
	var ink: AtlasInkLayer = AtlasInkLayer.new()
	ink.strokes = [stroke]
	return ink


func _remove(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	DirAccess.remove_absolute(path)
