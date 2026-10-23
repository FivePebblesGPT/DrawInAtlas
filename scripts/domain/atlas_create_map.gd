class_name AtlasCreateMap
extends AtlasEditCommand

var new_map_id: String
var _document: Dictionary


func _init(source_map_id: String, document: AtlasMapDocument) -> void:
    map_id = source_map_id
    new_map_id = document.id
    _document = document.to_dict().duplicate(true)


func apply(campaign: AtlasCampaign) -> bool:
    if campaign.get_map(map_id) == null or campaign.maps.has(new_map_id):
        return false
    if new_map_id.strip_edges().is_empty() or str(_document.get("name", "")).strip_edges().is_empty():
        return false
    var document: AtlasMapDocument = AtlasMapDocument.from_dict(_document)
    if document == null:
        return false
    campaign.add_map(document)
    return true


func revert(campaign: AtlasCampaign) -> bool:
    var document: AtlasMapDocument = campaign.get_map(new_map_id)
    if document == null or document.to_dict() != _document or campaign.root_map_id == new_map_id:
        return false
    for link: AtlasMapLink in campaign.links:
        if link.source_map_id == new_map_id or link.target_map_id == new_map_id:
            return false
    for placement: AtlasPlacement in campaign.placements:
        if placement.parent_map_id == new_map_id or placement.child_map_id == new_map_id:
            return false
    campaign.maps.erase(new_map_id)
    return true
