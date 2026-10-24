class_name AtlasMapMetadataEdit
extends AtlasEditCommand

var _before_name: String
var _after_name: String
var _before_tags: Array[String] = []
var _after_tags: Array[String] = []
var _valid: bool = false


func _init(target_map: String, before_name: String, before_tags: Array[String], after_name: String, after_tags: Array[String]) -> void:
    map_id = target_map
    _before_name = before_name
    _after_name = after_name
    _before_tags = before_tags.duplicate()
    _after_tags = after_tags.duplicate()
    _valid = AtlasData.text(before_name) and AtlasData.text(after_name) and _valid_tags(_before_tags) and _valid_tags(_after_tags)


func apply(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _before_name, _before_tags, _after_name, _after_tags)


func revert(campaign: AtlasCampaign) -> bool:
    return _replace(campaign, _after_name, _after_tags, _before_name, _before_tags)


func _replace(campaign: AtlasCampaign, expected_name: String, expected_tags: Array[String], next_name: String, next_tags: Array[String]) -> bool:
    if not _valid or campaign == null or (expected_name == next_name and expected_tags == next_tags):
        return false
    var document: AtlasMapDocument = campaign.get_map(map_id)
    if document == null or document.display_name != expected_name or document.tags != expected_tags:
        return false
    document.display_name = next_name
    document.tags = next_tags.duplicate()
    return true


func _valid_tags(tags: Array[String]) -> bool:
    if tags.size() > 128:
        return false
    var seen: Dictionary[String, bool] = {}
    for tag: String in tags:
        if not AtlasData.text(tag) or seen.has(tag.to_lower()):
            return false
        seen[tag.to_lower()] = true
    return true
