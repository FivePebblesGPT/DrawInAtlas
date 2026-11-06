class_name AtlasEditablePath
extends RefCounted
## Typed vector wall paths; control vertices remain unclosed in storage.
## No rasterization, resampling, or implicit topology edits.

const MAX_VERTICES: int = 256


static func valid_vertices(vertices: PackedVector2Array, closed: bool) -> bool:
	if vertices.size() < (3 if closed else 2) or vertices.size() > MAX_VERTICES:
		return false
	for index: int in range(vertices.size()):
		if not vertices[index].is_finite():
			return false
		if index > 0 and vertices[index].distance_squared_to(vertices[index - 1]) <= 0.0001:
			return false
	if closed:
		if vertices[-1].distance_squared_to(vertices[0]) <= 0.0001:
			return false
		var twice_area: float = 0.0
		for index: int in range(vertices.size()):
			twice_area += vertices[index].cross(vertices[(index + 1) % vertices.size()])
		if not is_finite(twice_area) or absf(twice_area) <= 0.0001:
			return false
	return true


static func make(vertices: PackedVector2Array, color: Color, width: float, closed: bool = false) -> AtlasStroke:
	if not valid_vertices(vertices, closed):
		return null
	var path: AtlasStroke = AtlasStroke.new(vertices, color, width)
	path.editable_path = true
	path.closed_path = closed
	return path if path.is_valid() else null


static func render_points(path: AtlasStroke) -> PackedVector2Array:
	var result: PackedVector2Array = path.points.duplicate()
	if path.editable_path and path.closed_path and not result.is_empty():
		result.append(result[0])
	return result


static func vertex_at(path: AtlasStroke, point: Vector2, radius: float) -> int:
	if not path.editable_path:
		return -1
	for index: int in range(path.points.size() - 1, -1, -1):
		if path.points[index].distance_to(point) <= radius:
			return index
	return -1


static func segment_at(path: AtlasStroke, point: Vector2, radius: float) -> int:
	if not path.editable_path:
		return -1
	var points: PackedVector2Array = render_points(path)
	for index: int in range(points.size() - 2, -1, -1):
		if Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1]).distance_to(point) <= radius:
			return index
	return -1


static func moved_vertex(path: AtlasStroke, index: int, point: Vector2) -> AtlasStroke:
	if not path.editable_path or index < 0 or index >= path.points.size() or not point.is_finite():
		return null
	var copy: AtlasStroke = path.copy()
	copy.points[index] = point
	return copy if copy.is_valid() else null


static func inserted_vertex(path: AtlasStroke, segment: int, point: Vector2) -> AtlasStroke:
	var count: int = path.points.size()
	if not path.editable_path or count >= MAX_VERTICES or segment < 0 or segment >= count - (0 if path.closed_path else 1):
		return null
	var copy: AtlasStroke = path.copy()
	copy.points.insert(segment + 1, point)
	return copy if copy.is_valid() else null


static func deleted_vertex(path: AtlasStroke, index: int) -> AtlasStroke:
	if not path.editable_path or index < 0 or index >= path.points.size():
		return null
	var copy: AtlasStroke = path.copy()
	copy.points.remove_at(index)
	return copy if copy.is_valid() else null


static func restyled(path: AtlasStroke, color: Color, width: float) -> AtlasStroke:
	if not path.editable_path:
		return null
	var copy: AtlasStroke = path.copy()
	copy.color = color
	copy.width = width
	return copy if copy.is_valid() else null
