class_name AtlasCampaign
extends RefCounted

const SCHEMA_VERSION: int = 6

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
        elif link.anchor.distance_to(point) <= link.hit_radius:
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


static func sample() -> AtlasCampaign:
    var campaign := AtlasCampaign.new()
    campaign.display_name = "Northern Marches (sample)"

    var world := AtlasMapDocument.new("world", "Northern Marches")
    world.kind = "WORLD"
    world.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
    world.grid.distance_per_cell = 3.0
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
