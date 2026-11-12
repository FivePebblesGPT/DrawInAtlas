extends SceneTree
## A Text modal must retain campaign/map/floor registry ownership until Apply.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T115_TEXT_FAILED: " + description)


func _case(change: String) -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-115 " + change, AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)),
		change + ": create board")
	editor.layer_panel._add_objects()
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	var canvas: AtlasCanvas = editor.canvas
	var original_map: AtlasMapDocument = canvas.map
	var original_floor: AtlasFloor = canvas.floor
	var layer: AtlasObjectsLayer = original_floor.layer_by_id(canvas.active_layer_id) as AtlasObjectsLayer
	var floor_index: int = original_map.floors.find(original_floor)
	_check(layer != null and floor_index >= 0 and editor.campaign.get_map(original_map.id) == original_map
		and original_map.floor_by_id(original_floor.id) == original_floor,
		change + ": registered Objects layer is editable")
	if layer == null:
		root.remove_child(scene)
		scene.free()
		return
	editor._open_text_editor(Vector2(32, 40), -1)
	editor.text_editor.text_input.text = "Unpublished text"
	var before: Dictionary = original_floor.to_dict()
	var history: AtlasEditCommand = editor.edits.get_undo_command()
	var cursor_before: int = editor.edits._cursor
	_check(editor.text_editor.visible and layer.strokes.is_empty(),
		change + ": modal owns an uncommitted draft")
	match change:
		"map_replaced":
			var clone_map: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
			_check(clone_map != null and clone_map != original_map and clone_map.to_dict() == original_map.to_dict(),
				change + ": replacement map retains IDs and serialized bytes")
			editor.campaign.add_map(clone_map)
		"map_removed":
			editor.campaign.maps.erase(original_map.id)
		"floor_replaced":
			var clone_floor: AtlasFloor = AtlasFloor.from_dict(original_floor.to_dict())
			_check(clone_floor != null and clone_floor != original_floor and clone_floor.to_dict() == original_floor.to_dict(),
				change + ": replacement floor retains IDs and serialized bytes")
			original_map.floors[floor_index] = clone_floor
		"floor_removed":
			original_map.floors.remove_at(floor_index)
		"canvas_campaign_replaced":
			var other_campaign: AtlasCampaign = AtlasCampaign.new()
			other_campaign.add_map(original_map)
			canvas.campaign = other_campaign
		"editor_campaign_replaced":
			var other_campaign: AtlasCampaign = AtlasCampaign.new()
			other_campaign.add_map(original_map)
			editor.campaign = other_campaign
	editor.text_editor.confirm_text()
	_check(editor.text_editor.visible and editor.text_editor.error_label.visible
		and editor.text_editor.text_input.text == "Unpublished text",
		change + ": rejected Apply retains user draft and actionable error")
	_check(layer.strokes.is_empty() and original_floor.to_dict() == before
		and editor.edits._cursor == cursor_before and editor.edits.get_undo_command() == history,
		change + ": rejected Apply preserves original bytes and history")
	editor.text_editor.close_editor()
	# The prior implementation had no campaign capture property; check it
	# when present without turning the expected red control into a script error.
	var campaign_released: bool = true
	for entry: Dictionary in editor.get_property_list():
		if entry.get("name") == "_text_campaign_at_open":
			campaign_released = editor.get("_text_campaign_at_open") == null
			break
	_check(campaign_released and editor._text_scope_at_open == null
		and editor._text_layer_at_open == null
		and editor._text_map_at_open == null and editor._text_floor_at_open == null,
		change + ": dismissed modal drops captured source references")
	root.remove_child(scene)
	scene.free()


func _valid_case() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-115 valid", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)),
		"valid: create board")
	editor.layer_panel._add_objects()
	editor._choose_tool(AtlasCanvas.Tool.TEXT)
	var layer: AtlasObjectsLayer = editor.canvas.floor.layer_by_id(editor.canvas.active_layer_id) as AtlasObjectsLayer
	var before: Dictionary = layer.to_dict()
	var cursor_before: int = editor.edits._cursor
	editor._open_text_editor(Vector2(32, 40), -1)
	editor.text_editor.text_input.text = "Valid new label"
	var unrelated: AtlasMapDocument = AtlasMapDocument.new("unrelated", "Other map")
	editor.campaign.add_map(unrelated)
	editor.text_editor.confirm_text()
	_check(not editor.text_editor.visible and layer.strokes.size() == 1
		and layer.strokes[0].text == "Valid new label" and editor.edits._cursor == cursor_before + 1,
		"valid: unrelated map update retains permission and commits one text edit")
	var after: Dictionary = layer.to_dict()
	_check(after != before and editor.edits.undo() and layer.to_dict() == before,
		"valid: Undo restores exact original object bytes")
	_check(editor.edits.redo() and layer.to_dict() == after,
		"valid: Redo restores exact text bytes")
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	for change: String in ["map_replaced", "map_removed", "floor_replaced",
			"floor_removed", "canvas_campaign_replaced", "editor_campaign_replaced"]:
		await _case(change)
	await _valid_case()
	print("T115_TEXT_%s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
