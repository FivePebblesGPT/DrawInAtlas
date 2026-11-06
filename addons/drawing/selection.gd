class_name DrawingSelection
extends RefCounted
## Generic pixel selection, independent of board grids, maps and campaigns.

var enabled: bool = false
var bounds: Rect2i = Rect2i()
var inverted: bool = false
var _pixel_mask: Dictionary[Vector2i, bool] = {}


func _init(rect: Rect2i = Rect2i(), active: bool = false) -> void:
	bounds = rect
	enabled = active


func set_mask(mask: Dictionary[Vector2i, bool]) -> void:
	_pixel_mask = mask.duplicate()


func allows(point: Vector2i) -> bool:
	if not enabled:
		return true
	var contained: bool = bounds.has_point(point)
	if not _pixel_mask.is_empty():
		contained = contained and _pixel_mask.get(point, false)
	return not contained if inverted else contained
