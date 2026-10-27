class_name AtlasCampaign
extends Resource

## Mutable runtime graph of independent map documents. A link is a directed
## navigation edge; an optional placement describes a spatial battlemap footprint.
## AtlasCampaignStore owns saving/loading; callers do not choose its serializer.

const SCHEMA_VERSION: int = 6

@export_storage var display_name: String = "West Marches"
@export_storage var root_map_id: String = "world"
var maps: Dictionary = {} # map ID -> AtlasMapDocument
@export_storage var links: Array[AtlasMapLink] = []
@export_storage var placements: Array[AtlasPlacement] = []


func add_map(map: AtlasMapDocument) -> void:
	maps[map.id] = map


func get_map(map_id: String) -> AtlasMapDocument:
	return maps.get(map_id) as AtlasMapDocument


func placement_by_id(placement_id: String) -> AtlasPlacement:
	for placement in placements:
		if placement.id == placement_id:
			return placement
	return null


## Find entrances at a point expressed in source MAP units, never screen pixels.
## Ignore dangling destinations and floor references; a missing placement must
## not silently turn a footprint link into an ordinary marker.
func find_links_at(map_id: String, point: Vector2, floor_id: String = "") -> Array[AtlasMapLink]:
	var matches: Array[AtlasMapLink] = []
	var source: AtlasMapDocument = get_map(map_id)
	if source == null:
		return matches
	for link in links:
		if link.source_map_id != map_id:
			continue
		if not floor_id.is_empty() and link.source_floor_id != floor_id:
			continue
		if source.floor_by_id(link.source_floor_id) == null:
			continue
		var target: AtlasMapDocument = get_map(link.target_map_id)
		if target == null or target.floor_by_id(link.target_floor_id) == null:
			continue
		if not link.placement_id.is_empty():
			var placement := placement_by_id(link.placement_id)
			if (placement != null and placement.parent_map_id == map_id
					and placement.child_map_id == link.target_map_id and placement.contains_parent_point(point)):
				matches.append(link)
		elif link.contains_marker_point(point):
			matches.append(link)
	return matches


func outgoing_links(map_id: String, floor_id: String = "") -> Array[AtlasMapLink]:
	var matches: Array[AtlasMapLink] = []
	for link in links:
		if link.source_map_id == map_id and (floor_id.is_empty() or link.source_floor_id == floor_id):
			matches.append(link)
	return matches


func to_dict() -> Dictionary:
	var saved_maps: Array[Dictionary] = []
	var saved_links: Array[Dictionary] = []
	var saved_placements: Array[Dictionary] = []
	for map: AtlasMapDocument in maps.values():
		saved_maps.append(map.to_dict())
	for link in links:
		saved_links.append(link.to_dict())
	for placement in placements:
		saved_placements.append(placement.to_dict())
	return {
		"schema_version": SCHEMA_VERSION, "name": display_name,
		"root_map_id": root_map_id,
		"maps": saved_maps, "links": saved_links,
		"placements": saved_placements
	}


## Validate and reconstruct the complete document graph before it becomes
## user-visible. Incomplete/dangling navigation links may still be represented
## so the overview can report them rather than destroying user content.
static func from_dict(data: Dictionary) -> AtlasCampaign:
	var version: Variant = data.get("schema_version")
	if not AtlasData.integer(version) or int(version) < 1 or int(version) > SCHEMA_VERSION:
		return null
	var raw_maps: Variant = data.get("maps")
	var raw_links: Variant = data.get("links", [])
	var raw_placements: Variant = data.get("placements", [])
	if not raw_maps is Array or not raw_links is Array or not raw_placements is Array:
		return null
	if not AtlasData.text(data.get("root_map_id")) or not AtlasData.text(data.get("name", "West Marches")):
		return null
	var campaign := AtlasCampaign.new()
	campaign.display_name = str(data.get("name", "West Marches"))
	campaign.root_map_id = str(data.get("root_map_id", "world"))
	for saved_map: Variant in raw_maps:
		if not saved_map is Dictionary:
			return null
		var document: AtlasMapDocument = AtlasMapDocument.from_dict(saved_map)
		if document == null:
			return null
		if campaign.maps.has(document.id):
			return null
		campaign.add_map(document)
	var link_ids: Dictionary[String, bool] = {}
	for saved_link: Variant in raw_links:
		if not saved_link is Dictionary:
			return null
		var link: AtlasMapLink = AtlasMapLink.from_dict(saved_link)
		if link == null or link_ids.has(link.id):
			return null
		var source_map: AtlasMapDocument = campaign.get_map(link.source_map_id)
		var target_map: AtlasMapDocument = campaign.get_map(link.target_map_id)
		if not saved_link.has("source_floor_id") and source_map != null:
			link.source_floor_id = source_map.default_floor_id
		if not saved_link.has("target_floor_id") and target_map != null:
			link.target_floor_id = target_map.default_floor_id
		link_ids[link.id] = true
		campaign.links.append(link)
	var placement_ids: Dictionary[String, bool] = {}
	for saved_placement: Variant in raw_placements:
		if not saved_placement is Dictionary:
			return null
		var placement: AtlasPlacement = AtlasPlacement.from_dict(saved_placement)
		if placement == null or placement_ids.has(placement.id):
			return null
		placement_ids[placement.id] = true
		campaign.placements.append(placement)
	if campaign.get_map(campaign.root_map_id) == null:
		return null
	return campaign


## Load the authorable example from a .tres Resource rather than constructing
## presentation content inline. The loaded preset is immutable; fresh model
## objects are created for each call, so edits never modify res:// assets.
static func sample() -> AtlasCampaign:
	var preset: AtlasExampleCampaign = load("res://examples/northern_marches.tres") as AtlasExampleCampaign
	if preset == null:
		push_error("Missing example campaign: res://examples/northern_marches.tres")
		return null

	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = preset.display_name

	var world: AtlasMapDocument = preset.world.create_document()
	var city: AtlasMapDocument = preset.city.create_document()
	campaign.root_map_id = world.id
	campaign.add_map(world)
	campaign.add_map(city)

	var entrance: AtlasMapLink = AtlasMapLink.from_dict(preset.entrance.to_dict())
	# The marker follows its source grid cell if cell size/rotation changes.
	entrance.anchor = world.grid.cell_to_document(preset.entrance_source_cell)
	campaign.links.append(entrance)
	return campaign
