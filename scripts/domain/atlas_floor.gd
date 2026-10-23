class_name AtlasFloor
extends RefCounted

## First vertical slice: one sparse terrain layer per floor.
var id: String = "ground"
var display_name: String = "Ground"
var terrain: Dictionary = {} # "x,y" -> palette index
var strokes: Array[AtlasStroke] = []


func paint(cell: Vector2i, palette_id: int) -> void:
    terrain["%d,%d" % [cell.x, cell.y]] = palette_id


func get_terrain(cell: Vector2i) -> int:
    return int(terrain.get("%d,%d" % [cell.x, cell.y], 0))


func to_dict() -> Dictionary:
    var artwork: Array[Dictionary] = []
    for stroke: AtlasStroke in strokes:
        artwork.append(stroke.to_dict())
    return {"id": id, "name": display_name, "terrain": terrain.duplicate(), "strokes": artwork}


static func from_dict(data: Dictionary) -> AtlasFloor:
    var floor := AtlasFloor.new()
    floor.id = str(data.get("id", "ground"))
    floor.display_name = str(data.get("name", "Ground"))
    floor.terrain = (data.get("terrain", {}) as Dictionary).duplicate()
    var artwork: Variant = data.get("strokes", [])
    if not artwork is Array:
        return null
    for saved: Variant in artwork:
        if not saved is Dictionary:
            return null
        var stroke: AtlasStroke = AtlasStroke.from_dict(saved)
        if stroke == null:
            return null
        floor.strokes.append(stroke)
    return floor
