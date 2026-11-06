class_name AtlasSelectionEdit
extends AtlasEditCommand
## No artwork mutation. Ordered with content changes but shares dirty-state token.

var before_context: DrawingHistoryContext
var after_context: DrawingHistoryContext


func _init(before: DrawingHistoryContext, after: DrawingHistoryContext) -> void:
	before_context = before.detached_copy()
	after_context = after.detached_copy()
	map_id = before_context.map_id
	floor_id = before_context.floor_group_id


func apply(_campaign: AtlasCampaign) -> bool:
	return true


func revert(_campaign: AtlasCampaign) -> bool:
	return true
