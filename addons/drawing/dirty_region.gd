class_name DrawingDirtyRegion
extends RefCounted
## Signed 64-bit pixel bounds; not limited by Vector2i's storage width.

var layer_id: String = ""
var x: int = 0
var y: int = 0
var width: int = 0
var height: int = 0


func _init(layer: String = "", left: int = 0, top: int = 0,
		columns: int = 0, rows: int = 0) -> void:
	layer_id = layer
	x = left
	y = top
	width = columns
	height = rows
