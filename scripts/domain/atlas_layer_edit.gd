class_name AtlasLayerEdit
extends AtlasEditCommand
## An ordered layer transaction, including content snapshots for creation/removal.

var _before: Array[AtlasLayer] = []
var _after: Array[AtlasLayer] = []
var _valid: bool = false


func _init(target_map: String, target_floor: String, before: Array[AtlasLayer], after: Array[AtlasLayer]) -> void:
    map_id = target_map
    floor_id = target_floor
    _valid = AtlasLayerCodec.valid_collection(before) and AtlasLayerCodec.valid_collection(after)
    if _valid:
        _before = AtlasLayerCodec.clone_all(before)
        _after = AtlasLayerCodec.clone_all(after)


func apply(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _before, _after, true)


func revert(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _after, _before, false)


func _replace(campaign: AtlasCampaign, expected: Array[AtlasLayer], replacement: Array[AtlasLayer], validate_target: bool) -> bool:
    if not _valid or AtlasLayerCodec.same_layers(expected, replacement):
        return false
    var document: AtlasMapDocument = campaign.get_map(map_id)
    if document == null:
        return false
    var floor: AtlasFloor = document.floor_by_id(floor_id)
    if floor == null or not AtlasLayerCodec.same_layers(floor.layers, expected):
        return false
    if validate_target:
        for old: AtlasLayer in expected:
            if old.is_editable():
                continue
            var found: AtlasLayer
            for candidate: AtlasLayer in replacement:
                if candidate.id == old.id:
                    found = candidate
                    break
            if found == null or _content(old, document) != _content(found, document):
                return false
    floor.layers = AtlasLayerCodec.clone_all(replacement)
    return true


func _content(layer: AtlasLayer, document: AtlasMapDocument) -> Dictionary:
    var data: Dictionary = layer.to_dict()
    for key: String in ["id", "name", "visible", "locked", "opacity"]:
        data.erase(key)
    if layer is AtlasTileLayer and layer.grid == null:
        data.grid = document.get_terrain_grid().to_dict()
    return data
