class_name AtlasCanvas
extends Control

signal paint_requested(cell: Vector2i)
signal selection_requested(cell: Vector2i)
signal battlemap_requested(start: Vector2, finish: Vector2, rotation_radians: float)
signal wheel_step(direction: int, local_position: Vector2)
signal enter_requested(link: AtlasMapLink)
signal pointer_moved(local_position: Vector2)
signal interaction_started
signal stroke_requested(stroke: AtlasStroke, erasing: bool)

enum Tool { PEN, ERASER, PAINT, SELECT, BATTLEMAP }
enum Preview { OFF, MARKERS, THUMBNAILS }

var campaign: AtlasCampaign
var map: AtlasMapDocument
var floor: AtlasFloor
var tool: Tool = Tool.PEN
var preview: Preview = Preview.THUMBNAILS

var camera_center: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var selected_cell: Vector2i = Vector2i.ZERO
var has_selected_cell: bool = false
var battle_rotation: float = 0.0
var reference_opacity: float = 0.35
var show_reference: bool = true
var show_grid: bool = true
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


func set_document(value: AtlasMapDocument, current_campaign: AtlasCampaign) -> void:
    cancel_edit()
    map = value
    campaign = current_campaign
    floor = map.floor_by_id(map.default_floor_id) if map != null else null
    has_selected_cell = false
    _drawing_battlemap = false
    queue_redraw()


func choose_tool(value: Tool) -> void:
    cancel_edit()
    tool = value


func is_editing() -> bool:
    return _draft_stroke != null


func cancel_edit() -> void:
    _draft_stroke = null
    _erase_preview.clear()
    _drawing_battlemap = false
    _panning = false
    queue_redraw()


func commit_edit() -> void:
    if _draft_stroke == null:
        return
    var stroke: AtlasStroke = _draft_stroke.copy()
    var erasing: bool = _erasing
    _draft_stroke = null
    _erase_preview.clear()
    stroke_requested.emit(stroke, erasing)
    queue_redraw()


func _on_resized() -> void:
    cancel_edit()
    queue_redraw()


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
    _draw_cells(false)
    var artwork: Array[AtlasStroke] = _erase_preview if is_editing() and _erasing else floor.strokes
    for stroke: AtlasStroke in artwork:
        _draw_stroke(stroke)
    if is_editing() and not _erasing:
        _draw_stroke(_draft_stroke)
    if show_grid:
        _draw_cells(true)
    _draw_links()
    if has_selected_cell and map.grid.kind != AtlasGrid.Kind.GRIDLESS:
        var outline := map.grid.cell_polygon(selected_cell)
        _stroke_polygon(outline, Color("#f9cc65"), 2.5 / camera_zoom)
    if _drawing_battlemap:
        _draw_draft()
    draw_set_transform(Vector2.ZERO)


func _draw_parent_reference() -> void:
    if not show_reference or campaign == null:
        return
    for placement in campaign.placements:
        if placement.child_map_id != map.id or placement.symbolic:
            continue
        var parent := campaign.get_map(placement.parent_map_id)
        if parent == null:
            continue
        var parent_floor := parent.floor_by_id(parent.default_floor_id)
        if parent_floor == null:
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
            var polygon := parent.grid.cell_polygon(cell)
            var transformed := PackedVector2Array()
            for point in polygon:
                transformed.append(placement.parent_point_to_child(point))
            var color := _terrain_color(parent_floor.get_terrain(cell))
            color.a = reference_opacity
            if transformed.size() >= 3:
                for clipped in Geometry2D.intersect_polygons(transformed, clipping):
                    if clipped.size() >= 3:
                        draw_colored_polygon(clipped, color)


func _draw_cells(grid_only: bool) -> void:
    var grid := map.grid
    if grid.kind == AtlasGrid.Kind.GRIDLESS:
        return
    # Bounded drawing around the camera; renderer will become chunk/viewport-driven later.
    var cell_center := grid.document_to_cell(camera_center)
    var cell_radius := mini(65, ceili(maxf(size.x, size.y) / camera_zoom / grid.cell_size) + 4)
    for x in range(cell_center.x - cell_radius, cell_center.x + cell_radius + 1):
        for y in range(cell_center.y - cell_radius, cell_center.y + cell_radius + 1):
            var cell := Vector2i(x, y)
            var polygon := grid.cell_polygon(cell)
            var color := _terrain_color(floor.get_terrain(cell))
            if not grid_only and floor.get_terrain(cell) != 0:
                draw_colored_polygon(polygon, color)
            if grid_only:
                _stroke_polygon(polygon, Color(0.77, 0.84, 0.78, 0.20), 0.8 / camera_zoom)


func _draw_stroke(stroke: AtlasStroke) -> void:
    if stroke.points.size() > 1:
        draw_polyline(stroke.points, stroke.color, stroke.width, true)
    for point: Vector2 in stroke.points:
        draw_circle(point, stroke.width * 0.5, stroke.color)


func _append_stroke_point(local_position: Vector2) -> void:
    if not Rect2(Vector2.ZERO, size).has_point(local_position):
        _stroke_left_canvas = true
    if _draft_stroke == null or _stroke_left_canvas:
        return
    var point: Vector2 = local_to_document(local_position)
    if _draft_stroke.points[-1].distance_squared_to(point) >= 0.01:
        _draft_stroke.points.append(point)
    if _erasing:
        _erase_preview = AtlasStrokeEraser.erase(floor.strokes, _draft_stroke.points, _draft_stroke.width)
    queue_redraw()


func _draw_links() -> void:
    if campaign == null or preview == Preview.OFF:
        return
    for link in campaign.outgoing_links(map.id):
        var target := campaign.get_map(link.target_map_id)
        if target == null:
            continue
        if not link.placement_id.is_empty():
            var placement := campaign.placement_by_id(link.placement_id)
            if placement == null:
                continue
            var corners := placement.corners()
            var fill := Color(0.24, 0.70, 0.82, 0.15)
            draw_colored_polygon(corners, fill)
            _stroke_polygon(corners, Color("#63d3e5"), 2.0 / camera_zoom)
            if preview == Preview.THUMBNAILS and not placement.symbolic:
                _draw_placement_preview(placement, target)
            draw_string(ThemeDB.fallback_font, placement.origin, target.display_name,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
        else:
            draw_circle(link.anchor, 18.0 / camera_zoom, Color("#efd797"))
            draw_arc(link.anchor, 18.0 / camera_zoom, 0.0, TAU, 24,
                Color("#395760"), 2.0 / camera_zoom)
            draw_string(ThemeDB.fallback_font, link.anchor + Vector2(20.0 / camera_zoom, 0.0),
                target.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw_placement_preview(placement: AtlasPlacement, target: AtlasMapDocument) -> void:
    var child_floor := target.floor_by_id(target.default_floor_id)
    if child_floor == null:
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
        color.a = 0.7
        draw_colored_polygon(square, color)


func _draw_draft() -> void:
    var footprint := _draft_polygon()
    draw_colored_polygon(footprint, Color(0.26, 0.76, 0.87, 0.16))
    _stroke_polygon(footprint, Color("#87e1f2"), 2.0 / camera_zoom)


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


func _stroke_polygon(polygon: PackedVector2Array, color: Color, width: float) -> void:
    if polygon.size() < 2:
        return
    var outline := polygon.duplicate()
    outline.append(polygon[0])
    draw_polyline(outline, color, width, true)


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
                    var links := campaign.find_links_at(map.id, position)
                    if links.size() == 1:
                        enter_requested.emit(links[0])
                        accept_event()
                        return
                match tool:
                    Tool.PEN, Tool.ERASER:
                        _erasing = tool == Tool.ERASER
                        _stroke_left_canvas = false
                        _draft_stroke = AtlasStroke.new(PackedVector2Array([position]), brush_color, brush_width)
                        _append_stroke_point(mouse.position)
                    Tool.PAINT:
                        paint_requested.emit(map.grid.document_to_cell(position))
                    Tool.SELECT:
                        selection_requested.emit(map.grid.document_to_cell(position))
                    Tool.BATTLEMAP:
                        _drawing_battlemap = true
                        _draft_start = position
                        _draft_end = position
                        queue_redraw()
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
        elif is_editing():
            _append_stroke_point(motion.position)
            accept_event()
        elif _drawing_battlemap:
            _draft_end = local_to_document(motion.position)
            queue_redraw()
            accept_event()
        elif tool == Tool.PAINT and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
            paint_requested.emit(map.grid.document_to_cell(local_to_document(motion.position)))
            accept_event()
