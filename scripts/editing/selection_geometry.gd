class_name AtlasSelectionGeometry
extends RefCounted

## Hit testing and transforms in canonical board coordinates. This service
## returns copies of layer data; the caller decides whether to commit an edit.


static func stroke_bounds(stroke: AtlasStroke) -> Rect2:
	if stroke.is_text():
		return AtlasTextLayout.bounds(stroke)
	var bounds: Rect2 = Rect2(stroke.points[0], Vector2.ZERO)
	for point: Vector2 in stroke.points:
		bounds = bounds.expand(point)
	return bounds.grow(stroke.width * 0.5)


## Local board-unit bounds of stored raster chunks, before layer.transform.
## Signed chunk coords are pixel origins (coord * SIZE) divided by density.
static func raster_local_bounds(layer: AtlasRasterLayer) -> Rect2:
	var bounds: Rect2
	var first: bool = true
	for chunk: AtlasRasterChunk in layer.chunks.values():
		var part: Rect2 = Rect2(Vector2(chunk.coord) * AtlasRasterChunk.SIZE / layer.pixels_per_unit,
			Vector2(chunk.width, chunk.height) / layer.pixels_per_unit)
		bounds = part if first else bounds.merge(part)
		first = false
	return bounds


## Derived axis-aligned board-space envelope of all four transformed corners;
## the rectangle is an interaction bound, not raster content or a saved mask.
static func transformed_rect(bounds: Rect2, transform: Transform2D) -> Rect2:
	var result: Rect2 = Rect2(transform * bounds.position, Vector2.ZERO)
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		result = result.expand(transform * corner)
	return result


static func select_indices(layer: AtlasLayer, indices: Array[int] = []) -> AtlasSelection:
	var result: AtlasSelection = AtlasSelection.new()
	if layer == null or not layer.visible:
		return result
	result.layer_id = layer.id
	result.source = layer.to_dict().duplicate(true)
	if layer is AtlasInkLayer:
		var first: bool = true
		for index: int in indices:
			if index < 0 or index >= layer.strokes.size() or result.stroke_indices.has(index):
				return AtlasSelection.new()
			result.stroke_indices.append(index)
			var bounds: Rect2 = stroke_bounds(layer.strokes[index])
			result.bounds = bounds if first else result.bounds.merge(bounds)
			first = false
	elif layer is AtlasRasterLayer and not layer.chunks.is_empty():
		result.raster_selected = true
		result.bounds = transformed_rect(raster_local_bounds(layer), layer.transform)
	return result


## Combine whole-object selections on the same active layer. The original
## selection must still match the live layer; stale selections never survive
## a layer edit or a switch to another layer/detail group.
## Ink is selected by stroke identity; raster currently selects whole layers.
enum CombineMode { REPLACE, ADD, SUBTRACT }

static func combined(layer: AtlasLayer, current: AtlasSelection, incoming: AtlasSelection,
		mode: CombineMode) -> AtlasSelection:
	if mode == CombineMode.REPLACE:
		return incoming if incoming.matches(layer) else AtlasSelection.new()
	if layer == null or not layer.visible:
		return AtlasSelection.new()
	var indices: Array[int] = []
	if layer is AtlasInkLayer:
		if current.matches(layer):
			indices = current.stroke_indices.duplicate()
		if incoming.matches(layer):
			for index: int in incoming.stroke_indices:
				if mode == CombineMode.ADD and not indices.has(index):
					indices.append(index)
				elif mode == CombineMode.SUBTRACT:
					indices.erase(index)
		return select_indices(layer, indices)
	if layer is AtlasRasterLayer:
		var selected: bool = current.matches(layer) and current.raster_selected
		var hit: bool = incoming.matches(layer) and incoming.raster_selected
		if mode == CombineMode.ADD:
			return select_all(layer) if selected or hit else AtlasSelection.new()
		return select_all(layer) if selected and not hit else AtlasSelection.new()
	return AtlasSelection.new()


static func select_all(layer: AtlasLayer) -> AtlasSelection:
	var indices: Array[int] = []
	if layer is AtlasInkLayer:
		for index: int in range(layer.strokes.size()):
			indices.append(index)
	return select_indices(layer, indices)


static func select_point(layer: AtlasLayer, point: Vector2, tolerance: float) -> AtlasSelection:
	if layer == null or not layer.visible:
		return AtlasSelection.new()
	if layer is AtlasInkLayer:
		for index: int in range(layer.strokes.size() - 1, -1, -1):
			var stroke: AtlasStroke = layer.strokes[index]
			var radius: float = stroke.width * 0.5 + tolerance
			if stroke.is_text():
				if stroke_bounds(stroke).grow(tolerance).has_point(point):
					return select_indices(layer, [index])
				continue
			if stroke.filled and Geometry2D.is_point_in_polygon(point, stroke.points):
				return select_indices(layer, [index])
			var path_points: PackedVector2Array = AtlasEditablePath.render_points(stroke) if stroke.editable_path else stroke.points
			for segment: int in range(maxi(1, path_points.size() - 1)):
				var start: Vector2 = path_points[segment]
				var finish: Vector2 = path_points[mini(segment + 1, path_points.size() - 1)]
				if Geometry2D.get_closest_point_to_segment(point, start, finish).distance_to(point) <= radius:
					return select_indices(layer, [index])
	elif layer is AtlasRasterLayer:
		var local: Vector2 = layer.transform.affine_inverse() * point
		if raster_local_bounds(layer).has_point(local):
			return select_all(layer)
	return AtlasSelection.new()


static func select_rect(layer: AtlasLayer, rectangle: Rect2) -> AtlasSelection:
	var indices: Array[int] = []
	if layer is AtlasInkLayer:
		for index: int in range(layer.strokes.size()):
			if rectangle.encloses(stroke_bounds(layer.strokes[index])):
				indices.append(index)
		return select_indices(layer, indices)
	if layer is AtlasRasterLayer:
		var selection: AtlasSelection = select_all(layer)
		if not selection.is_empty() and rectangle.encloses(selection.bounds):
			return selection
	return AtlasSelection.new()


## Ink strokes are uniformly scaled (including line width). Raster images
## retain exact stored pixels and instead compose affine layer transforms.
## Scope constraints check BOTH the source and the destination footprints.
static func transformed(layer: AtlasLayer, selection: AtlasSelection, transform: Transform2D,
		scope: AtlasEditScope = null) -> AtlasLayer:
	if selection.is_empty() or not selection.matches(layer) or not layer.is_editable():
		return null
	if not transform.x.is_finite() or not transform.y.is_finite() or not transform.origin.is_finite():
		return null
	if absf(transform.determinant()) < 0.00000001:
		return null
	var result: AtlasLayer = AtlasLayerCodec.clone(layer)
	if result is AtlasInkLayer:
		var scale: float = transform.x.length()
		if scale <= 0.0 or not is_equal_approx(scale, transform.y.length()) or not is_zero_approx(transform.x.dot(transform.y)):
			return null
		for index: int in selection.stroke_indices:
			var original: AtlasStroke = result.strokes[index]
			if scope != null and not scope.contains_rect(stroke_bounds(original)):
				return null
			for point: int in range(original.points.size()):
				original.points[point] = transform * original.points[point]
			original.width *= scale
			if original.is_text():
				original.text_rotation += transform.get_rotation()
			if not original.is_valid() or (scope != null and not scope.contains_rect(stroke_bounds(original))):
				return null
	elif result is AtlasRasterLayer:
		if scope != null and not scope.contains_rect(selection.bounds):
			return null
		result.transform = transform * result.transform
		var bounds: Rect2 = transformed_rect(raster_local_bounds(result), result.transform)
		if scope != null and not scope.contains_rect(bounds):
			return null
	else:
		return null
	return result if AtlasLayerCodec.clone(result) != null else null


static func about(pivot: Vector2, offset: Vector2, scale: float, angle: float = 0.0) -> Transform2D:
	return Transform2D(angle, Vector2.ONE * scale, 0.0, pivot + offset) * Transform2D(0.0, -pivot)
