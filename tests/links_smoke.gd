extends SceneTree
## Real command/history/store seam for reversible entrances and placements.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	for phase: String in ["_creation", "_editing", "_scope_and_sharing"]:
		_check(call(phase) == true, phase + " completes")
	print("ATLAS_LINKS_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LINKS FAILED: " + label)


func _campaign() -> AtlasCampaign:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "parent"
	var parent: AtlasMapDocument = AtlasMapDocument.new("parent", "Source")
	parent.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 100.0)
	parent.grid.distance_unit = "mi"
	var child: AtlasMapDocument = AtlasMapDocument.new("child", "Destination")
	child.grid.distance_unit = "ft"
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	child.floors.append(upper)
	var image: Image = Image.create(9, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.7, 0.5))
	child.floors[0].layers.append(AtlasRasterLayer.from_image(image))
	campaign.add_map(parent)
	campaign.add_map(child)
	return campaign


func _link(id: String = "entrance") -> AtlasMapLink:
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = id
	link.source_map_id = "parent"
	link.target_map_id = "child"
	link.target_floor_id = "upper"
	link.anchor = Vector2(40, 40)
	link.hit_radius = 2.0
	link.target_focus = Vector2(-31.25, 99.5)
	link.target_zoom = 2.25
	return link


func _placement() -> AtlasPlacement:
	var placement: AtlasPlacement = AtlasPlacement.new()
	placement.id = "footprint"
	placement.parent_map_id = "parent"
	placement.child_map_id = "child"
	placement.origin = Vector2(40, 40)
	placement.columns = 2
	placement.rows = 2
	placement.parent_units_per_cell = 10.0
	placement.child_units_per_cell = 64.0
	return placement


func _creation() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "parent"
	var original: Dictionary = campaign.to_dict()
	var document: AtlasMapDocument = AtlasMapDocument.new("new-child", "Independent encounter")
	var link: AtlasMapLink = _link()
	link.target_map_id = document.id
	link.target_floor_id = "ground"
	var placement: AtlasPlacement = _placement()
	placement.child_map_id = document.id
	link.placement_id = placement.id
	var command: AtlasLinkEdit = AtlasLinkEdit.new("parent", null, link, null, placement, document)
	link.anchor = Vector2(9999, 9999)
	placement.columns = 999
	document.display_name = "changed after snapshot"
	_check(history.execute(command), "atomic new map/link/placement creation")
	_check(campaign.get_map("new-child").display_name == "Independent encounter"
		and campaign.placement_by_id("footprint").columns == 2, "detached creation drafts")
	_check(history.is_dirty() and campaign.links.size() == 1, "creation dirties one history transaction")
	_check(history.undo() and campaign.to_dict() == original and not history.is_dirty(), "one undo removes the complete blank bundle")
	_check(history.redo() and campaign.get_map("new-child") != null, "redo restores stable document identity")
	campaign.get_map("new-child").floors[0].strokes.append(AtlasStroke.new(PackedVector2Array([Vector2.ONE])))
	var changed: Dictionary = campaign.to_dict()
	_check(not history.undo() and campaign.to_dict() == changed, "undo cannot delete externally edited child content")
	var wrong: AtlasLinkEdit = AtlasLinkEdit.new("child", campaign.links[0], null, campaign.placements[0])
	_check(not wrong.apply(campaign) and campaign.to_dict() == changed, "another document cannot unlink a source entrance")
	return true


func _editing() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var link: AtlasMapLink = _link()
	var placement: AtlasPlacement = _placement()
	link.placement_id = placement.id
	_check(AtlasLinkEdit.new("parent", null, link, null, placement).apply(campaign), "link an existing independent destination")
	var before_child: Dictionary = campaign.get_map("child").to_dict()
	var old: AtlasMapLink = campaign.link_by_id(link.id)
	var next: AtlasMapLink = AtlasMapLink.from_dict(old.to_dict())
	var resized: AtlasPlacement = AtlasPlacement.from_dict(placement.to_dict())
	resized.origin = Vector2(-17.5, 29.25)
	resized.rotation = deg_to_rad(37.0)
	resized.columns = 20
	resized.rows = 15
	resized.symbolic = true
	next.anchor = resized.origin
	next.target_focus = Vector2(-100.25, 500.5)
	var edit: AtlasLinkEdit = AtlasLinkEdit.new("parent", old, next, campaign.placement_by_id(placement.id), resized)
	_check(edit.apply(campaign), "move/rotate/resize and change arrival without resampling child")
	_check(campaign.get_map("child").to_dict() == before_child, "child artwork/grid/units are unchanged")
	var transform: Transform2D = campaign.placement_by_id(placement.id).child_to_parent()
	var roundtrip: Vector2 = transform.affine_inverse() * (transform * Vector2(123, 456))
	_check(roundtrip.is_equal_approx(Vector2(123, 456)), "37-degree child/parent affine basis is invertible")
	var native: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	var io: AtlasStoreIO = AtlasStoreIO.new()
	var restored: AtlasCampaign = AtlasNativeScene.unpack_campaign(io.decode_scene(io.encode_scene(native)))
	_check(restored != null and restored.to_dict() == campaign.to_dict(), "native v1 roundtrip retains entrance/floor/placement edits")
	_check(edit.revert(campaign), "undo restores original placement and arrival")
	var stale: AtlasLinkEdit = AtlasLinkEdit.new("parent", campaign.links[0], next, campaign.placements[0], resized)
	campaign.links[0].hit_radius += 1.0
	var stale_state: Dictionary = campaign.to_dict()
	_check(not stale.apply(campaign) and campaign.to_dict() == stale_state, "stale transaction is rejected atomically")
	var remove: AtlasLinkEdit = AtlasLinkEdit.new("parent", campaign.links[0], null, campaign.placements[0])
	_check(remove.apply(campaign) and campaign.links.is_empty() and campaign.placements.is_empty(), "unlink removes unshared footprint")
	_check(campaign.get_map("child").to_dict() == before_child, "unlink keeps destination and exact artwork")
	_check(remove.revert(campaign) and campaign.links.size() == 1, "undo unlink restores identity and order")
	return true


func _scope_and_sharing() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var scope: AtlasEditScope = AtlasEditScope.new(campaign.get_map("parent").grid.cell_polygon(Vector2i.ZERO), true)
	var link: AtlasMapLink = _link()
	var placement: AtlasPlacement = _placement()
	link.placement_id = placement.id
	_check(AtlasLinkEdit.new("parent", null, link, null, placement, null, scope).apply(campaign), "footprint inside selected cell accepted")
	var outside: AtlasPlacement = AtlasPlacement.from_dict(placement.to_dict())
	outside.columns = 100
	var before: Dictionary = campaign.to_dict()
	_check(not AtlasLinkEdit.new("parent", campaign.links[0], link, campaign.placements[0], outside, null, scope).apply(campaign)
		and campaign.to_dict() == before, "out-of-cell resize has no partial changes")
	var second: AtlasMapLink = _link("other-door")
	second.placement_id = placement.id
	campaign.links.append(second)
	_check(not AtlasLinkEdit.new("parent", campaign.links[0], link, campaign.placements[0], outside).apply(campaign), "shared geometry cannot be changed through one entrance")
	var remove: AtlasLinkEdit = AtlasLinkEdit.new("parent", campaign.links[0], null, campaign.placements[0])
	_check(remove.apply(campaign) and campaign.placements.size() == 1 and campaign.links.size() == 1, "unlink retains a footprint still used by another entrance")
	_check(remove.revert(campaign) and campaign.links[0].id == link.id, "undo shared unlink restores original entrance order")
	var marker: AtlasMapLink = _link("outside-marker")
	marker.anchor = Vector2(1000, 1000)
	_check(not AtlasLinkEdit.new("parent", null, marker, null, null, null, scope).apply(campaign), "cell scope also guards marker geometry")
	var invalid: AtlasMapLink = _link("bad-floor")
	invalid.target_floor_id = "missing"
	_check(not AtlasLinkEdit.new("parent", null, invalid).apply(campaign), "new links cannot introduce missing target floors")
	var self_link: AtlasMapLink = _link("self-footprint")
	self_link.target_map_id = "parent"
	self_link.target_floor_id = "ground"
	var self_placement: AtlasPlacement = _placement()
	self_placement.id = "self-placement"
	self_placement.child_map_id = "parent"
	self_link.placement_id = self_placement.id
	_check(not AtlasLinkEdit.new("parent", null, self_link, null, self_placement).apply(campaign),
		"a footprint must refer to an independent destination document")
	return true
