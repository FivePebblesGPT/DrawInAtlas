class_name AtlasPreviewPanel
extends VBoxContainer
## A read-only, selected-floor snapshot rendered by a private AtlasCanvas.

const PREVIEW_SIZE: Vector2i = Vector2i(192, 128)

var cache: AtlasPreviewCache = AtlasPreviewCache.new()
@onready var texture_rect: TextureRect = $TextureRect
@onready var caption: Label = $Caption

var _capture: AtlasMapCapture
var capture_renderer: AtlasMapCapture:
	get: return _capture
var _request_token: int = 0


func request_preview(campaign: AtlasCampaign, map_id: String, floor_id: String, detail_level: int = 0) -> void:
	_request_token += 1
	var token: int = _request_token
	_stop_rendering()
	texture_rect.texture = null
	var document: AtlasMapDocument = campaign.get_map(map_id) if campaign != null else null
	var floor: AtlasFloor = document.floor_by_id(floor_id) if document != null else null
	if floor == null:
		caption.text = "Preview unavailable"
		return
	if detail_level < 0 or detail_level > AtlasLayer.MAX_DETAIL_LEVEL:
		caption.text = "Preview unavailable"
		return
	var title: String = "%s — %s" % [document.display_name, floor.display_name]
	if detail_level != 0:
		title += " · D%d" % detail_level
	caption.text = title
	caption.tooltip_text = title
	# Dummy rendering never emits a usable capture; do not create a viewport or await it.
	var driver: String = RenderingServer.get_current_rendering_driver_name()
	if DisplayServer.get_name() == "headless" or driver.is_empty() or driver == "dummy":
		caption.text = title + " (preview unavailable in headless mode)"
		return
	var bounds: Rect2 = artwork_bounds(document, floor, detail_level)
	var audience: String = "editor-detail:%d" % detail_level
	if not bounds.has_area():
		_show_neutral_board()
		caption.text = title + " (empty)"
		return
	var cached: Image = cache.get_image(document, floor_id, PREVIEW_SIZE, audience)
	if cached != null:
		texture_rect.texture = ImageTexture.create_from_image(cached)
		return
	if not is_inside_tree():
		caption.text = title + " (preview unavailable)"
		return
	var usable: Vector2 = Vector2(PREVIEW_SIZE) - Vector2(16, 16)
	var zoom: float = minf(usable.x / maxf(bounds.size.x, 0.001), usable.y / maxf(bounds.size.y, 0.001))
	var crop: Rect2 = Rect2(bounds.get_center() - Vector2(PREVIEW_SIZE) / zoom * 0.5, Vector2(PREVIEW_SIZE) / zoom)
	if _capture == null:
		_capture = AtlasMapCapture.new()
		add_child(_capture)
	var expected: String = cache.signature(document, floor_id)
	var image: Image = await _capture.capture(campaign, document, floor_id, crop, PREVIEW_SIZE, false, detail_level)
	if token != _request_token or not is_inside_tree():
		return
	_stop_rendering()
	if campaign.get_map(map_id) != document or cache.signature(document, floor_id) != expected:
		caption.text = title + " (changed; request preview again)"
		return
	if image == null or image.is_empty() or image.get_size() != PREVIEW_SIZE:
		caption.text = title + " (preview unavailable)"
		return
	cache.put_image(document, floor_id, PREVIEW_SIZE, image, audience)
	texture_rect.texture = ImageTexture.create_from_image(image)


func clear_preview() -> void:
	_request_token += 1
	_stop_rendering()
	texture_rect.texture = null
	caption.text = "Select a map to preview"
	caption.tooltip_text = ""
	if _capture != null:
		_capture.cancel(true)


func _exit_tree() -> void:
	_request_token += 1
	_stop_rendering()


func _stop_rendering() -> void:
	if _capture != null:
		_capture.cancel()


func _show_neutral_board() -> void:
	var image: Image = Image.create(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(AtlasCanvas.EMPTY_COLOR)
	texture_rect.texture = ImageTexture.create_from_image(image)


static func artwork_bounds(document: AtlasMapDocument, floor: AtlasFloor, detail_level: int = 0) -> Rect2:
	var bounds: Rect2 = Rect2()
	var found: bool = false
	for layer: AtlasLayer in floor.layers:
		if not layer.visible or layer.opacity <= 0.0 or layer.detail_level != detail_level:
			continue
		var pieces: Array[Rect2] = []
		if layer is AtlasInkLayer:
			for stroke: AtlasStroke in layer.strokes:
				if stroke.points.is_empty() or stroke.color.a <= 0.0:
					continue
				pieces.append(AtlasSelectionGeometry.stroke_bounds(stroke))
		elif layer is AtlasRasterLayer:
			for chunk: AtlasRasterChunk in layer.chunks.values():
				if chunk.image == null or chunk.image.is_empty() or layer.pixels_per_unit <= 0.0:
					continue
				# Sparse raster chunks often contain large transparent margins. Fit
				# only painted pixels, even across signed seams and transforms.
				var used: Rect2i = chunk.image.get_used_rect()
				if not used.has_area():
					continue
				var origin: Vector2 = (Vector2(chunk.coord) * AtlasRasterChunk.SIZE + Vector2(used.position)) / layer.pixels_per_unit
				var dimensions: Vector2 = Vector2(used.size) / layer.pixels_per_unit
				pieces.append(layer.transform * Rect2(origin, dimensions))
		for piece: Rect2 in pieces:
			bounds = bounds.merge(piece) if found else piece
			found = true
	return bounds


static func _point_bounds(points: PackedVector2Array) -> Rect2:
	var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds
