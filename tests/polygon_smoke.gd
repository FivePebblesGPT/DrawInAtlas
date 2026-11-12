extends SceneTree
## T-025/T-112: polygon gestures, protections and portable-generation persistence.

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
	_check(canvas.floor.raster_layer() != null and editor.inspector.polygon_fill_checkbox.visible, "polygon picker and inspector controls")
	canvas.camera_center = Vector2(30, 25)
	canvas.camera_zoom = 1.5
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_check(canvas.is_editing() and canvas.floor.raster_layer().chunks.is_empty(), "multiple clicks leave source unchanged")
	_check(canvas._draft_stroke != null or canvas._polygon_vertices.size() == 3, "draft is held outside history")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = canvas.document_to_local(Vector2(70, 60))
	canvas._gui_input(motion)
	_check(canvas._draft_stroke != null and canvas._draft_stroke.points == AtlasShapes.polygon(triangle, canvas.brush_color, canvas.brush_width, false).points,
		"pending fourth vertex never changes the Enter-to-commit preview")
	canvas._process(0.0)
	var old_preview: Dictionary = canvas._preview_layer.to_dict() if canvas._preview_layer != null else {}
	var restyled_color: Color = Color(0.15, 0.85, 0.35, 0.8)
	var restyled_width: float = 15.0
	# Inspector events must repaint a fixed polygon without adding a fourth vertex.
	editor.inspector.brush_width_spinner.value = restyled_width
	editor.inspector.brush_color_changed.emit(restyled_color)
	_check(canvas._polygon_vertices == triangle and canvas._draft_stroke != null and
		canvas._draft_stroke.color == restyled_color and canvas._draft_stroke.width == restyled_width,
		"stationary outline draft follows live color and width")
	canvas._process(0.0)
	var outline_expected: AtlasFillResult = AtlasRasterBrush.paint_stroke(
		AtlasRasterLayer.paint_layer(), AtlasShapes.polygon(triangle, restyled_color, restyled_width, false))
	_check(outline_expected.ok and canvas._preview_layer != null and
		canvas._preview_layer.to_dict() == outline_expected.layer.to_dict(),
		"outline preview repaints exact styled pixels without pointer motion")
	_check(canvas._preview_layer.to_dict() != old_preview and canvas.floor.raster_layer().chunks.is_empty(),
		"restyling changes only detached preview, not artwork")
	_key(canvas, KEY_ENTER)
	_check(not canvas.is_editing() and not canvas.floor.raster_layer().chunks.is_empty(), "Enter commits raster polygon")
	_check(_matches(canvas, triangle, false), "restyled outline pixels persisted")
	_check(editor.edits.undo() and canvas.floor.raster_layer().chunks.is_empty(), "outline is one undo")
	_check(editor.edits.redo() and not canvas.floor.raster_layer().chunks.is_empty(), "outline redo")
	_check(editor.edits.undo(), "clear before next test")

	# Fill style is live as well, and must leave exactly the fixed vertices.
	editor.inspector.polygon_fill_checkbox.button_pressed = true
	_check(canvas.polygon_solid_fill, "inspector fill mode connects to input")
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	canvas._process(0.0)
	var fill_before: Dictionary = canvas._preview_layer.to_dict() if canvas._preview_layer != null else {}
	var fill_color: Color = Color(0.8, 0.25, 0.8, 0.65)
	editor.inspector.brush_color_changed.emit(fill_color)
	canvas._process(0.0)
	var fill_expected: AtlasFillResult = AtlasRasterBrush.paint_stroke(
		AtlasRasterLayer.paint_layer(), AtlasShapes.polygon(triangle, fill_color, restyled_width, true))
	_check(canvas._polygon_vertices == triangle and canvas._draft_stroke != null and canvas._draft_stroke.filled,
		"stationary filled polygon retains fixed vertices and fill mode")
	_check(fill_expected.ok and canvas._preview_layer != null and canvas._preview_layer.to_dict() == fill_expected.layer.to_dict(),
		"filled preview repaints exact live color before close")
	_check(canvas._preview_layer.to_dict() != fill_before, "filled preview no longer shows the old color")
	_mouse(canvas, triangle[0], true)
	_mouse(canvas, triangle[0], false)
	_check(_matches(canvas, triangle, true) and not canvas.is_editing(), "close by first vertex paints solid raster")
	_check(canvas.floor.objects_layer().strokes.is_empty(), "polygon does not create an editable object")
	var saved: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._on_save()
	var portable: AtlasStoreResult = AtlasCampaignStore.load_portable_result(editor.save_path)
	var loaded: AtlasCampaign = portable.campaign
	_check(editor.status_label.text.contains("Saved generation") and portable.error == OK
		and portable.generation != "" and loaded != null and loaded.to_dict() == saved,
		"filled polygon portable generation round-trip retains exact raster bytes")
	_check(FileAccess.file_exists(AtlasCampaignBundle.root_path(ProjectSettings.globalize_path(editor.save_path)))
		and not FileAccess.file_exists(ProjectSettings.globalize_path(editor.save_path)),
		"Save creates a portable generation rather than a legacy native head")
	var stored: AtlasRasterLayer = loaded.get_map(canvas.map.id).floor_by_id(canvas.floor.id).raster_layer() if loaded != null else null
	_check(stored != null and stored.to_dict() == canvas.floor.raster_layer().to_dict(), "portable generation keeps exact filled pixels")
	_check(editor.edits.undo() and canvas.floor.raster_layer().chunks.is_empty(), "filled polygon one undo")
	_check(loaded != null and loaded.to_dict() == saved,
		"Undo after Save leaves published polygon generation immutable")

	# Esc, Backspace and failed geometry produce no partial history commands.
	_vertex(canvas, triangle[0])
	_vertex(canvas, triangle[1])
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "invalid two-point shape cannot commit")
	_vertex(canvas, triangle[0])
	_vertex(canvas, triangle[1]); _vertex(canvas, triangle[2])
	_key(canvas, KEY_BACKSPACE)
	_check(canvas._polygon_vertices.size() == 2, "Backspace removes last vertex")
	_key(canvas, KEY_ESCAPE)
	_check(not canvas.is_editing() and canvas.floor.raster_layer().chunks.is_empty(), "Escape cancels without mutation")

	canvas.floor.raster_layer().locked = true
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "locked target blocks every vertex")
	canvas.floor.raster_layer().locked = false
	_check(canvas.set_presented_detail_level(1), "hide editing detail")
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "hidden detail blocks polygons")
	_check(canvas.set_presented_detail_level(0), "show editing detail")

	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i(100, 100)
	editor._on_scope_toggled(true)
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().chunks.is_empty(), "cell mask rejects filled polygon outside mask")
	# T-025: a multi-click Polygon may only close in the scope where its
	# first vertex was placed. No later cell selection may retarget its fill.
	var active_cell: Vector2i = Vector2i(2, 2)
	editor._on_select(active_cell)
	var masked_center: Vector2 = canvas.map.grid.cell_to_document(active_cell)
	var masked_triangle: PackedVector2Array = PackedVector2Array([
		masked_center + Vector2(-8, -8), masked_center + Vector2(8, -8),
		masked_center + Vector2(0, 7)])
	var before_masked: Dictionary = canvas.floor.raster_layer().to_dict()
	var before_history: int = editor.edits._cursor
	for point: Vector2 in masked_triangle:
		_vertex(canvas, point)
	canvas._process(0.0)
	_check(canvas._preview_layer != null and canvas._polygon_scope_at_start != null
		and canvas._polygon_scope_at_start.enabled, "Polygon preview records its first selected-cell mask")
	editor._on_select(active_cell + Vector2i(3, 0))
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().to_dict() == before_masked and editor.edits._cursor == before_history,
		"changed cell rejects Polygon without raster or undo mutation")
	_check(not canvas.is_editing() and canvas._preview_layer == null
		and canvas._polygon_scope_at_start == null and "edit mask changed" in editor.status_label.text,
		"rejected Polygon clears preview and reports changed mask")

	# Changing eligibility between vertex clicks must reject the entire draft,
	# not silently accept the next vertex under a new selection.
	editor._on_select(active_cell)
	_vertex(canvas, masked_triangle[0]); _vertex(canvas, masked_triangle[1])
	editor._on_select(active_cell + Vector2i(1, 0))
	_vertex(canvas, masked_triangle[2])
	_check(not canvas.is_editing() and canvas.floor.raster_layer().to_dict() == before_masked
		and editor.edits._cursor == before_history, "stale next vertex cancels the Polygon atomically")

	# Same selected cell, different rotated-grid polygon is a different mask.
	editor._on_select(active_cell)
	for point: Vector2 in masked_triangle:
		_vertex(canvas, point)
	var original_rotation: float = canvas.map.grid.rotation
	canvas.map.grid.rotation += deg_to_rad(17.0)
	editor.artwork.refresh_scope()
	_key(canvas, KEY_ENTER)
	_check(not canvas.is_editing() and canvas.floor.raster_layer().to_dict() == before_masked
		and editor.edits._cursor == before_history, "rotated edit-mask rejects pending Polygon")
	canvas.map.grid.rotation = original_rotation
	editor.artwork.refresh_scope()

	# An active-layer switch outside the tool also must not redirect the draft.
	for point: Vector2 in masked_triangle:
		_vertex(canvas, point)
	var raster_id: String = canvas.active_layer_id
	canvas.active_layer_id = canvas.floor.objects_layer().id
	_key(canvas, KEY_ENTER)
	_check(not canvas.is_editing() and canvas.floor.raster_layer().to_dict() == before_masked
		and editor.edits._cursor == before_history, "changed layer rejects pending Polygon")
	canvas.active_layer_id = raster_id

	# A new gesture with a current, unchanged mask still commits once.
	for point: Vector2 in masked_triangle:
		_vertex(canvas, point)
	canvas._process(0.0)
	var authorized_preview: Dictionary = canvas._preview_layer.to_dict() if canvas._preview_layer != null else {}
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().to_dict() == authorized_preview
		and canvas.floor.raster_layer().to_dict() != before_masked
		and editor.edits._cursor == before_history + 1, "fresh Polygon commits only authorized preview pixels")
	_check(editor.edits.undo() and canvas.floor.raster_layer().to_dict() == before_masked,
		"masked Polygon undo restores unchanged source")

	editor._on_scope_toggled(false)
	# Changing the highlighted cell while masking is OFF is not a veto.
	for point: Vector2 in masked_triangle:
		_vertex(canvas, point)
	editor._on_select(active_cell + Vector2i(5, 5))
	_key(canvas, KEY_ENTER)
	_check(canvas.floor.raster_layer().to_dict() != before_masked
		and editor.edits._cursor == before_history + 1,
		"unlocked cell selection does not reject an unmasked Polygon")
	_check(editor.edits.undo() and canvas.floor.raster_layer().to_dict() == before_masked,
		"unmasked Polygon undo restores source")
	# Clicking twice on final vertex should not create a duplicate invalid edge.
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	_mouse(canvas, triangle[2], true, true)
	_check(_matches(canvas, triangle, true), "double click finishes without duplicated vertex")
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
	_check(_matches(canvas, snapped, true), "snapped polygon pixels match authored vertices")
	_check(editor.edits.undo(), "snapped polygon undo")

	# A first polygon on another authored detail uses a separate raster target.
	_check(canvas.set_presented_detail_level(1), "present D1 for Polygon")
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	var detail_raster: AtlasRasterLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasRasterLayer
	_check(detail_raster != null and detail_raster.detail_level == 1 and detail_raster.pixels_per_unit == 4.0,
		"Polygon routing selects a paint-density D1 raster")
	for point: Vector2 in triangle:
		_vertex(canvas, point)
	canvas._process(0.0)
	var detail_expected: AtlasFillResult = AtlasRasterBrush.paint_stroke(detail_raster,
		AtlasShapes.polygon(triangle, canvas.brush_color, canvas.brush_width, true))
	_check(detail_expected.ok and canvas._preview_layer != null and
		canvas._preview_layer.to_dict() == detail_expected.layer.to_dict(),
		"D1 Polygon preview paints only the selected detail raster")
	_key(canvas, KEY_ENTER)
	_check(detail_expected.ok and canvas.floor.layer_by_id(detail_raster.id).to_dict() == detail_expected.layer.to_dict(),
		"D1 polygon commit equals isolated preview")
	_check(canvas.floor.raster_layer().chunks.is_empty(), "D1 polygon leaves D0 pixels unchanged")
	_check(editor.edits.undo() and canvas.floor.layer_by_id(detail_raster.id).to_dict() == detail_raster.to_dict(),
		"D1 polygon undo restores its original target")

	root.remove_child(scene)
	scene.free()
	_remove(folder)
	print("ATLAS_POLYGON_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(1 if failures > 0 else 0)


func _matches(canvas: AtlasCanvas, vertices: PackedVector2Array, filled: bool) -> bool:
	var shape: AtlasStroke = AtlasShapes.polygon(vertices, canvas.brush_color, canvas.brush_width, filled)
	var expected: AtlasFillResult = AtlasRasterBrush.paint_stroke(AtlasRasterLayer.paint_layer(), shape)
	return expected.ok and expected.layer.to_dict() == canvas.floor.raster_layer().to_dict()


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
