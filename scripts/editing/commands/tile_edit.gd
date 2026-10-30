class_name AtlasTileEdit
extends AtlasEditCommand

var layer_id: String
var _before: Dictionary
var _after: Dictionary


func _init(target_map: String, target_floor: String, target_layer: String, before: Dictionary, after: Dictionary) -> void:
	map_id = target_map
	floor_id = target_floor
	layer_id = target_layer
	_before = before.duplicate(true)
	_after = after.duplicate(true)


func apply(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _before, _after, true)


func revert(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _after, _before, false)


func _replace(campaign: AtlasCampaign, expected: Dictionary, replacement: Dictionary, validate_target: bool) -> bool:
	var document: AtlasMapDocument = campaign.get_map(map_id)
	if document == null or expected == replacement:
		return false
	var floor: AtlasFloor = document.floor_by_id(floor_id)
	if floor == null:
		return false
	var layer: AtlasTerrainLayer = floor.layer_by_id(layer_id) as AtlasTerrainLayer
	if layer == null or layer.terrain != expected or (validate_target and not layer.is_editable()):
		return false
	var candidate: Dictionary = layer.to_dict()
	candidate.terrain = replacement
	if AtlasLayerCodec.from_dict(candidate) == null:
		return false
	layer.terrain.assign(replacement)
	return true
