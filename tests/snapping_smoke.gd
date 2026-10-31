extends SceneTree
## T-016: document-grid snapping for shape drafts and selection moves.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SNAPPING FAILED: " + message)


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	canvas._gui_input(event)


func _motion(canvas: AtlasCanvas, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for index: int in range(6):
		await process_frame
	_check(editor.create_board("Snapping contract", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 50.0)), "create a board")
	var canvas: AtlasCanvas = editor.canvas
	var toggle: CheckBox = editor.inspector.snap_checkbox
	_check(not toggle.button_pressed and not canvas.snap_to_grid, "snapping defaults off")
	_check(AtlasGridSnap.point(AtlasGrid.new(AtlasGrid.Kind.GRIDLESS), Vector2(12.4, 19.8)) == Vector2(12.4, 19.8), "gridless positions are unchanged")
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	_check(toggle.visible and not toggle.disabled, "shape tool exposes enabled snap control")
	toggle.button_pressed = true
	_check(canvas.snap_to_grid, "UI toggles snapping")
	var grid: AtlasGrid = canvas.map.grid.copy()
	grid.kind = AtlasGrid.Kind.SQUARE
	grid.cell_size = 16.0
	grid.origin = Vector2(17, -15)
	grid.rotation = deg_to_rad(31.0)
	editor.apply_grid(grid)
	_check(canvas.map.grid.same_geometry(grid), "rotation and offset applied without moving artwork")
	for zoom: float in [0.7, 2.5, 6.0]:
		canvas.camera_zoom = zoom
		for quadrant: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var start: Vector2 = grid.cell_to_document(Vector2i(0, 0)) + Vector2(4, 7)
			var finish: Vector2 = start + quadrant * (70.0 if zoom < 1.0 else 28.0 if zoom < 3.0 else 18.0)
			canvas.camera_center = (start + finish) * 0.5
			var first: Vector2 = AtlasGridSnap.point(grid, start)
			var last: Vector2 = AtlasGridSnap.point(grid, finish)
			var local_start: Vector2 = canvas.document_to_local(start)
			var local_finish: Vector2 = canvas.document_to_local(finish)
			_button(canvas, local_start, true)
			_motion(canvas, local_finish)
			_check(canvas._draft_stroke != null and canvas._draft_stroke.points[0].distance_to(first) < 0.01
				and canvas._draft_stroke.points[-1].distance_to(last) < 0.01, "snapped preview matches board grid at zoom %s and quadrant %s" % [zoom, quadrant])
			_button(canvas, local_finish, false)
			var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
			var saved: AtlasStroke = ink.strokes[-1]
			_check(saved.points == PackedVector2Array([first, last]), "committed endpoints exactly match draft")
	# The raw pointer is preserved when toggled off, at the same zoom/grid.
	toggle.button_pressed = false
	var free_start: Vector2 = grid.cell_to_document(Vector2i(0, 0)) + Vector2(6, 9)
	var free_end: Vector2 = free_start + Vector2(14, 12)
	canvas.camera_center = (free_start + free_end) * 0.5
	_button(canvas, canvas.document_to_local(free_start), true)
	_motion(canvas, canvas.document_to_local(free_end))
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points[-1].distance_to(free_end) < 0.01,
		"free preview preserves arbitrary board coordinates")
	_button(canvas, canvas.document_to_local(free_end), false)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.strokes[-1].points[-1].distance_to(free_end) < 0.01, "free commit matches preview")
	# Changing the checkbox during an unfinished gesture must not retarget
	# the draft or make its final release use another snapping mode.
	toggle.button_pressed = true
	canvas.camera_center = (free_start + free_end) * 0.5
	_button(canvas, canvas.document_to_local(free_start), true)
	_motion(canvas, canvas.document_to_local(free_end))
	var locked_end: Vector2 = AtlasGridSnap.point(grid, free_end)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points[-1].distance_to(locked_end) < 0.01,
		"snap-on gesture previews snapped end")
	toggle.button_pressed = false
	_button(canvas, canvas.document_to_local(free_end), false)
	ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.strokes[-1].points[-1].distance_to(locked_end) < 0.01,
		"snap mode is frozen through final release")
	# A rotated hex grid uses axial centers, not the square-grid formula.
	grid.kind = AtlasGrid.Kind.HEX_POINTY
	grid.rotation = deg_to_rad(-27.0)
	editor.apply_grid(grid)
	var near: Vector2 = grid.cell_to_document(Vector2i(2, -1)) + Vector2(3, -4)
	_check(AtlasGridSnap.point(grid, near).distance_to(grid.cell_to_document(Vector2i(2, -1))) < 0.01,
		"rotated hex cells snap to actual axial centers")
	for quadrant: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var from: Vector2 = grid.cell_to_document(Vector2i(0, 0)) + Vector2(5, -4)
		var to: Vector2 = from + quadrant * 145.0
		var delta: Vector2 = AtlasGridSnap.move_delta(grid, from, to)
		_check((delta + AtlasGridSnap.move_delta(grid, to, from)).length() < 0.001,
			"hex snap move is direction symmetric")
		_check(AtlasGridSnap.move_delta(grid, from, from) == Vector2.ZERO,
			"snapped move does not jump unsnapped artwork on click")
	# Rotated/sheared raster objects receive only a board-space translation;
	# their orientation, pixel data and native coordinate scale stay intact.
	var pixels: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	raster.transform = Transform2D(Vector2(1.0, 0.35), Vector2(-0.5, 1.0), Vector2(12.0, -7.5))
	var raster_before: Dictionary = raster.to_dict().duplicate(true)
	var raster_delta: Vector2 = AtlasGridSnap.move_delta(grid, near, near + Vector2(120, -86))
	var moved_raster: AtlasRasterLayer = AtlasSelectionGeometry.transformed(raster,
		AtlasSelectionGeometry.select_all(raster), Transform2D(0.0, raster_delta)) as AtlasRasterLayer
	_check(moved_raster != null and moved_raster.transform.origin.distance_to(raster.transform.origin + raster_delta) < 0.001,
		"rotated/sheared raster translation is in board coordinates")
	_check(moved_raster.transform.x == raster.transform.x and moved_raster.transform.y == raster.transform.y
		and raster.to_dict() == raster_before,
		"snapped raster move does not resample, rotate, or mutate source")
	# The selection move preview and commit share the exact same lattice
	# displacement, including when the object's source is not grid-aligned.
	canvas.camera_zoom = 2.5
	toggle.button_pressed = true
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	_check(toggle.is_visible_in_tree() and toggle.button_pressed, "selection move exposes the same opt-in snap state")
	ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	var index: int = ink.strokes.size() - 1
	var initial: Dictionary = ink.to_dict().duplicate(true)
	for quadrant: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
		canvas.selection = AtlasSelectionGeometry.select_indices(ink, [index])
		var start: Vector2 = canvas.selection.bounds.get_center()
		var finish: Vector2 = start + quadrant * 34.0
		canvas.camera_center = (start + finish) * 0.5
		var expected: Vector2 = AtlasGridSnap.move_delta(grid, start, finish)
		_button(canvas, canvas.document_to_local(start), true)
		_motion(canvas, canvas.document_to_local(finish))
		_check(canvas._manipulation == AtlasCanvas.Manipulation.MOVE and canvas._gesture_transform.origin.distance_to(expected) < 0.01,
			"selection move preview uses snapped lattice displacement")
		var preview: AtlasInkLayer = canvas._preview_layer as AtlasInkLayer
		_check(preview != null and preview.strokes[index].points[0].distance_to(ink.strokes[index].points[0] + expected) < 0.01,
			"preview geometry matches selected move transform")
		_button(canvas, canvas.document_to_local(finish), false)
		ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
		_check(ink.strokes[index].points[0].distance_to(Vector2(initial["strokes"][index]["points"][0][0], initial["strokes"][index]["points"][0][1]) + expected) < 0.01,
			"committed move matches preview geometry")
		_check(editor.edits.undo(), "snapped move is undoable")
		ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
		_check(ink.to_dict() == initial, "undo restores unsnapped source exactly")
	# Mask rejection: the transformed object must not leak beyond the selected cell.
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [index])
	var source: Vector2 = canvas.selection.bounds.get_center()
	canvas.camera_center = source
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(200, 200)
	editor.locked_to_cell = true
	editor.artwork.refresh_scope()
	_button(canvas, canvas.document_to_local(source), true)
	_motion(canvas, canvas.document_to_local(source + Vector2(34, 34)))
	_button(canvas, canvas.document_to_local(source + Vector2(34, 34)), false)
	ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
	_check(ink.to_dict() == initial, "edit mask prevents snapped object escaping its scope")
	editor.locked_to_cell = false
	editor.artwork.refresh_scope()
	# Independent rectangle/ellipse drafts use exactly the same snapped end
	# points as their eventual stored shapes (negative quadrants included).
	for kind: AtlasCanvas.Tool in [AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE]:
		editor._choose_tool(kind)
		for quadrant: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var start: Vector2 = grid.cell_to_document(Vector2i(0, 0)) + Vector2(3, -5)
			var finish: Vector2 = start + quadrant * 83.0
			canvas.camera_zoom = 1.0
			canvas.camera_center = (start + finish) * 0.5
			var shape_name: String = AtlasCanvas.Tool.keys()[kind]
			var expected: AtlasStroke = AtlasShapes.stroke(shape_name, AtlasGridSnap.point(grid, start),
				AtlasGridSnap.point(grid, finish), canvas.brush_color, canvas.brush_width)
			_button(canvas, canvas.document_to_local(start), true)
			_motion(canvas, canvas.document_to_local(finish))
			_check(expected != null and canvas._draft_stroke != null and canvas._draft_stroke.points == expected.points,
				"%s preview snaps both opposite endpoints" % shape_name)
			_button(canvas, canvas.document_to_local(finish), false)
			ink = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasInkLayer
			_check(ink.strokes[-1].points == expected.points, "%s committed shape matches preview" % shape_name)
	# Gridless boards cannot snap even when an earlier board had snap enabled.
	var saved_grid: AtlasGrid = canvas.map.grid.copy()
	var gridless: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)
	editor.apply_grid(gridless)
	_check(toggle.disabled, "gridless board disables snapping")
	var raw: Vector2 = Vector2(7.21, -8.49)
	_check(AtlasGridSnap.point(canvas.map.grid, raw) == raw, "gridless snap never moves artwork")
	editor.apply_grid(saved_grid)
	_check(not toggle.disabled, "grid-backed board restores snapping control")
	# Pen remains free, even while the snap checkbox is enabled.
	toggle.button_pressed = true
	editor._choose_tool(AtlasCanvas.Tool.PEN)
	_check(not toggle.is_visible_in_tree(), "pen is not an implicitly snapping tool")
	var pen_start: Vector2 = Vector2(5.34, 8.29)
	var pen_end: Vector2 = Vector2(15.82, 17.15)
	canvas.camera_center = (pen_start + pen_end) * 0.5
	_button(canvas, canvas.document_to_local(pen_start), true)
	_motion(canvas, canvas.document_to_local(pen_end))
	_button(canvas, canvas.document_to_local(pen_end), false)
	_check(ink.strokes[-1].points[-1].distance_to(pen_end) < 0.01, "pen never snaps")
	# Grid edits change only the grid; existing strokes remain in board coordinates.
	var original: Dictionary = ink.to_dict()
	grid.rotation = deg_to_rad(77.0)
	editor.apply_grid(grid)
	_check(ink.to_dict() == original, "changing grid orientation does not transform content")
	_check(editor.edits.undo() and ink.to_dict() == original, "grid undo preserves content")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_SNAPPING_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)
