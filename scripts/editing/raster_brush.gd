class_name AtlasRasterBrush
extends RefCounted
## Hard round swept brush, measured in document units, returning a detached layer.

var _source: AtlasRasterLayer
var _snapshot: AtlasRasterLayer
var _color: Color
var _width: float
var _erase: bool
var _scope: AtlasEditScope
var _limit: int
var _last: Vector2
var _has_last: bool = false
var _covered: Dictionary[Vector2i, bool] = {}
var _error: String = ""


func _init(layer: AtlasRasterLayer = null, color: Color = Color.BLACK, width: float = 8.0,
		erase: bool = false, scope: AtlasEditScope = null, limit: int = 1048576) -> void:
	_source = layer
	_color = color
	_width = width
	_erase = erase
	_scope = scope
	_limit = limit
	_error = AtlasFill._raster_error(layer)
	if not is_finite(width) or width <= 0.0 or limit <= 0:
		_error = "Brush requires a path, positive finite width and pixel limit."
	elif not AtlasFill._finite_color(color):
		_error = "Brush color must be finite."


## Append new samples only. Every covered pixel blends once against the original
## layer, even where the gesture crosses itself or arrives in separate batches.
func append(path: PackedVector2Array) -> AtlasFillResult:
	if not _error.is_empty():
		return AtlasFill._failure(_error)
	if path.is_empty():
		return AtlasFill._failure("Brush requires a path, positive finite width and pixel limit.")
	for point: Vector2 in path:
		if not point.is_finite():
			_error = "Brush path must be finite."
			return AtlasFill._failure(_error)
	var changes: Dictionary[Vector2i, Color] = {}
	var replacement: Color = Color(0, 0, 0, 0) if _erase else AtlasFill._canonical_color(_color)
	for point: Vector2 in path:
		var start: Vector2 = _last if _has_last else point
		var segment_error: String = _stage_segment(start, point, replacement, changes)
		if not segment_error.is_empty():
			_error = segment_error
			return AtlasFill._failure(segment_error)
		_last = point
		_has_last = true
	if not changes.is_empty():
		if _snapshot == null:
			_snapshot = AtlasLayerCodec.clone(_source) as AtlasRasterLayer
			if _snapshot == null:
				_error = "Could not clone the raster layer."
				return AtlasFill._failure(_error)
		AtlasFill._write_pixel_colors(_snapshot, changes)
	if _snapshot == null:
		return AtlasFill._failure("Edit would not change any pixels.")
	var result: AtlasFillResult = AtlasFillResult.new()
	result.ok = true
	result.layer = _snapshot
	return result


## path/width are in document-board units; candidate coordinates and limit
## are in raster PIXELS after inverse transform and pixels_per_unit scaling.
## The resulting layer is detached; no source pixels are modified in place.
static func paint(layer: AtlasRasterLayer, path: PackedVector2Array, color: Color,
		width: float, erase: bool, scope: AtlasEditScope = null,
		limit: int = 1048576) -> AtlasFillResult:
	return AtlasRasterBrush.new(layer, color, width, erase, scope, limit).append(path)


## Outlines and freehand use the swept brush; solid shapes fill raster pixels.
static func paint_stroke(layer: AtlasRasterLayer, stroke: AtlasStroke, erase: bool = false,
		scope: AtlasEditScope = null, limit: int = 1048576) -> AtlasFillResult:
	if stroke == null or not stroke.is_valid() or stroke.is_text() or stroke.is_prop() or stroke.editable_path:
		return AtlasFill._failure("Raster drawing requires a valid brush stroke or shape.")
	if not stroke.filled:
		return paint(layer, stroke.points, stroke.color, stroke.width, erase, scope, limit)
	var brush: AtlasRasterBrush = AtlasRasterBrush.new(layer, stroke.color, stroke.width, erase, scope, limit)
	if not brush._error.is_empty():
		return AtlasFill._failure(brush._error)
	var bounds: Rect2 = Rect2(stroke.points[0], Vector2.ZERO)
	for point: Vector2 in stroke.points:
		bounds = bounds.expand(point)
	var pixels: Rect2i = brush._pixel_bounds(bounds)
	if not brush._error.is_empty():
		return AtlasFill._failure(brush._error)
	var changes: Dictionary[Vector2i, Color] = {}
	var covered: Dictionary[Vector2i, bool] = {}
	var error: String = _stage_pixel_changes(layer, stroke.points, 0.0,
		Color(0, 0, 0, 0) if erase else AtlasFill._canonical_color(stroke.color), erase,
		scope, pixels.position, pixels.end, changes, covered, true)
	return AtlasFill._failure(error) if not error.is_empty() else AtlasFill._paint_pixel_colors(layer, changes)


## Stage one swept leg of the gesture. A window wider than the pixel limit is
## split at its midpoint instead of failing the whole session, so long loops and
## sparse leg jumps stay bounded; coverage math is unchanged by the split.
func _stage_segment(start: Vector2, end: Vector2, replacement: Color,
		changes: Dictionary[Vector2i, Color]) -> String:
	var pixels: Rect2i = _pixel_bounds(Rect2(start, Vector2.ZERO).expand(end).grow(_width * 0.5))
	if _error.is_empty():
		return _stage_pixel_changes(_source, PackedVector2Array([start, end]), _width * 0.5,
			replacement, _erase, _scope, pixels.position, pixels.end, changes, _covered)
	var failure: String = _error
	if failure != "Brush exceeds the candidate pixel limit." or end == start:
		return failure
	_error = ""
	var middle: Vector2 = (start + end) * 0.5
	var first_error: String = _stage_segment(start, middle, replacement, changes)
	return first_error if not first_error.is_empty() else _stage_segment(middle, end, replacement, changes)


func _pixel_bounds(bounds: Rect2) -> Rect2i:
	if not bounds.position.is_finite() or not bounds.end.is_finite():
		_error = "Brush bounds are not finite."
		return Rect2i()
	var inverse: Transform2D = _source.transform.affine_inverse()
	var corners: PackedVector2Array = PackedVector2Array([
		bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)
	])
	var pixel_bounds: Rect2
	for index: int in range(corners.size()):
		var mapped: Vector2 = (inverse * corners[index]) * _source.pixels_per_unit
		if not AtlasFill._pixel_position_valid(mapped):
			_error = "Brush is outside the supported pixel range."
			return Rect2i()
		if index == 0:
			pixel_bounds = Rect2(mapped, Vector2.ZERO)
		else:
			pixel_bounds = pixel_bounds.expand(mapped)
	var left: int = floori(pixel_bounds.position.x)
	var top: int = floori(pixel_bounds.position.y)
	var right: int = ceili(pixel_bounds.end.x)
	var bottom: int = ceili(pixel_bounds.end.y)
	var columns: int = right - left
	var rows: int = bottom - top
	# Check using 64-bit ints before narrowing the rectangle to Vector2i.
	if columns > mini(_limit, 2147483647) or rows > mini(_limit, 2147483647) or (rows > 0 and columns > _limit / rows):
		_error = "Brush exceeds the candidate pixel limit."
		return Rect2i()
	return Rect2i(left, top, right - left, bottom - top)


## Scan the half-open rectangle of global raster pixel coordinates, staging only
## changed colors. A nonempty error means the caller must discard the changes.
## For erase, missing chunks are skipped *before* computing transformed centers;
## painting is allowed to create them in the shared snapshot writer.
static func _stage_pixel_changes(layer: AtlasRasterLayer, path: PackedVector2Array,
		radius: float, replacement: Color, erase: bool, scope: AtlasEditScope,
		pixel_start: Vector2i, pixel_end: Vector2i,
		changes: Dictionary[Vector2i, Color], covered: Dictionary[Vector2i, bool], filled: bool = false) -> String:
	for y: int in range(pixel_start.y, pixel_end.y):
		for x: int in range(pixel_start.x, pixel_end.x):
			var pixel: Vector2i = Vector2i(x, y)
			if covered.has(pixel):
				continue
			var source_chunk: AtlasRasterChunk = AtlasFill._existing_chunk(layer, pixel)
			if erase and source_chunk == null:
				continue

			# Coverage is measured at the transformed pixel center in document
			# units, even for rotated or skewed raster layers.
			var document_center: Vector2 = layer.transform * ((Vector2(pixel) + Vector2(0.5, 0.5))
				/ layer.pixels_per_unit)
			if not document_center.is_finite():
				return "Transformed brush pixel is not finite."
			if not (Geometry2D.is_point_in_polygon(document_center, path) if filled else _touches(document_center, path, radius)):
				continue

			# A scope must admit the entire transformed pixel quad, not just its
			# center. Neither coverage nor scope may mutate the source layer.
			if not AtlasFill._allows_pixel(layer, pixel, scope):
				continue
			covered[pixel] = true

			# Blend once per covered pixel against the pre-gesture image. Multiple
			# pointer samples must not multiply the alpha of one brush gesture.
			var previous: Color = Color(0.0, 0.0, 0.0, 0.0)
			if source_chunk != null:
				previous = source_chunk.image.get_pixelv(AtlasFill._local_pixel(pixel))
			var next_color: Color = replacement if erase else _source_over(replacement, previous)
			if previous != next_color:
				changes[pixel] = next_color
	return ""

static func _source_over(source: Color, destination: Color) -> Color:
	if source.a <= 0.0:
		return destination
	var opacity: float = clampf(source.a, 0.0, 1.0)
	var alpha: float = opacity + destination.a * (1.0 - opacity)
	if alpha <= 0.0:
		return Color.TRANSPARENT
	var result: Color = Color(
		(source.r * opacity + destination.r * destination.a * (1.0 - opacity)) / alpha,
		(source.g * opacity + destination.g * destination.a * (1.0 - opacity)) / alpha,
		(source.b * opacity + destination.b * destination.a * (1.0 - opacity)) / alpha,
		alpha)
	return AtlasFill._canonical_color(result)


static func _touches(point: Vector2, path: PackedVector2Array, radius: float) -> bool:
	if path.size() == 1:
		return point.distance_to(path[0]) <= radius
	for index: int in range(1, path.size()):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			point, path[index - 1], path[index])
		if point.distance_to(closest) <= radius:
			return true
	return false
