class_name AtlasStroke
extends RefCounted
## Editable ink in continuous document coordinates, independent of any grid.

var points: PackedVector2Array
var color: Color
var width: float


func _init(path: PackedVector2Array = PackedVector2Array(), ink: Color = Color.BLACK,
		diameter: float = 8.0) -> void:
	points = path.duplicate()
	color = ink
	width = diameter


func copy() -> AtlasStroke:
	return AtlasStroke.new(points, color, width)


func is_valid() -> bool:
	if points.is_empty() or not is_finite(width) or width <= 0.0:
		return false
	if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a):
		return false
	for point: Vector2 in points:
		if not point.is_finite():
			return false
	return true


func to_dict() -> Dictionary:
	var path: Array[Array] = []
	for point: Vector2 in points:
		path.append([point.x, point.y])
	return {"points": path, "color": [color.r, color.g, color.b, color.a], "width": width}


static func from_dict(data: Dictionary) -> AtlasStroke:
	var raw_points: Variant = data.get("points")
	var raw_color: Variant = data.get("color")
	var raw_width: Variant = data.get("width")
	if not raw_points is Array or not raw_color is Array or raw_color.size() != 4:
		return null
	if not _is_number(raw_width):
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
	var result: AtlasStroke = AtlasStroke.new(path, ink, float(raw_width))
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
		if first[index].points != second[index].points or first[index].color != second[index].color:
			return false
		if first[index].width != second[index].width:
			return false
	return true


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
