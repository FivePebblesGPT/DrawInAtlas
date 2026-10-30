class_name AtlasArtworkLOD
extends RefCounted
## View-only authored-detail selection. D numbers order authored groups; neither
## camera magnification nor distance-per-cell is encoded by the number.

# Trial ratios from T-004, to be calibrated with manual input/trackpad testing.
const ENTER_COVERAGE: float = 0.65
const EXIT_COVERAGE: float = 0.45

# Cache individual visible pieces, not a single merged group rectangle: two
# disconnected towns must not synthesize D1 artwork in the empty space between.
## Rebuilt, derived visible board-space rectangles by authored D level.
## This is a presentation cache, never persisted or used as edit ownership.
var _pieces_by_level: Dictionary[int, Array] = {}


func rebuild(document: AtlasMapDocument, floor: AtlasFloor) -> void:
	_pieces_by_level.clear()
	if document == null or floor == null:
		return
	for layer: AtlasLayer in floor.layers:
		if layer.detail_level <= 0 or not layer.visible or layer.opacity <= 0.0:
			continue
		var pieces: Array[Rect2] = []
		if layer is AtlasInkLayer:
			for stroke: AtlasStroke in layer.strokes:
				if stroke.points.is_empty() or stroke.color.a <= 0.0:
					continue
				pieces.append(_point_bounds(stroke.points).grow(stroke.width * 0.5))
		elif layer is AtlasTerrainLayer:
			var grid: AtlasGrid = layer.grid if layer.grid != null else document.get_terrain_grid(floor.id)
			if grid != null:
				for key: String in layer.terrain:
					if layer.terrain[key] == 0:
						continue
					var xy: PackedStringArray = key.split(",")
					if xy.size() != 2:
						continue
					var polygon: PackedVector2Array = grid.cell_polygon(Vector2i(int(xy[0]), int(xy[1])))
					if not polygon.is_empty():
						pieces.append(_point_bounds(polygon))
		elif layer is AtlasRasterLayer and layer.pixels_per_unit > 0.0:
			for chunk: AtlasRasterChunk in layer.chunks.values():
				if chunk.image == null or chunk.image.is_empty():
					continue
				var used: Rect2i = chunk.image.get_used_rect()
				if not used.has_area():
					continue
				var position: Vector2 = (Vector2(chunk.coord) * AtlasRasterChunk.SIZE + Vector2(used.position)) / layer.pixels_per_unit
				var dimensions: Vector2 = Vector2(used.size) / layer.pixels_per_unit
				pieces.append(layer.transform * Rect2(position, dimensions))
		if not pieces.is_empty():
			if not _pieces_by_level.has(layer.detail_level):
				_pieces_by_level[layer.detail_level] = []
			_pieces_by_level[layer.detail_level].append_array(pieces)


func choose(document: AtlasMapDocument, center: Vector2, zoom: float,
		viewport: Vector2, current: int) -> int:
	if document == null or zoom <= 0.0 or not is_finite(zoom) or viewport.x <= 0.0 or viewport.y <= 0.0:
		return current
	var visible: Rect2 = Rect2(center - viewport / (2.0 * zoom), viewport / zoom)
	var footprint: Rect2 = Rect2()
	var radius: float = 0.0
	if document.grid.kind != AtlasGrid.Kind.GRIDLESS:
		var polygon: PackedVector2Array = document.grid.cell_polygon(document.grid.document_to_cell(center))
		if not polygon.is_empty():
			footprint = _point_bounds(polygon)
			radius = document.grid.cell_size * 0.5
	var levels: Array[int] = _pieces_by_level.keys()
	levels.sort()
	var chosen: int = 0
	var prior_area: float = INF
	for level: int in levels:
		var candidate_area: float = INF
		var coverage: float = 0.0
		for piece: Rect2 in _pieces_by_level[level]:
			if not piece.has_area() or not piece.intersects(visible) or not piece.grow(radius).has_point(center):
				continue
			# A long stroke crossing many hexes must not force early LOD
			# merely because its total bounds cover multiple cells.
			var extent: Vector2 = piece.size
			if footprint.has_area():
				extent = Vector2(minf(extent.x, footprint.size.x), minf(extent.y, footprint.size.y))
			var area: float = extent.x * extent.y
			if area <= 0.0:
				continue
			var ratio: float = maxf(extent.x * zoom / viewport.x, extent.y * zoom / viewport.y)
			if ratio > coverage:
				coverage = ratio
				candidate_area = area
		# Equal-scale groups cannot be separated by camera geometry. Keep
		# the first eligible authored level rather than skipping directly.
		if chosen > 0 and candidate_area >= prior_area * 0.9:
			continue
		var threshold: float = EXIT_COVERAGE if level <= current else ENTER_COVERAGE
		if coverage >= threshold:
			chosen = level
			prior_area = candidate_area
	return chosen


static func _point_bounds(points: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
