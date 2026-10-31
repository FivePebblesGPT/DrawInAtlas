class_name AtlasViewState
extends RefCounted
## Viewer-local camera and layer selection; never serialized into the campaign.

## Viewer/session-only identifiers, never part of saved campaign defaults.
var map_id: String
var floor_id: String
## Camera center in current map's board units, not a screen-local offset.
var focus: Vector2
## Positive board-to-screen magnification, not an authored D0–D32 level.
var zoom: float
## Active editing layer ID; camera navigation never changes authored content.
var layer_id: String


func _init(target_map: String = "", target_floor: String = "", camera_focus: Vector2 = Vector2.ZERO, camera_zoom: float = 1.0, selected_layer: String = "ink") -> void:
	map_id = target_map
	floor_id = target_floor
	focus = camera_focus
	zoom = camera_zoom
	layer_id = selected_layer


func copy() -> AtlasViewState:
	return AtlasViewState.new(map_id, floor_id, focus, zoom, layer_id)
