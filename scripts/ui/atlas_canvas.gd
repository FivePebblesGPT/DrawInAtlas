class_name AtlasCanvas
extends Control

signal paint_requested(cell: Vector2i)
signal selection_requested(cell: Vector2i)
signal battlemap_requested(start: Vector2, finish: Vector2, rotation_radians: float)
signal wheel_step(direction: int, local_position: Vector2)
signal enter_requested(link: AtlasMapLink)

enum Tool { PAINT, SELECT, BATTLEMAP }
enum Preview { OFF, MARKERS, THUMBNAILS }

var campaign: AtlasCampaign
var map: AtlasMapDocument
var floor: AtlasFloor
var tool: Tool = Tool.PAINT
var preview: Preview = Preview.THUMBNAILS

var camera_center: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var selected_cell: Vector2i = Vector2i.ZERO
var has_selected_cell: bool = false
var battle_rotation: float = 0.0
var reference_opacity: float = 0.35
var show_reference: bool = true

var _panning: bool = false
var _drawing_battlemap: bool = false
var _draft_start: Vector2 = Vector2.ZERO
var _draft_end: Vector2 = Vector2.ZERO
var _wheel_fraction: float = 0.0

const EMPTY_COLOR := Color("#212c34")
const TERRAIN_COLORS := [
    Color("#36434b"), Color("#68846b"), Color("#94a47c"), Color("#ac8f68"),
    Color("#62798d"), Color("#bac3a0")
]


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    resized.connect(queue_redraw)


func set_document(value: AtlasMapDocument, current_campaign: AtlasCampaign) -> void:
    map = value
    campaign = current_campaign
    floor = map.floor_by_id(map.default_floor_id) if map != null else null
    has_selected_cell = false
    _drawing_battlemap = false
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
    _draw_terrain_and_grid()
    _draw_links()
    if has_selected_cell and map.grid.kind != AtlasGrid.Kind.GRIDLESS:
        var outline := map.grid.cell_polygon(selected_cell)
        _stroke_polygon(outline, Color("#f9cc65"), 2.5 / camera_zoom)
    if _drawing_battlemap:
        _draw_draft()
    draw_set_transform()


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
                draw_colored_polygon(transformed, color)


func _draw_terrain_and_grid() -> void:
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
            if floor.get_terrain(cell) != 0:
                draw_colored_polygon(polygon, color)
            _stroke_polygon(polygon, Color(0.77, 0.84, 0.78, 0.20), 0.8 / camera_zoom)


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
            if preview == Preview.THUMBNAILS:
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
            if mouse.pressed:
                var delta := mouse.factor if mouse.factor > 0.0 else 1.0
                _wheel_fraction += delta
                if _wheel_fraction >= 1.0:
                    _wheel_fraction -= 1.0
                    # At most one boundary step per event; avoid one touchpad burst skipping maps.
                    wheel_step.emit(1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mouse.position)
            accept_event()
            return
        if mouse.button_index == MOUSE_BUTTON_MIDDLE or mouse.button_index == MOUSE_BUTTON_RIGHT:
            _panning = mouse.pressed
            accept_event()
            return
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            if mouse.pressed:
                grab_focus()
                var position := local_to_document(mouse.position)
                if mouse.double_click and campaign != null:
                    var links := campaign.find_links_at(map.id, position)
                    if links.size() == 1:
                        enter_requested.emit(links[0])
                        accept_event()
                        return
                match tool:
                    Tool.PAINT:
                        paint_requested.emit(map.grid.document_to_cell(position))
                    Tool.SELECT:
                        selection_requested.emit(map.grid.document_to_cell(position))
                    Tool.BATTLEMAP:
                        _drawing_battlemap = true
                        _draft_start = position
                        _draft_end = position
                        queue_redraw()
            elif _drawing_battlemap:
                _draft_end = local_to_document(mouse.position)
                _drawing_battlemap = false
                battlemap_requested.emit(_draft_start, _draft_end, battle_rotation)
                queue_redraw()
            accept_event()
    elif event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        if _panning:
            camera_center -= motion.relative / camera_zoom
            queue_redraw()
            accept_event()
        elif _drawing_battlemap:
            _draft_end = local_to_document(motion.position)
            queue_redraw()
            accept_event()
        elif tool == Tool.PAINT and motion.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
            paint_requested.emit(map.grid.document_to_cell(local_to_document(motion.position)))
            accept_event()
