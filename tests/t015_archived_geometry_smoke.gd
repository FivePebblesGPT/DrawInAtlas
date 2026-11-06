extends SceneTree
## T-015: imported footprint metadata is archival, never a source of active
## geometry, marker hits, navigation, snapshots, or child-board pixels.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T015 ARCHIVE FAILED: " + label)


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "world"
	var world: AtlasMapDocument = AtlasMapDocument.new("world", "Independent world")
	var city: AtlasMapDocument = AtlasMapDocument.new("city", "Independent city")
	campaign.add_map(world)
	campaign.add_map(city)

	var marker: AtlasMapLink = AtlasMapLink.new()
	marker.id = "marker"
	marker.source_map_id = world.id
	marker.target_map_id = city.id
	marker.anchor = Vector2(-30, 42)
	marker.hit_radius = 8.0
	marker.target_focus = Vector2(100, -75)
	marker.target_zoom = 2.0
	campaign.links.append(marker)

	var archived: AtlasPlacement = AtlasPlacement.new()
	archived.id = "obsolete-footprint"
	archived.parent_map_id = world.id
	archived.child_map_id = city.id
	archived.origin = Vector2(50, 50)
	archived.columns = 40
	archived.rows = 30
	archived.parent_units_per_cell = 20.0
	campaign.placements.append(archived)
	var old_link: AtlasMapLink = AtlasMapLink.from_dict(marker.to_dict())
	old_link.id = "historical"
	old_link.placement_id = archived.id
	old_link.anchor = Vector2(1000, 1000)
	campaign.links.append(old_link)

	var original: Dictionary = campaign.to_dict()
	_check(campaign.placement_by_id(archived.id) == archived,
		"archive metadata can be inspected intentionally")
	_check(original.placements.size() == 1 and original.links.size() == 2,
		"native serialization retains legacy fields without deleting them")
	var restored: AtlasCampaign = AtlasCampaign.from_dict(original)
	_check(restored != null and restored.to_dict() == original,
		"archive round-trips without migrating geometry or changing map documents")
	_check(restored.get_map(city.id) != restored.get_map(world.id),
		"archived relationship never makes an independently stored child")
	_check(campaign.find_links_at(world.id, marker.anchor).size() == 1
		and campaign.find_links_at(world.id, marker.anchor)[0].id == marker.id,
		"only the supported marker is hittable")
	_check(campaign.find_links_at(world.id, old_link.anchor).is_empty(),
		"historical anchor never becomes a replacement marker")
	_check(campaign.find_links_at(world.id, archived.origin).is_empty(),
		"historical polygon never becomes a pointer target")
	_check(campaign.incoming_links(city.id).size() == 2,
		"archive remains inspectable as a named navigation record")

	var visible: PackedVector2Array = PackedVector2Array([
		Vector2(-40, 35), Vector2(-20, 35), Vector2(-20, 50), Vector2(-40, 50)])
	var result: AtlasOverviewResult = AtlasOverview.query(campaign, world.id, "ground",
		AtlasOverview.Filter.VISIBLE, "", visible, false)
	_check(result.entries.size() == 1 and result.entries[0].link_id == marker.id,
		"visible overview uses marker circles, never archived polygons")
	var historical_visible: PackedVector2Array = PackedVector2Array([
		Vector2(45, 45), Vector2(70, 45), Vector2(70, 70), Vector2(45, 70)])
	_check(AtlasOverview.query(campaign, world.id, "ground",
		AtlasOverview.Filter.VISIBLE, "", historical_visible, false).entries.is_empty(),
		"archived polygon cannot appear in spatial results")
	var map_results: AtlasOverviewResult = AtlasOverview.query(campaign, world.id, "ground",
		AtlasOverview.Filter.MAP, "", PackedVector2Array(), false)
	_check(map_results.entries.size() == 2, "ordinary overview still reports both link records")
	var archived_entry: AtlasOverviewEntry
	for entry: AtlasOverviewEntry in map_results.entries:
		if entry.link_id == old_link.id:
			archived_entry = entry
			break
	_check(archived_entry != null and not archived_entry.can_focus
		and archived_entry.broken_reason.contains("Retired placement"),
		"archived entry is explicitly non-actionable")
	_check(archived_entry != null and not AtlasOverview.entry_is_current(campaign, archived_entry),
		"archived entry cannot authorize Open or Focus")
	var fresh_entry: AtlasOverviewEntry
	for entry: AtlasOverviewEntry in map_results.entries:
		if entry.link_id == marker.id:
			fresh_entry = entry
	_check(fresh_entry != null and AtlasOverview.entry_is_current(campaign, fresh_entry),
		"independent marker entry authorizes navigation")
	marker.anchor += Vector2(3, 4)
	_check(not AtlasOverview.entry_is_current(campaign, fresh_entry),
		"a marker move invalidates its existing snapshot")
	marker.anchor -= Vector2(3, 4)

	var replacement: AtlasMapLink = AtlasMapLink.from_dict(old_link.to_dict())
	replacement.anchor += Vector2(9, 5)
	_check(not AtlasLinkEdit.new(world.id, old_link, replacement).apply(campaign),
		"marker-only command cannot mutate a legacy link")
	_check(not AtlasLinkEdit.new(world.id, old_link, null).apply(campaign),
		"marker-only command cannot destroy archived metadata")
	_check(campaign.to_dict() == original, "blocked edits preserve exact old serialized structure")

	var references: AtlasMapReferences = AtlasMapReferences.new()
	root.add_child(references)
	references.select_source(old_link.id)
	references.set_frozen(true)
	references.refresh()
	_check(references.source_link_id == old_link.id and references.frozen,
		"navigation source selection remains a non-destructive UI preference")
	_check(references.get_child_count() == 0 and references.omitted_count == 0,
		"archived source does not schedule child capture or create textures")
	references.reset()
	_check(references.source_link_id.is_empty() and not references.frozen,
		"source reset clears only transient state")
	references.free()
	_check(campaign.to_dict() == original, "reference actions do not change the saved graph")
	_check(campaign.get_map(city.id).to_dict() == city.to_dict(),
		"target document is unchanged after reference selection")

	print("ATLAS_T015_ARCHIVE_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
