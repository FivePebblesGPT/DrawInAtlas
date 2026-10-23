class_name AtlasMapDocument
extends RefCounted

var id: String = ""
var display_name: String = ""
var kind: String = "REGION"
var grid: AtlasGrid = AtlasGrid.new()
var terrain_grid: AtlasGrid
var floors: Array[AtlasFloor] = []
var default_floor_id: String = "ground"


func _init(map_id: String = "", map_name: String = "") -> void:
    id = map_id
    display_name = map_name
    floors.append(AtlasFloor.new())


func floor_by_id(floor_id: String) -> AtlasFloor:
    for floor in floors:
        if floor.id == floor_id:
            return floor
    return null


func get_terrain_grid() -> AtlasGrid:
    return terrain_grid if terrain_grid != null else grid


func to_dict() -> Dictionary:
    var saved_floors: Array[Dictionary] = []
    for floor in floors:
        saved_floors.append(floor.to_dict())
    return {
        "id": id, "name": display_name, "kind": kind,
        "grid": grid.to_dict(), "terrain_grid": get_terrain_grid().to_dict(), "floors": saved_floors,
        "default_floor_id": default_floor_id
    }


static func from_dict(data: Dictionary) -> AtlasMapDocument:
    var map := AtlasMapDocument.new(str(data.get("id", "")), str(data.get("name", "")))
    map.kind = str(data.get("kind", "REGION"))
    var raw_grid: Variant = data.get("grid", {})
    var raw_terrain_grid: Variant = data.get("terrain_grid", raw_grid)
    var raw_floors: Variant = data.get("floors", [])
    if not raw_grid is Dictionary or not raw_terrain_grid is Dictionary or not raw_floors is Array:
        return null
    map.grid = AtlasGrid.from_dict(raw_grid)
    map.terrain_grid = AtlasGrid.from_dict(raw_terrain_grid)
    if map.grid == null or map.terrain_grid == null:
        return null
    map.floors.clear()
    for saved_floor: Variant in raw_floors:
        if not saved_floor is Dictionary:
            return null
        var floor: AtlasFloor = AtlasFloor.from_dict(saved_floor)
        if floor == null:
            return null
        map.floors.append(floor)
    if map.floors.is_empty():
        map.floors.append(AtlasFloor.new())
    map.default_floor_id = str(data.get("default_floor_id", map.floors[0].id))
    return map if map.floor_by_id(map.default_floor_id) != null else null
