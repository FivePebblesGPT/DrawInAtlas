class_name AtlasPreviewPanel
extends VBoxContainer
## A read-only, selected-floor snapshot rendered by a private AtlasCanvas.

const PREVIEW_SIZE: Vector2i = Vector2i(192, 128)
const RENDERER_SCENE: PackedScene = preload("res://prefab/preview_renderer.tscn")

var cache: AtlasPreviewCache = AtlasPreviewCache.new()
@onready var texture_rect: TextureRect = $TextureRect
@onready var caption: Label = $Caption

var _viewport: SubViewport
var _canvas: AtlasCanvas
var _request_token: int = 0


func request_preview(campaign: AtlasCampaign, map_id: String, floor_id: String) -> void:
    _request_token += 1
    var token: int = _request_token
    _stop_rendering()
    texture_rect.texture = null
    var document: AtlasMapDocument = campaign.get_map(map_id) if campaign != null else null
    var floor: AtlasFloor = document.floor_by_id(floor_id) if document != null else null
    if floor == null:
        caption.text = "Preview unavailable"
        return
    var title: String = "%s — %s" % [document.display_name, floor.display_name]
    caption.text = title
    caption.tooltip_text = title
    # Dummy rendering never emits a usable capture; do not create a viewport or await it.
    var driver: String = RenderingServer.get_current_rendering_driver_name()
    if DisplayServer.get_name() == "headless" or driver.is_empty() or driver == "dummy":
        caption.text = title + " (preview unavailable in headless mode)"
        return
    var bounds: Rect2 = _artwork_bounds(document, floor)
    if bounds.size == Vector2.ZERO:
        _show_neutral_board()
        caption.text = title + " (empty)"
        return
    var cached: Image = cache.get_image(document, floor_id, PREVIEW_SIZE)
    if cached != null:
        texture_rect.texture = ImageTexture.create_from_image(cached)
        return
    if not is_inside_tree():
        caption.text = title + " (preview unavailable)"
        return
    _ensure_renderer()
    if not _canvas.set_document(document, campaign, floor_id):
        caption.text = "Preview unavailable"
        return
    _canvas.camera_center = bounds.get_center()
    var usable: Vector2 = Vector2(PREVIEW_SIZE) - Vector2(16, 16)
    _canvas.camera_zoom = minf(usable.x / maxf(bounds.size.x, 0.001),
        usable.y / maxf(bounds.size.y, 0.001))
    var expected: String = cache.signature(document, floor_id)
    _canvas.queue_redraw()
    # Warm up CanvasGroup drawers created during AtlasCanvas._draw, then capture
    # with another one-shot update. Neither pass leaves continuous rendering on.
    _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    for frame: int in range(2):
        await get_tree().process_frame
        if token != _request_token or not is_inside_tree():
            return
    _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    if token != _request_token or not is_inside_tree():
        return
    _stop_rendering()
    if campaign.get_map(map_id) != document or cache.signature(document, floor_id) != expected:
        caption.text = title + " (changed; request preview again)"
        return
    var image: Image = _viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != PREVIEW_SIZE:
        caption.text = title + " (preview unavailable)"
        return
    cache.put_image(document, floor_id, PREVIEW_SIZE, image)
    texture_rect.texture = ImageTexture.create_from_image(image)


func clear_preview() -> void:
    _request_token += 1
    _stop_rendering()
    texture_rect.texture = null
    caption.text = "Select a map to preview"
    caption.tooltip_text = ""
    if _canvas != null:
        # set_document rejects null; release only the renderer's references here.
        _canvas.cancel_edit()
        _canvas.map = null
        _canvas.floor = null
        _canvas.campaign = null


func _exit_tree() -> void:
    _request_token += 1
    _stop_rendering()


func _ensure_renderer() -> void:
    if _viewport != null:
        return

    _viewport = RENDERER_SCENE.instantiate() as SubViewport
    # A private world isolates this preview from the editor canvas.
    _viewport.world_2d = World2D.new()
    _canvas = _viewport.get_node("Canvas") as AtlasCanvas
    _canvas.render_grid = false
    _canvas.preview = AtlasCanvas.Preview.OFF
    _canvas.show_reference = false
    add_child(_viewport)

    # AtlasCanvas._ready restores interactive defaults, so disable input afterwards.
    _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _canvas.focus_mode = Control.FOCUS_NONE
    _canvas.set_process_input(false)
    _canvas.set_process_unhandled_input(false)
    _canvas.set_process_unhandled_key_input(false)


func _stop_rendering() -> void:
    if _viewport != null:
        _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _show_neutral_board() -> void:
    var image: Image = Image.create(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(AtlasCanvas.EMPTY_COLOR)
    texture_rect.texture = ImageTexture.create_from_image(image)


func _artwork_bounds(document: AtlasMapDocument, floor: AtlasFloor) -> Rect2:
    var bounds: Rect2 = Rect2()
    var found: bool = false
    for layer: AtlasLayer in floor.layers:
        if not layer.visible or layer.opacity <= 0.0:
            continue
        var pieces: Array[Rect2] = []
        if layer is AtlasInkLayer:
            for stroke: AtlasStroke in layer.strokes:
                if stroke.points.is_empty() or stroke.color.a <= 0.0:
                    continue
                pieces.append(_point_bounds(stroke.points).grow(stroke.width * 0.5))
        elif layer is AtlasTileLayer:
            var grid: AtlasGrid = layer.grid if layer.grid != null else document.get_terrain_grid(floor.id)
            if grid == null:
                continue
            for key: String in layer.terrain:
                if layer.terrain[key] == 0:
                    continue
                var xy: PackedStringArray = key.split(",")
                if xy.size() != 2:
                    continue
                var polygon: PackedVector2Array = grid.cell_polygon(Vector2i(int(xy[0]), int(xy[1])))
                if not polygon.is_empty():
                    pieces.append(_point_bounds(polygon))
        elif layer is AtlasRasterLayer:
            for chunk: AtlasRasterChunk in layer.chunks.values():
                if chunk.image == null or chunk.image.is_empty() or layer.pixels_per_unit <= 0.0:
                    continue
                var origin: Vector2 = Vector2(chunk.coord) * AtlasRasterChunk.SIZE / layer.pixels_per_unit
                var dimensions: Vector2 = Vector2(chunk.width, chunk.height) / layer.pixels_per_unit
                pieces.append(layer.transform * Rect2(origin, dimensions))
        for piece: Rect2 in pieces:
            bounds = bounds.merge(piece) if found else piece
            found = true
    return bounds


func _point_bounds(points: PackedVector2Array) -> Rect2:
    var bounds: Rect2 = Rect2(points[0], Vector2.ZERO)
    for point: Vector2 in points:
        bounds = bounds.expand(point)
    return bounds
