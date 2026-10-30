class_name AtlasFill
extends RefCounted
## Atomic tile and existing-pixel flood fills. Scope boundaries stop traversal.

## Four-connected INTEGER pixel-space offsets (not terrain grid neighbors).
## A raster fill never traverses an unstored chunk or leaves its edit scope.
const PIXEL_NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP
]
# Leave room for neighbor arithmetic and float32 pixel-to-document conversion.
## Conservative signed pixel-coordinate bounds for safe neighbor arithmetic;
## pixel coordinates are floor(inverse layer transform * board point * density).
const PIXEL_MIN: int = -2147483000
const PIXEL_MAX: int = 2147483000


static func tiles(grid: AtlasGrid, terrain: Dictionary, start: Vector2i, palette: int,
		scope: AtlasEditScope = null, limit: int = 8192) -> AtlasFillResult:
	if grid == null or not grid.is_valid() or grid.kind == AtlasGrid.Kind.GRIDLESS:
		return _failure("Fill requires a valid square or hex grid.")
	if palette < 0 or limit <= 0:
		return _failure("Invalid palette or fill limit.")
	for key: Variant in terrain:
		if not AtlasData.coordinate_key(key) or not terrain[key] is int or int(terrain[key]) < 0:
			return _failure("Invalid terrain data.")
	var target: int = int(terrain.get(_key(start), 0))
	if target == palette:
		return _failure("Fill would not change any cells.")
	if target == 0 and (scope == null or not scope.enabled):
		return _failure("Background fill requires a finite selection scope.")
	if scope != null and not scope.allows_polygon(grid.cell_polygon(start)):
		return _failure("Starting cell is outside the edit scope.")
	var pending: Array[Vector2i] = [start]
	var visited: Dictionary[Vector2i, bool] = {start: true}
	var affected: Array[Vector2i] = []
	var cursor: int = 0
	while cursor < pending.size():
		var cell: Vector2i = pending[cursor]
		cursor += 1
		if int(terrain.get(_key(cell), 0)) != target:
			continue
		if scope != null and not scope.allows_polygon(grid.cell_polygon(cell)):
			continue
		affected.append(cell)
		if affected.size() > limit:
			return _failure("Tile fill exceeds the cell limit.")
		for neighbor: Vector2i in grid.neighbors(cell):
			if not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	var result: AtlasFillResult = AtlasFillResult.new()
	result.terrain = terrain.duplicate(true)
	for cell: Vector2i in affected:
		if palette == 0:
			result.terrain.erase(_key(cell))
		else:
			result.terrain[_key(cell)] = palette
	result.ok = true
	return result


static func raster(layer: AtlasRasterLayer, document_point: Vector2, color: Color,
		scope: AtlasEditScope = null, limit: int = 262144, tolerance: float = 0.0,
		contiguous: bool = true) -> AtlasFillResult:
	var error: String = _raster_error(layer)
	if not error.is_empty():
		return _failure(error)
	if (not document_point.is_finite() or not _finite_color(color) or limit <= 0
			or not is_finite(tolerance) or tolerance < 0.0 or tolerance > 1.0):
		return _failure("Invalid fill point, color or pixel limit.")
	var mapped: Vector2 = (layer.transform.affine_inverse() * document_point) * layer.pixels_per_unit
	if not _pixel_position_valid(mapped):
		return _failure("Fill point is outside the supported pixel range.")
	var start: Vector2i = Vector2i(floori(mapped.x), floori(mapped.y))
	var chunk: AtlasRasterChunk = _existing_chunk(layer, start)
	if chunk == null:
		return _failure("Fill point has no existing raster pixel.")
	if not _allows_pixel(layer, start, scope):
		return _failure("Starting pixel is outside the edit scope.")
	var target: Color = chunk.image.get_pixelv(_local_pixel(start))
	var replacement: Color = _canonical_color(color)
	if target == replacement and tolerance == 0.0:
		return _failure("Fill would not change any pixels.")
	var affected: Array[Vector2i] = []
	if contiguous:
		# Visit only reachable pixels. Match each neighbor against the *seed* color,
		# not the last neighbor, so tolerance cannot progressively bleed outward.
		var pending: Array[Vector2i] = [start]
		var visited: Dictionary[Vector2i, bool] = {start: true}
		var cursor: int = 0
		while cursor < pending.size():
			var point: Vector2i = pending[cursor]
			cursor += 1
			chunk = _existing_chunk(layer, point)
			if chunk == null or not _matches(chunk.image.get_pixelv(_local_pixel(point)), target, tolerance):
				continue
			if not _allows_pixel(layer, point, scope):
				continue
			affected.append(point)
			if affected.size() > limit:
				return _failure("Raster fill exceeds the pixel limit; no pixels were changed.")
			for offset: Vector2i in PIXEL_NEIGHBORS:
				var neighbor: Vector2i = point + offset
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
	else:
		# Global mode never invents a canvas extent: visit *only* stored pixels,
		# even if the seed is fully transparent. Sorted keys stabilize traversal.
		var keys: Array[String] = layer.chunks.keys()
		keys.sort()
		for key: String in keys:
			chunk = layer.chunks[key]
			for y: int in range(chunk.height):
				for x: int in range(chunk.width):
					if not _matches(chunk.image.get_pixel(x, y), target, tolerance):
						continue
					var point: Vector2i = chunk.coord * AtlasRasterChunk.SIZE + Vector2i(x, y)
					if not _allows_pixel(layer, point, scope):
						continue
					affected.append(point)
					if affected.size() > limit:
						return _failure("Raster fill exceeds the pixel limit; no pixels were changed.")
	if affected.all(func(point: Vector2i) -> bool:
		var found: AtlasRasterChunk = _existing_chunk(layer, point)
		return found.image.get_pixelv(_local_pixel(point)) == replacement):
		return _failure("Fill would not change any pixels.")
	return _paint_snapshot(layer, affected, replacement)


## Premultiplied RGBA comparison: transparent colors match regardless of their
## hidden RGB bytes. At tolerance 0, only identical visible RGBA matches.
static func _matches(candidate: Color, seed: Color, tolerance: float) -> bool:
	if tolerance == 0.0 and candidate == seed:
		return true
	var diff: float = maxf(absf(candidate.a - seed.a),
		maxf(absf(candidate.r * candidate.a - seed.r * seed.a),
			maxf(absf(candidate.g * candidate.a - seed.g * seed.a),
				absf(candidate.b * candidate.a - seed.b * seed.a))))
	return diff <= tolerance + 0.0000001


static func _failure(message: String) -> AtlasFillResult:
	var result: AtlasFillResult = AtlasFillResult.new()
	result.message = message
	return result


static func _key(point: Vector2i) -> String:
	return "%d,%d" % [point.x, point.y]


static func _finite_color(color: Color) -> bool:
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)


static func _canonical_color(color: Color) -> Color:
	# Use the same quantization as Image writes, including clamping HDR colors.
	var pixel: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	pixel.set_pixel(0, 0, color)
	return pixel.get_pixel(0, 0)


static func _pixel_position_valid(point: Vector2) -> bool:
	return (point.is_finite() and point.x >= PIXEL_MIN and point.x <= PIXEL_MAX
		and point.y >= PIXEL_MIN and point.y <= PIXEL_MAX)


static func _raster_error(layer: AtlasRasterLayer) -> String:
	if layer == null:
		return "Missing raster layer."
	if not layer.visible or layer.locked:
		return "Raster layer must be visible and unlocked."
	if not is_finite(layer.pixels_per_unit) or layer.pixels_per_unit <= 0.0:
		return "Raster scale must be finite and positive."
	var placement: Transform2D = layer.transform
	if (not placement.x.is_finite() or not placement.y.is_finite()
			or not placement.origin.is_finite() or not is_finite(placement.determinant())
			or absf(placement.determinant()) < 0.00000001):
		return "Raster transform must be finite and invertible."
	var inverse: Transform2D = placement.affine_inverse()
	if not inverse.x.is_finite() or not inverse.y.is_finite() or not inverse.origin.is_finite():
		return "Raster inverse transform is not finite."
	for key: String in layer.chunks:
		var chunk: AtlasRasterChunk = layer.chunks[key]
		if chunk == null or not chunk.is_valid(true) or chunk.image.is_compressed():
			return "Raster chunks require valid canonical RGBA8 images."
		if key != _key(chunk.coord):
			return "Raster chunk key does not match its coordinates."
		var x: int = int(chunk.coord.x) * AtlasRasterChunk.SIZE
		var y: int = int(chunk.coord.y) * AtlasRasterChunk.SIZE
		if (x < PIXEL_MIN or y < PIXEL_MIN
				or x + chunk.width > PIXEL_MAX or y + chunk.height > PIXEL_MAX):
			return "Raster chunk is outside the supported pixel range."
	return ""


static func _local_pixel(point: Vector2i) -> Vector2i:
	return point - AtlasRasterLayer.pixel_to_chunk(point) * AtlasRasterChunk.SIZE


static func _existing_chunk(layer: AtlasRasterLayer, point: Vector2i) -> AtlasRasterChunk:
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get(_key(coord))
	if chunk == null:
		return null
	var local: Vector2i = _local_pixel(point)
	return chunk if local.x < chunk.width and local.y < chunk.height else null


static func _allows_pixel(layer: AtlasRasterLayer, point: Vector2i, scope: AtlasEditScope) -> bool:
	if scope == null or not scope.enabled:
		return true
	var quad: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		quad.append(layer.transform * ((Vector2(point) + offset) / layer.pixels_per_unit))
	return scope.allows_polygon(quad)


static func _paint_snapshot(layer: AtlasRasterLayer, points: Array[Vector2i],
		color: Color) -> AtlasFillResult:
	var changes: Dictionary[Vector2i, Color] = {}
	for point: Vector2i in points:
		changes[point] = color
	return _paint_pixel_colors(layer, changes)


## Shared immutable snapshot writer: fill uses one color, brush supplies blended pixels.
static func _paint_pixel_colors(layer: AtlasRasterLayer,
		changes: Dictionary[Vector2i, Color]) -> AtlasFillResult:
	if changes.is_empty():
		return _failure("Edit would not change any pixels.")
	var snapshot: AtlasRasterLayer = AtlasLayerCodec.clone(layer) as AtlasRasterLayer
	if snapshot == null:
		return _failure("Could not clone the raster layer.")
	for point: Vector2i in changes:
		var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
		var key: String = _key(coord)
		var local: Vector2i = _local_pixel(point)
		var chunk: AtlasRasterChunk = snapshot.chunks.get(key)
		if chunk == null:
			var image: Image = Image.create_empty(AtlasRasterChunk.SIZE, AtlasRasterChunk.SIZE,
				false, Image.FORMAT_RGBA8)
			chunk = AtlasRasterChunk.new(coord, image)
			snapshot.chunks[key] = chunk
		elif local.x >= chunk.width or local.y >= chunk.height:
			# Pen can grow a partial imported edge chunk without losing its pixels.
			var expanded: Image = Image.create_empty(AtlasRasterChunk.SIZE, AtlasRasterChunk.SIZE,
				false, Image.FORMAT_RGBA8)
			expanded.blit_rect(chunk.image, Rect2i(0, 0, chunk.width, chunk.height), Vector2i.ZERO)
			chunk.image = expanded
			chunk.width = AtlasRasterChunk.SIZE
			chunk.height = AtlasRasterChunk.SIZE
		chunk.image.set_pixelv(local, changes[point])
	var result: AtlasFillResult = AtlasFillResult.new()
	result.ok = true
	result.layer = snapshot
	return result
