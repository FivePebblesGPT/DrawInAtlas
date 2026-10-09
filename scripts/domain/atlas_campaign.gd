class_name AtlasCampaign
extends RefCounted

const SCHEMA_VERSION: int = 1

var display_name: String = "West Marches"
var root_map_id: String = "world"
var maps: Dictionary = {} # map ID -> AtlasMapDocument
var links: Array[AtlasMapLink] = []
var placements: Array[AtlasPlacement] = []


func add_map(map: AtlasMapDocument) -> void:
    maps[map.id] = map


func get_map(map_id: String) -> AtlasMapDocument:
    return maps.get(map_id) as AtlasMapDocument


func placement_by_id(placement_id: String) -> AtlasPlacement:
    for placement in placements:
        if placement.id == placement_id:
            return placement
    return null


func find_links_at(map_id: String, point: Vector2) -> Array[AtlasMapLink]:
    var matches: Array[AtlasMapLink] = []
    for link in links:
        if link.source_map_id != map_id:
            continue
        if not link.placement_id.is_empty():
            var placement := placement_by_id(link.placement_id)
            if placement != null and placement.contains_parent_point(point):
                matches.append(link)
        elif link.anchor.distance_to(point) <= link.hit_radius:
            matches.append(link)
    return matches


func outgoing_links(map_id: String) -> Array[AtlasMapLink]:
    var matches: Array[AtlasMapLink] = []
    for link in links:
        if link.source_map_id == map_id:
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


static func from_dict(data: Dictionary) -> AtlasCampaign:
    if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
        return null
    var campaign := AtlasCampaign.new()
    campaign.display_name = str(data.get("name", "West Marches"))
    campaign.root_map_id = str(data.get("root_map_id", "world"))
    for saved_map in data.get("maps", []):
        campaign.add_map(AtlasMapDocument.from_dict(saved_map))
    for saved_link in data.get("links", []):
        campaign.links.append(AtlasMapLink.from_dict(saved_link))
    for saved_placement in data.get("placements", []):
        campaign.placements.append(AtlasPlacement.from_dict(saved_placement))
    if campaign.get_map(campaign.root_map_id) == null:
        return null
    return campaign


static func sample() -> AtlasCampaign:
    var campaign := AtlasCampaign.new()
    campaign.display_name = "Northern Marches (sample)"

    var world := AtlasMapDocument.new("world", "Northern Marches")
    world.kind = "WORLD"
    world.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
    world.grid.distance_per_cell = 6.0
    world.grid.distance_unit = "mi"
    for q in range(-6, 7):
        for r in range(-5, 6):
            var terrain := 2 if (q + r * 3) % 7 == 0 else 1
            world.floors[0].paint(Vector2i(q, r), terrain)
    campaign.add_map(world)

    var city := AtlasMapDocument.new("greyhaven", "Greyhaven")
    city.kind = "CITY"
    city.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 48.0)
    city.grid.distance_per_cell = 10.0
    city.grid.distance_unit = "ft"
    for x in range(-6, 7):
        for y in range(-4, 5):
            if x % 4 == 0 or y % 3 == 0:
                city.floors[0].paint(Vector2i(x, y), 3)
            else:
                city.floors[0].paint(Vector2i(x, y), 1)
    campaign.add_map(city)

    var entrance := AtlasMapLink.new()
    entrance.id = "enter-greyhaven"
    entrance.source_map_id = "world"
    entrance.target_map_id = "greyhaven"
    entrance.anchor = world.grid.cell_to_document(Vector2i(2, 0))
    entrance.hit_radius = 44.0
    campaign.links.append(entrance)
    return campaign
