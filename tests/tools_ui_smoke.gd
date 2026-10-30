extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TOOLS UI FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	var directory: String = "user://tools-ui-%d" % Time.get_ticks_usec()
	editor.save_path = directory + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	grid.distance_unit = "tiles"
	editor.create_board("Sketch", grid)
	var source_id: String = editor.canvas.map.id
	var canvas: AtlasCanvas = editor.canvas
	editor.edits.mark_saved()
	_tool(editor, AtlasCanvas.Tool.LINE)
	var start: Vector2 = canvas.local_to_document(Vector2(50, 80))
	_button(canvas, Vector2(50, 80), true)
	_motion(canvas, Vector2(180, 140))
	_check(canvas.floor.strokes.is_empty(), "shape preview is not committed")
	_button(canvas, Vector2(180, 140), false)
	_check(canvas.floor.strokes.size() == 1 and canvas.floor.strokes[0].points[0] == start,
		"line gesture stores document coordinates")
	_tool(editor, AtlasCanvas.Tool.RECTANGLE)
	_drag(canvas, Vector2(50, 180), Vector2(180, 260))
	_check(canvas.floor.strokes.size() == 2 and canvas.floor.strokes[-1].points.size() == 5,
		"rectangle is one closed outline transaction")
	_key(KEY_Z, true)
	_check(canvas.floor.strokes.size() == 1, "one undo removes whole shape")
	_key(KEY_Z, true, true)
	_tool(editor, AtlasCanvas.Tool.ELLIPSE)
	_button(canvas, Vector2(250, 180), true)
	_motion(canvas, Vector2(250, 200))
	_motion(canvas, Vector2(310, 240))
	_button(canvas, Vector2(310, 240), false)
	_check(canvas.floor.strokes.size() == 3 and canvas.floor.strokes[-1].points.size() == 65,
		"ellipse recovers from an initially degenerate drag")
	_key(KEY_V)
	_button(canvas, Vector2(115, 110), true)
	_button(canvas, Vector2(115, 110), false)
	_check(canvas.selection.stroke_indices == [0], "selection click hits the intended stroke")
	var before: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	_button(canvas, Vector2(115, 110), true)
	_motion(canvas, Vector2(155, 135))
	_check(AtlasStroke.same_artwork(before, canvas.floor.strokes), "move preview never changes canonical ink")
	_button(canvas, Vector2(155, 135), false)
	_check(canvas.floor.strokes[0].points[0].is_equal_approx(before[0].points[0] + Vector2(40, 25)),
		"move gesture is one document-space translation")
	var width: float = canvas.floor.strokes[0].width
	var bounds: Rect2 = canvas.selection.bounds
	_drag(canvas, canvas.document_to_local(bounds.end), canvas.document_to_local(bounds.position + bounds.size * 2.0))
	_check(is_equal_approx(canvas.floor.strokes[0].width, width * 2.0), "corner handle scales ink proportionally")
	_key(KEY_Z, true)
	_check(canvas.floor.strokes[0].width == width, "resize undo restores original width")
	editor.select_all_artwork()
	var selection_center: Vector2 = canvas.document_to_local(canvas.selection.bounds.get_center())
	_button(canvas, selection_center, true)
	_motion(canvas, selection_center + Vector2(10, 10))
	_key(KEY_S, true)
	_check(not canvas.is_editing() and not editor.edits.is_dirty(), "Save commits an in-flight move before checkpointing")
	var saved_move: AtlasEditCommand = editor.edits.get_undo_command()
	_button(canvas, selection_center + Vector2(10, 10), false)
	_check(editor.edits.get_undo_command() == saved_move, "release after Save does not commit a gesture twice")
	_key(KEY_A, true)
	_check(canvas.selection.stroke_indices.size() == 3, "Ctrl+A selects all active ink")
	_key(KEY_C, true)
	_check(not editor.clipboard_text.is_empty(), "copy captures typed internal clipboard without touching OS clipboard")
	_key(KEY_X, true)
	_check(canvas.floor.strokes.is_empty(), "cut removes the copied selection")
	_key(KEY_V, true)
	_check(canvas.floor.strokes.size() == 3 and canvas.selection.bounds.position.is_equal_approx(Vector2.ZERO),
		"paste restores normalized artwork in one operation")
	var source: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	var other_grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 100.0)
	other_grid.distance_unit = "km"
	other_grid.distance_per_cell = 3.0
	editor.create_board("Other", other_grid)
	var other_id: String = canvas.map.id
	canvas.grab_focus()
	_key(KEY_V, true)
	_check(canvas.floor.strokes.size() == 3 and canvas.map.grid.distance_unit == "km",
		"cross-board paste does not harmonize native units")
	_check(AtlasStroke.same_artwork(editor.campaign.get_map(source_id).floors[0].strokes, source),
		"clipboard edits never mutate source board")
	_key(KEY_Z, true)
	_check(canvas.floor.strokes.is_empty(), "paste is undone as one transaction")
	_key(KEY_Z, true, true)
	editor._on_scope_toggled(true)
	var command: AtlasEditCommand = editor.edits.get_undo_command()
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO, Vector2(120, 0)])), false)
	_check(editor.edits.get_undo_command() == command, "locked scope with no cell denies new ink")
	editor._on_select(Vector2i.ZERO)
	_tool(editor, AtlasCanvas.Tool.PEN)
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-50, 50), Vector2(150, 50)]), Color.RED, 10.0), false)
	_check(editor.locked_to_cell and canvas.floor.strokes.size() == 4, "cell lock persists across drawing-tool changes")
	_check(editor.canvas.edit_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(canvas.floor.strokes[-1])),
		"new ink is clipped before committing to the selected cell")
	editor.select_all_artwork()
	before = AtlasStroke.clone_all(canvas.floor.strokes)
	_check(not editor.transform_selection(canvas.selection, Transform2D(0.0, Vector2(200, 0)))
		and AtlasStroke.same_artwork(before, canvas.floor.strokes), "scope rejects transform without partial mutation")
	editor._on_scope_toggled(false)
	editor.layer_panel._add_raster()
	var raster_id: String = canvas.active_layer_id
	_tool(editor, AtlasCanvas.Tool.PEN)
	canvas.brush_color = Color.RED
	canvas.brush_width = 4.0
	command = editor.edits.get_undo_command()
	_button(canvas, canvas.document_to_local(Vector2(-2, -2)), true)
	_motion(canvas, canvas.document_to_local(Vector2(3, 3)))
	_check((canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer).chunks.is_empty()
		and editor.edits.get_undo_command() == command, "raster preview leaves pixels and history untouched")
	_button(canvas, canvas.document_to_local(Vector2(3, 3)), false)
	var raster: AtlasRasterLayer = canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
	_check(raster != null and not raster.chunks.is_empty(), "raster pen allocates canonical chunks at negative coordinates")
	canvas.brush_color = Color.BLUE
	_check(editor.fill_at(Vector2(-1, -1)), "bucket fills an existing raster region")
	raster = canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
	_check(raster.chunks["-1,-1"].image.get_pixel(255, 255) == Color.BLUE, "raster fill changes exact canonical pixels")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.BLACK, 4.0), true)
	raster = canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
	_check(raster.chunks["0,0"].image.get_pixel(0, 0).a == 0.0, "raster eraser makes pixels transparent")
	editor._on_undo()
	editor.select_layer(raster_id)
	editor.select_all_artwork()
	_check(editor.copy_selection() and editor.paste_selection(), "raster clipboard is self-contained and pasteable")
	var pasted_id: String = canvas.active_layer_id
	_check(pasted_id != raster_id and canvas.floor.layer_by_id(pasted_id) is AtlasRasterLayer,
		"raster paste assigns a new independent layer identity")
	_check(canvas.tool == AtlasCanvas.Tool.ART_SELECT and canvas.selection.raster_selected,
		"pasted assets are immediately selected for placement")
	var overlay: AtlasGrid = canvas.map.grid.copy()
	overlay.kind = AtlasGrid.Kind.HEX_POINTY
	overlay.cell_size = 42.0
	overlay.rotation = deg_to_rad(37.0)
	editor.apply_grid(overlay)
	_tool(editor, AtlasCanvas.Tool.PAINT)
	editor.palette_id = 2
	var tile_center: Vector2 = canvas.document_to_local(Vector2(150, 50))
	_drag(canvas, tile_center, tile_center)
	_check(canvas.floor.terrain.get("1,0") == 2, "terrain pointer uses its fixed content grid, not the changed overlay")
	editor.palette_id = 3
	_check(editor.fill_at(Vector2(150, 50)) and canvas.floor.terrain.get("1,0") == 3,
		"terrain fill also resolves the content grid independently")
	var tile_layer: AtlasTerrainLayer = canvas.floor.terrain_layer()
	var payload: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_tiles(tile_layer.grid, {"1,0": 3}, Vector2i(1, 0)))
	_check(editor.paste_payload(payload, Vector2(250, 50)) and canvas.floor.terrain.get("2,0") == 3,
		"typed tile paste resolves destination content coordinates")
	var cells_before: Dictionary = canvas.floor.terrain.duplicate()
	payload.grid.kind = AtlasGrid.Kind.HEX_POINTY
	_check(not editor.paste_payload(payload, Vector2(350, 50)) and canvas.floor.terrain == cells_before,
		"tile paste rejects incompatible grids atomically")
	var saved: Dictionary = editor.campaign.to_dict()
	editor._on_save()
	editor._on_load()
	_check(editor.campaign.to_dict() == saved and editor.campaign.get_map(other_id) != null,
		"transforms and clipboard/raster content survive recoverable persistence")
	root.remove_child(scene)
	scene.free()
	_remove(directory)
	print("ATLAS_TOOLS_UI_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)


func _tool(editor: AtlasEditor, tool: AtlasCanvas.Tool) -> void:
	editor._choose_tool(tool)


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _motion(canvas: AtlasCanvas, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + position
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _drag(canvas: AtlasCanvas, start: Vector2, finish: Vector2) -> void:
	_button(canvas, start, true)
	_motion(canvas, finish)
	_button(canvas, finish, false)


func _key(code: Key, control: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)


func _remove(path: String) -> void:
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(name))
	DirAccess.remove_absolute(path)
