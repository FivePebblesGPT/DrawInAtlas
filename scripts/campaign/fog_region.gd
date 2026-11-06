class_name AtlasFogRegion
extends Resource
## Ordered board-space visibility operation. Newer regions override older ones.
## This is floor-wide state shared across every authored detail level.

@export_storage var bounds: Rect2 = Rect2(0, 0, 1, 1)
@export_storage var reveal: bool = true

const MAX_COORDINATE: float = 10000000.0


func _init(area: Rect2 = Rect2(0, 0, 1, 1), visible: bool = true) -> void:
	bounds = area
	reveal = visible


func is_valid() -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() \
		and bounds.size.x > 0.0 and bounds.size.y > 0.0 \
		and bounds.end.is_finite() \
		and absf(bounds.position.x) <= MAX_COORDINATE \
		and absf(bounds.position.y) <= MAX_COORDINATE \
		and absf(bounds.end.x) <= MAX_COORDINATE \
		and absf(bounds.end.y) <= MAX_COORDINATE


func copy() -> AtlasFogRegion:
	return AtlasFogRegion.new(bounds, reveal)


func to_dict() -> Dictionary:
	return {"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"reveal": reveal}


static func from_dict(data: Dictionary) -> AtlasFogRegion:
	var raw: Variant = data.get("bounds")
	var visible: Variant = data.get("reveal")
	if not raw is Array or raw.size() != 4 or not visible is bool:
		return null
	for component: Variant in raw:
		if not AtlasData.number(component):
			return null
	var region: AtlasFogRegion = AtlasFogRegion.new(Rect2(
		float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3])), visible)
	return region if region.is_valid() else null
