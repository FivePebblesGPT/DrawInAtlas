extends SceneTree
## A polygon's first-vertex authorization must still belong to the registered
## campaign/map/floor graph at closure, even when Canvas keeps the same pointers.

var checks: int = 0
var failures: int = 0
var strokes: int = 0
var rejections: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T114_POLYGON_FAILED: " + description)


func _mouse(canvas: AtlasCanvas, point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = canvas.document_to_local(point)
	canvas._gui_input(event)


func _vertex(canvas: AtlasCanvas, point: Vector2) -> void:
	_mouse(canvas, point, true)
	_mouse(canvas, point, false)


func _on_stroke(_shape: AtlasStroke, _erasing: bool) -> void:
	strokes += 1


func _on_rejected(_reason: String) -> void:
	rejections += 1


func _case(change: String) -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-114 " + change, AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)),
		change + ": create board")
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	var canvas: AtlasCanvas = editor.canvas
	canvas.stroke_requested.connect(_on_stroke)
	canvas.polygon_rejected.connect(_on_rejected)
	canvas.snap_to_grid = false
	canvas.brush_width = 6.0
	canvas.camera_center = Vector2(30, 25)
	canvas.camera_zoom = 1.5
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var target: AtlasRasterLayer = original_floor.layer_by_id(canvas.active_layer_id) as AtlasRasterLayer
	var floor_index: int = original_map.floors.find(original_floor)
	_check(target != null and target.is_editable() and floor_index >= 0
		and editor.campaign.get_map(original_map.id) == original_map
		and original_map.floor_by_id(original_floor.id) == original_floor,
		change + ": source is a registered editable target")
	if target == null:
		root.remove_child(scene)
		scene.free()
		return
	var start: Vector2 = canvas.camera_center
	for point: Vector2 in [start + Vector2(-22, -17), start + Vector2(30, -17),
			start + Vector2(4, 25)]:
		_vertex(canvas, point)
	var before: Dictionary = original_floor.to_dict()
	var cursor_before: int = editor.edits._cursor
	var strokes_before: int = strokes
	var rejected_before: int = rejections
	_check(canvas._polygon_vertices.size() == 3 and canvas._draft_stroke != null
		and canvas._polygon_context_matches() and original_floor.to_dict() == before,
		change + ": three vertices stage only a detached preview")
	match change:
		"registered_map_replaced":
			var clone_map: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
			_check(clone_map != null and clone_map != original_map
				and clone_map.to_dict() == original_map.to_dict(),
				"replaced map has same ID and bytes")
			editor.campaign.add_map(clone_map)
		"registered_map_removed":
			editor.campaign.maps.erase(original_map.id)
		"registered_floor_replaced":
			var clone_floor: AtlasFloor = AtlasFloor.from_dict(original_floor.to_dict())
			_check(clone_floor != null and clone_floor != original_floor
				and clone_floor.to_dict() == original_floor.to_dict(),
				"replaced floor has same ID and bytes")
			original_map.floors[floor_index] = clone_floor
		"registered_floor_removed":
			original_map.floors.remove_at(floor_index)
		"campaign_owner_replaced":
			var other_campaign: AtlasCampaign = AtlasCampaign.new()
			other_campaign.add_map(original_map)
			canvas.campaign = other_campaign
	_check(not canvas._polygon_context_matches(),
		change + ": detached ownership invalidates first-vertex authorization")
	canvas.commit_edit()
	_check(strokes == strokes_before and rejections == rejected_before + 1,
		change + ": no stroke emitted and one rejection signaled")
	_check(not canvas.is_editing() and canvas._preview_layer == null
		and canvas._polygon_scope_at_start == null,
		change + ": rejected draft clears all captured state")
	_check(editor.edits._cursor == cursor_before and original_floor.to_dict() == before,
		change + ": no history entry or source-byte mutation")
	root.remove_child(scene)
	scene.free()


func _valid_case() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-114 valid", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)),
		"valid: create board")
	editor._choose_tool(AtlasCanvas.Tool.POLYGON)
	var canvas: AtlasCanvas = editor.canvas
	canvas.stroke_requested.connect(_on_stroke)
	canvas.polygon_rejected.connect(_on_rejected)
	canvas.snap_to_grid = false
	canvas.camera_center = Vector2(30, 25)
	canvas.camera_zoom = 1.5
	var points: Array[Vector2] = [canvas.camera_center + Vector2(-23, -14),
		canvas.camera_center + Vector2(28, -14), canvas.camera_center + Vector2(1, 27)]
	for point: Vector2 in points:
		_vertex(canvas, point)
	var before: Dictionary = canvas.floor.raster_layer().to_dict()
	var before_cursor: int = editor.edits._cursor
	var strokes_before: int = strokes
	var rejected_before: int = rejections
	_check(canvas._polygon_context_matches(), "valid: registered Polygon remains authorized")
	var other_map: AtlasMapDocument = AtlasMapDocument.new("unrelated-map", "Other board")
	editor.campaign.add_map(other_map)
	_check(canvas._polygon_context_matches(),
		"valid: an unrelated registered map does not invalidate a live draft")
	canvas.commit_edit()
	var painted: Dictionary = canvas.floor.raster_layer().to_dict()
	_check(strokes == strokes_before + 1 and rejections == rejected_before
		and editor.edits._cursor == before_cursor + 1 and painted != before,
		"valid: one raster commit with one history command")
	_check(editor.edits.undo() and canvas.floor.raster_layer().to_dict() == before,
		"valid: Undo restores exact source pixels")
	_check(editor.edits.redo() and canvas.floor.raster_layer().to_dict() == painted,
		"valid: Redo restores exact painted pixels")
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	for change: String in ["registered_map_replaced", "registered_map_removed",
			"registered_floor_replaced", "registered_floor_removed", "campaign_owner_replaced"]:
		await _case(change)
	await _valid_case()
	print("T114_POLYGON_%s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
