class_name AtlasSelection
extends RefCounted
## Transient viewer selection, guarded against stale layer contents.

## Stable active-layer ID; stroke_indices below are *positions in its current*
## object array, not permanent object IDs. Never persist selection to a campaign.
var layer_id: String = ""
var stroke_indices: Array[int] = []
## Raster selection currently means whole-layer selection, not pixel islands.
var raster_selected: bool = false
## Derived board-space union for interaction handles, not authorable geometry.
var bounds: Rect2
## Deep detached layer dictionary at selection time: matches() invalidates the
## selection if contents have changed, preventing stale-index edits.
var source: Dictionary = {}


func is_empty() -> bool:
	return stroke_indices.is_empty() and not raster_selected


func matches(layer: AtlasLayer) -> bool:
	return layer != null and layer.id == layer_id and layer.to_dict() == source
