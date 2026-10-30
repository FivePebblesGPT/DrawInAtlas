class_name AtlasShapes
extends RefCounted


## For a straight line, Shift rounds its angle to 15-degree increments and Alt
## makes the press position its center. The caller snaps raw pointer positions
## first when grid snapping is enabled; angular restriction then takes priority
## over exact grid alignment of the endpoint.
static func line_endpoints(anchor: Vector2, pointer: Vector2, constrain_angle: bool, centered: bool) -> PackedVector2Array:
	if not anchor.is_finite() or not pointer.is_finite():
		return PackedVector2Array()
	if not constrain_angle and not centered:
		# Preserve snapped/editor coordinates bit-for-bit; subtraction and
		# re-addition can change the last ULP of a grid-aligned endpoint.
		return PackedVector2Array([anchor, pointer])
	var displacement: Vector2 = pointer - anchor
	if constrain_angle and displacement.length_squared() > 0.000001:
		var increment: float = PI / 12.0
		var angle: float = roundf(displacement.angle() / increment) * increment
		displacement = Vector2.from_angle(angle) * displacement.length()
	var first: Vector2 = anchor - displacement if centered else anchor
	return PackedVector2Array([first, anchor + displacement])


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
