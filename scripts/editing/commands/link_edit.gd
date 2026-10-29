class_name AtlasLinkEdit
extends AtlasEditCommand
## One entrance/footprint transaction. Unlinking never deletes its destination.
## A newly created blank destination is removed on undo only while unchanged and
## unreferenced. Detached metadata snapshots reject stale or shared-footprint edits.

var new_map_id: String = ""
var _before: Dictionary
var _after: Dictionary
var _old_placement: Dictionary
var _new_placement: Dictionary
var _new_map: Dictionary
var _scope: AtlasEditScope
var _link_index: int = -1
var _placement_index: int = -1


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


func _replace(campaign: AtlasCampaign, expected: Dictionary, next: Dictionary,
		expected_placement: Dictionary, next_placement: Dictionary, undoing: bool) -> bool:
	if campaign == null or campaign.get_map(map_id) == null or (expected == next and expected_placement == next_placement):
		return false
	var id: String = str(expected.get("id", next.get("id", "")))
	var current: AtlasMapLink = campaign.link_by_id(id)
	if id.is_empty() or (current == null) != expected.is_empty():
		return false
	if current != null and current.to_dict() != expected:
		return false
	if not expected.is_empty() and str(expected.get("source_map_id", "")) != map_id:
		return false
	if not new_map_id.is_empty() and (not _before.is_empty() or str(_after.get("target_map_id", "")) != new_map_id):
		return false
	var candidate: AtlasMapLink = AtlasMapLink.from_dict(next) if not next.is_empty() else null
	if not next.is_empty() and (candidate == null or candidate.id != id or candidate.source_map_id != map_id):
		return false
	if current != null and candidate != null and current.source_floor_id != candidate.source_floor_id:
		return false
	var source_floor: String = str(expected.get("source_floor_id", next.get("source_floor_id", "")))
	if campaign.get_map(map_id).floor_by_id(source_floor) == null:
		return false
	var fresh_map: AtlasMapDocument
	if not new_map_id.is_empty():
		if not undoing:
			if campaign.maps.has(new_map_id):
				return false
			fresh_map = AtlasMapDocument.from_dict(_new_map)
			if fresh_map == null:
				return false
			# Creation accepts a new document, not raster metadata stripped of its
			# runtime pixels. Imported art belongs to subsequent artwork commands.
			for floor: AtlasFloor in fresh_map.floors:
				for layer: AtlasLayer in floor.layers:
					if layer is AtlasRasterLayer and not layer.chunks.is_empty():
						return false
		else:
			var created: AtlasMapDocument = campaign.get_map(new_map_id)
			if created == null or created.to_dict() != _new_map or campaign.root_map_id == new_map_id:
				return false
			for link: AtlasMapLink in campaign.links:
				if link.id != id and (link.source_map_id == new_map_id or link.target_map_id == new_map_id):
					return false
			for placement: AtlasPlacement in campaign.placements:
				if placement.id != str(expected_placement.get("id", "")) and (placement.parent_map_id == new_map_id or placement.child_map_id == new_map_id):
					return false
	if candidate != null:
		var target: AtlasMapDocument = fresh_map if fresh_map != null and fresh_map.id == candidate.target_map_id else campaign.get_map(candidate.target_map_id)
		if target == null or target.floor_by_id(candidate.target_floor_id) == null \
				or campaign.get_map(map_id).floor_by_id(candidate.source_floor_id) == null:
			return false
	var old: AtlasPlacement = campaign.placement_by_id(str(expected_placement.get("id", "")))
	if not expected_placement.is_empty() and (old == null or old.to_dict() != expected_placement):
		return false
	if current != null and campaign.placement_by_id(current.placement_id) != old:
		return false
	if old != null and (current == null or old.id != current.placement_id or old.parent_map_id != map_id or old.child_map_id != current.target_map_id):
		return false
	var replacement: AtlasPlacement = AtlasPlacement.from_dict(next_placement) if not next_placement.is_empty() else null
	if not next_placement.is_empty() and replacement == null:
		return false
	var keep_old: bool = false
	for link: AtlasMapLink in campaign.links:
		if link.id != id and old != null and link.placement_id == old.id:
			keep_old = true
	var reuse_next: bool = false
	if replacement != null:
		if candidate == null or candidate.placement_id != replacement.id or replacement.parent_map_id != map_id or replacement.child_map_id != candidate.target_map_id or replacement.child_map_id == map_id:
			return false
		var occupied: AtlasPlacement = campaign.placement_by_id(replacement.id)
		if occupied != null and occupied != old:
			if occupied.to_dict() != next_placement:
				return false
			var referenced: bool = false
			for link: AtlasMapLink in campaign.links:
				if link.id != id and link.placement_id == occupied.id:
					referenced = true
			if not referenced:
				return false
			reuse_next = true
		if keep_old and replacement.id == old.id:
			if next_placement != expected_placement:
				return false
			reuse_next = true
	elif candidate != null and not candidate.placement_id.is_empty():
		return false
	# Scope checks apply to both the old and new geometry. Undo restores the exact
	# accepted transaction even if the viewer has since selected another cell.
	if not undoing:
		if current != null and not _within_scope(current, old):
			return false
		if candidate != null and not _within_scope(candidate, replacement):
			return false
	# No mutation occurs until every affected endpoint and object is validated.
	if fresh_map != null:
		campaign.add_map(fresh_map)
	if current != null:
		_link_index = campaign.links.find(current)
		campaign.links.remove_at(_link_index)
	if old != null and not keep_old:
		_placement_index = campaign.placements.find(old)
		campaign.placements.remove_at(_placement_index)
	if candidate != null:
		campaign.links.insert(clampi(_link_index, 0, campaign.links.size()) if _link_index >= 0 else campaign.links.size(), candidate)
	if replacement != null and not reuse_next:
		campaign.placements.insert(clampi(_placement_index, 0, campaign.placements.size()) if _placement_index >= 0 else campaign.placements.size(), replacement)
	if undoing and not new_map_id.is_empty():
		campaign.maps.erase(new_map_id)
	return true


func _within_scope(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	if placement != null:
		return _scope.allows_polygon(placement.corners())
	return _scope.contains_rect(Rect2(link.anchor - Vector2.ONE * link.hit_radius, Vector2.ONE * link.hit_radius * 2.0))
