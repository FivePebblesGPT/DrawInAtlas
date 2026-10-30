class_name AtlasStrokeGeometry
extends RefCounted
## Render-only union outline for a constant-width round brush. Stored paths stay unchanged.


static func centers(path: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in path:
		if result.is_empty() or result[-1].distance_squared_to(point) > 0.0001:
			result.append(point)
	return result


static func outline(path: PackedVector2Array, width: float) -> Array[PackedVector2Array]:
	var cleaned: PackedVector2Array = centers(path)
	if cleaned.size() < 2 or not is_finite(width) or width <= 0.0:
		return []
	# Clipper unions neighboring round joins/caps into a silhouette. Drawing the
	# line plus a separate translucent circle at every sample paints joins twice.
	return Geometry2D.offset_polyline(cleaned, width * 0.5,
		Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
