class_name AtlasLinkEdit
extends AtlasEditCommand
## T-015: one reversible marker-only navigation edge. Source and destination
## are independent maps; no footprint or child-map creation belongs to a link.

var _before: Dictionary
var _after: Dictionary
var _scope: AtlasEditScope
var _legacy_request: bool = false
var _restore_slot: int = -1


func _init(source_id: String, before: AtlasMapLink, after: AtlasMapLink,
		old_placement: AtlasPlacement = null, new_placement: AtlasPlacement = null,
		new_map: AtlasMapDocument = null, scope: AtlasEditScope = null) -> void:
	map_id = source_id
	_before = before.to_dict().duplicate(true) if before != null else {}
	_after = after.to_dict().duplicate(true) if after != null else {}
	# Keep the old arguments only to reject stale callers deterministically,
	# never to reconstruct an obsolete container or save data.
	_legacy_request = old_placement != null or new_placement != null or new_map != null
	_scope = AtlasEditScope.new(scope.polygon, scope.enabled) if scope != null else AtlasEditScope.new()


func apply(campaign: AtlasCampaign) -> bool:
	return not _legacy_request and _replace(campaign, _before, _after, false)


func revert(campaign: AtlasCampaign) -> bool:
	return not _legacy_request and _replace(campaign, _after, _before, true)


func _replace(campaign: AtlasCampaign, expected: Dictionary, next: Dictionary,
		undoing: bool) -> bool:
	if campaign == null or campaign.get_map(map_id) == null or expected == next:
		return false
	if not _marker_only(expected) or not _marker_only(next):
		return false
	var link_id: String = str(expected.get("id", next.get("id", "")))
	if link_id.is_empty():
		return false
	var registered: AtlasMapLink = campaign.link_by_id(link_id)
	if expected.is_empty():
		if registered != null:
			return false
	elif registered == null or registered.to_dict() != expected:
		return false
	if not _valid_snapshot(campaign, expected, map_id):
		return false
	if not _valid_snapshot(campaign, next, map_id):
		return false
	if not expected.is_empty() and not next.is_empty() \
			and (expected["id"] != next["id"] \
			or expected["source_floor_id"] != next["source_floor_id"]):
		return false
	if not undoing and (not _within_scope(expected) or not _within_scope(next)):
		return false
	var replacement: AtlasMapLink = AtlasMapLink.from_dict(next) if not next.is_empty() else null
	# All validation precedes mutation, including the destination and mask.
	if registered != null:
		_restore_slot = campaign.links.find(registered)
		campaign.links.remove_at(_restore_slot)
	if replacement != null:
		var insertion: int = clampi(_restore_slot, 0, campaign.links.size()) \
			if _restore_slot >= 0 else campaign.links.size()
		campaign.links.insert(insertion, replacement)
	return true


func _marker_only(snapshot: Dictionary) -> bool:
	return snapshot.is_empty() or str(snapshot.get("placement_id", "")).is_empty()


func _valid_snapshot(campaign: AtlasCampaign, snapshot: Dictionary,
		source_map_id: String) -> bool:
	if snapshot.is_empty():
		return true
	var link: AtlasMapLink = AtlasMapLink.from_dict(snapshot)
	if link == null or link.source_map_id != source_map_id:
		return false
	var source: AtlasMapDocument = campaign.get_map(source_map_id)
	var target: AtlasMapDocument = campaign.get_map(link.target_map_id)
	return source.floor_by_id(link.source_floor_id) != null \
		and target != null and target.floor_by_id(link.target_floor_id) != null


func _within_scope(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return true
	var link: AtlasMapLink = AtlasMapLink.from_dict(snapshot)
	return link != null and _scope.contains_rect(Rect2(
		link.anchor - Vector2.ONE * link.hit_radius,
		Vector2.ONE * link.hit_radius * 2.0))
