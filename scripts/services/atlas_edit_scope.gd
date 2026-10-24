class_name AtlasEditScope
extends RefCounted
## Document-space convex selection boundary. An enabled empty scope denies edits.

var enabled: bool = false
var polygon: PackedVector2Array = PackedVector2Array()


func _init(boundary: PackedVector2Array = PackedVector2Array(), active: bool = false) -> void:
    polygon = boundary.duplicate()
    enabled = active


func allows_polygon(candidate: PackedVector2Array) -> bool:
    if not enabled:
        return true
    if not _valid_boundary() or candidate.size() < 3:
        return false
    # Both the boundary and the cell/pixel quad are convex: vertices suffice.
    for point: Vector2 in candidate:
        if not point.is_finite() or not Geometry2D.is_point_in_polygon(point, polygon):
            return false
    return true


func contains_rect(rect: Rect2) -> bool:
    if not enabled:
        return true
    if not rect.position.is_finite() or not rect.size.is_finite():
        return false
    return allows_polygon(PackedVector2Array([
        rect.position, Vector2(rect.end.x, rect.position.y),
        rect.end, Vector2(rect.position.x, rect.end.y)
    ]))


func clip_strokes(strokes: Array[AtlasStroke]) -> Array[AtlasStroke]:
    if not enabled:
        return AtlasStroke.clone_all(strokes)
    var result: Array[AtlasStroke] = []
    if not _valid_boundary():
        return result
    for stroke: AtlasStroke in strokes:
        if stroke == null or not stroke.is_valid():
            continue
        var centerline: PackedVector2Array = PackedVector2Array()
        for point: Vector2 in stroke.points:
            if centerline.is_empty() or point != centerline[-1]:
                centerline.append(point)
        var insets: Array[PackedVector2Array] = Geometry2D.offset_polygon(
            polygon, -stroke.width * 0.5, Geometry2D.JOIN_MITER)
        for inset: PackedVector2Array in insets:
            if centerline.size() == 1:
                if Geometry2D.is_point_in_polygon(centerline[0], inset):
                    result.append(AtlasStroke.new(centerline, stroke.color, stroke.width))
                continue
            var parts: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(
                centerline, inset)
            for part: PackedVector2Array in parts:
                if not part.is_empty():
                    result.append(AtlasStroke.new(part, stroke.color, stroke.width))
    return result


func erase(strokes: Array[AtlasStroke], path: PackedVector2Array, width: float) -> Array[AtlasStroke]:
    if not enabled:
        return AtlasStrokeEraser.erase(strokes, path, width)
    var result: Array[AtlasStroke] = []
    for stroke: AtlasStroke in strokes:
        if stroke == null:
            continue
        if not stroke.is_valid() or not _valid_boundary():
            result.append(stroke.copy())
            continue
        var bounds: Rect2 = Rect2(stroke.points[0], Vector2.ZERO)
        for point: Vector2 in stroke.points:
            bounds = bounds.expand(point)
        if contains_rect(bounds.grow(stroke.width * 0.5)):
            var eligible: Array[AtlasStroke] = [stroke]
            result.append_array(AtlasStrokeEraser.erase(eligible, path, width))
        else:
            # A crossing stroke stays intact, even where its centerline is inside.
            result.append(stroke.copy())
    return result


func _valid_boundary() -> bool:
    if polygon.size() < 3:
        return false
    var orientation: float = 0.0
    for index: int in range(polygon.size()):
        var a: Vector2 = polygon[index]
        var b: Vector2 = polygon[(index + 1) % polygon.size()]
        if not a.is_finite() or not b.is_finite() or a == b:
            return false
        for point: Vector2 in polygon:
            var cross: float = (b - a).cross(point - a)
            if not is_finite(cross):
                return false
            if cross == 0.0:
                continue
            if orientation == 0.0:
                orientation = signf(cross)
            elif cross * orientation < 0.0:
                return false
    return orientation != 0.0
