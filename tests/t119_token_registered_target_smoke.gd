extends SceneTree
## A GM Token drag or direct edit must retain its registered campaign/map/floor.
## Same IDs and serialized bytes must not transfer an in-flight authorization.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T119_TOKEN_FAILED: " + description)


func _run() -> void:
	for change: String in ["map_replaced", "map_removed", "floor_replaced", "floor_removed",
			"canvas_campaign_replaced"]:
		await _stale_drag(change)
	await _valid_drag()
	await _stale_direct_edits()
	print("T119_TOKEN_%s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(1 if failures > 0 else 0)


func _setup(name: String) -> Dictionary:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("T-119 " + name, AtlasGrid.new(AtlasGrid.Kind.GRIDLESS)),
		name + ": board created")
	editor._choose_tool(AtlasCanvas.Tool.TOKEN)
	var canvas: AtlasCanvas = editor.canvas
	canvas.snap_to_grid = false
	var start: Vector2 = Vector2(40, 48)
	canvas._begin_token_press(start)
	var layer: AtlasTokenLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	_check(layer != null and layer.tokens.size() == 1 and layer.tokens[0].position == start,
		name + ": canonical GM token created")
	return {"scene": scene, "editor": editor, "canvas": canvas, "layer": layer,
		"start": start, "map": canvas.map, "floor": canvas.floor}


func _cleanup(case: Dictionary) -> void:
	var scene: Node = case["scene"]
	root.remove_child(scene)
	scene.free()


func _stale_drag(change: String) -> void:
	var case: Dictionary = await _setup(change)
	var editor: AtlasEditor = case["editor"]
	var canvas: AtlasCanvas = case["canvas"]
	var layer: AtlasTokenLayer = case["layer"]
	var original_map: AtlasMapDocument = case["map"]
	var original_floor: AtlasFloor = case["floor"]
	var original: Dictionary = layer.to_dict().duplicate(true)
	var start: Vector2 = case["start"]
	var finish: Vector2 = start + Vector2(15, 8)
	var cursor_before: int = editor.edits._cursor
	var submitted: Array[int] = [0]
	var rejected: Array[String] = []
	canvas.token_edit_requested.connect(func(_before: AtlasToken, _after: AtlasToken) -> void:
		submitted[0] += 1)
	canvas.token_rejected.connect(func(message: String) -> void:
		rejected.append(message))
	canvas._begin_token_press(start)
	_check(canvas._token_drag_before != null and canvas._token_drag_preview != null,
		change + ": drag captures source before graph change")
	var registered_map: AtlasMapDocument = original_map
	var registered_floor: AtlasFloor = original_floor
	match change:
		"map_replaced":
			registered_map = AtlasMapDocument.from_dict(original_map.to_dict())
			_check(registered_map != null and registered_map != original_map
				and registered_map.to_dict() == original_map.to_dict(),
				change + ": replacement has same ID and bytes")
			editor.campaign.add_map(registered_map)
			registered_floor = registered_map.floor_by_id(original_floor.id)
		"map_removed":
			editor.campaign.maps.erase(original_map.id)
		"floor_replaced":
			registered_floor = AtlasFloor.from_dict(original_floor.to_dict())
			_check(registered_floor != null and registered_floor != original_floor
				and registered_floor.to_dict() == original_floor.to_dict(),
				change + ": replacement has same ID and bytes")
			original_map.floors[original_map.floors.find(original_floor)] = registered_floor
		"floor_removed":
			original_map.floors.erase(original_floor)
		"canvas_campaign_replaced":
			var other: AtlasCampaign = AtlasCampaign.new()
			other.add_map(original_map)
			canvas.campaign = other
	canvas._finish_token_drag(finish)
	_check(submitted[0] == 0 and rejected.size() == 1,
		change + ": stale release rejected before an edit request")
	_check(canvas._token_drag_before == null and canvas._token_drag_preview == null
		and canvas.selected_token_id.is_empty(),
		change + ": rejected preview and selection cleared")
	_check(layer.to_dict() == original and editor.edits._cursor == cursor_before,
		change + ": original pixel-independent token source and history unchanged")
	if registered_floor != null:
		var replacement_layer: AtlasTokenLayer = registered_floor.layer_by_id(layer.id) as AtlasTokenLayer
		_check(replacement_layer == null or replacement_layer.to_dict() == original,
			change + ": registered replacement unchanged")
	_cleanup(case)


func _valid_drag() -> void:
	var case: Dictionary = await _setup("valid")
	var editor: AtlasEditor = case["editor"]
	var canvas: AtlasCanvas = case["canvas"]
	var layer: AtlasTokenLayer = case["layer"]
	var start: Vector2 = case["start"]
	var finish: Vector2 = start + Vector2(19, -11)
	var cursor_before: int = editor.edits._cursor
	# Another registered map does not change the original target authorization.
	editor.campaign.add_map(AtlasMapDocument.new("other", "Unrelated"))
	var submitted: Array[int] = [0]
	canvas.token_edit_requested.connect(func(_before: AtlasToken, _after: AtlasToken) -> void:
		submitted[0] += 1)
	canvas._begin_token_press(start)
	canvas._finish_token_drag(finish)
	_check(submitted[0] == 1 and editor.edits._cursor == cursor_before + 1
		and layer.tokens[0].position == finish, "valid: one edit on still-registered source")
	_check(editor.edits.undo() and layer.tokens[0].position == start,
		"valid: Undo restores exact original token position")
	_check(editor.edits.redo() and layer.tokens[0].position == finish,
		"valid: Redo restores exact committed token position")
	_cleanup(case)


func _stale_direct_edits() -> void:
	var case: Dictionary = await _setup("direct")
	var editor: AtlasEditor = case["editor"]
	var canvas: AtlasCanvas = case["canvas"]
	var layer: AtlasTokenLayer = case["layer"]
	var original_map: AtlasMapDocument = case["map"]
	var before: Dictionary = layer.to_dict().duplicate(true)
	var clone_map: AtlasMapDocument = AtlasMapDocument.from_dict(original_map.to_dict())
	editor.campaign.add_map(clone_map)
	var clone_layer: AtlasTokenLayer = clone_map.floor_by_id(canvas.floor.id).layer_by_id(layer.id) as AtlasTokenLayer
	var history_before: int = editor.edits._cursor
	var submitted: Array[int] = [0]
	canvas.token_edit_requested.connect(func(_before: AtlasToken, _after: AtlasToken) -> void:
		submitted[0] += 1)
	canvas.selected_token_id = layer.tokens[0].id
	_check(not canvas.delete_selected_token(), "direct: detached source cannot request deletion")
	canvas._begin_token_press(Vector2(180, 80))
	_check(submitted[0] == 0, "direct: detached source cannot request new placement")
	var next: AtlasToken = layer.tokens[0].copy()
	next.position += Vector2(10, 0)
	editor._edit_token(layer.tokens[0].copy(), next)
	_check(layer.to_dict() == before and clone_layer.to_dict() == before
		and editor.edits._cursor == history_before,
		"direct: editor rejects stale command despite equal IDs/bytes")
	_cleanup(case)
