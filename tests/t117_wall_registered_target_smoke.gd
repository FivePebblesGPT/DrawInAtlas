extends SceneTree
## An unfinished editable Wall Path (including vertex drags) must still belong
## to the original registered campaign/map/floor when it publishes a command.

var checks: int = 0
var failures: int = 0
var commands: int = 0
var rejections: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T117_WALL_FAILED: " + description)


func _mouse(canvas: AtlasCanvas, point: Vector2, down: bool, shift: bool = false, alt: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.shift_pressed = shift
	event.alt_pressed = alt
	event.position = canvas.document_to_local(point)
	canvas._gui_input(event)


func _vertex(canvas: AtlasCanvas, point: Vector2, shift: bool = false, alt: bool = false) -> void:
	_mouse(canvas, point, true, shift, alt)
	_mouse(canvas, point, false, shift, alt)


func _on_command(_index: int, _expected: AtlasStroke, _replacement: AtlasStroke) -> void:
	commands += 1


func _on_rejected(_reason: String) -> void:
	rejections += 1


func _scene(case_name: String) -> Dictionary:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-117 " + case_name, AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)),
		case_name + ": board created")
	editor.layer_panel.auto_detail_checkbox.button_pressed = false
	editor._choose_tool(AtlasCanvas.Tool.WALL_PATH)
	var canvas: AtlasCanvas = editor.canvas
	canvas.path_edit_requested.connect(_on_command)
	canvas.wall_rejected.connect(_on_rejected)
	canvas.snap_to_grid = false
	canvas.camera_zoom = 1.5
	canvas.camera_center = Vector2(32, 25)
	return {"scene": scene, "editor": editor, "canvas": canvas}


func _detach(change: String, editor: AtlasEditor, canvas: AtlasCanvas,
		original_map: AtlasMapDocument, original_floor: AtlasFloor) -> void:
	match change:
		"registered_map_replaced":
			var clone_map: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
			_check(clone_map != null and clone_map != original_map
				and clone_map.to_dict() == original_map.to_dict(),
				change + ": same-ID/byte replacement map")
			editor.campaign.add_map(clone_map)
		"registered_map_removed":
			editor.campaign.maps.erase(original_map.id)
		"registered_floor_replaced":
			var clone_floor: AtlasFloor = AtlasFloor.from_dict(original_floor.to_dict())
			_check(clone_floor != null and clone_floor != original_floor
				and clone_floor.to_dict() == original_floor.to_dict(),
				change + ": same-ID/byte replacement floor")
			var index: int = original_map.floors.find(original_floor)
			original_map.floors[index] = clone_floor
		"registered_floor_removed":
			original_map.floors.erase(original_floor)
		"campaign_owner_replaced":
			var replacement: AtlasCampaign = AtlasCampaign.new()
			replacement.add_map(original_map)
			canvas.campaign = replacement


func _case(change: String, drag: bool) -> void:
	var title: String = ("drag " if drag else "draft ") + change
	var context: Dictionary = await _scene(title)
	var scene: Node = context["scene"]
	var editor: AtlasEditor = context["editor"]
	var canvas: AtlasCanvas = context["canvas"]
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var layer: AtlasObjectsLayer = original_floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	_check(layer != null and layer.is_editable()
		and editor.campaign.get_map(original_map.id) == original_map
		and original_map.floor_by_id(original_floor.id) == original_floor,
		title + ": source registered and editable")
	if layer == null:
		root.remove_child(scene)
		scene.free()
		return
	var first: Vector2 = Vector2(5, 8)
	var second: Vector2 = Vector2(65, 8)
	var third: Vector2 = Vector2(65, 60)
	if drag:
		for point: Vector2 in [first, second, third]:
			_vertex(canvas, point)
		canvas.commit_edit()
		_check(layer.strokes.size() == 1 and layer.strokes[0].editable_path,
			title + ": source path created")
		_mouse(canvas, second, true)
		_check(canvas._wall_drag_vertex == 1 and canvas._wall_preview != null,
			title + ": vertex drag stages an isolated preview")
	else:
		_vertex(canvas, first)
		_vertex(canvas, second)
		_check(canvas._wall_vertices.size() == 2 and canvas._wall_draft != null,
			title + ": two draft vertices are unpublished")
	var source_before: Dictionary = original_floor.to_dict().duplicate(true)
	var cursor_before: int = editor.edits._cursor
	var commands_before: int = commands
	var rejections_before: int = rejections
	_check(canvas._wall_context_matches(), title + ": original owner is valid")
	_detach(change, editor, canvas, original_map, original_floor)
	_check(not canvas._wall_context_matches(),
		title + ": detached registration must invalidate captured authorization")
	if drag:
		_mouse(canvas, second + Vector2(12, 12), false)
	else:
		canvas.commit_edit()
	_check(commands == commands_before and rejections == rejections_before + 1,
		title + ": release rejected without a path command")
	_check(not canvas.is_editing() and canvas._wall_vertices.is_empty()
		and canvas._wall_draft == null and canvas._wall_preview == null
		and canvas._wall_drag_vertex == -1 and canvas._wall_scope_at_start == null,
		title + ": rejection clears draft and ownership references")
	_check(editor.edits._cursor == cursor_before and original_floor.to_dict() == source_before,
		title + ": no new history or source mutation")
	root.remove_child(scene)
	scene.free()


func _immediate_case(change: String) -> void:
	var context: Dictionary = await _scene("immediate " + change)
	var scene: Node = context["scene"]
	var editor: AtlasEditor = context["editor"]
	var canvas: AtlasCanvas = context["canvas"]
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var layer: AtlasObjectsLayer = original_floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	if layer == null:
		_check(false, change + ": missing editable wall layer")
		root.remove_child(scene)
		scene.free()
		return
	for point: Vector2 in [Vector2(5, 8), Vector2(65, 8), Vector2(65, 60)]:
		_vertex(canvas, point)
	canvas.commit_edit()
	_check(layer.strokes.size() == 1, change + ": original path is committed")
	if layer.strokes.is_empty():
		root.remove_child(scene)
		scene.free()
		return
	var before: Dictionary = original_floor.to_dict().duplicate(true)
	var cursor: int = editor.edits._cursor
	var emitted: int = commands
	_detach(change, editor, canvas, original_map, original_floor)
	_check(not canvas._wall_target_registered(), change + ": detached source not registered")
	_vertex(canvas, Vector2(35, 8), true)
	_vertex(canvas, Vector2(65, 8), false, true)
	canvas._wall_selected_index = 0
	canvas.brush_color = Color.RED
	canvas.restyle_selected_wall()
	_check(commands == emitted and editor.edits._cursor == cursor
		and original_floor.to_dict() == before,
		change + ": insert, delete and restyle cannot target a detached path")
	_check(canvas._wall_vertices.is_empty() and canvas._wall_drag_vertex == -1,
		change + ": unauthorized direct edit leaves no gesture")
	root.remove_child(scene)
	scene.free()


func _valid() -> void:
	var context: Dictionary = await _scene("valid")
	var scene: Node = context["scene"]
	var editor: AtlasEditor = context["editor"]
	var canvas: AtlasCanvas = context["canvas"]
	var layer: AtlasObjectsLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	if layer == null:
		_check(false, "valid: missing Objects layer")
		root.remove_child(scene)
		scene.free()
		return
	var before: Dictionary = layer.to_dict().duplicate(true)
	var cursor_before: int = editor.edits._cursor
	var commands_before: int = commands
	var rejections_before: int = rejections
	var first: Vector2 = Vector2(5, 8)
	var second: Vector2 = Vector2(65, 8)
	_vertex(canvas, first)
	_vertex(canvas, second)
	var unrelated: AtlasMapDocument = AtlasMapDocument.new("unrelated-wall", "Other")
	editor.campaign.add_map(unrelated)
	_check(canvas._wall_context_matches(),
		"valid: unrelated registered map does not revoke the draft")
	canvas.commit_edit()
	_check(commands == commands_before + 1 and rejections == rejections_before
		and editor.edits._cursor == cursor_before + 1
		and layer.strokes.size() == 1 and layer.strokes[0].editable_path,
		"valid: one open wall and one atomic history command")
	var finished: Dictionary = layer.to_dict().duplicate(true)
	_check(editor.edits.undo() and layer.to_dict() == before,
		"valid: undo restores exact objects bytes")
	_check(editor.edits.redo() and layer.to_dict() == finished,
		"valid: redo restores exact finished wall")
	var current_cursor: int = editor.edits._cursor
	var current_commands: int = commands
	var at_second: Vector2 = layer.strokes[0].points[1]
	_mouse(canvas, at_second, true)
	_check(canvas._wall_drag_vertex == 1 and canvas._wall_context_matches(),
		"valid: registered source permits vertex drag")
	_mouse(canvas, at_second + Vector2(12, 12), false)
	_check(commands == current_commands + 1 and editor.edits._cursor == current_cursor + 1
		and layer.strokes[0].points[1] == at_second + Vector2(12, 12),
		"valid: vertex release commits one new edit")
	_check(editor.edits.undo() and layer.strokes[0].points[1] == at_second,
		"valid: vertex drag undo preserves geometry")
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	for change: String in ["registered_map_replaced", "registered_map_removed",
			"registered_floor_replaced", "registered_floor_removed", "campaign_owner_replaced"]:
		await _case(change, false)
	for change: String in ["registered_map_replaced", "registered_floor_replaced",
			"campaign_owner_replaced"]:
		await _case(change, true)
	for change: String in ["registered_map_replaced", "registered_floor_replaced"]:
		await _immediate_case(change)
	await _valid()
	print("T117_WALL_%s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
