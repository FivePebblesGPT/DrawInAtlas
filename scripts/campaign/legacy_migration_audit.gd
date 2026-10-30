class_name AtlasLegacyMigrationAudit
extends RefCounted

## Read-only inventory for T-015. It describes historical ownership, but never
## decides whether a linked document should be flattened or converted to D1+.
## In particular, a placement supplies a possible spatial transform, not an
## approved artwork migration or a guarantee of real-world scale.


static func inspect(campaign: AtlasCampaign) -> Dictionary:
	if campaign == null:
		return {}
	var report: Dictionary = {
		"approval_required": true,
		"maps": [], "placements": [], "links": [], "risks": []
	}
	var map_ids: Array[String] = []
	for map_id: String in campaign.maps:
		map_ids.append(map_id)
	map_ids.sort()
	for map_id: String in map_ids:
		var document: AtlasMapDocument = campaign.get_map(map_id)
		if document == null:
			_risk(report, "invalid_map", map_id)
			continue
		var map_record: Dictionary = {
			"id": document.id, "name": document.display_name,
			"kind": document.kind, "tags": document.tags.duplicate(),
			"default_floor_id": document.default_floor_id,
			"grid": document.grid.to_dict(), "terrain_grid": document.get_terrain_grid().to_dict(),
			"floors": [], "incoming_link_ids": [], "outgoing_link_ids": [],
			"placement_ids": []
		}
		for floor: AtlasFloor in document.floors:
			var layers: Array[Dictionary] = []
			for layer: AtlasLayer in floor.layers:
				var layer_record: Dictionary = {
					"id": layer.id, "name": layer.display_name, "kind": layer.kind,
					"detail_level": layer.detail_level, "visible": layer.visible,
					"locked": layer.locked, "opacity": layer.opacity
				}
				if layer is AtlasInkLayer:
					layer_record["stroke_count"] = (layer as AtlasInkLayer).strokes.size()
				elif layer is AtlasTerrainLayer:
					var tiles: AtlasTerrainLayer = layer as AtlasTerrainLayer
					layer_record["cell_count"] = tiles.terrain.size()
					layer_record["grid"] = tiles.grid.to_dict() if tiles.grid != null else document.get_terrain_grid(floor.id).to_dict()
				elif layer is AtlasRasterLayer:
					var raster: AtlasRasterLayer = layer as AtlasRasterLayer
					var chunk_keys: Array[String] = raster.chunks.keys()
					chunk_keys.sort()
					layer_record["chunk_keys"] = chunk_keys
					layer_record["pixels_per_unit"] = raster.pixels_per_unit
					layer_record["transform"] = raster.to_dict()["transform"]
				layers.append(layer_record)
			(map_record["floors"] as Array).append({"id": floor.id, "name": floor.display_name,
				"layers": layers})
		(report["maps"] as Array).append(map_record)
		if document.kind == "BATTLEMAP":
			_risk(report, "legacy_document_kind", map_id)

	for placement: AtlasPlacement in campaign.placements:
		var referencing_links: Array[String] = []
		for link: AtlasMapLink in campaign.links:
			if link.placement_id == placement.id:
				referencing_links.append(link.id)
		referencing_links.sort()
		var map_owner: AtlasMapDocument = campaign.get_map(placement.parent_map_id)
		var map_child: AtlasMapDocument = campaign.get_map(placement.child_map_id)
		var placement_record: Dictionary = placement.to_dict()
		placement_record["link_ids"] = referencing_links
		# Candidate transform documented as a matrix; not an approved remap.
		var candidate: Transform2D = placement.child_to_parent()
		placement_record["candidate_child_to_parent"] = [
			candidate.x.x, candidate.x.y, candidate.y.x, candidate.y.y,
			candidate.origin.x, candidate.origin.y]
		(report["placements"] as Array).append(placement_record)
		if referencing_links.is_empty():
			_risk(report, "orphan_placement", placement.id)
		if placement.symbolic:
			_risk(report, "symbolic_no_spatial_registration", placement.id)
		if referencing_links.size() > 1:
			_risk(report, "shared_placement", placement.id)
		if map_owner == null or map_child == null:
			_risk(report, "missing_placement_map", placement.id)
		for link_id: String in referencing_links:
			var used_by: AtlasMapLink = campaign.link_by_id(link_id)
			if used_by.source_map_id != placement.parent_map_id or used_by.target_map_id != placement.child_map_id:
				_risk(report, "placement_link_mismatch", link_id)

	for link: AtlasMapLink in campaign.links:
		var link_record: Dictionary = link.to_dict()
		var source: AtlasMapDocument = campaign.get_map(link.source_map_id)
		var destination: AtlasMapDocument = campaign.get_map(link.target_map_id)
		(report["links"] as Array).append(link_record)
		if source == null or destination == null:
			_risk(report, "dangling_link_map", link.id)
		elif source.floor_by_id(link.source_floor_id) == null or destination.floor_by_id(link.target_floor_id) == null:
			_risk(report, "dangling_link_floor", link.id)
		if not link.placement_id.is_empty() and campaign.placement_by_id(link.placement_id) == null:
			_risk(report, "missing_link_placement", link.id)
		for map_record: Dictionary in report["maps"]:
			if map_record["id"] == link.source_map_id:
				(map_record["outgoing_link_ids"] as Array).append(link.id)
			if map_record["id"] == link.target_map_id:
				(map_record["incoming_link_ids"] as Array).append(link.id)
	for placement: AtlasPlacement in campaign.placements:
		for map_record: Dictionary in report["maps"]:
			if map_record["id"] == placement.parent_map_id or map_record["id"] == placement.child_map_id:
				(map_record["placement_ids"] as Array).append(placement.id)
	return report


static func _risk(report: Dictionary, reason: String, item_id: String) -> void:
	(report["risks"] as Array).append({"reason": reason, "id": item_id})
