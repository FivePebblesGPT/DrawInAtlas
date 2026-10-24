class_name AtlasFloorEdit
extends AtlasEditCommand
## Ordered floor metadata transaction with detached snapshots for creation/removal.

var _before: Array[AtlasFloor] = []
var _after: Array[AtlasFloor] = []
var _before_default: String
var _after_default: String
var _valid: bool = false


func _init(target_map: String, before: Array[AtlasFloor], after: Array[AtlasFloor], before_default: String, after_default: String) -> void:
    map_id = target_map
    _before_default = before_default
    _after_default = after_default
    _valid = _valid_floors(before, before_default) and _valid_floors(after, after_default)
    if not _valid:
        return
    for old: AtlasFloor in before:
        var retained: AtlasFloor = _find(after, old.id)
        if retained != null and not AtlasLayerCodec.same_layers(old.layers, retained.layers):
            _valid = false
            return
    _before = _clone(before)
    _after = _clone(after)


func apply(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _before, _after, _before_default, _after_default)


func revert(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _after, _before, _after_default, _before_default)


func _replace(campaign: AtlasCampaign, expected: Array[AtlasFloor], replacement: Array[AtlasFloor], expected_default: String, next_default: String) -> bool:
    if not _valid or campaign == null or (expected_default == next_default and _same(expected, replacement)):
        return false
    var document: AtlasMapDocument = campaign.get_map(map_id)
    if document == null or document.default_floor_id != expected_default:
        return false
    if not _valid_floors(document.floors, expected_default) or not _same(document.floors, expected):
        return false
    for old: AtlasFloor in document.floors:
        if _find(replacement, old.id) != null:
            continue
        for layer: AtlasLayer in old.layers:
            if not layer.is_editable():
                return false
        for link: AtlasMapLink in campaign.links:
            if ((link.source_map_id == map_id and link.source_floor_id == old.id)
                    or (link.target_map_id == map_id and link.target_floor_id == old.id)):
                return false
    var next: Array[AtlasFloor] = _clone(replacement)
    for index: int in range(next.size()):
        var retained: AtlasFloor = document.floor_by_id(next[index].id)
        if retained != null:
            retained.display_name = next[index].display_name
            next[index] = retained
    document.floors = next
    document.default_floor_id = next_default
    return true


func _valid_floors(floors: Array[AtlasFloor], default_id: String) -> bool:
    var ids: Dictionary[String, bool] = {}
    for floor: AtlasFloor in floors:
        if floor == null or not AtlasData.text(floor.id) or not AtlasData.text(floor.display_name):
            return false
        if ids.has(floor.id) or not AtlasLayerCodec.valid_collection(floor.layers):
            return false
        ids[floor.id] = true
    return not floors.is_empty() and ids.has(default_id)


func _clone(floors: Array[AtlasFloor]) -> Array[AtlasFloor]:
    var result: Array[AtlasFloor] = []
    for floor: AtlasFloor in floors:
        var copy: AtlasFloor = AtlasFloor.new()
        copy.id = floor.id
        copy.display_name = floor.display_name
        copy.layers = AtlasLayerCodec.clone_all(floor.layers)
        result.append(copy)
    return result


func _find(floors: Array[AtlasFloor], id: String) -> AtlasFloor:
    for floor: AtlasFloor in floors:
        if floor.id == id:
            return floor
    return null


func _same(first: Array[AtlasFloor], second: Array[AtlasFloor]) -> bool:
    if first.size() != second.size():
        return false
    for index: int in range(first.size()):
        if (first[index].id != second[index].id or first[index].display_name != second[index].display_name
                or not AtlasLayerCodec.same_layers(first[index].layers, second[index].layers)):
            return false
    return true
