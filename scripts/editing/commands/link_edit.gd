class_name AtlasLinkEdit
extends AtlasEditCommand
## One entrance/footprint transaction. Unlinking never deletes its destination.
## Creation undo removes a destination only while unchanged and unreferenced.

class ValidatedChange extends RefCounted:
	var link_id: String
	var current_link: AtlasMapLink
	var next_link: AtlasMapLink
	var current_placement: AtlasPlacement
	var next_placement: AtlasPlacement
	var fresh_map: AtlasMapDocument
	var current_placement_is_shared: bool = false
	var reuse_registered_placement: bool = false


var new_map_id: String = ""
var _before: Dictionary
var _after: Dictionary
var _old_placement: Dictionary
var _new_placement: Dictionary
var _new_map: Dictionary
var _scope: AtlasEditScope
var _link_restore_slot: int = -1
var _placement_restore_slot: int = -1


func _init(source_id: String, before: AtlasMapLink, after: AtlasMapLink,
		old_placement: AtlasPlacement = null, new_placement: AtlasPlacement = null,
		new_map: AtlasMapDocument = null, scope: AtlasEditScope = null) -> void:
	map_id = source_id
	_before = before.to_dict().duplicate(true) if before != null else {}
	_after = after.to_dict().duplicate(true) if after != null else {}
	_old_placement = old_placement.to_dict().duplicate(true) if old_placement != null else {}
	_new_placement = new_placement.to_dict().duplicate(true) if new_placement != null else {}
	_new_map = new_map.to_dict().duplicate(true) if new_map != null else {}
	new_map_id = new_map.id if new_map != null else ""
	_scope = AtlasEditScope.new(scope.polygon, scope.enabled) if scope != null else AtlasEditScope.new()


func apply(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _before, _after, _old_placement, _new_placement, false)


func revert(campaign: AtlasCampaign) -> bool:
	return _replace(campaign, _after, _before, _new_placement, _old_placement, true)


func _replace(campaign: AtlasCampaign, expected_link_snapshot: Dictionary, next_link_snapshot: Dictionary,
		expected_placement_snapshot: Dictionary, next_placement_snapshot: Dictionary, undoing: bool) -> bool:
	if campaign == null:
		return false
	var source: AtlasMapDocument = campaign.get_map(map_id)
	if source == null:
		return false
	if expected_link_snapshot == next_link_snapshot and expected_placement_snapshot == next_placement_snapshot:
		return false
	var change := ValidatedChange.new()
	if not _prepare_link(campaign, source, change, expected_link_snapshot, next_link_snapshot):
		return false
	if not _prepare_document(campaign, change, expected_placement_snapshot, undoing):
		return false
	if not _valid_destination(campaign, source, change):
		return false
	if not _prepare_placement(campaign, change, expected_placement_snapshot, next_placement_snapshot):
		return false
	if not undoing and not _within_original_scope(change):
		return false
	_apply_validated_change(campaign, change, undoing)
	return true


func _prepare_link(campaign: AtlasCampaign, source: AtlasMapDocument, change: ValidatedChange,
		expected_snapshot: Dictionary, next_snapshot: Dictionary) -> bool:
	change.link_id = str(expected_snapshot.get("id", next_snapshot.get("id", "")))
	change.current_link = campaign.link_by_id(change.link_id)
	if change.link_id.is_empty() or (change.current_link == null) != expected_snapshot.is_empty():
		return false
	if change.current_link != null and change.current_link.to_dict() != expected_snapshot:
		return false
	if not expected_snapshot.is_empty() and str(expected_snapshot.get("source_map_id", "")) != map_id:
		return false
	if not new_map_id.is_empty() and (not _before.is_empty() or str(_after.get("target_map_id", "")) != new_map_id):
		return false
	if not next_snapshot.is_empty():
		change.next_link = AtlasMapLink.from_dict(next_snapshot)
		if change.next_link == null or change.next_link.id != change.link_id or change.next_link.source_map_id != map_id:
			return false
	if change.current_link != null and change.next_link != null:
		if change.current_link.source_floor_id != change.next_link.source_floor_id:
			return false
	var source_floor: String = str(expected_snapshot.get("source_floor_id", next_snapshot.get("source_floor_id", "")))
	return source.floor_by_id(source_floor) != null


func _prepare_document(campaign: AtlasCampaign, change: ValidatedChange,
		expected_placement_snapshot: Dictionary, undoing: bool) -> bool:
	if new_map_id.is_empty():
		return true
	if undoing:
		return _can_remove_created_map(campaign, change.link_id, expected_placement_snapshot)
	if campaign.maps.has(new_map_id):
		return false
	change.fresh_map = AtlasMapDocument.from_dict(_new_map)
	if change.fresh_map == null:
		return false
	# Raster metadata alone cannot restore runtime pixels; import art in a later command.
	for floor: AtlasFloor in change.fresh_map.floors:
		for layer: AtlasLayer in floor.layers:
			if layer is AtlasRasterLayer and not layer.chunks.is_empty():
				return false
	return true


func _can_remove_created_map(campaign: AtlasCampaign, link_id: String, expected_placement_snapshot: Dictionary) -> bool:
	var created: AtlasMapDocument = campaign.get_map(new_map_id)
	if created == null or created.to_dict() != _new_map or campaign.root_map_id == new_map_id:
		return false
	for link: AtlasMapLink in campaign.links:
		if link.id != link_id and (link.source_map_id == new_map_id or link.target_map_id == new_map_id):
			return false
	var placement_id: String = str(expected_placement_snapshot.get("id", ""))
	for placement: AtlasPlacement in campaign.placements:
		if placement.id != placement_id and (placement.parent_map_id == new_map_id or placement.child_map_id == new_map_id):
			return false
	return true


func _valid_destination(campaign: AtlasCampaign, source: AtlasMapDocument, change: ValidatedChange) -> bool:
	if change.next_link == null:
		return true
	var target: AtlasMapDocument = change.fresh_map
	if target == null or target.id != change.next_link.target_map_id:
		target = campaign.get_map(change.next_link.target_map_id)
	return (target != null and target.floor_by_id(change.next_link.target_floor_id) != null
		and source.floor_by_id(change.next_link.source_floor_id) != null)


func _prepare_placement(campaign: AtlasCampaign, change: ValidatedChange,
		expected_snapshot: Dictionary, next_snapshot: Dictionary) -> bool:
	var current: AtlasPlacement = campaign.placement_by_id(str(expected_snapshot.get("id", "")))
	if not expected_snapshot.is_empty() and (current == null or current.to_dict() != expected_snapshot):
		return false
	if change.current_link != null and campaign.placement_by_id(change.current_link.placement_id) != current:
		return false
	if current != null:
		if change.current_link == null or current.id != change.current_link.placement_id:
			return false
		if current.parent_map_id != map_id or current.child_map_id != change.current_link.target_map_id:
			return false
	change.current_placement = current
	if not next_snapshot.is_empty():
		change.next_placement = AtlasPlacement.from_dict(next_snapshot)
		if change.next_placement == null:
			return false
	change.current_placement_is_shared = current != null and _referenced_by_other_link(campaign, current.id, change.link_id)
	if change.next_placement == null:
		return change.next_link == null or change.next_link.placement_id.is_empty()
	var next: AtlasPlacement = change.next_placement
	if change.next_link == null or change.next_link.placement_id != next.id:
		return false
	if next.parent_map_id != map_id or next.child_map_id != change.next_link.target_map_id or next.child_map_id == map_id:
		return false
	return _resolve_placement_reuse(campaign, change, expected_snapshot, next_snapshot)


func _resolve_placement_reuse(campaign: AtlasCampaign, change: ValidatedChange,
		expected_snapshot: Dictionary, next_snapshot: Dictionary) -> bool:
	var registered: AtlasPlacement = campaign.placement_by_id(change.next_placement.id)
	if registered != null and registered != change.current_placement:
		if registered.to_dict() != next_snapshot:
			return false
		if not _referenced_by_other_link(campaign, registered.id, change.link_id):
			return false
		change.reuse_registered_placement = true
	if change.current_placement_is_shared and change.next_placement.id == change.current_placement.id:
		if next_snapshot != expected_snapshot:
			return false
		change.reuse_registered_placement = true
	return true


func _referenced_by_other_link(campaign: AtlasCampaign, placement_id: String, excluded_link_id: String) -> bool:
	for link: AtlasMapLink in campaign.links:
		if link.id != excluded_link_id and link.placement_id == placement_id:
			return true
	return false


func _within_original_scope(change: ValidatedChange) -> bool:
	if change.current_link != null and not _within_scope(change.current_link, change.current_placement):
		return false
	if change.next_link != null and not _within_scope(change.next_link, change.next_placement):
		return false
	return true


func _apply_validated_change(campaign: AtlasCampaign, change: ValidatedChange, undoing: bool) -> void:
	# Campaign mutation and restoration-slot updates occur only after all validation.
	if change.fresh_map != null:
		campaign.add_map(change.fresh_map)
	if change.current_link != null:
		_link_restore_slot = campaign.links.find(change.current_link)
		campaign.links.remove_at(_link_restore_slot)
	if change.current_placement != null and not change.current_placement_is_shared:
		_placement_restore_slot = campaign.placements.find(change.current_placement)
		campaign.placements.remove_at(_placement_restore_slot)
	if change.next_link != null:
		campaign.links.insert(_insertion_slot(_link_restore_slot, campaign.links.size()), change.next_link)
	if change.next_placement != null and not change.reuse_registered_placement:
		campaign.placements.insert(_insertion_slot(_placement_restore_slot, campaign.placements.size()), change.next_placement)
	if undoing and not new_map_id.is_empty():
		campaign.maps.erase(new_map_id)


func _within_scope(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	if placement != null:
		return _scope.allows_polygon(placement.corners())
	return _scope.contains_rect(Rect2(link.anchor - Vector2.ONE * link.hit_radius, Vector2.ONE * link.hit_radius * 2.0))


func _insertion_slot(saved_slot: int, collection_size: int) -> int:
	if saved_slot < 0:
		return collection_size
	return clampi(saved_slot, 0, collection_size)
