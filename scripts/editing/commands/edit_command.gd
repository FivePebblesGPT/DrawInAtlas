class_name AtlasEditCommand
extends RefCounted

var map_id: String
var floor_id: String


func apply(_campaign: AtlasCampaign) -> bool:
	return false


func revert(_campaign: AtlasCampaign) -> bool:
	return false
