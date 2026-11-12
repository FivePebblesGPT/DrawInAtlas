extends SceneTree
## T-024/T-112: Line gestures, source history, and portable-generation Save/Open.

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
				_check(_matches(canvas, expected), "committed pixels match preview endpoints, width and RGBA")
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
	_check(_matches(canvas, AtlasShapes.line_endpoints(anchor, pointer, true, true)),
		"release modifier state recomputes final preview before commit")
	_check(editor.edits.undo(), "modified release undo")
	_button(canvas, anchor, true)
	_motion(canvas, pointer, true)
	canvas.cancel_edit()
	_button(canvas, pointer, false, true)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "Escape cancels draft without history")

	# Changing inspector style while the pointer is stationary must repaint
	# the detached Line preview, not just the eventual release-to-commit stroke.
	canvas.brush_width = 8.0
	canvas.brush_color = Color(0.2, 0.7, 0.2, 0.5)
	_button(canvas, anchor, true)
	_motion(canvas, pointer, true, true)
	await process_frame
	var before_style: Dictionary = canvas._preview_layer.to_dict() if canvas._preview_layer != null else {}
	var restyled_color: Color = Color(0.9, 0.25, 0.4, 0.8)
	var restyled_width: float = 17.5
	editor.inspector.brush_width_spinner.value = restyled_width
	editor.inspector.brush_color_picker.color = restyled_color
	# Programmatic picker assignment does not emit color_changed in Godot;
	# the real picker gesture dispatches this inspector signal.
	editor.inspector.brush_color_changed.emit(restyled_color)
	_check(canvas.brush_width == restyled_width and canvas.brush_color == restyled_color,
		"inspector forwards live Line color and width")
	await process_frame
	var restyled_endpoints: PackedVector2Array = AtlasShapes.line_endpoints(anchor, pointer, true, true)
	var restyled_preview: AtlasFillResult = AtlasRasterBrush.paint(AtlasRasterLayer.paint_layer(),
		restyled_endpoints, restyled_color, restyled_width, false)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == restyled_endpoints
		and canvas._draft_stroke.width == restyled_width and canvas._draft_stroke.color == restyled_color,
		"stationary draft adopts inspector style without requiring pointer motion")
	_check(restyled_preview.ok and canvas._preview_layer != null
		and canvas._preview_layer.to_dict() == restyled_preview.layer.to_dict()
		and canvas._preview_layer.to_dict() != before_style,
		"detached raster preview repaints with new color and width before release")
	_button(canvas, pointer, false, true, true)
	_check(restyled_preview.ok and canvas.floor.raster_layer().to_dict() == restyled_preview.layer.to_dict(),
		"committed Line exactly matches its restyled stationary preview")
	_check(editor.edits.undo(), "restyled line is undoable once")
	_check(canvas.floor.raster_layer().chunks.is_empty(), "restyled line undo restores blank pixels")

	# Raster-first Line creates pixels at the selected authored detail rather
	# than writing an editable stroke object or modifying a different D-level.
	_check(canvas.set_presented_detail_level(1), "present D1 for Line")
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	var detail_layer: AtlasRasterLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasRasterLayer
	_check(detail_layer != null and detail_layer.detail_level == 1 and detail_layer.pixels_per_unit == 4.0,
		"Line routing creates a paint-density D1 raster target")
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	await process_frame
	var detail_expected: AtlasFillResult = AtlasRasterBrush.paint(detail_layer, PackedVector2Array([anchor, pointer]),
		restyled_color, restyled_width, false)
	_check(detail_expected.ok and canvas._preview_layer != null
		and canvas._preview_layer.to_dict() == detail_expected.layer.to_dict(),
		"D1 Line draft paints its isolated raster target")
	_button(canvas, pointer, false)
	_check(detail_expected.ok and canvas.floor.layer_by_id(detail_layer.id).to_dict() == detail_expected.layer.to_dict(),
		"D1 release matches preview in the selected authored detail")
	_check(canvas.floor.raster_layer().chunks.is_empty(), "D1 Line does not modify D0")
	_check(editor.edits.undo(), "D1 Line is one undo command")
	_check(canvas.floor.layer_by_id(detail_layer.id).to_dict() == detail_layer.to_dict(),
		"D1 undo restores that layer's original pixels")
	_check(canvas.set_presented_detail_level(0), "return to D0 Line")
	editor._choose_tool(AtlasCanvas.Tool.LINE)
	_check(canvas.active_layer_id == ink_id, "Line route selects the existing D0 raster")

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
	_check(_matches(canvas, expected_snapped), "snapped preview equals stored pixels")
	_check(editor.edits.undo(), "snapped line undo")

	# Active layer, presentation, and edit-mask rules remain command-owned.
	canvas.floor.raster_layer().locked = true
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "locked layer rejects line")
	canvas.floor.raster_layer().locked = false
	_check(canvas.set_presented_detail_level(1), "switch to absent authored detail")
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "hidden detail rejects line")
	_check(canvas.set_presented_detail_level(0), "restore visible detail")
	editor.inspector.snap_checkbox.button_pressed = false
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(500, 500)
	editor._on_scope_toggled(true)
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	_button(canvas, pointer, false)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "masked outside-area line cannot be committed")
	# A mid-drag cell change must not reuse pixels previewed under the previous
	# cell mask. Unlike a valid Line, rejection creates no undo entry.
	var active_cell: Vector2i = canvas.map.grid.document_to_cell(canvas.camera_center)
	var masked_center: Vector2 = canvas.map.grid.cell_to_document(active_cell)
	var masked_start: Vector2 = masked_center - Vector2(4.0, 0.0)
	var masked_finish: Vector2 = masked_center + Vector2(4.0, 0.0)
	canvas.selected_cell = active_cell
	canvas.has_selected_cell = true
	editor.artwork.refresh_scope()
	var pixels_before: Dictionary = canvas.floor.raster_layer().to_dict()
	var undo_before: int = editor.edits._cursor
	_button(canvas, masked_start, true)
	_motion(canvas, masked_finish)
	await process_frame
	_check(canvas._preview_layer != null and canvas._preview_layer.to_dict() != pixels_before,
		"masked Line preview draws eligible pixels before release")
	editor._on_select(active_cell + Vector2i(3, 0))
	_button(canvas, masked_finish, false)
	_check(canvas.floor.raster_layer().to_dict() == pixels_before
		and editor.edits._cursor == undo_before,
		"changed selected cell rejects stale Line without pixels or history")
	_check(not canvas.is_editing() and canvas._preview_layer == null
		and "edit mask changed" in editor.status_label.text,
		"rejected Line clears its preview and explains the mask conflict")

	# An unchanged authorized mask still paints. A changed selected cell while
	# masking is OFF must not invalidate a valid freehand Line.
	editor._on_select(active_cell)
	_button(canvas, masked_start, true)
	_motion(canvas, masked_finish)
	_button(canvas, masked_finish, false)
	_check(canvas.floor.raster_layer().to_dict() != pixels_before
		and editor.edits._cursor == undo_before + 1,
		"fresh Line in restored cell commits exactly once")
	_check(editor.edits.undo(), "masked Line can be undone")
	_check(canvas.floor.raster_layer().to_dict() == pixels_before,
		"masked Line undo restores source pixels")
	editor._on_scope_toggled(false)
	_button(canvas, anchor, true)
	_motion(canvas, pointer)
	editor._on_select(active_cell + Vector2i(5, 5))
	_button(canvas, pointer, false)
	_check(not canvas.floor.raster_layer().chunks.is_empty(),
		"cell selection with masking disabled does not block a Line")
	var saved: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._on_save()
	var portable: AtlasStoreResult = AtlasCampaignStore.load_portable_result(editor.save_path)
	var loaded: AtlasCampaign = portable.campaign
	_check(editor.status_label.text.contains("Saved generation") and portable.error == OK
		and portable.generation != "" and loaded != null and loaded.to_dict() == saved,
		"portable campaign generation roundtrip preserves line and exact raster bytes")
	_check(FileAccess.file_exists(AtlasCampaignBundle.root_path(ProjectSettings.globalize_path(editor.save_path)))
		and not FileAccess.file_exists(ProjectSettings.globalize_path(editor.save_path)),
		"Save writes a portable generation, never a legacy native head")
	_check(editor.edits.undo() and editor.campaign.to_dict() != saved
		and loaded != null and loaded.to_dict() == saved,
		"a later Undo cannot mutate the published portable generation")
	root.remove_child(scene)
	scene.free()
	_remove(folder)
	print("ATLAS_LINE_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)


func _matches(canvas: AtlasCanvas, endpoints: PackedVector2Array) -> bool:
	var expected: AtlasFillResult = AtlasRasterBrush.paint(AtlasRasterLayer.paint_layer(), endpoints,
		canvas.brush_color, canvas.brush_width, false)
	return expected.ok and expected.layer.to_dict() == canvas.floor.raster_layer().to_dict()


func _remove(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	DirAccess.remove_absolute(path)
