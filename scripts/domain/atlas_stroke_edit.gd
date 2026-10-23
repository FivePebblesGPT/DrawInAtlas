class_name AtlasStrokeEdit
extends AtlasEditCommand
## Owns immutable before/after snapshots; undo never depends on the current camera or grid.

var _before: Array[AtlasStroke]
var _after: Array[AtlasStroke]


func _init(target_map: String, target_floor: String, before: Array[AtlasStroke],
        after: Array[AtlasStroke]) -> void:
    map_id = target_map
    floor_id = target_floor
    _before = AtlasStroke.clone_all(before)
    _after = AtlasStroke.clone_all(after)


func apply(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _before, _after)


func revert(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _after, _before)


func _replace(campaign: AtlasCampaign, expected: Array[AtlasStroke], replacement: Array[AtlasStroke]) -> bool:
    var document: AtlasMapDocument = campaign.get_map(map_id)
    if document == null or AtlasStroke.same_artwork(expected, replacement):
        return false
    var floor: AtlasFloor = document.floor_by_id(floor_id)
    if floor == null or not AtlasStroke.same_artwork(floor.strokes, expected):
        return false
    for stroke: AtlasStroke in replacement:
        if not stroke.is_valid():
            return false
    floor.strokes = AtlasStroke.clone_all(replacement)
    return true
