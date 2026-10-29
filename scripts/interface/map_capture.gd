class_name AtlasMapCapture
extends Node
## One cancellable, input-disabled artwork renderer shared by thumbnails and
## reference crops. It never renders references, grids, links or selection UI.

const RENDERER_SCENE: PackedScene = preload("res://prefab/preview_renderer.tscn")
var viewport: SubViewport
var canvas: AtlasCanvas
var captured_rect: Rect2 # Latest configured framing, including captures that fail.
var _generation: int = 0


func capture(campaign: AtlasCampaign, document: AtlasMapDocument, floor_id: String,
		bounds: Rect2, size: Vector2i) -> Image:
	cancel()
	var request_generation: int = _generation
	var driver: String = RenderingServer.get_current_rendering_driver_name()
	if DisplayServer.get_name() == "headless" or driver.is_empty() or driver == "dummy" or not is_inside_tree():
		return null
	if document == null or document.floor_by_id(floor_id) == null or not bounds.has_area() or size.x < 1 or size.y < 1:
		return null
	_ensure_renderer()
	if not _frame_document(campaign, document, floor_id, bounds, size):
		return null
	var expected_source_signature: String = AtlasPreviewCache.new().signature(document, floor_id)
	canvas.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame: int in range(2):
		await get_tree().process_frame
		if not _request_is_current(request_generation):
			return null
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not _request_is_current(request_generation):
		return null
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if campaign.get_map(document.id) != document or expected_source_signature != AtlasPreviewCache.new().signature(document, floor_id):
		return null
	var image: Image = viewport.get_texture().get_image()
	return image if image != null and image.get_size() == size else null


func cancel(clear_document: bool = false) -> void:
	_generation += 1
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if clear_document and canvas != null:
		canvas.cancel_edit()
		canvas.map = null
		canvas.floor = null
		canvas.campaign = null


func _ensure_renderer() -> void:
	if viewport != null:
		return
	viewport = RENDERER_SCENE.instantiate() as SubViewport
	viewport.world_2d = World2D.new()
	canvas = viewport.get_node("Canvas") as AtlasCanvas
	canvas.render_grid = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	add_child(viewport)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.focus_mode = Control.FOCUS_NONE
	canvas.set_process_input(false)
	canvas.set_process_unhandled_input(false)
	canvas.set_process_unhandled_key_input(false)


func _frame_document(campaign: AtlasCampaign, document: AtlasMapDocument, floor_id: String,
		bounds: Rect2, size: Vector2i) -> bool:
	viewport.size = size
	canvas.size = Vector2(size)
	if not canvas.set_document(document, campaign, floor_id):
		return false
	canvas.camera_center = bounds.get_center()
	canvas.camera_zoom = minf(size.x / bounds.size.x, size.y / bounds.size.y)
	captured_rect = Rect2(bounds.get_center() - Vector2(size) / canvas.camera_zoom * 0.5,
		Vector2(size) / canvas.camera_zoom)
	return true


func _request_is_current(request_generation: int) -> bool:
	return request_generation == _generation and is_inside_tree()


func _exit_tree() -> void:
	cancel()
