extends SceneTree
## T-041: canonical token identity, history, native save and privacy exclusion.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TOKEN FAILED: " + label)


func _run() -> void:
	_model_checks()
	await _editor_checks()
	print("ATLAS_TOKEN_%s checks=%d failures=%d" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _model_checks() -> void:
	var first: AtlasToken = AtlasToken.new("token-1", Vector2(-82.5, 71.25), "Ghost")
	first.radius = 19.0
	first.tint = Color(0.1, 0.4, 0.9, 0.75)
	_check(first.is_valid(), "valid token at negative/fractional position")
	var decoded: AtlasToken = AtlasToken.from_dict(first.to_dict())
	_check(decoded != null and decoded.to_dict() == first.to_dict() and decoded != first,
		"token dictionary round-trip is independent")
	for bad: Variant in [Vector2.INF, Vector2(NAN, 4), Vector2(3, -INF)]:
		var broken: AtlasToken = first.copy()
		broken.position = bad
		_check(not broken.is_valid(), "invalid token positions rejected")
	var other: AtlasToken = first.copy()
	other.id = "token-2"
	other.position = Vector2(-1, 12)
	var layer: AtlasTokenLayer = AtlasTokenLayer.new("gm-tokens", "Secret tokens")
	layer.tokens = [first, other]
	layer.detail_level = 1
	_check(AtlasTokenLayer.valid_tokens(layer.tokens), "unique token IDs on a floor and detail level")
	var clone: AtlasTokenLayer = AtlasLayerCodec.clone(layer) as AtlasTokenLayer
	_check(clone != null and clone.to_dict() == layer.to_dict() and clone.tokens[0] != first,
		"layer codec retains tokens without aliasing")
	clone.tokens[0].position.x += 3.0
	_check(first.position == Vector2(-82.5, 71.25), "editing clone does not mutate original token")
	var duplicate: Dictionary = layer.to_dict()
	duplicate["tokens"].append(first.to_dict())
	_check(AtlasLayerCodec.from_dict(duplicate) == null, "duplicate stable IDs are rejected")
	var malformed: Dictionary = layer.to_dict()
	malformed["tokens"][0]["position"] = [INF, 10.0]
	_check(AtlasLayerCodec.from_dict(malformed) == null, "nonfinite persisted token positions rejected")
	var mismatched: Dictionary = layer.to_dict()
	mismatched["kind"] = "RASTER"
	_check(AtlasLayerCodec.from_dict(mismatched) == null, "token records cannot be interpreted as raster")
	var bad_id: AtlasToken = first.copy()
	bad_id.id = "bad/id"
	_check(not bad_id.is_valid(), "token identity excludes path separators")
	bad_id.id = "bad\nname"
	_check(not bad_id.is_valid(), "token identity excludes control characters")
	var bad_label: AtlasToken = first.copy()
	bad_label.label = "hidden\rmessage"
	_check(not bad_label.is_valid(), "token label excludes hidden line controls")
	var bad_radius: AtlasToken = first.copy()
	bad_radius.radius = AtlasToken.MAX_RADIUS + 1.0
	_check(not bad_radius.is_valid(), "unbounded token radius rejected")
	var source: AtlasMapDocument = AtlasMapDocument.new("map", "GM secret campaign")
	source.floors[0].layers.append(layer)
	_check(AtlasPlayerProjection.build_capture_input(source, "ground", 1, ["gm-tokens"]) == null,
		"player grants for token layers fail closed")
	var public: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source, "ground", 1, [])
	_check(public != null and not JSON.stringify(public.to_dict()).contains("Ghost") \
		and not JSON.stringify(public.to_dict()).contains("gm-tokens"),
		"ungranted GM token labels and layer IDs never reach sanitized input")


func _editor_checks() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for _i: int in range(8):
		await process_frame
	editor.create_board("Token test", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS))
	var canvas: AtlasCanvas = editor.canvas
	editor._choose_tool(AtlasCanvas.Tool.TOKEN)
	var tokens: AtlasTokenLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	_check(tokens != null and tokens.is_editable() and tokens.tokens.is_empty(),
		"Token tool provisions an editable dedicated GM layer")
	if tokens == null:
		root.remove_child(scene)
		scene.free()
		return
	var map_id: String = canvas.map.id
	var layer_id: String = tokens.id
	canvas.token_label = "Scary Dragon"
	canvas.token_radius = 23.0
	canvas.brush_color = Color.RED
	canvas._begin_token_press(Vector2(-37, 62))
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens.size() == 1 and tokens.tokens[0].position == Vector2(-37, 62),
		"click places token at signed board coordinates")
	_check(tokens.tokens[0].label == "Scary Dragon" and tokens.tokens[0].radius == 23.0 \
		and tokens.tokens[0].tint == Color.RED, "placement records label, radius and tint")
	var token_id: String = tokens.tokens[0].id
	canvas._begin_token_press(Vector2(-37, 62))
	canvas._update_token_drag(Vector2(-10, 80))
	_check(tokens.tokens[0].position == Vector2(-37, 62) and canvas._token_drag_preview.position == Vector2(-10, 80),
		"drag preview leaves canonical token unchanged")
	canvas._finish_token_drag(Vector2(-10, 80))
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens[0].position == Vector2(-10, 80) and tokens.tokens[0].id == token_id,
		"one history transaction moves stable ID without renaming")
	_check(editor.edits.undo(), "undo token movement")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens[0].position == Vector2(-37, 62), "undo restores original position")
	_check(editor.edits.redo(), "redo token movement")
	var base_for_scope: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(tokens.tokens)
	var outside_scope: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(tokens.tokens)
	outside_scope[0].position = Vector2(190, 100)
	var mask: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2(-100, 0), Vector2(20, 0), Vector2(20, 120), Vector2(-100, 120)]), true)
	var blocked_move: AtlasTokenEdit = AtlasTokenEdit.new(map_id, canvas.floor.id, layer_id,
		base_for_scope, outside_scope, mask)
	_check(not editor.edits.execute(blocked_move) and tokens.tokens[0].position == Vector2(-10, 80),
		"edit-scope mask prevents dragging a token beyond its boundary")
	var scope_denies_all: AtlasEditScope = AtlasEditScope.new(PackedVector2Array(), true)
	var blocked_delete: AtlasTokenEdit = AtlasTokenEdit.new(map_id, canvas.floor.id, layer_id,
		base_for_scope, [], scope_denies_all)
	_check(not editor.edits.execute(blocked_delete) and tokens.tokens.size() == 1,
		"invalid active mask denies token deletion without modifying the layer")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens[0].position == Vector2(-10, 80), "redo restores moved position")
	canvas.selected_token_id = token_id
	editor.inspector.token_name_input.text = "Scout"
	editor.inspector.token_radius_spinner.value = 15.0
	editor.inspector.brush_color_picker.color = Color.BLUE
	editor._restyle_selected_token()
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens[0].label == "Scout" and tokens.tokens[0].radius == 15.0 \
		and tokens.tokens[0].tint == Color.BLUE, "selected token restyle updates label, size, color")
	_check(editor.edits.undo(), "undo token restyle")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens[0].label == "Scary Dragon" and tokens.tokens[0].radius == 23.0,
		"undo restores original token appearance")
	_check(editor.edits.redo(), "redo token restyle")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	var stale: AtlasToken = tokens.tokens[0].copy()
	stale.position = Vector2(90, 20)
	var bogus_before: AtlasToken = tokens.tokens[0].copy()
	bogus_before.label = "stale revision"
	var state: Dictionary = editor.campaign.to_dict().duplicate(true)
	editor._edit_token(bogus_before, stale)
	_check(editor.campaign.to_dict() == state, "stale token edits cannot overwrite newer data")
	var not_editable: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(tokens.tokens)
	var next: Array[AtlasToken] = AtlasTokenLayer.clone_tokens(tokens.tokens)
	next[0].position = Vector2(100, 100)
	var command: AtlasTokenEdit = AtlasTokenEdit.new(map_id, canvas.floor.id, layer_id, not_editable, next)
	tokens.locked = true
	_check(not editor.edits.execute(command) and tokens.tokens[0].position == Vector2(-10, 80),
		"locked layers reject token movement atomically")
	tokens.locked = false
	canvas.selected_token_id = token_id
	_check(canvas.delete_selected_token(), "Delete removes selected marker")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens.is_empty(), "deleted token no longer exists")
	_check(editor.edits.undo(), "undo token deletion")
	tokens = canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer
	_check(tokens.tokens.size() == 1 and tokens.tokens[0].id == token_id, "undo restores exact token")
	var save_path: String = "user://atlas_t041_tokens.scn"
	_check(AtlasCampaignStore.save_campaign(editor.campaign, save_path) == OK, "native save writes token layer")
	var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(save_path)
	var saved_layer: AtlasTokenLayer = restored.get_map(map_id).floor_by_id(canvas.floor.id).layer_by_id(layer_id) as AtlasTokenLayer if restored != null else null
	_check(saved_layer != null and saved_layer.tokens.size() == 1 and saved_layer.tokens[0].to_dict() == tokens.tokens[0].to_dict(),
		"native save/load restores identity, geometry, label and tint")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	canvas.set_presented_detail_level(1)
	editor._choose_tool(AtlasCanvas.Tool.TOKEN)
	var detail_layer: AtlasTokenLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTokenLayer
	_check(detail_layer != null and detail_layer.id != layer_id and detail_layer.detail_level == 1,
		"D1 token authoring routes to a separate editable layer")
	canvas.token_label = "D1 only"
	canvas._begin_token_press(Vector2(200, -65))
	_check(detail_layer.tokens.size() == 1 and detail_layer.tokens[0].label == "D1 only" \
		and (canvas.floor.layer_by_id(layer_id) as AtlasTokenLayer).tokens.size() == 1,
		"creating D1 token never edits or relocates D0 tokens")
	root.remove_child(scene)
	scene.free()
