extends SceneTree
## T-024: solid round line with optional angular/centered drawing on an active ink layer.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LINE FAILED: " + reason)


func _button(canvas: AtlasCanvas, point: Vector2, down: bool, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = canvas.document_to_local(point)
	event.shift_pressed = shift
	event.alt_pressed = alt
	canvas._gui_input(event)


func _motion(canvas: AtlasCanvas, point: Vector2, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.document_to_local(point)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.shift_pressed = shift
	event.alt_pressed = alt
	canvas._gui_input(event)


func _close(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.02


func _run() -> void:
	for quadrant: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var anchor: Vector2 = Vector2(15, -30)
		var pointer: Vector2 = anchor + quadrant * Vector2(47, 29)
		for centered: bool in [false, true]:
			var endpoints: PackedVector2Array = AtlasShapes.line_endpoints(anchor, pointer, true, centered)
			var direction: Vector2 = endpoints[1] - (anchor if centered else endpoints[0])
			var angle: float = direction.angle()
			_check(absf(angle - roundf(angle / (PI / 12.0)) * PI / 12.0) < 0.0001,
				"Shift quantizes line direction to 15-degree multiples")
			_check(is_equal_approx(direction.length(), pointer.distance_to(anchor)),
				"angle restriction retains drag distance")
			_check(_close((endpoints[0] + endpoints[1]) * 0.5, anchor) if centered else _close(endpoints[0], anchor),
				"Alt center versus ordinary anchored start")
	_check(AtlasShapes.line_endpoints(Vector2.ZERO, Vector2(3, 4), false, false) == PackedVector2Array([Vector2.ZERO, Vector2(3, 4)]),
		"unmodified line is exact")
	_check(AtlasShapes.line_endpoints(Vector2.ZERO, Vector2(3, 4), false, true) == PackedVector2Array([Vector2(-3, -4), Vector2(3, 4)]),
		"Alt line is centered without angle restriction")
	_check(AtlasShapes.line_endpoints(Vector2.INF, Vector2.ZERO, true, false).is_empty(),
		"nonfinite line geometry is rejected")

	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	var folder: String = "user://line-%d" % Time.get_ticks_usec()
	editor.save_path = folder + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Line test", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 35.0)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	var canvas: AtlasCanvas = editor.canvas
	var ink_id: String = canvas.active_layer_id
	var anchor: Vector2 = canvas.camera_center - Vector2(20, 18)
	var pointer: Vector2 = anchor + Vector2(40, 31)
	canvas.brush_color = Color(0.1, 0.7, 0.9, 0.45)
	canvas.brush_width = 13.5
	_check(editor.inspector._line_hint.visible and editor.inspector.brush_width_spinner.visible,
		"Line inspector displays constraints and width")
	for zoom: float in [0.75, 1.5, 3.0]:
		canvas.camera_zoom = zoom
		canvas.camera_center = (anchor + pointer) * 0.5
		for shift: bool in [false, true]:
			for centered: bool in [false, true]:
				_button(canvas, anchor, true, shift, centered)
				_motion(canvas, pointer, shift, centered)
				var expected: PackedVector2Array = AtlasShapes.line_endpoints(anchor, pointer, shift, centered)
				_check(canvas._draft_stroke != null and canvas._draft_stroke.points == expected,
					"preview exact geometry for modifiers and zoom")
				_button(canvas, pointer, false, shift, centered)
				var ink: AtlasInkLayer = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
				_check(ink.strokes[-1].points == expected, "committed endpoints match preview")
				_check(ink.strokes[-1].width == 13.5 and ink.strokes[-1].color == canvas.brush_color,
					"stroke retains width and RGBA")
				_check(editor.edits.undo(), "line is one undo")
				_check(editor.edits.redo(), "line is one redo")
				_check(editor.edits.undo(), "restore source for next gesture")

	# Keyboard modifiers also refresh the last pointer position without motion.
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	key.shift_pressed = true
	canvas._gui_input(key)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == AtlasShapes.line_endpoints(anchor, pointer, true, false),
		"Shift key updates an already stationary line preview")
	key = InputEventKey.new()
	key.keycode = KEY_ALT
	key.pressed = true
	key.shift_pressed = true
	key.alt_pressed = true
	canvas._gui_input(key)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == AtlasShapes.line_endpoints(anchor, pointer, true, true),
		"Alt key immediately centers a Shift-constrained preview")
	key = InputEventKey.new()
	key.keycode = KEY_ALT
	key.pressed = false
	key.shift_pressed = true
	canvas._gui_input(key)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == AtlasShapes.line_endpoints(anchor, pointer, true, false),
		"Alt release restores anchored preview before mouse release")
	canvas.cancel_edit()
	_button(canvas, pointer, false)

	# A release's current modifier state, not a stale intermediate motion,
	# determines the exact committed line.
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false, true, true)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes[-1].points == AtlasShapes.line_endpoints(anchor, pointer, true, true),
		"release modifier state recomputes final preview before commit")
	_check(editor.edits.undo(), "modified release undo")
	_button(canvas, anchor, true)
	_motion(canvas, pointer, true)
	canvas.cancel_edit()
	_button(canvas, pointer, false, true)
	_check(ink.strokes.is_empty(), "Escape cancels draft without history")

	var grid: AtlasGrid = canvas.map.grid.copy()
	grid.rotation = deg_to_rad(32.0)
	grid.origin = Vector2(9, -22)
	editor.apply_grid(grid)
	editor.inspector.snap_checkbox.button_pressed = true
	var snapped_start: Vector2 = AtlasGridSnap.point(grid, anchor)
	var snapped_end: Vector2 = AtlasGridSnap.point(grid, pointer)
	_button(canvas, anchor, true)
	_motion(canvas, pointer, true, true)
	var expected_snapped: PackedVector2Array = AtlasShapes.line_endpoints(snapped_start, snapped_end, true, true)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == expected_snapped,
		"grid snaps raw endpoints first, angular and center modifiers then apply")
	_button(canvas, pointer, false, true, true)
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes[-1].points == expected_snapped, "snapped preview equals stored line")
	_check(editor.edits.undo(), "snapped line undo")

	# Active layer, presentation, and edit-mask rules remain command-owned.
	ink.locked = true
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(ink.strokes.is_empty(), "locked layer rejects line")
	ink.locked = false
	_check(canvas.set_presented_detail_level(1), "switch to absent authored detail")
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(ink.strokes.is_empty(), "hidden detail rejects line")
	_check(canvas.set_presented_detail_level(0), "restore visible detail")
	editor.inspector.snap_checkbox.button_pressed = false
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(500, 500)
	editor._on_scope_toggled(true)
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(ink.strokes.is_empty(), "masked outside-area line cannot be committed")
	editor._on_scope_toggled(false)
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes.size() == 1, "unmasked valid line commits")
	var saved: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._on_save()
	var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(loaded != null and loaded.to_dict() == saved, "native save roundtrip preserves line")
	root.remove_child(scene)
	scene.free()
	_remove(folder)
	print("ATLAS_LINE_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)


func _remove(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	DirAccess.remove_absolute(path)
