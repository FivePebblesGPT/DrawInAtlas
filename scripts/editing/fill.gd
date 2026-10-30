class_name AtlasFill
extends RefCounted
## Atomic tile and existing-pixel flood fills. Scope boundaries stop traversal.

## Four-connected INTEGER pixel-space offsets (not terrain grid neighbors).
## A raster fill never traverses an unstored chunk or leaves its edit scope.
const PIXEL_NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP
]
## Conservative signed pixel-coordinate bounds for safe neighbor arithmetic;
## pixel coordinates are floor(inverse layer transform * board point * density).
## Leave room for neighbor arithmetic and float32 pixel-to-document conversion.
const PIXEL_MIN: int = -2147483000
const PIXEL_MAX: int = 2147483000


## Terrain uses string "x,y" (square) or "q,r" (axial hex) -> palette ID.
## Palette 0 denotes the absent/background cell; the result owns a deep copy.
static func tiles(grid: AtlasGrid, terrain: Dictionary, start: Vector2i, palette: int,
		scope: AtlasEditScope = null, limit: int = 8192) -> AtlasFillResult:
	# Validate the terrain map and fill request before traversing or copying cells.
	if grid == null or not grid.is_valid() or grid.kind == AtlasGrid.Kind.GRIDLESS:
		return _failure("Fill requires a valid square or hex grid.")
	if palette < 0 or limit <= 0:
		return _failure("Invalid palette or fill limit.")
	for key: Variant in terrain:
		if not AtlasData.coordinate_key(key) or not terrain[key] is int or int(terrain[key]) < 0:
			return _failure("Invalid terrain data.")

	# A missing key is background. Filling background requires a finite scope;
	# scope eligibility covers the *entire* grid cell polygon, not its center.
	var seed_palette: int = int(terrain.get(_key(start), 0))
	if seed_palette == palette:
		return _failure("Fill would not change any cells.")
	if seed_palette == 0 and (scope == null or not scope.enabled):
		return _failure("Background fill requires a finite selection scope.")
	if scope != null and not scope.allows_polygon(grid.cell_polygon(start)):
		return _failure("Starting cell is outside the edit scope.")

	# Breadth-first over grid neighbors (four square / six axial hex). Visit each
	# candidate once, but count only matching, in-scope cells toward the limit.
	var pending_cells: Array[Vector2i] = [start]
	var visited_cells: Dictionary[Vector2i, bool] = {start: true}
	var affected_cells: Array[Vector2i] = []
	var next_index: int = 0
	while next_index < pending_cells.size():
		var cell: Vector2i = pending_cells[next_index]
		next_index += 1
		if int(terrain.get(_key(cell), 0)) != seed_palette:
			continue
		if scope != null and not scope.allows_polygon(grid.cell_polygon(cell)):
			continue
		affected_cells.append(cell)
		if affected_cells.size() > limit:
			return _failure("Tile fill exceeds the cell limit.")
		for neighbor: Vector2i in grid.neighbors(cell):
			if not visited_cells.has(neighbor):
				visited_cells[neighbor] = true
				pending_cells.append(neighbor)

	# Stage edits on a detached terrain copy only after all eligibility and
	# limit checks pass; an overflowing fill never partially changes the source.
	var result: AtlasFillResult = AtlasFillResult.new()
	result.terrain = terrain.duplicate(true)
	for cell: Vector2i in affected_cells:
		if palette == 0:
			result.terrain.erase(_key(cell))
		else:
			result.terrain[_key(cell)] = palette
	result.ok = true
	return result


## document_point is in board units; traversal uses integer RGBA8 pixel
## coordinates after the inverse layer transform and pixels_per_unit scaling.
static func raster(layer: AtlasRasterLayer, document_point: Vector2, color: Color,
		scope: AtlasEditScope = null, limit: int = 262144, tolerance: float = 0.0,
		contiguous: bool = true) -> AtlasFillResult:
	# Reject malformed layers and options before touching any candidate pixels.
	var error: String = _raster_error(layer)
	if not error.is_empty():
		return _failure(error)
	if (not document_point.is_finite() or not _finite_color(color) or limit <= 0
			or not is_finite(tolerance) or tolerance < 0.0 or tolerance > 1.0):
		return _failure("Invalid fill point, color or pixel limit.")

	# Map the document-space seed to a stored pixel. Neither mode is allowed to
	# start in an absent chunk or in the padding of a partial imported chunk.
	var mapped_pixel: Vector2 = (layer.transform.affine_inverse() * document_point) * layer.pixels_per_unit
	if not _pixel_position_valid(mapped_pixel):
		return _failure("Fill point is outside the supported pixel range.")
	var seed_pixel: Vector2i = Vector2i(floori(mapped_pixel.x), floori(mapped_pixel.y))
	var seed_chunk: AtlasRasterChunk = _existing_chunk(layer, seed_pixel)
	if seed_chunk == null:
		return _failure("Fill point has no existing raster pixel.")
	if not _allows_pixel(layer, seed_pixel, scope):
		return _failure("Starting pixel is outside the edit scope.")
	var seed_color: Color = seed_chunk.image.get_pixelv(_local_pixel(seed_pixel))
	var replacement: Color = _canonical_color(color)
	if seed_color == replacement and tolerance == 0.0:
		return _failure("Fill would not change any pixels.")

	# Collect eligible pixels without writing: connected mode walks four-neighbor
	# pixels; global mode scans only stored image extents in sorted chunk order.
	# Both scans stop at limit+1, so overflow can be rejected atomically here.
	var affected_pixels: Array[Vector2i]
	if contiguous:
		affected_pixels = _connected_raster_pixels(layer, seed_pixel, seed_color, scope, limit, tolerance)
	else:
		affected_pixels = _matching_stored_raster_pixels(layer, seed_color, scope, limit, tolerance)
	if affected_pixels.size() > limit:
		return _failure("Raster fill exceeds the pixel limit; no pixels were changed.")

	# With tolerance, an accepted region can already have the requested color.
	# Avoid returning an unchanged snapshot after scanning the whole region.
	var would_change: bool = false
	for pixel: Vector2i in affected_pixels:
		var original_chunk: AtlasRasterChunk = _existing_chunk(layer, pixel)
		if original_chunk.image.get_pixelv(_local_pixel(pixel)) != replacement:
			would_change = true
			break
	if not would_change:
		return _failure("Fill would not change any pixels.")

	# Construct the detached snapshot only once the entire scan has succeeded.
	return _paint_snapshot(layer, affected_pixels, replacement)


## The caller has already validated that seed_pixel is stored and in scope.
## Compare all candidates to the *seed* color, never to the previous pixel:
## tolerance must not allow the match to drift along the flood frontier.
## Return at most limit+1 pixels; a longer region signals overflow to the caller.
static func _connected_raster_pixels(layer: AtlasRasterLayer, seed_pixel: Vector2i,
		seed_color: Color, scope: AtlasEditScope, limit: int, tolerance: float) -> Array[Vector2i]:
	var pending_pixels: Array[Vector2i] = [seed_pixel]
	var visited_pixels: Dictionary[Vector2i, bool] = {seed_pixel: true}
	var matching_pixels: Array[Vector2i] = []
	var next_index: int = 0
	while next_index < pending_pixels.size():
		var pixel: Vector2i = pending_pixels[next_index]
		next_index += 1
		var chunk: AtlasRasterChunk = _existing_chunk(layer, pixel)
		if chunk == null or not _matches(chunk.image.get_pixelv(_local_pixel(pixel)), seed_color, tolerance):
			continue
		if not _allows_pixel(layer, pixel, scope):
			continue
		matching_pixels.append(pixel)
		if matching_pixels.size() > limit:
			return matching_pixels
		for offset: Vector2i in PIXEL_NEIGHBORS:
			var neighbor: Vector2i = pixel + offset
			if not visited_pixels.has(neighbor):
				visited_pixels[neighbor] = true
				pending_pixels.append(neighbor)
	return matching_pixels


## Global mode has no implicit canvas bounds: even a fully transparent seed
## only matches stored pixels, not neighboring blank/unstored chunks.
## Return at most limit+1 pixels, in sorted-chunk/row-major traversal order.
static func _matching_stored_raster_pixels(layer: AtlasRasterLayer, seed_color: Color,
		scope: AtlasEditScope, limit: int, tolerance: float) -> Array[Vector2i]:
	var matching_pixels: Array[Vector2i] = []
	var chunk_keys: Array[String] = layer.chunks.keys()
	chunk_keys.sort()
	for key: String in chunk_keys:
		var chunk: AtlasRasterChunk = layer.chunks[key]
		for y: int in range(chunk.height):
			for x: int in range(chunk.width):
				if not _matches(chunk.image.get_pixel(x, y), seed_color, tolerance):
					continue
				var pixel: Vector2i = chunk.coord * AtlasRasterChunk.SIZE + Vector2i(x, y)
				if not _allows_pixel(layer, pixel, scope):
					continue
				matching_pixels.append(pixel)
				if matching_pixels.size() > limit:
					return matching_pixels
	return matching_pixels


## Premultiplied RGBA comparison: transparent colors match regardless of their
## hidden RGB bytes. At tolerance 0, only identical visible RGBA matches.
static func _matches(candidate: Color, seed: Color, tolerance: float) -> bool:
	if tolerance == 0.0 and candidate == seed:
		return true
	var alpha_difference: float = absf(candidate.a - seed.a)
	var red_difference: float = absf(candidate.r * candidate.a - seed.r * seed.a)
	var green_difference: float = absf(candidate.g * candidate.a - seed.g * seed.a)
	var blue_difference: float = absf(candidate.b * candidate.a - seed.b * seed.a)
	var largest_difference: float = maxf(alpha_difference,
		maxf(red_difference, maxf(green_difference, blue_difference)))
	return largest_difference <= tolerance + 0.0000001


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
	# Validate transform and scale before using the inverse to map the seed.
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
	# Validate every sparse chunk, including those not reached by this fill.
	# Keys encode signed chunk coordinates; limits below are in global pixels.
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
	# Require the entire transformed document-space pixel quad in the mask,
	# not merely the center (especially important for rotated raster layers).
	var quad: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		quad.append(layer.transform * ((Vector2(point) + offset) / layer.pixels_per_unit))
	return scope.allows_polygon(quad)


static func _paint_snapshot(layer: AtlasRasterLayer, points: Array[Vector2i],
		color: Color) -> AtlasFillResult:
	# A fill uses one color; the shared writer also accepts per-pixel brush colors.
	var changes: Dictionary[Vector2i, Color] = {}
	for point: Vector2i in points:
		changes[point] = color
	return _paint_pixel_colors(layer, changes)


## Shared immutable snapshot writer: fill uses one color, brush supplies blended pixels.
static func _paint_pixel_colors(layer: AtlasRasterLayer,
		changes: Dictionary[Vector2i, Color]) -> AtlasFillResult:
	# Clone the complete layer before any change. Failed validation or cloning
	# leaves the original chunks and Image buffers untouched.
	if changes.is_empty():
		return _failure("Edit would not change any pixels.")
	var snapshot: AtlasRasterLayer = AtlasLayerCodec.clone(layer) as AtlasRasterLayer
	if snapshot == null:
		return _failure("Could not clone the raster layer.")

	# Apply staged pixels to the snapshot only. Brush may create chunks or grow
	# partial imported edge chunks; fill itself selects existing pixels only.
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

	# The caller decides when to install this complete edit and record history.
	var result: AtlasFillResult = AtlasFillResult.new()
	result.ok = true
	result.layer = snapshot
	return result
