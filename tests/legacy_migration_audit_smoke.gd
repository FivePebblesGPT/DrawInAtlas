extends SceneTree
## T-015: inventory and guard the historical graph before an approved migration.
## No conversion or edits to a user's default save slot are performed.

const SLOT: String = "user://atlas_legacy_audit/fixture.scn"
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("LEGACY MIGRATION AUDIT FAILED: " + description)


func _map_record(report: Dictionary, map_id: String) -> Dictionary:
	for record: Dictionary in report["maps"]:
		if record["id"] == map_id:
			return record
	return {}


func _placement_record(report: Dictionary, placement_id: String) -> Dictionary:
	for record: Dictionary in report["placements"]:
		if record["id"] == placement_id:
			return record
	return {}


func _has_risk(report: Dictionary, reason: String, item_id: String) -> bool:
	for risk: Dictionary in report["risks"]:
		if risk["reason"] == reason and risk["id"] == item_id:
			return true
	return false


func _link(link_id: String, source: String, target: String, placement_id: String) -> AtlasMapLink:
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = link_id
	link.source_map_id = source
	link.target_map_id = target
	link.placement_id = placement_id
	return link


func _run() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var child: AtlasMapDocument = campaign.get_map("greyhaven")
	child.kind = "BATTLEMAP"
	child.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 32.0)
	var ink: AtlasInkLayer = child.floors[0].ink_layer()
	ink.strokes.append(AtlasStroke.new(PackedVector2Array([
		Vector2(-25, 12), Vector2(19, 47)]), Color(0.3, 0.5, 0.7, 0.4), 3.0))
	var tile: AtlasTileLayer = child.floors[0].terrain_layer()
	tile.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 15.0)
	tile.terrain["-3,4"] = 2
	var image: Image = Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.2, 0.7, 0.5))
	var raster: AtlasRasterLayer = AtlasRasterLayer.new("legacy-raster", "Legacy transparent pixels")
	raster.transform = Transform2D(0.3, Vector2(1.0, 0.8), 0.0, Vector2(-10, 16))
	raster.pixels_per_unit = 2.0
	raster.chunks["-2,3"] = AtlasRasterChunk.new(Vector2i(-2, 3), image)
	child.floors[0].layers.append(raster)
	var upper: AtlasFloor = AtlasFloor.new()
	upper.id = "upper"
	upper.display_name = "Upper"
	child.floors.append(upper)

	var standalone: AtlasMapDocument = AtlasMapDocument.new("standalone", "Unplaced legacy map")
	standalone.kind = "BATTLEMAP"
	campaign.add_map(standalone)

	var spatial: AtlasPlacement = AtlasPlacement.new()
	spatial.id = "spatial"
	spatial.parent_map_id = "world"
	spatial.child_map_id = "greyhaven"
	spatial.origin = Vector2(23, -11)
	spatial.parent_units_per_cell = 24.0
	spatial.child_units_per_cell = 64.0
	campaign.placements.append(spatial)
	campaign.links.append(_link("spatial-a", "world", "greyhaven", spatial.id))
	campaign.links.append(_link("spatial-b", "world", "greyhaven", spatial.id))
	campaign.links.append(_link("conflicting", "greyhaven", "world", spatial.id))

	var symbolic: AtlasPlacement = AtlasPlacement.new()
	symbolic.id = "symbolic"
	symbolic.parent_map_id = "world"
	symbolic.child_map_id = "greyhaven"
	symbolic.symbolic = true
	campaign.placements.append(symbolic)
	campaign.links.append(_link("symbolic-link", "world", "greyhaven", symbolic.id))
	var orphan: AtlasPlacement = AtlasPlacement.new()
	orphan.id = "orphan"
	orphan.parent_map_id = "world"
	orphan.child_map_id = "standalone"
	campaign.placements.append(orphan)
	campaign.links.append(_link("missing-placement", "world", "greyhaven", "not-in-registry"))
	campaign.links.append(_link("missing-map", "world", "not-in-registry", ""))
	var bad_floor: AtlasMapLink = _link("missing-floor", "world", "greyhaven", "")
	bad_floor.target_floor_id = "not-in-registry"
	campaign.links.append(bad_floor)

	var default_existed: bool = FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH)
	var default_bytes: PackedByteArray = (FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH)
		if default_existed else PackedByteArray())
	var before: Dictionary = campaign.to_dict().duplicate(true)
	var pixels_before: PackedByteArray = image.get_data().duplicate()
	var report: Dictionary = AtlasLegacyMigrationAudit.inspect(campaign)
	_check(report["approval_required"] and report["maps"].size() == 3,
		"preflight cannot authorize conversion and includes every map")
	_check(report["links"].size() == campaign.links.size()
		and report["placements"].size() == campaign.placements.size(),
		"preflight retains every link/placement, including unresolved and unreferenced records")
	_check(campaign.to_dict() == before and image.get_data() == pixels_before,
		"preflight has no model or raster-pixel side effects")
	_check(AtlasLegacyMigrationAudit.inspect(campaign) == report,
		"preflight report is deterministic for an unchanged campaign")

	var child_record: Dictionary = _map_record(report, "greyhaven")
	var standalone_record: Dictionary = _map_record(report, "standalone")
	_check(child_record["kind"] == "BATTLEMAP" and child_record["floors"].size() == 2,
		"legacy kind and independent floor identities are inventoried")
	_check(standalone_record["incoming_link_ids"].is_empty() and standalone_record["outgoing_link_ids"].is_empty(),
		"unplaced independent map is retained, not silently merged")
	_check(_has_risk(report, "legacy_document_kind", "greyhaven")
		and _has_risk(report, "legacy_document_kind", "standalone"),
		"legacy kind is flagged even without an incoming placement")
	var layers: Array = child_record["floors"][0]["layers"]
	var layer_found: bool = false
	for layer: Dictionary in layers:
		if layer["id"] == "legacy-raster":
			layer_found = (layer["chunk_keys"] == ["-2,3"]
				and layer["pixels_per_unit"] == 2.0 and layer["transform"].size() == 6)
	_check(layer_found, "raster chunk keys, pixel scale, and transform are inventoried")
	var ink_found: bool = false
	var terrain_found: bool = false
	for layer: Dictionary in layers:
		if layer["kind"] == "INK" and layer["stroke_count"] == ink.strokes.size():
			ink_found = true
		if layer["kind"] == "TILES" and layer["cell_count"] == tile.terrain.size() and layer["grid"]["cell_size"] == 15.0:
			terrain_found = true
	_check(ink_found and terrain_found, "ink count and independent tile grid are inventoried")

	var spatial_record: Dictionary = _placement_record(report, "spatial")
	_check(spatial_record["link_ids"].size() == 3 and spatial_record["child_units_per_cell"] == 64.0,
		"shared footprint references and legacy unit ratios are reported")
	var matrix: Array = spatial_record["candidate_child_to_parent"]
	_check(is_equal_approx(matrix[0], 0.375) and is_zero_approx(matrix[1])
		and matrix[4] == 23.0 and matrix[5] == -11.0,
		"candidate affine transform is recorded without applying it")
	_check(_has_risk(report, "shared_placement", "spatial")
		and _has_risk(report, "placement_link_mismatch", "conflicting"),
		"shared and conflicting placements require explicit review")
	_check(_has_risk(report, "symbolic_no_spatial_registration", "symbolic"),
		"symbolic placement is never treated as a registered canvas transform")
	_check(_has_risk(report, "orphan_placement", "orphan")
		and _has_risk(report, "missing_link_placement", "missing-placement"),
		"orphan and missing placements are reported rather than discarded")
	_check(_has_risk(report, "dangling_link_map", "missing-map")
		and _has_risk(report, "dangling_link_floor", "missing-floor"),
		"dangling destinations and floor references remain visible for manual repair")

	# Existing validated native saves are still byte-for-byte artwork-compatible;
	# this is a separate test slot, never the editor's default campaign slot.
	var saved: Error = AtlasCampaignStore.save_campaign(campaign, SLOT)
	_check(saved == OK, "legacy graph writes to an isolated native save slot")
	if saved == OK:
		var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(SLOT)
		_check(restored != null and restored.to_dict() == before,
			"unconverted legacy graph round-trips without lost metadata")
		if restored != null:
			var loaded_raster: AtlasRasterLayer = restored.get_map("greyhaven").floors[0].layer_by_id("legacy-raster") as AtlasRasterLayer
			_check(loaded_raster != null and loaded_raster.chunks["-2,3"].image.get_data() == pixels_before,
				"original transparent pixels in signed raster chunk survive native save")
			_check(AtlasLegacyMigrationAudit.inspect(restored) == report,
				"audit findings survive native save/load unchanged")
	for suffix: String in [".scn", ".bak.scn", ".pending.scn", ".bak.pending.scn"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SLOT.trim_suffix(".scn") + suffix))
	_check(FileAccess.file_exists(AtlasCampaignStore.DEFAULT_PATH) == default_existed,
		"the user's default campaign slot is not created or deleted")
	if default_existed:
		_check(FileAccess.get_file_as_bytes(AtlasCampaignStore.DEFAULT_PATH) == default_bytes,
			"the user's default campaign save bytes are untouched")
	print("ATLAS_LEGACY_MIGRATION_AUDIT_%s (%d checks, %d failures)" % [
		"PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)
