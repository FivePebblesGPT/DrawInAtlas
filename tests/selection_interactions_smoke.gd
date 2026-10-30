extends SceneTree
## T-019: selection gestures operate on the active authored layer only.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("SELECTION INTERACTIONS FAILED: " + description)


func _button(canvas: AtlasCanvas, position: Vector2, pressed: bool, ctrl: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	canvas._gui_input(event)


func _motion(canvas: AtlasCanvas, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


func _click(canvas: AtlasCanvas, position: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_button(canvas, position, true, ctrl, alt)
	_button(canvas, position, false, ctrl, alt)


func _drag(canvas: AtlasCanvas, start: Vector2, end: Vector2, ctrl: bool = false, alt: bool = false) -> void:
	_button(canvas, start, true, ctrl, alt)
	_motion(canvas, end)
	_button(canvas, end, false, ctrl, alt)


func _key(editor: AtlasEditor, code: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = ctrl
	event.pressed = true
	editor._unhandled_key_input(event)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.use_system_clipboard = false
	var directory: String = "user://selection-interactions-%d" % Time.get_ticks_usec()
	editor.save_path = directory + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("Selection board", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 160.0)), "create board")
	var canvas: AtlasCanvas = editor.canvas
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var ink_id: String = canvas.active_layer_id
	var first: Vector2 = Vector2(85, 95)
	var second: Vector2 = Vector2(190, 95)
	var third: Vector2 = Vector2(290, 95)
	for location: Vector2 in [first, second, third]:
		var start: Vector2 = canvas.local_to_document(location)
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([start, start + Vector2(20, 0)]), Color.WHITE, 3), false)
	_check(canvas.floor.strokes.size() == 3, "three separated editable objects")
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	_click(canvas, first + Vector2(10, 0))
	_check(canvas.selection.stroke_indices == [0], "plain click selects active-layer stroke")
	_click(canvas, second + Vector2(10, 0), true)
	_check(canvas.selection.stroke_indices == [0, 1], "Ctrl+click adds without moving source")
	_click(canvas, first + Vector2(10, 0), false, true)
	_check(canvas.selection.stroke_indices == [1], "Alt+click subtracts a selected stroke")
	_click(canvas, third + Vector2(10, 0), false, true)
	_check(canvas.selection.stroke_indices == [1], "Alt+click miss leaves selection unchanged")
	_drag(canvas, second + Vector2(45, 10), first + Vector2(-15, -10), true)
	_check(canvas.selection.stroke_indices == [1, 0], "Ctrl+marquee adds whole objects in stable order")
	_drag(canvas, third + Vector2(-15, -10), third + Vector2(45, 10), true)
	_check(canvas.selection.stroke_indices == [1, 0, 2], "Ctrl+marquee adds last object")
	_drag(canvas, second + Vector2(-15, -10), second + Vector2(45, 10), false, true)
	_check(canvas.selection.stroke_indices == [0, 2], "Alt+marquee subtracts only enclosed object")
	_key(editor, KEY_D, true)
	_check(canvas.selection.is_empty(), "Ctrl+D deselects")
	_click(canvas, first + Vector2(10, 0))
	_key(editor, KEY_ENTER)
	_check(canvas.selection.is_empty(), "Enter deselects in artwork-selection mode")
	_click(canvas, first + Vector2(10, 0))
	_button(canvas, Vector2(15, 20), true)
	_motion(canvas, Vector2(400, 300))
	_check(canvas.is_editing(), "marquee is transient until mouse release")
	_key(editor, KEY_ESCAPE)
	_check(not canvas.is_editing() and canvas.selection.stroke_indices == [0], "Escape cancels gesture without losing prior selection")
	_button(canvas, Vector2(400, 300), false)
	_check(canvas.selection.stroke_indices == [0], "release after cancellation cannot replace selection")
	_click(canvas, Vector2(30, 20))
	_check(canvas.selection.is_empty(), "click on empty board clears selection")

	# A second authored ink layer at the same screen coordinates must never
	# enter the initial layer's object selection or cut/copy scope.
	editor.layer_panel._add_ink()
	var top_id: String = canvas.active_layer_id
	_check(top_id != ink_id and canvas.selection.is_empty(), "layer change clears selection")
	var top_start: Vector2 = canvas.local_to_document(first)
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([top_start, top_start + Vector2(20, 0)]), Color.CYAN, 3), false)
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	_click(canvas, first + Vector2(10, 0))
	_check(canvas.selection.layer_id == top_id and canvas.selection.stroke_indices == [0], "selection uses active layer at overlapping coordinates")
	_check(editor.copy_selection() and not editor.clipboard_text.is_empty(), "copy reads active layer only")
	_check(editor.cut_selection(), "cut deletes selected active-layer object")
	_check((canvas.floor.layer_by_id(top_id) as AtlasInkLayer).strokes.is_empty()
		and (canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).strokes.size() == 3, "cut preserves other layer")
	_check(editor.edits.undo() and (canvas.floor.layer_by_id(top_id) as AtlasInkLayer).strokes.size() == 1, "undo restores exact cut layer")
	_check(editor.edits.redo() and (canvas.floor.layer_by_id(top_id) as AtlasInkLayer).strokes.is_empty(), "redo reapplies cut atomically")
	editor.select_layer(ink_id)
	_check(canvas.active_layer_id == ink_id and canvas.selection.is_empty(), "switching back cannot reuse another layer selection")
	_click(canvas, first + Vector2(10, 0))
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	var original: Dictionary = ink.to_dict().duplicate(true)
	ink.locked = true
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0])
	_check(editor.copy_selection() and not editor.can_modify_selection(), "locked source may be copied but not modified")
	_check(not editor.delete_selection() and ink.strokes.size() == 3, "locked selection cannot be deleted")
	ink.locked = false
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0])

	# Cell restriction is an edit mask; it cannot move artwork or change the
	# active layer. A whole selected object crossing the mask is not mutated.
	var bounds: Rect2 = canvas.selection.bounds
	var outside: Vector2 = bounds.get_center() + Vector2(500, 0)
	editor._on_select(canvas.map.grid.document_to_cell(bounds.get_center()))
	editor._on_scope_toggled(true)
	_check(not editor.transform_selection(canvas.selection, Transform2D(0.0, outside - bounds.get_center()))
		and ink.to_dict() == original, "cell mask rejects transform escaping edit scope")
	_check(canvas.active_layer_id == ink_id, "cell mask does not change active editing layer")
	editor._on_scope_toggled(false)
	_check(editor.transform_selection(canvas.selection, Transform2D(0.0, Vector2(500, 0))), "unmasked transform can move artwork across grid boundaries")
	_check(editor.edits.undo(), "transform undo")
	_check((canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).to_dict() == original, "undo exactly restores board-space positions")

	# Camera, rotated-grid and authored-detail presentation changes must not
	# reinterpret coordinates or select hidden artwork.
	_check(canvas.set_presented_detail_level(1), "inspect empty D1 detail")
	editor.select_all_artwork()
	_check(canvas.selection.is_empty() and not editor.can_copy_selection(), "Ctrl+A cannot select hidden D0 objects")
	_click(canvas, first + Vector2(10, 0))
	_check(canvas.selection.is_empty(), "hidden authored detail does not accept selection gestures")
	_check(canvas.set_presented_detail_level(0), "return to authored D0")
	canvas.camera_zoom = 2.5
	var selectable: Vector2 = canvas.document_to_local(ink.strokes[0].points[0] + Vector2(10, 0))
	_click(canvas, selectable)
	_check(canvas.selection.stroke_indices == [0], "zoom transforms pointer to same board-space stroke")
	var grid_before: AtlasGrid = canvas.map.grid.copy()
	var rotated: AtlasGrid = grid_before.copy()
	rotated.kind = AtlasGrid.Kind.HEX_POINTY
	rotated.rotation = deg_to_rad(33.0)
	rotated.origin = Vector2(23, -19)
	editor.apply_grid(rotated)
	_check(canvas.map.grid.same_geometry(rotated), "apply rotated world hex grid")
	_check((canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).to_dict() == original, "rotating overlay does not move artwork")
	_click(canvas, selectable)
	_check(canvas.selection.stroke_indices == [0], "selection stays in board coordinates across rotated hex grid")
	_check(editor.edits.undo(), "undo grid overlay change")
	_check((canvas.floor.layer_by_id(ink_id) as AtlasInkLayer).to_dict() == original, "undo overlay leaves ink unchanged")
	var state: Dictionary = editor.campaign.to_dict()
	editor._on_save()
	_check(FileAccess.file_exists(editor.save_path), "native save selection campaign")
	var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(loaded != null and loaded.to_dict() == state, "native save preserves layers and artwork without serializing transient selection")
	root.remove_child(scene)
	scene.free()
	_remove(directory)
	print("ATLAS_SELECTION_INTERACTIONS_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(1 if _failures > 0 else 0)


func _remove(path: String) -> void:
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(name))
	DirAccess.remove_absolute(path)
