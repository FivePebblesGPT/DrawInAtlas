class_name AtlasGridEdit
extends AtlasEditCommand
## Changes the overlay/measurement configuration, never canonical artwork coordinates.

var _before: AtlasGrid
var _after: AtlasGrid


func _init(target_map: String, before: AtlasGrid, after: AtlasGrid) -> void:
	map_id = target_map
	_before = before.copy()
	_after = after.copy()


func apply(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _before, _after)


func revert(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _after, _before)


func _replace(campaign: AtlasCampaign, expected: AtlasGrid, replacement: AtlasGrid) -> bool:
	var document: AtlasMapDocument = campaign.get_map(map_id)
	if document == null or not replacement.is_valid() or not expected.is_valid():
		return false
	if expected.same_as(replacement) or not document.grid.same_as(expected):
		return false
	document.grid = replacement.copy()
	return true
