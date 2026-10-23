class_name AtlasGrid
extends RefCounted

## A document-local grid. Coordinate conversion has no knowledge of map links.
enum Kind { GRIDLESS, SQUARE, HEX_POINTY, HEX_FLAT }

var kind: Kind = Kind.HEX_POINTY
var cell_size: float = 48.0
var origin: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var distance_per_cell: float = 6.0
var distance_unit: String = "mi"


func _init(grid_kind: Kind = Kind.HEX_POINTY, size: float = 48.0) -> void:
    kind = grid_kind
    cell_size = maxf(size, 0.001)


func cell_to_document(cell: Vector2i) -> Vector2:
    var local := Vector2.ZERO
    match kind:
        Kind.SQUARE:
            local = Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5
        Kind.HEX_POINTY:
            local = Vector2(sqrt(3.0) * (float(cell.x) + float(cell.y) * 0.5), 1.5 * float(cell.y)) * cell_size
        Kind.HEX_FLAT:
            local = Vector2(1.5 * float(cell.x), sqrt(3.0) * (float(cell.y) + float(cell.x) * 0.5)) * cell_size
    return origin + local.rotated(rotation)


func document_to_cell(position: Vector2) -> Vector2i:
    var local := (position - origin).rotated(-rotation) / cell_size
    match kind:
        Kind.SQUARE:
            return Vector2i(floori(local.x), floori(local.y))
        Kind.HEX_POINTY:
            return _round_axial((sqrt(3.0) / 3.0) * local.x - local.y / 3.0, (2.0 / 3.0) * local.y)
        Kind.HEX_FLAT:
            return _round_axial((2.0 / 3.0) * local.x, -local.x / 3.0 + (sqrt(3.0) / 3.0) * local.y)
    return Vector2i.ZERO


func cell_polygon(cell: Vector2i) -> PackedVector2Array:
    var result := PackedVector2Array()
    if kind == Kind.GRIDLESS:
        return result
    var center := cell_to_document(cell)
    if kind == Kind.SQUARE:
        for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
            result.append(center + (corner * cell_size).rotated(rotation))
    else:
        var offset: float = -PI / 6.0 if kind == Kind.HEX_POINTY else 0.0
        for side in range(6):
            var angle := offset + float(side) * TAU / 6.0 + rotation
            result.append(center + Vector2.RIGHT.rotated(angle) * cell_size)
    return result


func neighbors(cell: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    var offsets: Array[Vector2i] = [
        Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)
    ]
    if kind == Kind.HEX_POINTY or kind == Kind.HEX_FLAT:
        offsets.append(Vector2i(1, -1))
        offsets.append(Vector2i(-1, 1))
    for offset in offsets:
        result.append(cell + offset)
    return result


func to_dict() -> Dictionary:
    return {
        "kind": kind, "cell_size": cell_size,
        "origin": [origin.x, origin.y], "rotation": rotation,
        "distance_per_cell": distance_per_cell, "distance_unit": distance_unit
    }


static func from_dict(data: Dictionary) -> AtlasGrid:
    var result := AtlasGrid.new(int(data.get("kind", Kind.HEX_POINTY)), float(data.get("cell_size", 48.0)))
    var p: Array = data.get("origin", [0.0, 0.0])
    result.origin = Vector2(float(p[0]), float(p[1]))
    result.rotation = float(data.get("rotation", 0.0))
    result.distance_per_cell = float(data.get("distance_per_cell", 6.0))
    result.distance_unit = str(data.get("distance_unit", "mi"))
    return result


static func _round_axial(q: float, r: float) -> Vector2i:
    var s := -q - r
    var rq := roundi(q)
    var rr := roundi(r)
    var rs := roundi(s)
    var q_error := absf(float(rq) - q)
    var r_error := absf(float(rr) - r)
    var s_error := absf(float(rs) - s)
    if q_error > r_error and q_error > s_error:
        rq = -rr - rs
    elif r_error > s_error:
        rr = -rq - rs
    return Vector2i(rq, rr)
