class_name DrawingSnap
extends RefCounted
## Generic grid/guide/object snapping with deterministic proximity preference.


static func point(position: Vector2, spacing: Vector2 = Vector2.ZERO,
		origin: Vector2 = Vector2.ZERO, guide_x: PackedFloat32Array = PackedFloat32Array(),
		guide_y: PackedFloat32Array = PackedFloat32Array(),
		candidates: PackedVector2Array = PackedVector2Array(),
		tolerance: float = 8.0) -> Vector2:
	if not position.is_finite() or not origin.is_finite() or not is_finite(tolerance) or tolerance < 0.0:
		return position
	var snapped: Vector2 = position
	var best_x: float = tolerance + 0.000001
	var best_y: float = tolerance + 0.000001
	if spacing.x > 0.0 and is_finite(spacing.x):
		var gx: float = origin.x + roundf((position.x - origin.x) / spacing.x) * spacing.x
		if absf(gx - position.x) <= tolerance:
			best_x = absf(gx - position.x)
			snapped.x = gx
	if spacing.y > 0.0 and is_finite(spacing.y):
		var gy: float = origin.y + roundf((position.y - origin.y) / spacing.y) * spacing.y
		if absf(gy - position.y) <= tolerance:
			best_y = absf(gy - position.y)
			snapped.y = gy
	for x: float in guide_x:
		if is_finite(x) and absf(position.x - x) < best_x:
			best_x = absf(position.x - x)
			snapped.x = x
	for y: float in guide_y:
		if is_finite(y) and absf(position.y - y) < best_y:
			best_y = absf(position.y - y)
			snapped.y = y
	for candidate: Vector2 in candidates:
		if not candidate.is_finite():
			continue
		if absf(position.x - candidate.x) < best_x:
			best_x = absf(position.x - candidate.x)
			snapped.x = candidate.x
		if absf(position.y - candidate.y) < best_y:
			best_y = absf(position.y - candidate.y)
			snapped.y = candidate.y
	return snapped


static func displacement(start: Vector2, finish: Vector2, spacing: Vector2,
		origin: Vector2 = Vector2.ZERO, tolerance: float = 8.0) -> Vector2:
	if not start.is_finite() or not finish.is_finite():
		return finish - start
	return point(finish, spacing, origin, PackedFloat32Array(), PackedFloat32Array(),
		PackedVector2Array(), tolerance) - point(start, spacing, origin,
		PackedFloat32Array(), PackedFloat32Array(), PackedVector2Array(), tolerance)
