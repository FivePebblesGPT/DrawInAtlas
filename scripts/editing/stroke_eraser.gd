class_name AtlasStrokeEraser
extends RefCounted
## Erases vector ink in document/board units by sweeping a round eraser over
## stroke centerlines. Text, editable wall paths and filled shapes stay whole.


## The sweep points and both diameters use board units (not screen pixels).
## Centerline collision uses half the sum of eraser and ink widths. The result
## owns independent stroke objects/point arrays for exact edit-history undo;
## neither the source strokes nor the pointer path are modified.
static func erase(strokes: Array[AtlasStroke], path: PackedVector2Array, width: float) -> Array[AtlasStroke]:
	# Reject unusable gestures as value no-ops. The editor/model validates the
	# source strokes before calling this geometry service.
	if path.is_empty() or not is_finite(width) or width <= 0.0:
		return AtlasStroke.clone_all(strokes)
	for point: Vector2 in path:
		if not point.is_finite():
			return AtlasStroke.clone_all(strokes)

	var result: Array[AtlasStroke] = []
	for stroke: AtlasStroke in strokes:
		var radius: float = (width + stroke.width) * 0.5

		# Semantic objects cannot be turned into ordinary open-line fragments.
		# A hit removes the whole object; a miss retains all its metadata.
		if stroke.is_text() or stroke.editable_path or stroke.filled:
			if not _touches_whole_object(stroke, path, width, radius):
				result.append(stroke.copy())
			continue

		# Untouched centerlines keep their original shape and style. Only
		# intersecting lines need the more expensive sequential polygon clips.
		if not _touches(stroke.points, path, radius):
			result.append(stroke.copy())
			continue
		for part: PackedVector2Array in _retained_centerline_parts(stroke.points, path, radius):
			if not part.is_empty():
				result.append(AtlasStroke.new(part, stroke.color, stroke.width))
	return result


## Text uses its laid-out axis-aligned bounds expanded by *eraser* radius;
## editable paths test rendered geometry (not control handles). Solid polygons
## are removed when their boundary is touched or a sweep vertex is inside.
## The latter is deliberately not a general filled-area clipping operation.
## Called only for these three semantic object kinds.
static func _touches_whole_object(stroke: AtlasStroke, path: PackedVector2Array,
		eraser_width: float, collision_radius: float) -> bool:
	if stroke.is_text():
		var hit_region: Rect2 = AtlasTextLayout.bounds(stroke).grow(eraser_width * 0.5)
		for segment: int in range(maxi(1, path.size() - 1)):
			if _segment_hits_rect(hit_region, path[segment], path[mini(segment + 1, path.size() - 1)]):
				return true
		return false
	if stroke.editable_path:
		return _touches(AtlasEditablePath.render_points(stroke), path, collision_radius)

	if _touches(stroke.points, path, collision_radius):
		return true
	for point: Vector2 in path:
		if Geometry2D.is_point_in_polygon(point, stroke.points):
			return true
	return false


## Subtract each consecutive eraser capsule from the surviving centerlines.
## Sequential clipping keeps fragment order and supports multiple cuts in a
## single gesture. A one-point gesture or stroke is treated as a zero-length
## segment; single-point fragments are tested for containment before clipping.
static func _retained_centerline_parts(points: PackedVector2Array, path: PackedVector2Array,
		collision_radius: float) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [points.duplicate()]
	for index: int in range(maxi(1, path.size() - 1)):
		var start: Vector2 = path[index]
		var finish: Vector2 = path[mini(index + 1, path.size() - 1)]
		var masks: Array[PackedVector2Array] = _capsule(start, finish, collision_radius)
		for mask: PackedVector2Array in masks:
			var remaining: Array[PackedVector2Array] = []
			for part: PackedVector2Array in parts:
				if part.size() == 1:
					if not Geometry2D.is_point_in_polygon(part[0], mask):
						remaining.append(part)
				else:
					remaining.append_array(Geometry2D.clip_polyline_with_polygon(part, mask))
			parts = remaining
	return parts


## A nonzero segment uses Godot's round-ended offset; a stationary tap uses
## the same 32-sided approximation as before. This approximation and Godot's
## polygon boundary behavior are intentionally unchanged by this readability pass.
static func _capsule(start: Vector2, finish: Vector2, radius: float) -> Array[PackedVector2Array]:
	if not start.is_equal_approx(finish):
		return Geometry2D.offset_polyline(PackedVector2Array([start, finish]), radius,
			Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	var circle: PackedVector2Array = PackedVector2Array()
	for side: int in range(32):
		circle.append(start + Vector2.RIGHT.rotated(float(side) * TAU / 32.0) * radius)
	return [circle]


## Closest-point distance includes both round endpoint caps. Squared distance
## and <= retain exact tangent/boundary acceptance; degenerate paths are dots.
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


## Text hit test includes a segment crossing the box with both endpoints
## outside it, not just taps or segment endpoints contained by the rectangle.
static func _segment_hits_rect(bounds: Rect2, start: Vector2, finish: Vector2) -> bool:
	if bounds.has_point(start) or bounds.has_point(finish):
		return true
	var corners: Array[Vector2] = [bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	for side: int in range(4):
		if Geometry2D.segment_intersects_segment(start, finish, corners[side], corners[(side + 1) % 4]) != null:
			return true
	return false
