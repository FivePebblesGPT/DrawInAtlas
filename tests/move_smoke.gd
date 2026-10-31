extends SceneTree
## T-022: lossless active-layer movement through real canvas gestures.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("MOVE FAILED: " + label)


func _button(canvas: AtlasCanvas, point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = canvas.document_to_local(point)
	event.pressed = down
	canvas._gui_input(event)


func _motion(canvas: AtlasCanvas, point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.document_to_local(point)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


func _drag(canvas: AtlasCanvas, start: Vector2, finish: Vector2) -> void:
	_button(canvas, start, true)
	_motion(canvas, finish)
	_button(canvas, finish, false)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	var directory: String = "user://move-%d" % Time.get_ticks_usec()
	editor.save_path = directory + "/campaign.scn"
	root.add_child(scene)
	for frame: int in range(8):
		await process_frame
	_check(editor.create_board("Move board", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 50)), "create board")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	var canvas: AtlasCanvas = editor.canvas
	var ink_id: String = canvas.active_layer_id
	var a: Vector2 = canvas.camera_center - Vector2(35, 12)
	var b: Vector2 = a + Vector2(140, 0)
	for start: Vector2 in [a, b]:
		editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([start, start + Vector2(18, 0)]), Color.WHITE, 4), false)
	var ink: AtlasInkLayer = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	var original: Dictionary = ink.to_dict().duplicate(true)
	_check(ink.strokes.size() == 2, "separate ink objects")
	editor._choose_tool(AtlasCanvas.Tool.MOVE)
	_check(canvas.tool == AtlasCanvas.Tool.MOVE and editor.tool_palette.button_for(AtlasCanvas.Tool.MOVE).button_pressed,
		"Move palette and canvas synchronize")
	_check(editor.inspector.get_node("%SelectionSection").visible and editor.inspector.snap_checkbox.visible,
		"Move shows selection settings and snapping")
	_button(canvas, a + Vector2(8, 0), true)
	_check(canvas.selection.stroke_indices == [0] and canvas.is_editing(), "pointer picks first active-layer stroke")
	_motion(canvas, a + Vector2(24, 16))
	_check(canvas._preview_layer != null and (canvas._preview_layer as AtlasInkLayer).strokes[0].points[0] == a + Vector2(16, 16),
		"live ink preview matches unsnapped displacement")
	_check(ink.to_dict() == original, "preview does not mutate source")
	_button(canvas, a + Vector2(24, 16), false)
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes[0].points[0] == a + Vector2(16, 16) and ink.strokes[1].points[0] == b,
		"release commits only hit object")
	_check(editor.edits.undo(), "single undo for moved object")
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.to_dict() == original, "undo restores exact vectors and width")
	_check(editor.edits.redo(), "single redo for moved object")
	_check(editor.edits.undo(), "restore for remaining checks")

	# V selection transfers to M without discarding selected ink objects.
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0, 1])
	canvas.selection_changed.emit()
	editor._choose_tool(AtlasCanvas.Tool.MOVE)
	_check(canvas.selection.stroke_indices == [0, 1], "switch from select to move retains multi-object selection")
	_drag(canvas, a + Vector2(8, 0), a + Vector2(14, -11))
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes[0].points[0] == a + Vector2(6, -11) and ink.strokes[1].points[0] == b + Vector2(6, -11),
		"move selected objects together")
	_check(editor.edits.undo(), "multi-object move undo")
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.to_dict() == original, "group move undo restores exact source")
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0])
	canvas.selection_changed.emit()
	_button(canvas, a + Vector2(8, 0), true)
	_motion(canvas, a + Vector2(44, 26))
	_check(canvas._preview_layer != null, "drag previews before cancellation")
	canvas.cancel_edit()
	_button(canvas, a + Vector2(44, 26), false)
	_check(ink.to_dict() == original and canvas.selection.stroke_indices == [0], "Escape/cancel retains selection and source")
	_drag(canvas, canvas.camera_center + Vector2(110, 80), canvas.camera_center + Vector2(180, 80))
	_check(canvas.selection.is_empty() and ink.to_dict() == original, "empty board does not move or mutate")
	ink.locked = true
	var locked_snapshot: Dictionary = ink.to_dict().duplicate(true)
	_drag(canvas, a + Vector2(8, 0), a + Vector2(24, 16))
	_check(ink.to_dict() == locked_snapshot and not canvas.is_editing(), "locked ink can be selected but cannot move")
	ink.locked = false

	# Mask restrictions are checked in the preview and again by the command.
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0])
	editor._on_select(canvas.map.grid.document_to_cell(a))
	editor._on_scope_toggled(true)
	_button(canvas, a + Vector2(8, 0), true)
	_motion(canvas, a + Vector2(600, 0))
	_check(canvas._preview_layer == null, "edit mask rejects destination preview")
	_button(canvas, a + Vector2(600, 0), false)
	_check(ink.to_dict() == original, "masked movement cannot reach history")
	editor._on_scope_toggled(false)
	_check(canvas.set_presented_detail_level(1), "switch presentation away from editing target")
	_drag(canvas, a + Vector2(8, 0), a + Vector2(34, 12))
	_check(ink.to_dict() == original and not canvas.is_editing(), "hidden authored detail cannot be moved")
	_check(canvas.set_presented_detail_level(0), "restore presented editing detail")

	# Snapping is a cell-to-cell delta even with a rotated hex overlay.
	var rotated: AtlasGrid = canvas.map.grid.copy()
	rotated.kind = AtlasGrid.Kind.HEX_POINTY
	rotated.rotation = deg_to_rad(27.0)
	rotated.origin = Vector2(21, -17)
	editor.apply_grid(rotated)
	editor.inspector.snap_checkbox.button_pressed = true
	_check(canvas.snap_to_grid, "opt-in grid snapping enabled")
	canvas.selection = AtlasSelectionGeometry.select_indices(ink, [0])
	var finish: Vector2 = a + Vector2(75, 89)
	var delta: Vector2 = AtlasGridSnap.move_delta(rotated, a + Vector2(8, 0), finish)
	_button(canvas, a + Vector2(8, 0), true)
	_motion(canvas, finish)
	_check(canvas._preview_layer != null and (canvas._preview_layer as AtlasInkLayer).strokes[0].points[0].distance_to(a + delta) < 0.01,
		"snapped preview honors rotated hex grid")
	_button(canvas, finish, false)
	ink = canvas.floor.layer_by_id(ink_id) as AtlasInkLayer
	_check(ink.strokes[0].points[0].distance_to(a + delta) < 0.01, "snapped commit matches preview")
	_check(editor.edits.undo(), "snapped move undo")

	# Whole raster layer movement composes its affine transform; pixels are never resampled.
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.7, 0.2, 0.8, 0.6))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	raster.id = "move-raster"
	raster.transform = Transform2D(Vector2(1.0, 0.25), Vector2(-0.2, 1.0), a + Vector2(-5, -5))
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	layers.append(raster)
	_check(editor.apply_layers(layers, raster.id), "create raster layer")
	editor.select_layer(raster.id)
	editor._choose_tool(AtlasCanvas.Tool.MOVE)
	var raster_before: Dictionary = (canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer).to_dict().duplicate(true)
	var pick: Vector2 = raster.transform * Vector2(4, 4)
	var raster_finish: Vector2 = pick + Vector2(60, -27)
	var raster_delta: Vector2 = AtlasGridSnap.move_delta(rotated, pick, raster_finish)
	_drag(canvas, pick, raster_finish)
	var moved: AtlasRasterLayer = canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer
	_check(moved.transform.origin.distance_to(raster.transform.origin + raster_delta) < 0.01, "raster moves by board-space delta")
	_check(moved.transform.x == raster.transform.x and moved.transform.y == raster.transform.y and moved.chunks.keys() == raster.chunks.keys(),
		"raster affine basis and chunk ownership preserved")
	_check(editor.edits.undo(), "raster move undo")
	moved = canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer
	_check(moved.to_dict() == raster_before, "raster undo restores exact pixels and transform")
	_check(editor.edits.redo(), "raster redo")
	var saved: Dictionary = editor.campaign.to_dict()
	editor._on_save()
	var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(editor.save_path)
	_check(loaded != null and loaded.to_dict() == saved, "native save roundtrip keeps moved raster and ink")
	_check(canvas.map.floors[0].layer_by_id(ink_id) != null and canvas.floor.layer_by_id(raster.id) != null,
		"move does not create containers or change active document")
	root.remove_child(scene)
	scene.free()
	_remove(directory)
	print("ATLAS_MOVE_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)


func _remove(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	DirAccess.remove_absolute(path)
