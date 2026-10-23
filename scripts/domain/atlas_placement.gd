class_name AtlasPlacement
extends RefCounted

## A parent-space rectangle with independent child-map cell coordinates.
var id: String = ""
var parent_map_id: String = ""
var child_map_id: String = ""
var origin: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var columns: int = 10
var rows: int = 10
var parent_units_per_cell: float = 24.0
var child_units_per_cell: float = 64.0
var symbolic: bool = false


func local_to_parent() -> Transform2D:
    return Transform2D(rotation, Vector2.ONE * maxf(parent_units_per_cell, 0.001), 0.0, origin)


func parent_to_local(position: Vector2) -> Vector2:
    return local_to_parent().affine_inverse() * position


func contains_parent_point(position: Vector2) -> bool:
    var local := parent_to_local(position)
    return local.x >= 0.0 and local.y >= 0.0 and local.x < columns and local.y < rows


func parent_point_to_child(position: Vector2) -> Vector2:
    return parent_to_local(position) * child_units_per_cell


func corners() -> PackedVector2Array:
    var transform := local_to_parent()
    return PackedVector2Array([
        transform * Vector2.ZERO,
        transform * Vector2(columns, 0),
        transform * Vector2(columns, rows),
        transform * Vector2(0, rows)
    ])


func to_dict() -> Dictionary:
    return {
        "id": id, "parent_map_id": parent_map_id,
        "child_map_id": child_map_id,
        "origin": [origin.x, origin.y], "rotation": rotation,
        "columns": columns, "rows": rows,
        "parent_units_per_cell": parent_units_per_cell,
        "child_units_per_cell": child_units_per_cell,
        "symbolic": symbolic
    }


static func from_dict(data: Dictionary) -> AtlasPlacement:
    var result := AtlasPlacement.new()
    result.id = str(data.get("id", ""))
    result.parent_map_id = str(data.get("parent_map_id", ""))
    result.child_map_id = str(data.get("child_map_id", ""))
    var coords: Array = data.get("origin", [0.0, 0.0])
    result.origin = Vector2(float(coords[0]), float(coords[1]))
    result.rotation = float(data.get("rotation", 0.0))
    result.columns = maxi(1, int(data.get("columns", 10)))
    result.rows = maxi(1, int(data.get("rows", 10)))
    result.parent_units_per_cell = maxf(0.001, float(data.get("parent_units_per_cell", 24.0)))
    result.child_units_per_cell = maxf(0.001, float(data.get("child_units_per_cell", 64.0)))
    result.symbolic = bool(data.get("symbolic", false))
    return result
