class_name AtlasCanvas
extends Control

## Document-space renderer and gesture input, not the campaign's source of
## truth. The static editor shell lives in .tscn; per-layer draw nodes are
## runtime-created because their count/order depends on the open document.

signal paint_requested(cell: Vector2i)
signal selection_requested(cell: Vector2i)
signal battlemap_requested(start: Vector2, finish: Vector2, rotation_radians: float)
signal wheel_step(direction: int, local_position: Vector2)
signal enter_requested(link: AtlasMapLink)
signal pointer_moved(local_position: Vector2)
signal interaction_started
signal stroke_requested(stroke: AtlasStroke, erasing: bool)
signal selection_changed
signal transform_requested(selection: AtlasSelection, transform: Transform2D)
signal fill_requested(position: Vector2)
signal view_region_changed

enum Tool { PEN, ERASER, PAINT, SELECT, BATTLEMAP, LINE, RECTANGLE, ELLIPSE, ART_SELECT, FILL }
enum Preview { OFF, MARKERS, THUMBNAILS }
enum Manipulation { NONE, MARQUEE, MOVE, RESIZE }

var campaign: AtlasCampaign
var map: AtlasMapDocument
var floor: AtlasFloor
var active_layer_id: String = "ink"
var selection: AtlasSelection = AtlasSelection.new()
var edit_scope: AtlasEditScope = AtlasEditScope.new()
var tool: Tool = Tool.PEN
var preview: Preview = Preview.THUMBNAILS

var camera_center: Vector2 = Vector2.ZERO:
    set(value):
        if camera_center == value:
            return
        camera_center = value
        view_region_changed.emit()
var camera_zoom: float = 1.0:
    set(value):
        if camera_zoom == value:
            return
        camera_zoom = value
        view_region_changed.emit()
var selected_cell: Vector2i = Vector2i.ZERO
var has_selected_cell: bool = false
var battle_rotation: float = 0.0
var reference_opacity: float = 0.35
var show_reference: bool = true
var render_grid: bool = true
var show_grid: bool:
    get:
        return map != null and map.grid.visible
    set(value):
        if map != null:
            map.grid.visible = value
        queue_redraw()
var brush_color: Color = Color("#f5b545")
var brush_width: float = 8.0

var _panning: bool = false
var _drawing_battlemap: bool = false
var _draft_start: Vector2 = Vector2.ZERO
var _draft_end: Vector2 = Vector2.ZERO
var _wheel_fraction: float = 0.0
var _wheel_direction: int = 0
var _draft_stroke: AtlasStroke
var _erasing: bool = false
var _stroke_left_canvas: bool = false
var _erase_preview: Array[AtlasStroke] = []
var _layer_groups: Dictionary[String, CanvasGroup] = {}
var _layer_drawers: Dictionary[String, Node2D] = {}
var _raster_textures: Dictionary[String, ImageTexture] = {}
var _overlay: Node2D
var _manipulation: Manipulation = Manipulation.NONE
var _gesture_start: Vector2
var _gesture_end: Vector2
var _shape_kind: String = ""
var _preview_layer: AtlasLayer
var _gesture_transform: Transform2D = Transform2D.IDENTITY
var _add_selection: bool = false

const EMPTY_COLOR := Color("#212c34")
const TERRAIN_COLORS := [
    Color("#36434b"), Color("#68846b"), Color("#94a47c"), Color("#ac8f68"),
    Color("#62798d"), Color("#bac3a0")
]


func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    resized.connect(_on_resized)
    get_window().focus_exited.connect(cancel_edit)
    _overlay = Node2D.new()
    _overlay.z_index = 1
    _overlay.draw.connect(_draw_overlays.bind(_overlay))
    add_child(_overlay)


func set_document(value: AtlasMapDocument, current_campaign: AtlasCampaign, floor_id: String = "") -> bool:
    if value == null:
        return false
    var selected_id: String = value.default_floor_id if floor_id.is_empty() else floor_id
    var selected_floor: AtlasFloor = value.floor_by_id(selected_id)
    if selected_floor == null:
        return false
    cancel_edit()
    map = value
    campaign = current_campaign
    floor = selected_floor
    _raster_textures.clear()
    clear_selection()
    has_selected_cell = false
    _drawing_battlemap = false
    queue_redraw()
    return true


func choose_tool(value: Tool) -> void:
    cancel_edit()
    tool = value


func is_editing() -> bool:
    return _draft_stroke != null or _manipulation != Manipulation.NONE or not _shape_kind.is_empty()


func cancel_edit() -> void:
    _draft_stroke = null
    _erase_preview.clear()
    _drawing_battlemap = false
    _panning = false
    _manipulation = Manipulation.NONE
    _shape_kind = ""
    _preview_layer = null
    _raster_textures.clear()
    queue_redraw()


func commit_edit() -> void:
    if _manipulation != Manipulation.NONE:
        _finish_manipulation()
        return
    if _draft_stroke == null:
        _shape_kind = ""
        _preview_layer = null
        queue_redraw()
        return
    var stroke: AtlasStroke = _draft_stroke.copy()
    var erasing: bool = _erasing
    _draft_stroke = null
    _erase_preview.clear()
    _shape_kind = ""
    _preview_layer = null
    _raster_textures.clear()
    stroke_requested.emit(stroke, erasing)
    queue_redraw()


func clear_selection() -> void:
    selection = AtlasSelection.new()
    selection_changed.emit()
    queue_redraw()


func select_all_artwork() -> void:
    cancel_edit()
    selection = AtlasSelectionGeometry.select_all(floor.layer_by_id(active_layer_id))
    selection_changed.emit()
    queue_redraw()


func _update_manipulation(position: Vector2) -> void:
    _gesture_end = position
    var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
    if _manipulation == Manipulation.MOVE:
        _gesture_transform = Transform2D(0.0, position - _gesture_start)
    elif _manipulation == Manipulation.RESIZE:
        var pivot: Vector2 = selection.bounds.position
        var initial: Vector2 = _gesture_start - pivot
        var scale: float = clampf((position - pivot).dot(initial) / maxf(initial.length_squared(), 0.0001), 0.05, 100.0)
        _gesture_transform = AtlasSelectionGeometry.about(pivot, Vector2.ZERO, scale)
    if _manipulation in [Manipulation.MOVE, Manipulation.RESIZE]:
        _preview_layer = AtlasSelectionGeometry.transformed(layer, selection, _gesture_transform, edit_scope)
    queue_redraw()


func _finish_manipulation() -> void:
    var mode: Manipulation = _manipulation
    _manipulation = Manipulation.NONE
    _preview_layer = null
    if mode == Manipulation.MARQUEE:
        var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
        var next: AtlasSelection
        if _gesture_start.distance_to(_gesture_end) < 3.0 / camera_zoom:
            next = AtlasSelectionGeometry.select_point(layer, _gesture_end, 5.0 / camera_zoom)
        else:
            next = AtlasSelectionGeometry.select_rect(layer, Rect2(_gesture_start, _gesture_end - _gesture_start).abs())
        if _add_selection and layer is AtlasInkLayer and selection.matches(layer):
            var indices: Array[int] = selection.stroke_indices.duplicate()
            for index: int in next.stroke_indices:
                if not indices.has(index):
                    indices.append(index)
            next = AtlasSelectionGeometry.select_indices(layer, indices)
        selection = next
        selection_changed.emit()
    else:
        transform_requested.emit(selection, _gesture_transform)
    queue_redraw()


func _on_resized() -> void:
    cancel_edit()
    queue_redraw()
    view_region_changed.emit()


## Screen pixels are converted to stable document units via the editor camera.
## Brush widths, link hit radii and terrain coordinates all use document units.
func local_to_document(local_position: Vector2) -> Vector2:
    return camera_center + (local_position - size * 0.5) / camera_zoom


func document_to_local(position: Vector2) -> Vector2:
    return (position - camera_center) * camera_zoom + size * 0.5


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), EMPTY_COLOR)
    if map == null or floor == null:
        return

    draw_set_transform(size * 0.5 - camera_center * camera_zoom, 0.0, Vector2.ONE * camera_zoom)
    _draw_parent_reference()
    draw_set_transform(Vector2.ZERO)
    _sync_layer_renderers()


## One CanvasGroup per current layer isolates opacity/visibility. Reconcile by
## stable layer ID so ordering/undo reuses drawers and deleted layers are freed.
## This dynamic tree should NOT be duplicated as dozens of static scene nodes.
func _sync_layer_renderers() -> void:
    var present: Dictionary[String, bool] = {}
    for index: int in range(floor.layers.size()):
        var layer: AtlasLayer = floor.layers[index]
        present[layer.id] = true
        if not _layer_groups.has(layer.id):
            var group: CanvasGroup = CanvasGroup.new()
            var drawer: Node2D = Node2D.new()
            drawer.draw.connect(_draw_content_layer.bind(drawer, layer.id))
            group.add_child(drawer)
            add_child(group)
            _layer_groups[layer.id] = group
            _layer_drawers[layer.id] = drawer
        var group: CanvasGroup = _layer_groups[layer.id]
        move_child(group, index)
        group.position = size * 0.5 - camera_center * camera_zoom
        group.scale = Vector2.ONE * camera_zoom
        group.self_modulate = Color(1, 1, 1, layer.opacity)
        group.visible = layer.visible and layer.opacity > 0.0
        _layer_drawers[layer.id].queue_redraw()
    for id: String in _layer_groups.keys():
        if not present.has(id):
            _layer_groups[id].hide()
            _layer_groups[id].queue_free()
            _layer_groups.erase(id)
            _layer_drawers.erase(id)
    _overlay.position = size * 0.5 - camera_center * camera_zoom
    _overlay.scale = Vector2.ONE * camera_zoom
    _overlay.queue_redraw()


func _draw_content_layer(item: Node2D, id: String) -> void:
    if floor == null:
        return
    var layer: AtlasLayer = floor.layer_by_id(id)
    if id == active_layer_id and _preview_layer != null:
        layer = _preview_layer
    if layer is AtlasTileLayer:
        var grid: AtlasGrid = layer.grid if layer.grid != null else map.get_terrain_grid(floor.id)
        for key: String in layer.terrain:
            var xy: PackedStringArray = key.split(",")
            var cell: Vector2i = Vector2i(int(xy[0]), int(xy[1]))
            if layer.terrain[key] != 0:
                item.draw_colored_polygon(grid.cell_polygon(cell), _terrain_color(layer.terrain[key]))
    elif layer is AtlasInkLayer:
        var previewing: bool = _draft_stroke != null and active_layer_id == id
        var artwork: Array[AtlasStroke] = _erase_preview if previewing and _erasing else layer.strokes
        for stroke: AtlasStroke in artwork:
            _draw_stroke(stroke, item)
        if previewing and not _erasing:
            for stroke: AtlasStroke in edit_scope.clip_strokes([_draft_stroke]):
                _draw_stroke(stroke, item)
    elif layer is AtlasRasterLayer:
        item.draw_set_transform_matrix(layer.transform)
        for chunk: AtlasRasterChunk in layer.chunks.values():
            if chunk.image == null:
                continue
            var asset: String = chunk.asset_id
            if not _raster_textures.has(asset):
                _raster_textures[asset] = ImageTexture.create_from_image(chunk.image)
            var origin: Vector2 = Vector2(chunk.coord) * AtlasRasterChunk.SIZE / layer.pixels_per_unit
            var dimensions: Vector2 = Vector2(chunk.width, chunk.height) / layer.pixels_per_unit
            item.draw_texture_rect(_raster_textures[asset], Rect2(origin, dimensions), false)


func _draw_overlays(item: Node2D) -> void:
    if map == null or floor == null:
        return
    if render_grid and show_grid:
        _draw_grid(item)
    _draw_links(item)
    if has_selected_cell and map.grid.kind != AtlasGrid.Kind.GRIDLESS:
        var outline := map.grid.cell_polygon(selected_cell)
        _stroke_polygon(outline, Color("#f9cc65"), 2.5 / camera_zoom, item)
    if _drawing_battlemap:
        _draw_draft(item)
    if _manipulation == Manipulation.MARQUEE:
        item.draw_rect(Rect2(_gesture_start, _gesture_end - _gesture_start).abs(), Color(0.3, 0.7, 1.0, 0.15))
        item.draw_rect(Rect2(_gesture_start, _gesture_end - _gesture_start).abs(), Color("#4dabf2"), false, 1.0 / camera_zoom)
    if not selection.is_empty() and selection.matches(floor.layer_by_id(active_layer_id)):
        var bounds: Rect2 = selection.bounds
        var color: Color = Color("#4dabf2")
        if _manipulation in [Manipulation.MOVE, Manipulation.RESIZE]:
            if _preview_layer != null:
                bounds = AtlasSelectionGeometry.select_indices(_preview_layer, selection.stroke_indices).bounds
            else:
                color = Color("#f48771")
        item.draw_rect(bounds, color, false, 1.5 / camera_zoom)
        item.draw_rect(Rect2(bounds.end - Vector2.ONE * 4.0 / camera_zoom, Vector2.ONE * 8.0 / camera_zoom), color)


func _draw_parent_reference() -> void:
    if not show_reference or campaign == null:
        return
    for placement in campaign.placements:
        if placement.child_map_id != map.id or placement.symbolic:
            continue
        var parent := campaign.get_map(placement.parent_map_id)
        if parent == null:
            continue
        var references: Array[AtlasMapLink] = []
        for link: AtlasMapLink in campaign.links:
            if (link.placement_id == placement.id and link.source_map_id == parent.id
                    and link.target_map_id == map.id and link.target_floor_id == floor.id):
                references.append(link)
        if references.size() != 1:
            continue
        var parent_floor: AtlasFloor = parent.floor_by_id(references[0].source_floor_id)
        if parent_floor == null:
            continue
        var terrain: AtlasTileLayer = parent_floor.terrain_layer()
        if terrain == null or not terrain.visible or terrain.opacity <= 0.0:
            continue
        var clipping := PackedVector2Array([
            Vector2.ZERO,
            Vector2(placement.columns * placement.child_units_per_cell, 0.0),
            Vector2(placement.columns, placement.rows) * placement.child_units_per_cell,
            Vector2(0.0, placement.rows * placement.child_units_per_cell)
        ])
        for key: String in parent_floor.terrain.keys():
            var xy := key.split(",")
            if xy.size() != 2:
                continue
            var cell := Vector2i(int(xy[0]), int(xy[1]))
            var polygon: PackedVector2Array = parent.get_terrain_grid(parent_floor.id).cell_polygon(cell)
            var transformed := PackedVector2Array()
            for point in polygon:
                transformed.append(placement.parent_point_to_child(point))
            var color := _terrain_color(parent_floor.get_terrain(cell))
            color.a = reference_opacity * terrain.opacity
            if transformed.size() >= 3:
                for clipped in Geometry2D.intersect_polygons(transformed, clipping):
                    if clipped.size() >= 3:
                        draw_colored_polygon(clipped, color)


func _draw_grid(item: Node2D) -> void:
    var grid: AtlasGrid = map.grid
    if grid.kind == AtlasGrid.Kind.GRIDLESS:
        return
    # Dense grids are hidden rather than drawing an incomplete central patch or stalling the UI.
    if grid.cell_size * camera_zoom < 8.0:
        return
    var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]
    var minimum: Vector2i = grid.document_to_cell(local_to_document(corners[0]))
    var maximum: Vector2i = minimum
    for corner: Vector2 in corners:
        var cell: Vector2i = grid.document_to_cell(local_to_document(corner))
        minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
        maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
    minimum -= Vector2i(2, 2)
    maximum += Vector2i(2, 2)
    if (maximum.x - minimum.x + 1) * (maximum.y - minimum.y + 1) > 15000:
        return
    for x: int in range(minimum.x, maximum.x + 1):
        for y: int in range(minimum.y, maximum.y + 1):
            var cell := Vector2i(x, y)
            var polygon := grid.cell_polygon(cell)
            _stroke_polygon(polygon, Color(0.77, 0.84, 0.78, 0.20), 0.8 / camera_zoom, item)


func _draw_stroke(stroke: AtlasStroke, item: Node2D) -> void:
    if stroke.points.size() > 1:
        item.draw_polyline(stroke.points, stroke.color, stroke.width, true)
    for point: Vector2 in stroke.points:
        item.draw_circle(point, stroke.width * 0.5, stroke.color)


func _append_stroke_point(local_position: Vector2) -> void:
    if not Rect2(Vector2.ZERO, size).has_point(local_position):
        _stroke_left_canvas = true
    if (_draft_stroke == null and _shape_kind.is_empty()) or _stroke_left_canvas:
        return
    var point: Vector2 = local_to_document(local_position)
    if not _shape_kind.is_empty():
        _draft_stroke = AtlasShapes.stroke(_shape_kind, _gesture_start, point, brush_color, brush_width)
        queue_redraw()
        return
    if _draft_stroke.points[-1].distance_squared_to(point) >= 0.01:
        _draft_stroke.points.append(point)
    var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
    if layer is AtlasInkLayer and _erasing:
        _erase_preview = edit_scope.erase(layer.strokes, _draft_stroke.points, _draft_stroke.width)
    elif layer is AtlasRasterLayer:
        var result: AtlasFillResult = AtlasRasterBrush.paint(layer, _draft_stroke.points, _draft_stroke.color,
            _draft_stroke.width, _erasing, edit_scope)
        _preview_layer = result.layer if result.ok else null
    queue_redraw()


func _draw_links(item: Node2D) -> void:
    if campaign == null or preview == Preview.OFF:
        return
    for link in campaign.outgoing_links(map.id, floor.id):
        var target := campaign.get_map(link.target_map_id)
        if target == null:
            continue
        if not link.placement_id.is_empty():
            var placement := campaign.placement_by_id(link.placement_id)
            if placement == null:
                continue
            var corners := placement.corners()
            var fill := Color(0.24, 0.70, 0.82, 0.15)
            item.draw_colored_polygon(corners, fill)
            _stroke_polygon(corners, Color("#63d3e5"), 2.0 / camera_zoom, item)
            if preview == Preview.THUMBNAILS and not placement.symbolic:
                _draw_placement_preview(placement, target, item, link.target_floor_id)
            item.draw_string(ThemeDB.fallback_font, placement.origin, target.display_name,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
        else:
            item.draw_circle(link.anchor, 18.0 / camera_zoom, Color("#efd797"))
            item.draw_arc(link.anchor, 18.0 / camera_zoom, 0.0, TAU, 24,
                Color("#395760"), 2.0 / camera_zoom)
            item.draw_string(ThemeDB.fallback_font, link.anchor + Vector2(20.0 / camera_zoom, 0.0),
                target.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw_placement_preview(placement: AtlasPlacement, target: AtlasMapDocument, item: Node2D, floor_id: String = "") -> void:
    var selected_id: String = target.default_floor_id if floor_id.is_empty() else floor_id
    var child_floor: AtlasFloor = target.floor_by_id(selected_id)
    if child_floor == null:
        return
    var terrain: AtlasTileLayer = child_floor.terrain_layer()
    if terrain == null or not terrain.visible or terrain.opacity <= 0.0:
        return
    for key: String in child_floor.terrain.keys():
        var xy := key.split(",")
        if xy.size() != 2:
            continue
        var cell := Vector2i(int(xy[0]), int(xy[1]))
        var u := Vector2(cell)
        if u.x < 0 or u.y < 0 or u.x >= placement.columns or u.y >= placement.rows:
            continue
        var transform := placement.local_to_parent()
        var square := PackedVector2Array([
            transform * u, transform * (u + Vector2.RIGHT),
            transform * (u + Vector2.ONE), transform * (u + Vector2.DOWN)
        ])
        var color := _terrain_color(child_floor.get_terrain(cell))
        color.a = 0.7 * terrain.opacity
        item.draw_colored_polygon(square, color)


func _draw_draft(item: Node2D) -> void:
    var footprint := _draft_polygon()
    item.draw_colored_polygon(footprint, Color(0.26, 0.76, 0.87, 0.16))
    _stroke_polygon(footprint, Color("#87e1f2"), 2.0 / camera_zoom, item)


func _draft_polygon() -> PackedVector2Array:
    var rotated := (_draft_end - _draft_start).rotated(-battle_rotation)
    var minimum := Vector2(minf(rotated.x, 0.0), minf(rotated.y, 0.0))
    var maximum := Vector2(maxf(rotated.x, 0.0), maxf(rotated.y, 0.0))
    return PackedVector2Array([
        _draft_start + minimum.rotated(battle_rotation),
        _draft_start + Vector2(maximum.x, minimum.y).rotated(battle_rotation),
        _draft_start + maximum.rotated(battle_rotation),
        _draft_start + Vector2(minimum.x, maximum.y).rotated(battle_rotation)
    ])


func _stroke_polygon(polygon: PackedVector2Array, color: Color, width: float, item: Node2D) -> void:
    if polygon.size() < 2:
        return
    var outline := polygon.duplicate()
    outline.append(polygon[0])
    item.draw_polyline(outline, color, width, true)


func _terrain_color(palette: int) -> Color:
    if palette < 0 or palette >= TERRAIN_COLORS.size():
        return TERRAIN_COLORS[0]
    return TERRAIN_COLORS[palette]


func _gui_input(event: InputEvent) -> void:
    if map == null:
        return
    if event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            if is_editing():
                accept_event()
                return
            if mouse.pressed:
                var delta := mouse.factor if mouse.factor > 0.0 else 1.0
                var wheel_direction := 1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1
                if _wheel_direction != wheel_direction:
                    _wheel_fraction = 0.0
                    _wheel_direction = wheel_direction
                _wheel_fraction += minf(delta, 1.0)
                if _wheel_fraction >= 1.0:
                    _wheel_fraction = 0.0
                    # Never carry a burst's overscroll into later wheel events.
                    wheel_step.emit(wheel_direction, mouse.position)
            accept_event()
            return
        if mouse.button_index == MOUSE_BUTTON_MIDDLE or mouse.button_index == MOUSE_BUTTON_RIGHT:
            if mouse.pressed:
                cancel_edit()
                interaction_started.emit()
            _panning = mouse.pressed
            accept_event()
            return
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            if mouse.pressed:
                interaction_started.emit()
                grab_focus()
                var position := local_to_document(mouse.position)
                if mouse.double_click and campaign != null and tool == Tool.SELECT:
                    var links := campaign.find_links_at(map.id, position, floor.id)
                    if links.size() == 1:
                        enter_requested.emit(links[0])
                        accept_event()
                        return
                match tool:
                    Tool.PEN, Tool.ERASER:
                        var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
                        if not (layer is AtlasInkLayer or layer is AtlasRasterLayer) or not layer.is_editable():
                            accept_event()
                            return
                        _erasing = tool == Tool.ERASER
                        _stroke_left_canvas = false
                        _draft_stroke = AtlasStroke.new(PackedVector2Array([position]), brush_color, brush_width)
                        _append_stroke_point(mouse.position)
                    Tool.LINE, Tool.RECTANGLE, Tool.ELLIPSE:
                        var layer: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
                        if layer != null and layer.is_editable():
                            _shape_kind = Tool.keys()[tool]
                            _gesture_start = position
                            _stroke_left_canvas = false
                            _draft_stroke = AtlasShapes.stroke("LINE", position, position, brush_color, brush_width)
                    Tool.ART_SELECT:
                        var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
                        _gesture_start = position
                        _gesture_end = position
                        _gesture_transform = Transform2D.IDENTITY
                        _add_selection = mouse.shift_pressed
                        if not mouse.shift_pressed and selection.matches(layer) and not selection.is_empty() and layer.is_editable():
                            if position.distance_to(selection.bounds.end) <= 8.0 / camera_zoom:
                                _manipulation = Manipulation.RESIZE
                            elif selection.bounds.has_point(position):
                                _manipulation = Manipulation.MOVE
                        if _manipulation == Manipulation.NONE:
                            _manipulation = Manipulation.MARQUEE
                    Tool.FILL:
                        fill_requested.emit(position)
                    Tool.PAINT:
                        _request_cell_paint(position)
                    Tool.SELECT:
                        selection_requested.emit(map.grid.document_to_cell(position))
                    Tool.BATTLEMAP:
                        _drawing_battlemap = true
                        _draft_start = position
                        _draft_end = position
                        queue_redraw()
            elif _manipulation != Manipulation.NONE:
                _update_manipulation(local_to_document(mouse.position))
                _finish_manipulation()
            elif is_editing():
                _append_stroke_point(mouse.position)
                commit_edit()
            elif _drawing_battlemap:
                _draft_end = local_to_document(mouse.position)
                _drawing_battlemap = false
                battlemap_requested.emit(_draft_start, _draft_end, battle_rotation)
                queue_redraw()
            accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        pointer_moved.emit(motion.position)
        if _panning:
            camera_center -= motion.relative / camera_zoom
            queue_redraw()
            accept_event()
        elif _manipulation != Manipulation.NONE:
            _update_manipulation(local_to_document(motion.position))
            accept_event()
        elif is_editing():
            _append_stroke_point(motion.position)
            accept_event()
        elif _drawing_battlemap:
            _draft_end = local_to_document(motion.position)
            queue_redraw()
            accept_event()
        elif tool == Tool.PAINT and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
            _request_cell_paint(local_to_document(motion.position))
            accept_event()


func _request_cell_paint(position: Vector2) -> void:
    var layer: AtlasTileLayer = floor.layer_by_id(active_layer_id) as AtlasTileLayer
    if layer == null:
        return
    var grid: AtlasGrid = layer.grid if layer.grid != null else map.get_terrain_grid(floor.id)
    if grid.kind != AtlasGrid.Kind.GRIDLESS:
        paint_requested.emit(grid.document_to_cell(position))
