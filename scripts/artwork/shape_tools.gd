class_name AtlasShapes
extends RefCounted


static func stroke(kind: String, start: Vector2, finish: Vector2, color: Color, width: float) -> AtlasStroke:
	if not start.is_finite() or not finish.is_finite():
		return null
	var points: PackedVector2Array = PackedVector2Array()
	var bounds: Rect2 = Rect2(start, finish - start).abs()
	match kind:
		"LINE":
			points.append(start)
			if start != finish:
				points.append(finish)
		"RECTANGLE":
			if bounds.size.x < 0.0001 or bounds.size.y < 0.0001:
				return null
			points = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
				bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.position])
		"ELLIPSE":
			if bounds.size.x < 0.0001 or bounds.size.y < 0.0001:
				return null
			for index: int in range(65):
				var angle: float = float(index) * TAU / 64.0
				points.append(bounds.get_center() + Vector2(cos(angle), sin(angle)) * bounds.size * 0.5)
		_:
			return null
	var result: AtlasStroke = AtlasStroke.new(points, color, width)
	return result if result.is_valid() else null
