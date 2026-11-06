class_name DrawingEditSession
extends RefCounted
## Detached gesture transaction. No tile is changed before commit; cancel is free.
## View coordinates are camera-relative floats, anchor offsets are signed 64-bit.

var document: DrawingDocument
var layer_id: String = ""
var expected_revision: int = -1
var view_transform: Transform2D = Transform2D.IDENTITY
var anchor_x: int = 0
var anchor_y: int = 0
var _before: Dictionary[String, int] = {}
var _after: Dictionary[String, int] = {}
var _covered: Dictionary[String, bool] = {}
# An edit sees one immutable source revision; avoid re-resolving its tile for
# each covered pixel. Cache successful absent tiles (null), never failed loads.
var _source_tiles: Dictionary[String, Variant] = {}
## Detached preview indexed by storage tile + pixel offset; never stored on the document.
var _preview_tiles: Dictionary[String, Dictionary] = {}
## Only touched pixels need rollback. A full triple-dictionary duplicate per motion
## event grew quadratically over long strokes.
var _paint_journal: Dictionary[String, Array] = {}
var _journaling: bool = false
var _closed: bool = false
var _has_last: bool = false
var _last: Vector2 = Vector2.ZERO


func _init(target: DrawingDocument, layer: String, source_revision: int,
		transform: Transform2D, origin_x: int, origin_y: int) -> void:
	document = target
	layer_id = layer
	expected_revision = source_revision
	view_transform = transform
	anchor_x = origin_x
	anchor_y = origin_y


func change_count() -> int:
	return _after.size()


## Renderer reads only this session's detached patch; a closed/stale session is blank.
func preview_tile(tile_key: String) -> Dictionary:
	if _closed or document.revision != expected_revision:
		return {}
	return _preview_tiles.get(tile_key, {})


func _sync_preview_pixel(tile_key: String, local_index: int, pixel_key: String) -> void:
	var tile_patch: Dictionary = _preview_tiles.get(tile_key, {})
	if _after.has(pixel_key):
		tile_patch[local_index] = _after[pixel_key]
		_preview_tiles[tile_key] = tile_patch
	else:
		tile_patch.erase(local_index)
		if tile_patch.is_empty():
			_preview_tiles.erase(tile_key)


## Rare failure path for the other edit APIs which still use full snapshots.
## Their preview index must never outlive a rolled-back staging dictionary.
func _rebuild_preview_tiles() -> void:
	_preview_tiles.clear()
	for key: String in _after:
		var parts: PackedStringArray = key.split(",")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		var stride: int = document.tile_stride
		_sync_preview_pixel(DrawingDocument.TILES.tile_key64(x, y, stride),
			posmod(y, stride) * stride + posmod(x, stride), key)


func _rollback_paint() -> void:
	for key: String in _paint_journal:
		var snapshot: Array = _paint_journal[key]
		if snapshot[0]:
			_before[key] = snapshot[1]
		else:
			_before.erase(key)
		if snapshot[2]:
			_after[key] = snapshot[3]
		else:
			_after.erase(key)
		if not snapshot[4]:
			_covered.erase(key)
		_sync_preview_pixel(String(snapshot[5]), int(snapshot[6]), key)
	_paint_journal.clear()
	_journaling = false


func cancel() -> void:
	_before.clear()
	_after.clear()
	_covered.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_paint_journal.clear()
	_journaling = false
	_closed = true


func commit() -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	_closed = true
	var result: DrawingResult = document._publish_edit(layer_id, expected_revision, _before, _after)
	_before.clear()
	_after.clear()
	_covered.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_paint_journal.clear()
	return result


func _stage(x: int, y: int, rgba: int, selection: DrawingSelection = null,
		once: bool = false, blend: bool = false, verified_source: int = -1) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	if x <= -1073741824 or x >= 1073741824 or y <= -1073741824 or y >= 1073741824:
		return DrawingResult.failure("COORD_RANGE", "Gesture view-relative pixel exceeds safe bounds")
	if selection != null and not selection.allows(Vector2i(x, y)):
		return DrawingResult.success()
	var global_x: int = anchor_x + x
	var global_y: int = anchor_y + y
	var key: String = "%d,%d" % [global_x, global_y]
	if once and _covered.has(key):
		return DrawingResult.success()
	# Flood fill has already read this exact pixel through the verified source
	# snapshot. Re-resolving its tile here needlessly allocates a tile key and
	# repeats the pixel lookup. -1 means all other callers read it normally.
	var old: int = verified_source
	if old == -1:
		var stride: int = document.tile_stride
		var tile_key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride)
		if not _source_tiles.has(tile_key):
			var resolved: DrawingResult = document._resolve_chunk(layer_id, tile_key)
			if not resolved.ok:
				return resolved
			_source_tiles[tile_key] = resolved.value
		var tile: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		old = tile.get_rgba(posmod(global_x, stride), posmod(global_y, stride)) \
			if tile != null else 0
	var replacement: int = _blend(rgba, old) if blend else rgba
	var stride_local: int = document.tile_stride
	var preview_tile_key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride_local)
	var local_index: int = posmod(global_y, stride_local) * stride_local + posmod(global_x, stride_local)
	if _journaling and not _paint_journal.has(key):
		_paint_journal[key] = [_before.has(key), _before.get(key, 0),
			_after.has(key), _after.get(key, 0), _covered.has(key),
			preview_tile_key, local_index]
	if once:
		_covered[key] = true
	if not _before.has(key):
		_before[key] = old
	if replacement == _before[key]:
		_after.erase(key)
		_before.erase(key)
	else:
		_after[key] = replacement
	_sync_preview_pixel(preview_tile_key, local_index, key)
	return DrawingResult.success()


## Exact canonical bytes, optionally including nonzero RGB when alpha is zero.
## A region is always view-relative, and bounded before allocating/staging changes.
func apply_region(area: Rect2i, rgba8: PackedByteArray,
		selection: DrawingSelection = null, max_pixels: int = 1048576) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("REGION_LIMIT", "Region is empty or over pixel budget")
	if rgba8.size() != area.size.x * area.size.y * 4:
		return DrawingResult.failure("RGBA", "Region bytes must be tightly packed RGBA8")
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for row: int in range(area.size.y):
		for column: int in range(area.size.x):
			var position: int = (row * area.size.x + column) * 4
			var rgba: int = int(rgba8[position]) | (int(rgba8[position + 1]) << 8) | (int(rgba8[position + 2]) << 16) | (int(rgba8[position + 3]) << 24)
			var result: DrawingResult = _stage(area.position.x + column, area.position.y + row, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


func fill_rect(area: Rect2i, rgba: int, selection: DrawingSelection = null,
		max_pixels: int = 1048576) -> DrawingResult:
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("REGION_LIMIT", "Rectangle is empty or over pixel budget")
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var result: DrawingResult = _stage(x, y, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


func clear_rect(area: Rect2i, selection: DrawingSelection = null,
		max_pixels: int = 1048576) -> DrawingResult:
	return fill_rect(area, 0, selection, max_pixels)


## Swept hard brush; one alpha blend per covered pixel for the entire gesture.
## Pointer path is in view coordinates; transform freezes the raster-space mapping.
func paint_path(path: PackedVector2Array, rgba: int, width: float = 1.0,
		erase: bool = false, selection: DrawingSelection = null,
		max_candidates: int = 1048576) -> DrawingResult:
	if _closed or path.is_empty() or width <= 0.0 or not is_finite(width) or max_candidates <= 0:
		return DrawingResult.failure("BRUSH", "Invalid brush session, radius or pointer path")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "Invalid straight RGBA8 color")
	var inverse: Transform2D = view_transform.affine_inverse()
	_journaling = true
	_paint_journal.clear()
	var previous: Vector2 = _last
	for index: int in range(path.size()):
		var position: Vector2 = inverse * path[index]
		if not position.is_finite() or absf(position.x) > 1000000000.0 or absf(position.y) > 1000000000.0:
			_rollback_paint()
			return DrawingResult.failure("COORD_RANGE", "Brush point is outside the view-relative range")
		var start: Vector2 = previous if index > 0 or _has_last else position
		var touched: DrawingResult = _paint_segment(start, position, width * 0.5, rgba,
			erase, selection, max_candidates)
		if not touched.ok:
			_rollback_paint()
			return touched
		previous = position
	_has_last = true
	_last = previous
	_paint_journal.clear()
	_journaling = false
	return DrawingResult.success(_after.size())


func _paint_segment(start: Vector2, finish: Vector2, radius: float, rgba: int,
		erase: bool, selection: DrawingSelection, max_candidates: int,
		depth: int = 0) -> DrawingResult:
	var left: int = floori(minf(start.x, finish.x) - radius - 0.5)
	var top: int = floori(minf(start.y, finish.y) - radius - 0.5)
	var right: int = ceili(maxf(start.x, finish.x) + radius + 0.5)
	var bottom: int = ceili(maxf(start.y, finish.y) + radius + 0.5)
	var columns: int = right - left
	var rows: int = bottom - top
	if columns <= 0 or rows <= 0:
		return DrawingResult.success()
	if columns > max_candidates or rows > max_candidates / columns:
		if depth >= 32 or start == finish:
			return DrawingResult.failure("BRUSH_LIMIT", "Brush candidate window exceeds pixel limit")
		var middle: Vector2 = (start + finish) * 0.5
		var first: DrawingResult = _paint_segment(start, middle, radius, rgba, erase,
			selection, max_candidates, depth + 1)
		if not first.ok:
			return first
		return _paint_segment(middle, finish, radius, rgba, erase,
			selection, max_candidates, depth + 1)
	# A stationary dab has no segment projection. Axis-aligned segments can
	# compute squared distance without a Geometry2D call per candidate. Keep
	# the original native geometry oracle for all oblique sweeps.
	if start != finish and (start.x == finish.x or start.y == finish.y):
		return _paint_axis_segment(start, finish, left, top, right, bottom,
			radius * radius, rgba, erase, selection)
	var stationary: bool = start == finish
	var radius_squared: float = radius * radius
	for y: int in range(top, bottom):
		for x: int in range(left, right):
			var center: Vector2 = Vector2(x + 0.5, y + 0.5)
			var nearest: Vector2 = start if stationary else Geometry2D.get_closest_point_to_segment(center, start, finish)
			if center.distance_squared_to(nearest) > radius_squared:
				continue
			var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
				selection, true, not erase)
			if not result.ok:
				return result
	return DrawingResult.success()


func _paint_axis_segment(start: Vector2, finish: Vector2, left: int, top: int,
		right: int, bottom: int, radius_squared: float, rgba: int, erase: bool,
		selection: DrawingSelection) -> DrawingResult:
	if start.y == finish.y:
		var min_x: float = minf(start.x, finish.x)
		var max_x: float = maxf(start.x, finish.x)
		for y: int in range(top, bottom):
			var dy: float = (y + 0.5) - start.y
			var dy_squared: float = dy * dy
			if dy_squared > radius_squared:
				continue
			for x: int in range(left, right):
				var center_x: float = x + 0.5
				var dx: float = center_x - clampf(center_x, min_x, max_x)
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase)
				if not result.ok:
					return result
	else:
		var min_y: float = minf(start.y, finish.y)
		var max_y: float = maxf(start.y, finish.y)
		for y: int in range(top, bottom):
			var center_y: float = y + 0.5
			var dy: float = center_y - clampf(center_y, min_y, max_y)
			var dy_squared: float = dy * dy
			for x: int in range(left, right):
				var dx: float = (x + 0.5) - start.x
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase)
				if not result.ok:
					return result
	return DrawingResult.success()


func paint_polygon(polygon: PackedVector2Array, rgba: int,
		selection: DrawingSelection = null, max_pixels: int = 1048576) -> DrawingResult:
	if polygon.size() < 3:
		return DrawingResult.failure("SHAPE", "A filled polygon needs three vertices")
	var inverse: Transform2D = view_transform.affine_inverse()
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in polygon:
		var pixel_point: Vector2 = inverse * point
		if not pixel_point.is_finite() or absf(pixel_point.x) > 1000000000.0 or absf(pixel_point.y) > 1000000000.0:
			return DrawingResult.failure("COORD_RANGE", "Polygon point out of view-relative bounds")
		points.append(pixel_point)
	var min_x: float = points[0].x
	var min_y: float = points[0].y
	var max_x: float = points[0].x
	var max_y: float = points[0].y
	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var area: Rect2i = Rect2i(floori(min_x), floori(min_y),
		ceili(max_x) - floori(min_x), ceili(max_y) - floori(min_y))
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("SHAPE_LIMIT", "Polygon exceeds candidate budget")
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				continue
			var result: DrawingResult = _stage(x, y, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


## Read one canonical source pixel from the gesture's immutable tile snapshot.
## This also materializes verified lazy tiles: has_stored_pixel() only inspects
## resident tiles, so using it to gate fill would silently reject persisted
## artwork that has not yet been decoded. A zero RGBA8 pixel is still blank;
## nonzero hidden RGB (alpha=0) remains a legitimate stored fill source.
func _fill_source_pixel(point: Vector2i) -> DrawingResult:
	var global_x: int = anchor_x + point.x
	var global_y: int = anchor_y + point.y
	var stride: int = document.tile_stride
	var key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride)
	if not _source_tiles.has(key):
		var loaded: DrawingResult = document._resolve_chunk(layer_id, key)
		if not loaded.ok:
			return loaded
		_source_tiles[key] = loaded.value
	var tile: DrawingRasterTile = _source_tiles[key] as DrawingRasterTile
	if tile == null:
		return DrawingResult.success(0)
	return DrawingResult.success(tile.get_rgba(posmod(global_x, stride),
		posmod(global_y, stride)))


## Four-connected fill of existing pixels; never expands into implicit blank space.
func flood_fill(seed: Vector2i, rgba: int, selection: DrawingSelection = null,
		limit: int = 262144) -> DrawingResult:
	if limit <= 0 or _closed:
		return DrawingResult.failure("FILL_LIMIT", "Invalid flood fill budget/session")
	var original: DrawingResult = _fill_source_pixel(seed)
	if not original.ok:
		return original
	if int(original.value) == 0:
		return DrawingResult.failure("BLANK_SEED", "Fill begins in unallocated transparent space")
	if original.value == rgba:
		return DrawingResult.failure("NO_CHANGE", "Target color is already present")
	var frontier: Array[Vector2i] = [seed]
	# Mark a point when queued, rather than when popped. Dense regions would
	# otherwise enqueue the same interior and boundary coordinates repeatedly.
	# The limit still counts unique examined candidates, including boundaries.
	var queued: Dictionary[Vector2i, bool] = {seed: true}
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	var head: int = 0
	while head < frontier.size():
		if head >= limit:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return DrawingResult.failure("FILL_LIMIT", "Fill was cancelled at the pixel budget")
		var point: Vector2i = frontier[head]
		head += 1
		if selection != null and not selection.allows(point):
			continue
		var current: DrawingResult = _fill_source_pixel(point)
		if not current.ok:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return current
		if int(current.value) == 0 or current.value != original.value:
			continue
		var staged: DrawingResult = _stage(point.x, point.y, rgba, selection,
			false, false, int(current.value))
		if not staged.ok:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return staged
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + offset
			if not queued.has(next):
				queued[next] = true
				frontier.append(next)
	return DrawingResult.success(_after.size())


## Source-over in unpremultiplied 8-bit color. Unmodified destination bytes stay exact.
static func _blend(source: int, destination: int) -> int:
	var sa: float = float((source >> 24) & 255) / 255.0
	if sa <= 0.0:
		return destination
	var da: float = float((destination >> 24) & 255) / 255.0
	var out_alpha: float = sa + da * (1.0 - sa)
	var a: int = clampi(roundi(out_alpha * 255.0), 0, 255)
	var channels: Array[int] = []
	for channel: int in range(3):
		var shift: int = channel * 8
		var sc: float = float((source >> shift) & 255)
		var dc: float = float((destination >> shift) & 255)
		channels.append(clampi(roundi((sc * sa + dc * da * (1.0 - sa)) / out_alpha), 0, 255))
	return channels[0] | (channels[1] << 8) | (channels[2] << 16) | (a << 24)
