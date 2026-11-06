extends Node2D
## Derived screen-space coverage for complex semantic/legacy objects.
## Source color and opacity are applied once by the caller drawing the texture.

class Batch extends Node2D:
	var points: PackedVector2Array = PackedVector2Array()
	var width: float
	var scope: AtlasEditScope

	func _draw() -> void:
		if scope == null or points.is_empty():
			return
		var stroke: AtlasStroke = AtlasStroke.new(points, Color.WHITE, width)
		for part: AtlasStroke in scope.clip_strokes([stroke]):
			if part.points.size() > 1:
				draw_polyline(part.points, Color.WHITE, width, true)
			for point: Vector2 in part.points:
				draw_circle(point, width * 0.5, Color.WHITE, true, -1.0, true)

var _consumed: int = 0
var _viewport: SubViewport
var _batch: Batch
var document_rect: Rect2


func configure(dimensions: Vector2, zoom: float, camera: Vector2) -> void:
	document_rect = Rect2(camera - dimensions * 0.5 / zoom, dimensions / zoom)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(dimensions.ceil())
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_viewport.canvas_transform = Transform2D(0, Vector2.ONE * zoom, 0, dimensions * 0.5 - camera * zoom)
	_batch = Batch.new()
	_viewport.add_child(_batch)


func update_stroke(stroke: AtlasStroke, scope: AtlasEditScope) -> void:
	if _consumed >= stroke.points.size():
		return
	_batch.width = stroke.width
	_batch.scope = scope
	_batch.points = stroke.points.slice(maxi(0, _consumed - 1))
	_consumed = stroke.points.size()
	_batch.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func texture() -> Texture2D:
	return _viewport.get_texture()
