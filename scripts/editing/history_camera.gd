class_name AtlasHistoryCamera
extends RefCounted
## Pure viewport policy for history playback: never modify zoom.


static func pan_if_hidden(center: Vector2, zoom: float, viewport_size: Vector2,
		affected: Rect2) -> Vector2:
	if not center.is_finite() or not is_finite(zoom) or zoom <= 0.0 \
			or viewport_size.x <= 0.0 or viewport_size.y <= 0.0 \
			or affected.size.x < 0.0 or affected.size.y < 0.0:
		return center
	var visible: Rect2 = Rect2(center - viewport_size / (2.0 * zoom),
		viewport_size / zoom)
	# Godot's intersects excludes mere edge contact; edge contact has no visible area.
	if affected.intersects(visible, true):
		return center
	return affected.get_center()
