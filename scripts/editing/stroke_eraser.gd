class_name AtlasStrokeEraser
extends RefCounted
## Cuts vector centerlines against the swept round eraser, accounting for ink width.


static func erase(strokes: Array[AtlasStroke], path: PackedVector2Array, width: float) -> Array[AtlasStroke]:
	if path.is_empty() or not is_finite(width) or width <= 0.0:
		return AtlasStroke.clone_all(strokes)
	for point: Vector2 in path:
		if not point.is_finite():
			return AtlasStroke.clone_all(strokes)
	var result: Array[AtlasStroke] = []
	for stroke: AtlasStroke in strokes:
		var radius: float = (width + stroke.width) * 0.5
		if stroke.editable_path:
			var path_points: PackedVector2Array = AtlasEditablePath.render_points(stroke)
			if not _touches(path_points, path, radius):
				result.append(stroke.copy())
			continue
		if stroke.filled:
			# Solid polygons are single shapes, not polylines to be split into
			# open segments. Erasing a touched filled area removes the whole shape.
			var touches_fill: bool = _touches(stroke.points, path, radius)
			for point: Vector2 in path:
				if Geometry2D.is_point_in_polygon(point, stroke.points):
					touches_fill = true
					break
			if not touches_fill:
				result.append(stroke.copy())
			continue
		if not _touches(stroke.points, path, radius):
			result.append(stroke.copy())
			continue
		var parts: Array[PackedVector2Array] = [stroke.points.duplicate()]
		for index: int in range(maxi(1, path.size() - 1)):
			var start: Vector2 = path[index]
			var finish: Vector2 = path[mini(index + 1, path.size() - 1)]
			var masks: Array[PackedVector2Array] = _capsule(start, finish, radius)
			for mask: PackedVector2Array in masks:
				var remaining: Array[PackedVector2Array] = []
				for part: PackedVector2Array in parts:
					if part.size() == 1:
						if not Geometry2D.is_point_in_polygon(part[0], mask):
							remaining.append(part)
					else:
						remaining.append_array(Geometry2D.clip_polyline_with_polygon(part, mask))
				parts = remaining
		for part: PackedVector2Array in parts:
			if not part.is_empty():
				result.append(AtlasStroke.new(part, stroke.color, stroke.width))
	return result


static func _capsule(start: Vector2, finish: Vector2, radius: float) -> Array[PackedVector2Array]:
	if not start.is_equal_approx(finish):
		return Geometry2D.offset_polyline(PackedVector2Array([start, finish]), radius,
			Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	var circle: PackedVector2Array = PackedVector2Array()
	for side: int in range(32):
		circle.append(start + Vector2.RIGHT.rotated(float(side) * TAU / 32.0) * radius)
	return [circle]


static func _touches(ink: PackedVector2Array, path: PackedVector2Array, radius: float) -> bool:
	for a: int in range(maxi(1, ink.size() - 1)):
		for b: int in range(maxi(1, path.size() - 1)):
			var closest: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
				ink[a], ink[mini(a + 1, ink.size() - 1)],
				path[b], path[mini(b + 1, path.size() - 1)]
			)
			if closest[0].distance_squared_to(closest[1]) <= radius * radius:
				return true
	return false
