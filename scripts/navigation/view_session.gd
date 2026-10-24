class_name AtlasViewSession
extends RefCounted

## Ephemeral per-map/per-floor camera and edit-target preferences. This is
## intentionally separate from campaign data: visiting a floor does not dirty
## the document or change the default floor written to the save file.

class MapViews extends RefCounted:
    var floors: Dictionary[String, AtlasViewState] = {}
    var last_floor_id: String = ""

var _maps: Dictionary[String, MapViews] = {}


func reset() -> void:
    _maps.clear()


func remember(state: AtlasViewState) -> void:
    if not _valid_state(state):
        return
    if not _maps.has(state.map_id):
        _maps[state.map_id] = MapViews.new()
    var views: MapViews = _maps[state.map_id]
    views.floors[state.floor_id] = state.copy()
    views.last_floor_id = state.floor_id


## Prefer the last explicitly visited floor if none was requested. Validate
## the retained layer ID against the current floor, since undo can remove layers.
func resolve(campaign: AtlasCampaign, map_id: String, floor_id: String = "", fallback_focus: Vector2 = Vector2.ZERO, fallback_zoom: float = 1.0) -> AtlasViewState:
    if campaign == null:
        return null
    var document: AtlasMapDocument = campaign.get_map(map_id)
    if document == null:
        return null
    var views: MapViews = _maps.get(map_id)
    var selected: String = floor_id
    if selected.is_empty():
        selected = document.default_floor_id
        if views != null and document.floor_by_id(views.last_floor_id) != null:
            selected = views.last_floor_id
    var floor: AtlasFloor = document.floor_by_id(selected)
    if floor == null:
        return null
    var state: AtlasViewState = views.floors.get(selected) if views != null else null
    if not _valid_state(state):
        state = AtlasViewState.new(map_id, selected, fallback_focus, fallback_zoom)
    else:
        state = state.copy()
    if not _valid_state(state):
        return null
    if floor.layer_by_id(state.layer_id) == null:
        state.layer_id = "ink" if floor.layer_by_id("ink") != null else ""
        if state.layer_id.is_empty() and not floor.layers.is_empty():
            state.layer_id = floor.layers.back().id
    remember(state)
    return state


func prune(campaign: AtlasCampaign) -> void:
    for map_id: String in _maps.keys():
        var document: AtlasMapDocument = campaign.get_map(map_id) if campaign != null else null
        if document == null:
            _maps.erase(map_id)
            continue
        var views: MapViews = _maps[map_id]
        for floor_id: String in views.floors.keys():
            if document.floor_by_id(floor_id) == null:
                views.floors.erase(floor_id)
        if not views.floors.has(views.last_floor_id):
            views.last_floor_id = ""


func _valid_state(state: AtlasViewState) -> bool:
    return (state != null and AtlasData.text(state.map_id) and AtlasData.text(state.floor_id)
        and state.focus.is_finite() and is_finite(state.zoom) and state.zoom > 0.0)
