class_name AtlasRasterBrush
extends RefCounted
## Hard round swept brush, measured in document units, returning a detached layer.


static func paint(layer: AtlasRasterLayer, path: PackedVector2Array, color: Color,
		width: float, erase: bool, scope: AtlasEditScope = null,
		limit: int = 1048576) -> AtlasFillResult:
	var error: String = AtlasFill._raster_error(layer)
	if not error.is_empty():
		return AtlasFill._failure(error)
	if path.is_empty() or not is_finite(width) or width <= 0.0 or limit <= 0:
		return AtlasFill._failure("Brush requires a path, positive finite width and pixel limit.")
	if not AtlasFill._finite_color(color):
		return AtlasFill._failure("Brush color must be finite.")
	for point: Vector2 in path:
		if not point.is_finite():
			return AtlasFill._failure("Brush path must be finite.")
	var radius: float = width * 0.5
	var bounds: Rect2 = Rect2(path[0], Vector2.ZERO)
	for point: Vector2 in path:
		bounds = bounds.expand(point)
	bounds = bounds.grow(radius)
	if not bounds.position.is_finite() or not bounds.end.is_finite():
		return AtlasFill._failure("Brush bounds are not finite.")
	var inverse: Transform2D = layer.transform.affine_inverse()
	var corners: PackedVector2Array = PackedVector2Array([
		bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)
	])
	var pixel_bounds: Rect2
	for index: int in range(corners.size()):
		var mapped: Vector2 = (inverse * corners[index]) * layer.pixels_per_unit
		if not AtlasFill._pixel_position_valid(mapped):
			return AtlasFill._failure("Brush is outside the supported pixel range.")
		if index == 0:
			pixel_bounds = Rect2(mapped, Vector2.ZERO)
		else:
			pixel_bounds = pixel_bounds.expand(mapped)
	var left: int = floori(pixel_bounds.position.x)
	var top: int = floori(pixel_bounds.position.y)
	var right: int = ceili(pixel_bounds.end.x)
	var bottom: int = ceili(pixel_bounds.end.y)
	# Bound work before scanning or allocating, even for a mostly empty eraser.
	var columns: int = right - left
	var rows: int = bottom - top
	if columns <= 0 or rows <= 0:
		return AtlasFill._failure("Brush covers no pixel centers.")
	if columns > limit or rows > limit or columns > limit / rows:
		return AtlasFill._failure("Brush exceeds the candidate pixel limit.")
	var replacement: Color = Color(0.0, 0.0, 0.0, 0.0) if erase else AtlasFill._canonical_color(color)
	var affected: Array[Vector2i] = []
	for y: int in range(top, bottom):
		for x: int in range(left, right):
			var pixel: Vector2i = Vector2i(x, y)
			var chunk: AtlasRasterChunk = AtlasFill._existing_chunk(layer, pixel)
			if erase and chunk == null:
				continue
			var center: Vector2 = layer.transform * ((Vector2(pixel) + Vector2(0.5, 0.5))
				/ layer.pixels_per_unit)
			if not center.is_finite():
				return AtlasFill._failure("Transformed brush pixel is not finite.")
			if not _touches(center, path, radius):
				continue
			if not AtlasFill._allows_pixel(layer, pixel, scope):
				continue
			var previous: Color = Color(0.0, 0.0, 0.0, 0.0)
			if chunk != null:
				previous = chunk.image.get_pixelv(AtlasFill._local_pixel(pixel))
			if previous != replacement:
				affected.append(pixel)
	return AtlasFill._paint_snapshot(layer, affected, replacement)


static func _touches(point: Vector2, path: PackedVector2Array, radius: float) -> bool:
	if path.size() == 1:
		return point.distance_to(path[0]) <= radius
	for index: int in range(1, path.size()):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			point, path[index - 1], path[index])
		if point.distance_to(closest) <= radius:
			return true
	return false
