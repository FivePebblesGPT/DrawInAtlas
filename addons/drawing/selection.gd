class_name DrawingSelection
extends RefCounted
## Drawing-owned, view-relative selection channel. Rectangles are producers,
## not the channel itself: ordered boolean operations preserve holes/islands
## without allocating one byte (or dictionary entry) per selected pixel.

const MAX_OPERATIONS: int = 128
var enabled: bool = false
## Conservative enclosing area. Use allows() for the actual per-pixel mask.
var bounds: Rect2i = Rect2i()
var inverted: bool = false
var _base_bounds: Rect2i = Rect2i()
var _pixel_mask: Dictionary[Vector2i, bool] = {}
var _operations: Array[Dictionary] = []


func _init(rect: Rect2i = Rect2i(), active: bool = false) -> void:
	clear()
	# Atlas uses an *enabled empty mask* to deny every pixel. It is not a
	# deselection; changing this silently paints outside a board-cell boundary.
	if active:
		enabled = true
		bounds = rect
		_base_bounds = rect


func clear() -> void:
	enabled = false
	bounds = Rect2i()
	_base_bounds = Rect2i()
	_pixel_mask.clear()
	_operations.clear()
	inverted = false


func set_rectangle(rect: Rect2i) -> void:
	clear()
	if rect.has_area():
		enabled = true
		bounds = rect
		_base_bounds = rect


func set_mask(mask: Dictionary[Vector2i, bool]) -> void:
	_pixel_mask = mask.duplicate()


func detached_copy() -> DrawingSelection:
	var copy: DrawingSelection = DrawingSelection.new()
	copy.enabled = enabled
	copy.bounds = bounds
	copy.inverted = inverted
	copy._base_bounds = _base_bounds
	copy._pixel_mask = _pixel_mask.duplicate()
	copy._operations = _operations.duplicate(true)
	return copy


func same_as(other: DrawingSelection) -> bool:
	return other != null and enabled == other.enabled and bounds == other.bounds \
		and inverted == other.inverted and _base_bounds == other._base_bounds \
		and _pixel_mask == other._pixel_mask and _operations == other._operations


## Replace, Add, Subtract and Intersect. Rejected oversized expression trees
## leave the prior selection untouched. An empty subtract/intersect has no effect.
func combine_rectangle(rect: Rect2i, mode: String = "Replace") -> bool:
	if mode not in ["Replace", "Add", "Subtract", "Intersect"]:
		return false
	if mode == "Replace":
		set_rectangle(rect)
		return true
	if not rect.has_area():
		return true
	if not enabled:
		if mode == "Add":
			set_rectangle(rect)
		return true
	if _operations.size() >= MAX_OPERATIONS:
		return false
	_operations.append({"rect": rect, "mode": mode})
	if mode == "Add":
		bounds = bounds.merge(rect)
	elif mode == "Intersect":
		bounds = bounds.intersection(rect)
		if not bounds.has_area():
			# Preserve active-empty (deny-all) rather than unrestricted paint.
			_base_bounds = Rect2i()
			_pixel_mask.clear()
			_operations.clear()
	return true


func allows(point: Vector2i) -> bool:
	if not enabled:
		return true
	if not bounds.has_point(point):
		return inverted
	var contained: bool = _base_bounds.has_point(point)
	if not _pixel_mask.is_empty():
		contained = contained and _pixel_mask.get(point, false)
	for operation: Dictionary in _operations:
		var inside: bool = (operation["rect"] as Rect2i).has_point(point)
		match String(operation["mode"]):
			"Add": contained = contained or inside
			"Subtract": contained = contained and not inside
			"Intersect": contained = contained and inside
	return not contained if inverted else contained


func translated(offset: Vector2i) -> DrawingSelection:
	var copy: DrawingSelection = detached_copy()
	copy.bounds.position += offset
	copy._base_bounds.position += offset
	var shifted: Dictionary[Vector2i, bool] = {}
	for position: Vector2i in copy._pixel_mask:
		shifted[position + offset] = copy._pixel_mask[position]
	copy._pixel_mask = shifted
	for operation: Dictionary in copy._operations:
		var moved: Rect2i = operation["rect"] as Rect2i
		moved.position += offset
		operation["rect"] = moved
	return copy


## A row is represented by sorted, disjoint half-open [x0, x1) spans.
## Rectangle expressions are evaluated per *visible row*, not per source pixel.
## Inversion changes which side is selected but never the boundary itself.
static func _add_span(spans: Array[Vector2i], start: int, end: int) -> Array[Vector2i]:
	if start >= end:
		return spans
	var merged: Array[Vector2i] = []
	var inserted: bool = false
	for span: Vector2i in spans:
		if span.y < start:
			merged.append(span)
		elif end < span.x:
			if not inserted:
				merged.append(Vector2i(start, end))
				inserted = true
			merged.append(span)
		else:
			start = mini(start, span.x)
			end = maxi(end, span.y)
	if not inserted:
		merged.append(Vector2i(start, end))
	return merged


static func _subtract_span(spans: Array[Vector2i], start: int, end: int) -> Array[Vector2i]:
	var remaining: Array[Vector2i] = []
	for span: Vector2i in spans:
		if span.y <= start or span.x >= end:
			remaining.append(span)
		else:
			if span.x < start:
				remaining.append(Vector2i(span.x, start))
			if span.y > end:
				remaining.append(Vector2i(end, span.y))
	return remaining


static func _intersect_span(spans: Array[Vector2i], start: int, end: int) -> Array[Vector2i]:
	var intersection: Array[Vector2i] = []
	for span: Vector2i in spans:
		var left: int = maxi(span.x, start)
		var right: int = mini(span.y, end)
		if left < right:
			intersection.append(Vector2i(left, right))
	return intersection


## Read-only contour input. The optional explicit pixel mask is evaluated only
## inside this row's caller-supplied window; the canvas budgets those probes.
func contour_row_spans(y: int, left: int, right: int) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	if not enabled or left >= right:
		return spans
	if y >= _base_bounds.position.y and y < _base_bounds.end.y:
		var start: int = maxi(left, _base_bounds.position.x)
		var end: int = mini(right, _base_bounds.end.x)
		if start < end:
			if _pixel_mask.is_empty():
				spans.append(Vector2i(start, end))
			else:
				var run_start: int = start
				var in_run: bool = false
				for x: int in range(start, end):
					if _pixel_mask.get(Vector2i(x, y), false):
						if not in_run:
							run_start = x
							in_run = true
					elif in_run:
						spans.append(Vector2i(run_start, x))
						in_run = false
				if in_run:
					spans.append(Vector2i(run_start, end))
	for operation: Dictionary in _operations:
		var rect: Rect2i = operation["rect"] as Rect2i
		if y < rect.position.y or y >= rect.end.y:
			if operation["mode"] == "Intersect":
				spans.clear()
			continue
		var start: int = maxi(left, rect.position.x)
		var end: int = mini(right, rect.end.x)
		match String(operation["mode"]):
			"Add": spans = _add_span(spans, start, end)
			"Subtract": spans = _subtract_span(spans, start, end)
			"Intersect": spans = _intersect_span(spans, start, end)
	return spans


static func _horizontal_difference(first: Array[Vector2i], second: Array[Vector2i],
		y: int, edges: PackedVector2Array) -> void:
	for span: Vector2i in first:
		var remaining: Array[Vector2i] = [span]
		for opposite: Vector2i in second:
			remaining = _subtract_span(remaining, opposite.x, opposite.y)
		for piece: Vector2i in remaining:
			edges.append(Vector2(piece.x, y))
			edges.append(Vector2(piece.y, y))


## Exact outlines in source coordinates, clipped to viewport WITHOUT emitting
## false edges along the clip rectangle. The caller limits the visible window.
## A plain 20,000 x 20,000 rectangle costs O(visible rows), not 400M probes.
func contour_segments(visible: Rect2i) -> PackedVector2Array:
	var edges: PackedVector2Array = PackedVector2Array()
	if not enabled or not bounds.has_area() or not visible.has_area():
		return edges
	var area: Rect2i = bounds.intersection(visible.grow(1))
	if not area.has_area():
		return edges
	var left: int = area.position.x
	var right: int = area.end.x
	var previous: Array[Vector2i] = contour_row_spans(area.position.y - 1, left, right)
	for y: int in range(area.position.y, area.end.y + 1):
		var current: Array[Vector2i] = contour_row_spans(y, left, right)
		_horizontal_difference(previous, current, y, edges)
		_horizontal_difference(current, previous, y, edges)
		if y < area.end.y:
			for span: Vector2i in current:
				edges.append(Vector2(span.x, y))
				edges.append(Vector2(span.x, y + 1))
				edges.append(Vector2(span.y, y))
				edges.append(Vector2(span.y, y + 1))
		previous = current
	# Each tile/viewport samples neighbors outside the clip, but the returned
	# line segments must not leak into neighboring tiles or a clipped view.
	var clipped: PackedVector2Array = PackedVector2Array()
	for index: int in range(0, edges.size(), 2):
		var start: Vector2 = edges[index]
		var finish: Vector2 = edges[index + 1]
		if start.x == finish.x:
			if start.x < visible.position.x or start.x > visible.end.x:
				continue
			var y0: float = maxf(minf(start.y, finish.y), visible.position.y)
			var y1: float = minf(maxf(start.y, finish.y), visible.end.y)
			if y0 < y1:
				clipped.append(Vector2(start.x, y0))
				clipped.append(Vector2(start.x, y1))
		else:
			if start.y < visible.position.y or start.y > visible.end.y:
				continue
			var x0: float = maxf(minf(start.x, finish.x), visible.position.x)
			var x1: float = minf(maxf(start.x, finish.x), visible.end.x)
			if x0 < x1:
				clipped.append(Vector2(x0, start.y))
				clipped.append(Vector2(x1, start.y))
	return clipped
