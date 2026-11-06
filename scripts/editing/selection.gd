class_name AtlasSelection
extends RefCounted
## Transient viewer selection, guarded against stale layer contents.

var layer_id: String = ""
var stroke_indices: Array[int] = []
var raster_selected: bool = false
var bounds: Rect2
var source: Dictionary = {}


func is_empty() -> bool:
	return stroke_indices.is_empty() and not raster_selected


func matches(layer: AtlasLayer) -> bool:
	return layer != null and layer.id == layer_id and layer.to_dict() == source
