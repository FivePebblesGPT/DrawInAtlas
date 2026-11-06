class_name AtlasTokenEdit
extends AtlasEditCommand
## Atomic token placement/move/removal with exact before/after layer snapshots.
## A stale or locked target fails without touching the campaign or history.

var layer_id: String = ""
var _before: Array[AtlasToken] = []
var _after: Array[AtlasToken] = []
var _valid: bool = false
var _scope: AtlasEditScope


func _init(target_map: String, target_floor: String, target_layer: String,
		before: Array[AtlasToken], after: Array[AtlasToken], scope: AtlasEditScope = null) -> void:
	map_id = target_map
	floor_id = target_floor
	layer_id = target_layer
	_scope = AtlasEditScope.new(scope.polygon, scope.enabled) if scope != null else AtlasEditScope.new()
	_valid = AtlasTokenLayer.valid_tokens(before) and AtlasTokenLayer.valid_tokens(after) \
		and not AtlasTokenLayer.same_tokens(before, after)
	if _valid:
		_before = AtlasTokenLayer.clone_tokens(before)
		_after = AtlasTokenLayer.clone_tokens(after)


func apply(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _before, _after)


func revert(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _after, _before)


func _replace(campaign: AtlasCampaign, expected: Array[AtlasToken], replacement: Array[AtlasToken]) -> bool:
	if not _valid or campaign == null:
		return false
	var document: AtlasMapDocument = campaign.get_map(map_id)
	var floor: AtlasFloor = document.floor_by_id(floor_id) if document != null else null
	var layer: AtlasTokenLayer = floor.layer_by_id(layer_id) as AtlasTokenLayer if floor != null else null
	if layer == null or not layer.is_editable() or not AtlasTokenLayer.same_tokens(layer.tokens, expected):
		return false
	# Apply the original mask to the *changed* tokens, not every unrelated token
	# on the layer. Undo must obey exactly the same recorded boundary.
	var old_ids: Dictionary[String, AtlasToken] = {}
	var new_ids: Dictionary[String, AtlasToken] = {}
	for token: AtlasToken in expected:
		old_ids[token.id] = token
	for token: AtlasToken in replacement:
		new_ids[token.id] = token
	for id: String in old_ids:
		var previous: AtlasToken = old_ids[id]
		var next: AtlasToken = new_ids.get(id)
		if next == null or next.to_dict() != previous.to_dict():
			if not _token_within_scope(previous):
				return false
	for id: String in new_ids:
		var next: AtlasToken = new_ids[id]
		var previous: AtlasToken = old_ids.get(id)
		if previous == null or next.to_dict() != previous.to_dict():
			if not _token_within_scope(next):
				return false
	layer.tokens = AtlasTokenLayer.clone_tokens(replacement)
	return true


func _token_within_scope(token: AtlasToken) -> bool:
	return _scope.contains_rect(Rect2(token.position - Vector2.ONE * token.radius,
		Vector2.ONE * token.radius * 2.0))
