class_name AtlasSelectionGeometry
extends RefCounted

## Hit testing and transforms in canonical document/board coordinates. Ink
## geometry is stored in that space; raster chunks use local board units and
## layer.transform maps them to the document. Results are detached layer copies;
## the caller decides whether to commit an edit.


## A stroke's selectable envelope includes half its line width. Text uses its
## laid-out glyph bounds instead of treating the anchor as a stroked polyline.
static func stroke_bounds(stroke: AtlasStroke) -> Rect2:
	if stroke.is_text():
		return AtlasTextLayout.bounds(stroke)
	var bounds: Rect2 = Rect2(stroke.points[0], Vector2.ZERO)
	for point: Vector2 in stroke.points:
		bounds = bounds.expand(point)
	return bounds.grow(stroke.width * 0.5)


## Local board-unit envelope of stored raster chunks, including transparent
## pixels and gaps between chunks. Signed chunk coordinates are pixel origins
## (coord * SIZE); density converts their pixel rectangles into local units.
static func raster_local_bounds(layer: AtlasRasterLayer) -> Rect2:
	var bounds: Rect2
	var first: bool = true
	for chunk: AtlasRasterChunk in layer.chunks.values():
		var part: Rect2 = Rect2(Vector2(chunk.coord) * AtlasRasterChunk.SIZE / layer.pixels_per_unit,
			Vector2(chunk.width, chunk.height) / layer.pixels_per_unit)
		bounds = part if first else bounds.merge(part)
		first = false
	return bounds


## Axis-aligned document-space envelope of a transformed local rectangle.
## All four corners are required for rotation/skew. This is an interaction
## bound, not a new raster mask or a tight content silhouette.
static func transformed_rect(bounds: Rect2, transform: Transform2D) -> Rect2:
	var result: Rect2 = Rect2(transform * bounds.position, Vector2.ZERO)
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		result = result.expand(transform * corner)
	return result


## Capture live layer identity/content before collecting whole stroke objects.
## Stroke indices are array positions (not persistent IDs); any bad or repeated
## index rejects the entire selection rather than returning a partial subset.
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
		# Raster selects the complete layer, never individual chunks or pixels.
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

	if layer is AtlasInkLayer:
		# Keep the current selection's ordering, then add/remove incoming indices.
		# Stale snapshots are ignored independently on both sides of the operation.
		var indices: Array[int] = []
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
		# A raster hit toggles an all-or-nothing layer selection.
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


## Pick the uppermost ink stroke first; all hit coordinates and tolerance are
## in document units (the canvas converts pointer pixels before calling us).
## Raster hit testing instead maps the document point back into local units.
static func select_point(layer: AtlasLayer, point: Vector2, tolerance: float) -> AtlasSelection:
	if layer == null or not layer.visible:
		return AtlasSelection.new()
	if layer is AtlasInkLayer:
		for index: int in range(layer.strokes.size() - 1, -1, -1):
			if _hits_stroke(layer.strokes[index], point, tolerance):
				return select_indices(layer, [index])
	elif layer is AtlasRasterLayer:
		var local: Vector2 = layer.transform.affine_inverse() * point
		if raster_local_bounds(layer).has_point(local):
			return select_all(layer)
	return AtlasSelection.new()


## Text uses glyph AABB; a filled shape hits its interior; all other strokes
## hit the rendered path with half-width plus pointer tolerance. Editable
## paths use rendered points rather than their authoring/control handles.
static func _hits_stroke(stroke: AtlasStroke, point: Vector2, tolerance: float) -> bool:
	var radius: float = stroke.width * 0.5 + tolerance
	if stroke.is_text():
		return stroke_bounds(stroke).grow(tolerance).has_point(point)
	if stroke.filled and Geometry2D.is_point_in_polygon(point, stroke.points):
		return true
	var path_points: PackedVector2Array = AtlasEditablePath.render_points(stroke) if stroke.editable_path else stroke.points
	for segment: int in range(maxi(1, path_points.size() - 1)):
		var start: Vector2 = path_points[segment]
		var finish: Vector2 = path_points[mini(segment + 1, path_points.size() - 1)]
		if Geometry2D.get_closest_point_to_segment(point, start, finish).distance_to(point) <= radius:
			return true
	return false


## A marquee must enclose the *whole* padded stroke or raster-layer AABB,
## rather than merely overlapping a centerline, polygon, or transformed quad.
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
## Scope constraints check BOTH the source and destination footprints.
static func transformed(layer: AtlasLayer, selection: AtlasSelection, transform: Transform2D,
		scope: AtlasEditScope = null) -> AtlasLayer:
	# Reject empty/stale/locked selections and non-finite or singular transforms
	# before allocating any editable snapshot.
	if selection.is_empty() or not selection.matches(layer) or not layer.is_editable():
		return null
	if not transform.x.is_finite() or not transform.y.is_finite() or not transform.origin.is_finite():
		return null
	if absf(transform.determinant()) < 0.00000001:
		return null

	# Apply the operation to a detached layer. Any failed transform or mask
	# check discards it, leaving source strokes and raster pixels untouched.
	var result: AtlasLayer = AtlasLayerCodec.clone(layer)
	if result is AtlasInkLayer:
		if not _transform_ink(result as AtlasInkLayer, selection.stroke_indices, transform, scope):
			return null
	elif result is AtlasRasterLayer:
		if not _transform_raster(result as AtlasRasterLayer, selection.bounds, transform, scope):
			return null
	else:
		return null

	# Revalidate the complete changed layer; a locally valid stroke or affine
	# matrix alone does not guarantee a persistable artwork snapshot.
	return result if AtlasLayerCodec.clone(result) != null else null


## Transform selected ink positions in document space. Only uniform,
## orthogonal scaling is supported for ink: line width scales with geometry,
## and text orientation tracks rotation. Unselected strokes stay on the clone.
static func _transform_ink(layer: AtlasInkLayer, indices: Array[int], transform: Transform2D,
		scope: AtlasEditScope) -> bool:
	var scale: float = transform.x.length()
	if scale <= 0.0 or not is_equal_approx(scale, transform.y.length()) or not is_zero_approx(transform.x.dot(transform.y)):
		return false
	for index: int in indices:
		var original: AtlasStroke = layer.strokes[index]
		# The old and new complete stroke bounds must both fit the edit mask.
		if scope != null and not scope.contains_rect(stroke_bounds(original)):
			return false
		for point: int in range(original.points.size()):
			original.points[point] = transform * original.points[point]
		original.width *= scale
		if original.is_text():
			original.text_rotation += transform.get_rotation()
		if not original.is_valid() or (scope != null and not scope.contains_rect(stroke_bounds(original))):
			return false
	return true


## Compose document-space placement on the left. The local chunks and their
## RGBA bytes are never resampled; mask checks use the old and new document
## AABBs of the complete sparse-layer envelope, not per-chunk silhouettes.
static func _transform_raster(layer: AtlasRasterLayer, source_bounds: Rect2,
		transform: Transform2D, scope: AtlasEditScope) -> bool:
	if scope != null and not scope.contains_rect(source_bounds):
		return false
	layer.transform = transform * layer.transform
	var bounds: Rect2 = transformed_rect(raster_local_bounds(layer), layer.transform)
	if scope != null and not scope.contains_rect(bounds):
		return false
	return true


static func about(pivot: Vector2, offset: Vector2, scale: float, angle: float = 0.0) -> Transform2D:
	return Transform2D(angle, Vector2.ONE * scale, 0.0, pivot + offset) * Transform2D(0.0, -pivot)
