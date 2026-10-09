class_name AtlasMapDocument
extends RefCounted

var id: String = ""
var display_name: String = ""
var kind: String = "REGION"
var grid: AtlasGrid = AtlasGrid.new()
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


func to_dict() -> Dictionary:
    var saved_floors: Array[Dictionary] = []
    for floor in floors:
        saved_floors.append(floor.to_dict())
    return {
        "id": id, "name": display_name, "kind": kind,
        "grid": grid.to_dict(), "floors": saved_floors,
        "default_floor_id": default_floor_id
    }


static func from_dict(data: Dictionary) -> AtlasMapDocument:
    var map := AtlasMapDocument.new(str(data.get("id", "")), str(data.get("name", "")))
    map.kind = str(data.get("kind", "REGION"))
    map.grid = AtlasGrid.from_dict(data.get("grid", {}))
    map.floors.clear()
    for saved_floor in data.get("floors", []):
        map.floors.append(AtlasFloor.from_dict(saved_floor))
    if map.floors.is_empty():
        map.floors.append(AtlasFloor.new())
    map.default_floor_id = str(data.get("default_floor_id", map.floors[0].id))
    return map
