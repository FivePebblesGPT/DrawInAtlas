extends SceneTree
## T-015: reversible marker-only links between independent map documents.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	for phase: String in ["_creation", "_editing", "_scope_and_rejection"]:
		_check(call(phase) == true, phase + " completes")
	print("ATLAS_LINKS_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
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
	var painted: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	painted.id = "painted"
	child.floors[0].layers.append(painted)
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


func _creation() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "parent"
	var original: Dictionary = campaign.to_dict()
	var child: AtlasMapDocument = AtlasMapDocument.new("new-child", "Independent encounter")
	var add_child: AtlasCreateMap = AtlasCreateMap.new("parent", child)
	_check(history.execute(add_child), "an independent document can be created without a link")
	_check(campaign.get_map(child.id) != null and campaign.placements.is_empty(),
		"independent map has no placement/owner footprint")
	_check(history.undo() and campaign.to_dict() == original, "one undo removes independent document")
	_check(history.redo() and campaign.get_map(child.id) != null,
		"redo restores its stable map ID")
	var link: AtlasMapLink = _link()
	link.target_map_id = child.id
	link.target_floor_id = "ground"
	var command: AtlasLinkEdit = AtlasLinkEdit.new("parent", null, link)
	link.anchor = Vector2(9000, 9000)
	_check(history.execute(command), "create marker-only entrance as separate history command")
	_check(campaign.link_by_id("entrance").anchor == Vector2(40, 40),
		"link drafts are detached from mutation after construction")
	_check(campaign.find_links_at("parent", Vector2(40, 40)).size() == 1,
		"the registered marker is hit-testable")
	_check(history.undo() and campaign.links.is_empty() and campaign.get_map(child.id) != null,
		"unlink undo does not delete destination map")
	_check(history.redo() and campaign.link_by_id("entrance") != null,
		"link redo preserves identity")
	return true


func _editing() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var link: AtlasMapLink = _link()
	_check(AtlasLinkEdit.new("parent", null, link).apply(campaign), "marker links existing destination")
	var destination_before: Dictionary = campaign.get_map("child").to_dict()
	var current: AtlasMapLink = campaign.link_by_id(link.id)
	var next: AtlasMapLink = AtlasMapLink.from_dict(current.to_dict())
	next.anchor = Vector2(-17.5, 29.25)
	next.target_focus = Vector2(-100.25, 500.5)
	var edit: AtlasLinkEdit = AtlasLinkEdit.new("parent", current, next)
	_check(edit.apply(campaign), "marker move and arrival edit succeed without source conversion")
	_check(campaign.find_links_at("parent", next.anchor).size() == 1
		and campaign.find_links_at("parent", current.anchor).is_empty(),
		"marker collision area moves with the entry")
	_check(campaign.get_map("child").to_dict() == destination_before,
		"editing navigation does not resample destination pixels, grid or units")
	var native: PackedScene = AtlasNativeScene.pack_campaign(campaign)
	var io: AtlasStoreIO = AtlasStoreIO.new()
	var restored: AtlasCampaign = AtlasNativeScene.unpack_campaign(io.decode_scene(io.encode_scene(native)))
	_check(restored != null and restored.to_dict() == campaign.to_dict(),
		"native roundtrip keeps precise marker and arrival metadata")
	_check(edit.revert(campaign), "undo restores original entrance")
	var stale: AtlasLinkEdit = AtlasLinkEdit.new("parent", campaign.links[0], next)
	campaign.links[0].hit_radius += 1.0
	var snapshot: Dictionary = campaign.to_dict()
	_check(not stale.apply(campaign) and campaign.to_dict() == snapshot,
		"stale transaction fails without partial mutation")
	var wrong: AtlasLinkEdit = AtlasLinkEdit.new("child", campaign.links[0], null)
	_check(not wrong.apply(campaign) and campaign.to_dict() == snapshot,
		"other maps cannot unlink this source entrance")
	var remove: AtlasLinkEdit = AtlasLinkEdit.new("parent", campaign.links[0], null)
	_check(remove.apply(campaign) and campaign.links.is_empty() and campaign.get_map("child") != null,
		"unlink retains independent destination and source artwork")
	_check(remove.revert(campaign) and campaign.links.size() == 1,
		"undo restores stable entrance identity and list position")
	return true


func _scope_and_rejection() -> bool:
	var campaign: AtlasCampaign = _campaign()
	var scope: AtlasEditScope = AtlasEditScope.new(
		campaign.get_map("parent").grid.cell_polygon(Vector2i.ZERO), true)
	var inside: AtlasMapLink = _link()
	_check(AtlasLinkEdit.new("parent", null, inside, null, null, null, scope).apply(campaign),
		"marker inside finite selected cell is allowed")
	var forbidden: AtlasMapLink = _link("outside")
	forbidden.anchor = Vector2(1000, 1000)
	var snapshot: Dictionary = campaign.to_dict()
	_check(not AtlasLinkEdit.new("parent", null, forbidden, null, null, null, scope).apply(campaign)
		and campaign.to_dict() == snapshot, "outside-cell marker cannot escape edit mask")
	forbidden.target_floor_id = "missing"
	_check(not AtlasLinkEdit.new("parent", null, forbidden).apply(campaign),
		"links cannot create missing destination floors")
	var footprint: AtlasPlacement = AtlasPlacement.new()
	footprint.id = "legacy"
	footprint.parent_map_id = "parent"
	footprint.child_map_id = "child"
	var spatial: AtlasMapLink = _link("spatial")
	spatial.placement_id = footprint.id
	_check(not AtlasLinkEdit.new("parent", null, spatial, null, footprint).apply(campaign)
		and campaign.to_dict() == snapshot, "obsolete spatial footprint cannot be authored")
	_check(not AtlasLinkEdit.new("parent", null, spatial).apply(campaign),
		"placement ID cannot bypass the retired-authoring gate")
	var nested: AtlasMapDocument = AtlasMapDocument.new("nested", "Forbidden")
	var bundle: AtlasMapLink = _link("bundle")
	bundle.target_map_id = nested.id
	bundle.target_floor_id = "ground"
	_check(not AtlasLinkEdit.new("parent", null, bundle, null, null, nested).apply(campaign)
		and campaign.to_dict() == snapshot, "low-level link cannot bundle a new document")
	var battle: AtlasMapDocument = AtlasMapDocument.new("battle", "Forbidden")
	battle.kind = "BATTLEMAP"
	_check(not AtlasCreateMap.new("parent", battle).apply(campaign)
		and campaign.to_dict() == snapshot, "low-level map command refuses BATTLEMAP kind")
	return true
