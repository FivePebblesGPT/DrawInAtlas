class_name AtlasStroke
extends Resource
## Editable ink in continuous document coordinates, independent of any grid.

@export_storage var points: PackedVector2Array
@export_storage var color: Color
@export_storage var width: float
## Solid polygon shape, as opposed to a round-ended centerline stroke.
@export_storage var filled: bool = false
## T-026: semantic wall path with independently editable control vertices.
@export_storage var editable_path: bool = false
@export_storage var closed_path: bool = false


func _init(path: PackedVector2Array = PackedVector2Array(), ink: Color = Color.BLACK,
		diameter: float = 8.0, solid_fill: bool = false) -> void:
	points = path.duplicate()
	color = ink
	width = diameter
	filled = solid_fill


func copy() -> AtlasStroke:
	var result: AtlasStroke = AtlasStroke.new(points, color, width, filled)
	result.editable_path = editable_path
	result.closed_path = closed_path
	return result


func is_valid() -> bool:
	if points.is_empty() or not is_finite(width) or width <= 0.0:
		return false
	if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
		return false
	for point: Vector2 in points:
		if not point.is_finite():
			return false
	if not editable_path and closed_path:
		return false
	if editable_path and not AtlasEditablePath.valid_vertices(points, closed_path):
		return false
	if filled and editable_path:
		return false
	if filled:
		if points.size() < 4 or points[0] != points[-1]:
			return false
		var vertices: PackedVector2Array = points.duplicate()
		vertices.remove_at(vertices.size() - 1)
		if not AtlasShapes.valid_polygon_vertices(vertices):
			return false
	return true


func to_dict() -> Dictionary:
	var path: Array[Array] = []
	for point: Vector2 in points:
		path.append([point.x, point.y])
	var data: Dictionary = {"points": path, "color": [color.r, color.g, color.b, color.a], "width": width}
	if filled:
		data["filled"] = true
	if editable_path:
		data["editable_path"] = true
		data["closed_path"] = closed_path
	return data


static func from_dict(data: Dictionary) -> AtlasStroke:
	var raw_points: Variant = data.get("points")
	var raw_color: Variant = data.get("color")
	var raw_width: Variant = data.get("width")
	var raw_fill: Variant = data.get("filled", false)
	var raw_editable: Variant = data.get("editable_path", false)
	var raw_closed: Variant = data.get("closed_path", false)
	if not raw_points is Array or not raw_color is Array or raw_color.size() != 4:
		return null
	if not _is_number(raw_width) or not raw_fill is bool or not raw_editable is bool or not raw_closed is bool:
		return null
	var path: PackedVector2Array = PackedVector2Array()
	for value: Variant in raw_points:
		if not value is Array or value.size() != 2:
			return null
		if not _is_number(value[0]) or not _is_number(value[1]):
			return null
		path.append(Vector2(float(value[0]), float(value[1])))
	for value: Variant in raw_color:
		if not _is_number(value):
			return null
	var ink: Color = Color(float(raw_color[0]), float(raw_color[1]), float(raw_color[2]), float(raw_color[3]))
	var result: AtlasStroke = AtlasStroke.new(path, ink, float(raw_width), raw_fill)
	result.editable_path = raw_editable
	result.closed_path = raw_closed
	return result if result.is_valid() else null


static func clone_all(strokes: Array[AtlasStroke]) -> Array[AtlasStroke]:
	var result: Array[AtlasStroke] = []
	for stroke: AtlasStroke in strokes:
		result.append(stroke.copy())
	return result


static func same_artwork(first: Array[AtlasStroke], second: Array[AtlasStroke]) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if first[index].points != second[index].points or first[index].color != second[index].color or first[index].filled != second[index].filled \
				or first[index].editable_path != second[index].editable_path or first[index].closed_path != second[index].closed_path:
			return false
		if first[index].width != second[index].width:
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
