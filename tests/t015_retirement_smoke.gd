extends SceneTree
## T-015: no public command can reintroduce battlemat child ownership.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T015 RETIREMENT FAILED: " + description)


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "parent"
	var parent: AtlasMapDocument = AtlasMapDocument.new("parent", "Parent")
	var child: AtlasMapDocument = AtlasMapDocument.new("child", "Independent")
	child.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 24.0)
	campaign.add_map(parent)
	campaign.add_map(child)
	var before: Dictionary = campaign.to_dict()

	var legacy: AtlasMapDocument = AtlasMapDocument.new("battle", "Forbidden child")
	legacy.kind = "BATTLEMAP"
	var create: AtlasCreateMap = AtlasCreateMap.new(parent.id, legacy)
	_check(not create.apply(campaign) and campaign.to_dict() == before,
		"low-level map command rejects legacy battlemap kind atomically")

	var normal: AtlasMapDocument = AtlasMapDocument.new("independent", "Allowed map")
	var independent_create: AtlasCreateMap = AtlasCreateMap.new(parent.id, normal)
	_check(independent_create.apply(campaign) and campaign.get_map(normal.id) != null,
		"independent map creation remains supported")
	_check(independent_create.revert(campaign) and campaign.to_dict() == before,
		"independent map creation still undoes without affecting existing maps")

	var marker: AtlasMapLink = AtlasMapLink.new()
	marker.id = "door"
	marker.source_map_id = parent.id
	marker.target_map_id = child.id
	marker.anchor = Vector2(-50.5, 28.25)
	marker.target_focus = Vector2(99.5, -70.25)
	marker.target_zoom = 1.5
	var create_marker: AtlasLinkEdit = AtlasLinkEdit.new(parent.id, null, marker)
	_check(create_marker.apply(campaign) and campaign.links.size() == 1,
		"marker-only navigation edge can be created")
	_check(campaign.find_links_at(parent.id, marker.anchor).size() == 1,
		"independent target is reachable by the marker")
	var clean: Dictionary = campaign.to_dict()

	var footprint: AtlasPlacement = AtlasPlacement.new()
	footprint.id = "obsolete"
	footprint.parent_map_id = parent.id
	footprint.child_map_id = child.id
	var with_placement: AtlasMapLink = AtlasMapLink.from_dict(marker.to_dict())
	with_placement.id = "door-with-footprint"
	with_placement.placement_id = footprint.id
	_check(not AtlasLinkEdit.new(parent.id, null, with_placement, null, footprint).apply(campaign)
		and campaign.to_dict() == clean,
		"command rejects new spatial or symbolic ownership atomically")
	_check(not AtlasLinkEdit.new(parent.id, null, with_placement).apply(campaign)
		and campaign.to_dict() == clean,
		"dangling placement references cannot bypass the command guard")
	var nested: AtlasMapDocument = AtlasMapDocument.new("nested", "Nested")
	var new_child_link: AtlasMapLink = AtlasMapLink.from_dict(marker.to_dict())
	new_child_link.id = "nested-door"
	new_child_link.target_map_id = nested.id
	_check(not AtlasLinkEdit.new(parent.id, null, new_child_link, null, null, nested).apply(campaign)
		and campaign.to_dict() == clean,
		"link command cannot create child documents even without a footprint")

	# An old fixture imported into memory remains unmodified by any attempted
	# legacy edit. This is not approval to migrate or write historical user data.
	var legacy_link: AtlasMapLink = AtlasMapLink.from_dict(marker.to_dict())
	legacy_link.id = "old-link"
	legacy_link.placement_id = footprint.id
	campaign.links.append(legacy_link)
	campaign.placements.append(footprint)
	var legacy_state: Dictionary = campaign.to_dict()
	var altered: AtlasMapLink = AtlasMapLink.from_dict(legacy_link.to_dict())
	altered.anchor += Vector2(10, 5)
	_check(not AtlasLinkEdit.new(parent.id, legacy_link, altered, footprint, footprint).apply(campaign)
		and campaign.to_dict() == legacy_state,
		"legacy placement editing no longer mutates imported fixtures")
	campaign.links.erase(legacy_link)
	campaign.placements.erase(footprint)
	_check(campaign.to_dict() == clean, "historical fixture cleanup restores marker-only graph")

	var moved: AtlasMapLink = AtlasMapLink.from_dict(marker.to_dict())
	moved.anchor = Vector2(500.5, 125.25)
	var edit_marker: AtlasLinkEdit = AtlasLinkEdit.new(parent.id, campaign.links[0], moved)
	_check(edit_marker.apply(campaign) and campaign.find_links_at(parent.id, moved.anchor).size() == 1,
		"marker navigation can still move")
	_check(edit_marker.revert(campaign) and campaign.to_dict() == clean,
		"marker edit reverts atomically and preserves arrival metadata")
	_check(create_marker.revert(campaign) and campaign.to_dict() == before,
		"marker creation undo returns the complete original campaign")

	print("ATLAS_T015_RETIREMENT_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
