class_name AtlasFogEdit
extends AtlasEditCommand
## Floor-wide visibility history. Stale state and changed map/floor identities
## reject atomically instead of editing another floor with the same ID.

var _source_document: AtlasMapDocument
var _source_floor: AtlasFloor
var _before_enabled: bool
var _after_enabled: bool
var _before: Array[AtlasFogRegion] = []
var _after: Array[AtlasFogRegion] = []
var _scope: AtlasEditScope
var _valid: bool = false


func _init(document: AtlasMapDocument, floor: AtlasFloor, after: AtlasFogRegion,
		scope: AtlasEditScope = null) -> void:
	if document == null or floor == null or after == null:
		return
	map_id = document.id
	floor_id = floor.id
	_source_document = document
	_source_floor = floor
	_scope = AtlasEditScope.new(scope.polygon, scope.enabled) if scope != null else AtlasEditScope.new()
	_before_enabled = floor.fog_enabled
	_after_enabled = true
	if not floor.valid_fog() or floor.fog_regions.size() >= AtlasFloor.MAX_FOG_REGIONS \
			or not after.is_valid() or not _scope.contains_rect(after.bounds):
		return
	_before = AtlasFloor.clone_fog(floor.fog_regions)
	_after = AtlasFloor.clone_fog(floor.fog_regions)
	_after.append(after.copy())
	_valid = true


func apply(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _before_enabled, _before, _after_enabled, _after)


func revert(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _after_enabled, _after, _before_enabled, _before)


func _replace(campaign: AtlasCampaign, expected_enabled: bool, expected: Array[AtlasFogRegion],
		next_enabled: bool, replacement: Array[AtlasFogRegion]) -> bool:
	if not _valid or campaign == null or campaign.get_map(map_id) != _source_document \
			or _source_document.floor_by_id(floor_id) != _source_floor \
			or _source_floor.fog_enabled != expected_enabled \
			or not AtlasFloor.same_fog(_source_floor.fog_regions, expected):
		return false
	_source_floor.fog_regions = AtlasFloor.clone_fog(replacement)
	_source_floor.fog_enabled = next_enabled
	return true
