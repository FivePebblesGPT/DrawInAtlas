class_name AtlasPlacement
extends Resource

## A rotated battlemap footprint in the PARENT board's coordinate system.
## Origin is the top-left corner in parent units; columns/rows count cells,
## parent_units_per_cell controls only the footprint, and child_units_per_cell
## maps parent footprint cells into independent child-map coordinates.
## Unlike a marker link, picking uses this polygon rather than hit_radius.
@export var id: String = ""
@export var parent_map_id: String = ""
@export var child_map_id: String = ""
@export var origin: Vector2 = Vector2.ZERO
@export var rotation: float = 0.0
@export var columns: int = 10
@export var rows: int = 10
@export var parent_units_per_cell: float = 24.0
@export var child_units_per_cell: float = 64.0
@export var symbolic: bool = false


func local_to_parent() -> Transform2D:
	return Transform2D(rotation, Vector2.ONE * maxf(parent_units_per_cell, 0.001), 0.0, origin)


func parent_to_local(position: Vector2) -> Vector2:
	return local_to_parent().affine_inverse() * position


func contains_parent_point(position: Vector2) -> bool:
	var local: Vector2 = parent_to_local(position)
	return local.x >= 0.0 and local.y >= 0.0 and local.x < columns and local.y < rows


## Entering a child map converts its local cell coordinate to the child's
## board units; the child's grid need not share the parent's physical scale.
func parent_point_to_child(position: Vector2) -> Vector2:
	return parent_to_local(position) * child_units_per_cell


func child_to_parent() -> Transform2D:
	var basis: Transform2D = local_to_parent()
	return Transform2D(basis.x / child_units_per_cell, basis.y / child_units_per_cell, origin)


func child_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(columns, rows) * child_units_per_cell)


func corners() -> PackedVector2Array:
	var transform: Transform2D = local_to_parent()
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
	for field: String in ["id", "parent_map_id", "child_map_id"]:
		if not AtlasData.text(data.get(field)):
			return null
	var coords: Variant = data.get("origin", [0.0, 0.0])
	if not AtlasData.vector(coords) or not AtlasData.number(data.get("rotation", 0.0)):
		return null
	for field: String in ["columns", "rows"]:
		if not AtlasData.integer(data.get(field, 10)) or int(data.get(field, 10)) < 1:
			return null
	for field: String in ["parent_units_per_cell", "child_units_per_cell"]:
		if not AtlasData.number(data.get(field, 24.0)) or float(data.get(field, 24.0)) <= 0.0:
			return null
	if not data.get("symbolic", false) is bool:
		return null
	var result: AtlasPlacement = AtlasPlacement.new()
	result.id = str(data.get("id", ""))
	result.parent_map_id = str(data.get("parent_map_id", ""))
	result.child_map_id = str(data.get("child_map_id", ""))
	result.origin = Vector2(float(coords[0]), float(coords[1]))
	result.rotation = float(data.get("rotation", 0.0))
	result.columns = maxi(1, int(data.get("columns", 10)))
	result.rows = maxi(1, int(data.get("rows", 10)))
	result.parent_units_per_cell = maxf(0.001, float(data.get("parent_units_per_cell", 24.0)))
	result.child_units_per_cell = maxf(0.001, float(data.get("child_units_per_cell", 64.0)))
	result.symbolic = bool(data.get("symbolic", false))
	return result
