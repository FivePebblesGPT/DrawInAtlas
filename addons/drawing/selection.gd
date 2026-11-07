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
