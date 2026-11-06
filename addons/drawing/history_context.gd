class_name DrawingHistoryContext
extends RefCounted
## Immutable-by-convention UI snapshot. IDs are stable, never display names.
## The Atlas host validates map/instance generations before restoring a snapshot.

var map_id: String = ""
var floor_group_id: String = ""
var detail_group_id: String = ""
var document_id: String = ""
var asset_id: String = ""
var selected_layer_ids: Array[String] = []
var selected_instance_id: String = ""
var selected_instance_generation: String = ""
var editor_mode: String = ""
var focus_bounds: Rect2 = Rect2()
var has_focus: bool = false
var selected_rect: Rect2i = Rect2i()


func detached_copy() -> DrawingHistoryContext:
	var value: DrawingHistoryContext = DrawingHistoryContext.new()
	value.map_id = map_id
	value.floor_group_id = floor_group_id
	value.detail_group_id = detail_group_id
	value.document_id = document_id
	value.asset_id = asset_id
	value.selected_layer_ids = selected_layer_ids.duplicate()
	value.selected_instance_id = selected_instance_id
	value.selected_instance_generation = selected_instance_generation
	value.editor_mode = editor_mode
	value.focus_bounds = focus_bounds
	value.has_focus = has_focus
	value.selected_rect = selected_rect
	return value


func same_selection(other: DrawingHistoryContext) -> bool:
	# Mode-only, camera-only and navigation-only events are not selections.
	return other != null and selected_layer_ids == other.selected_layer_ids \
		and selected_instance_id == other.selected_instance_id \
		and selected_instance_generation == other.selected_instance_generation \
		and selected_rect == other.selected_rect
