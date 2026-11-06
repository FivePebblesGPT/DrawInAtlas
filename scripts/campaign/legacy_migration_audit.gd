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
			"grid": document.grid.to_dict(),
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
				if layer is AtlasObjectsLayer:
					var objects: AtlasObjectsLayer = layer as AtlasObjectsLayer
					layer_record["stroke_count"] = objects.strokes.size()
					layer_record["text_count"] = 0
					layer_record["prop_count"] = 0
					layer_record["wall_path_count"] = 0
					for object: AtlasStroke in objects.strokes:
						if object.is_text():
							layer_record["text_count"] += 1
						elif object.is_prop():
							layer_record["prop_count"] += 1
						elif object.editable_path:
							layer_record["wall_path_count"] += 1
				elif layer is AtlasTokenLayer:
					layer_record["token_count"] = (layer as AtlasTokenLayer).tokens.size()
				elif layer is AtlasRasterLayer:
					var raster: AtlasRasterLayer = layer as AtlasRasterLayer
					var chunk_keys: Array[String] = raster.chunks.keys()
					chunk_keys.sort()
					layer_record["chunk_keys"] = chunk_keys
					layer_record["pixels_per_unit"] = raster.pixels_per_unit
					layer_record["transform"] = raster.to_dict()["transform"]
				layers.append(layer_record)
			(map_record["floors"] as Array).append({"id": floor.id, "name": floor.display_name,
				"layers": layers, "fog_enabled": floor.fog_enabled,
				"fog_region_count": floor.fog_regions.size()})
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
		# The footprint is not proof that its child artwork fits inside it.
		# Report potential clipping before offering a copy-first conversion.
		placement_record["artwork_crop_warnings"] = (
			_inspect_child_artwork(placement, map_child) if not placement.symbolic else [])
		var registered_risks: Dictionary[String, bool] = {}
		for warning: Dictionary in placement_record["artwork_crop_warnings"]:
			var reason: String = warning["reason"]
			if not registered_risks.has(reason):
				_risk(report, reason, placement.id)
				registered_risks[reason] = true
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


## The footprint is a child-board rectangle, not a clipping authority. For
## rasters, use only nontransparent pixel extents (not whole sparse chunks).
## The transformed bounding quad is conservative under rotation: a warning may
## require inspection, but it must never authorize conversion or discard art.
static func _inspect_child_artwork(placement: AtlasPlacement,
		child: AtlasMapDocument) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	if child == null:
		return warnings
	var crop: Rect2 = placement.child_bounds()
	for floor: AtlasFloor in child.floors:
		if floor.fog_enabled or not floor.fog_regions.is_empty():
			warnings.append({"reason": "fog_policy_requires_review", "floor_id": floor.id})
		for layer: AtlasLayer in floor.layers:
			if layer is AtlasRasterLayer:
				var raster: AtlasRasterLayer = layer as AtlasRasterLayer
				if not is_finite(raster.pixels_per_unit) or raster.pixels_per_unit <= 0.0:
					warnings.append({"reason": "invalid_raster_density",
						"floor_id": floor.id, "layer_id": layer.id})
					continue
				var chunk_keys: Array[String] = raster.chunks.keys()
				chunk_keys.sort()
				for key: String in chunk_keys:
					var chunk: AtlasRasterChunk = raster.chunks[key]
					if chunk == null or chunk.image == null or chunk.image.is_empty():
						warnings.append({"reason": "raster_pixels_unavailable",
							"floor_id": floor.id, "layer_id": layer.id, "chunk_key": key})
						continue
					var used: Rect2i = chunk.image.get_used_rect()
					if not used.has_area():
						continue
					var origin: Vector2 = Vector2(chunk.coord * AtlasRasterChunk.SIZE + used.position)
					var end: Vector2 = origin + Vector2(used.size)
					var transform: Transform2D = raster.transform * Transform2D(0.0,
						Vector2.ONE / raster.pixels_per_unit, 0.0, Vector2.ZERO)
					if not _quad_inside_crop(crop, transform,
						Rect2(origin, end - origin)):
						warnings.append({"reason": "raster_outside_registered_crop",
							"floor_id": floor.id, "layer_id": layer.id, "chunk_key": key})
			elif layer is AtlasObjectsLayer:
				var objects: AtlasObjectsLayer = layer as AtlasObjectsLayer
				for index: int in range(objects.strokes.size()):
					var object: AtlasStroke = objects.strokes[index]
					if object == null or object.points.is_empty():
						warnings.append({"reason": "invalid_object_geometry",
							"floor_id": floor.id, "layer_id": layer.id, "object_index": index})
						continue
					if object.is_text() or object.is_prop():
						warnings.append({"reason": "semantic_extent_requires_review",
							"floor_id": floor.id, "layer_id": layer.id, "object_index": index})
						continue
					var bounds: Rect2 = _stroke_extent(object)
					if not _quad_inside_crop(crop, Transform2D.IDENTITY, bounds):
						warnings.append({"reason": "object_outside_registered_crop",
							"floor_id": floor.id, "layer_id": layer.id, "object_index": index})
			elif layer is AtlasTokenLayer and not (layer as AtlasTokenLayer).tokens.is_empty():
				warnings.append({"reason": "token_policy_requires_review",
					"floor_id": floor.id, "layer_id": layer.id})
	return warnings


static func _stroke_extent(object: AtlasStroke) -> Rect2:
	var min_corner: Vector2 = object.points[0]
	var max_corner: Vector2 = min_corner
	for point: Vector2 in object.points:
		min_corner = min_corner.min(point)
		max_corner = max_corner.max(point)
	# A filled polygon is defined by vertices, a line/path by its brush radius.
	var radius: float = 0.0 if object.filled else object.width * 0.5
	return Rect2(min_corner - Vector2.ONE * radius,
		max_corner - min_corner + Vector2.ONE * (2.0 * radius))


static func _quad_inside_crop(crop: Rect2, transform: Transform2D,
		bounds: Rect2) -> bool:
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y),
			bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var point: Vector2 = transform * corner
		if not point.is_finite() or point.x < crop.position.x - 0.0001 \
				or point.y < crop.position.y - 0.0001 \
				or point.x > crop.end.x + 0.0001 or point.y > crop.end.y + 0.0001:
			return false
	return true
