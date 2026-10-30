class_name AtlasCanvas
extends Control

## Document-space renderer and gesture input, not the campaign's source of
## truth. The static editor shell lives in .tscn; per-layer draw nodes are
## runtime-created because their count/order depends on the open document.

signal paint_requested(cell: Vector2i)
signal selection_requested(cell: Vector2i)
signal wheel_step(direction: int, local_position: Vector2)
signal enter_requested(link: AtlasMapLink)
signal link_candidates_requested(links: Array[AtlasMapLink])
signal link_selected(id: String)
signal magnify_requested(factor: float, position: Vector2)
signal link_move_requested(id: String, offset: Vector2)
signal zoom_interrupted
signal pointer_moved(local_position: Vector2)
signal interaction_started
signal interaction_finished
signal stroke_requested(stroke: AtlasStroke, erasing: bool)
signal path_edit_requested(index: int, expected: AtlasStroke, replacement: AtlasStroke)
signal selection_changed
signal transform_requested(selection: AtlasSelection, transform: Transform2D)
signal fill_requested
signal fill_preview_requested(position: Vector2, invert_global: bool)
signal fill_cancel_requested
signal view_region_changed

enum Tool { PEN, ERASER, PAINT, SELECT, LINE, RECTANGLE, ELLIPSE, ART_SELECT, FILL, MOVE, POLYGON, WALL_PATH }
enum Preview { OFF, MARKERS, THUMBNAILS, OVERLAY }
enum Manipulation { NONE, MARQUEE, MOVE, RESIZE }

var campaign: AtlasCampaign
var map: AtlasMapDocument
var floor: AtlasFloor
var active_layer_id: String = "ink"
## Presentation only: never changes the authored layer, floor, map or camera.
## Automatic LOD (T-004/T-005) must use set_presented_detail_level so an
## in-progress gesture cannot be redirected or visually interrupted.
var presented_detail_level: int = 0


func set_presented_detail_level(level: int) -> bool:
	if level < 0 or level > AtlasLayer.MAX_DETAIL_LEVEL or is_editing():
		return false
	if presented_detail_level != level:
		clear_selection()
	presented_detail_level = level
	queue_redraw()
	return true


func editing_target_is_presented() -> bool:
	if floor == null:
		return false
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	return layer != null and layer.detail_level == presented_detail_level
var selection: AtlasSelection = AtlasSelection.new()
var edit_scope: AtlasEditScope = AtlasEditScope.new()
var tool: Tool = Tool.PEN
var preview: Preview = Preview.OVERLAY
## Private capture only: retain source alpha instead of painting the editor board.
var transparent_background: bool = false

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
var reference_opacity: float = 0.35
var show_reference: bool = true
var references: AtlasMapReferences
var selected_link_id: String = ""
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
## Session-only; grid changes never rewrite existing artwork.
var snap_to_grid: bool = false
var polygon_solid_fill: bool = false
var fill_tolerance: float = 0.0
var fill_global: bool = false

var _panning: bool = false
var _tile_painting: bool = false
var _fill_pending: bool = false
var _pending_wheel_fraction: float = 0.0
var _wheel_dispatch_direction: int = 0
var _last_wheel_dispatch_ms: int = -1
var _draft_stroke: AtlasStroke
var _erasing: bool = false
var _stroke_left_canvas: bool = false
var _brush_cursor_local: Vector2 = Vector2.ZERO
var _brush_cursor_inside: bool = false
var _erase_preview: Array[AtlasStroke] = []
var _layer_groups: Dictionary[String, CanvasGroup] = {}
var _layer_drawers: Dictionary[String, Node2D] = {}
var _raster_textures: Dictionary[String, ImageTexture] = {}
var _overlay: Node2D
var _manipulation: Manipulation = Manipulation.NONE
var _gesture_start: Vector2
var _gesture_end: Vector2
var _gesture_snap: bool = false
var _shape_kind: String = ""
var _polygon_vertices: PackedVector2Array = PackedVector2Array()
var _polygon_pointer: Vector2 = Vector2.ZERO
## Session-only vertex editing; resources remain in the ink layer and history.
var _wall_vertices: PackedVector2Array = PackedVector2Array()
var _wall_pointer: Vector2 = Vector2.ZERO
var _wall_selected_index: int = -1
var _wall_drag_vertex: int = -1
var _wall_drag_origin: Vector2 = Vector2.ZERO
var _wall_before: AtlasStroke
var _wall_preview: AtlasStroke
var _preview_layer: AtlasLayer
var _gesture_transform: Transform2D = Transform2D.IDENTITY
var _selection_mode: AtlasSelectionGeometry.CombineMode = AtlasSelectionGeometry.CombineMode.REPLACE
var _moving_link_id: String = ""
var _link_move_start: Vector2
var _link_move_end: Vector2

const EMPTY_COLOR: Color = Color("#212c34")
const TERRAIN_COLORS: Array[Color] = [
	Color("#36434b"), Color("#68846b"), Color("#94a47c"), Color("#ac8f68"),
	Color("#62798d"), Color("#bac3a0")
]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(_on_resized)
	get_window().focus_exited.connect(cancel_edit)
	mouse_exited.connect(_clear_brush_cursor)
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
	presented_detail_level = 0
	_raster_textures.clear()
	clear_selection()
	has_selected_cell = false
	selected_link_id = ""
	queue_redraw()
	return true


func choose_tool(value: Tool) -> void:
	cancel_edit()
	tool = value
	_overlay.queue_redraw()


func is_editing() -> bool:
	return not _moving_link_id.is_empty() or _draft_stroke != null or _tile_painting or _fill_pending or _manipulation != Manipulation.NONE or not _shape_kind.is_empty() or not _polygon_vertices.is_empty() or not _wall_vertices.is_empty() or _wall_drag_vertex >= 0


func cancel_edit() -> void:
	if _fill_pending:
		_fill_pending = false
		fill_cancel_requested.emit()
	_draft_stroke = null
	_erase_preview.clear()
	_panning = false
	_tile_painting = false
	_manipulation = Manipulation.NONE
	_shape_kind = ""
	_polygon_vertices.clear()
	_wall_vertices.clear()
	_wall_drag_vertex = -1
	_wall_before = null
	_wall_preview = null
	_wall_selected_index = -1
	_gesture_snap = false
	_preview_layer = null
	_pending_wheel_fraction = 0.0
	_wheel_dispatch_direction = 0
	_last_wheel_dispatch_ms = -1
	_moving_link_id = ""
	_raster_textures.clear()
	queue_redraw()
	interaction_finished.emit()


func commit_edit() -> void:
	if not _wall_vertices.is_empty():
		_finish_wall_path(false)
		return
	if _wall_drag_vertex >= 0:
		_finish_wall_drag()
		return
	if not _polygon_vertices.is_empty():
		var shape: AtlasStroke = AtlasShapes.polygon(_polygon_vertices, brush_color, brush_width, polygon_solid_fill)
		_polygon_vertices.clear()
		_draft_stroke = null
		_gesture_snap = false
		if shape != null:
			stroke_requested.emit(shape, false)
		queue_redraw()
		interaction_finished.emit()
		return
	if not _moving_link_id.is_empty():
		var id: String = _moving_link_id
		_moving_link_id = ""
		var offset: Vector2 = _link_move_end - _link_move_start
		if offset.length_squared() > 0.0001:
			link_move_requested.emit(id, offset)
		queue_redraw()
		interaction_finished.emit()
		return
	if _manipulation != Manipulation.NONE:
		_finish_manipulation()
		return
	if _draft_stroke == null:
		_shape_kind = ""
		_preview_layer = null
		queue_redraw()
		interaction_finished.emit()
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
	interaction_finished.emit()


func restyle_selected_wall() -> void:
	if floor == null or not editing_target_is_presented() or _wall_selected_index < 0:
		return
	var layer: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
	if layer == null or not layer.is_editable() or _wall_selected_index >= layer.strokes.size():
		return
	var original: AtlasStroke = layer.strokes[_wall_selected_index]
	var restyled: AtlasStroke = AtlasEditablePath.restyled(original, brush_color, brush_width)
	if restyled != null:
		path_edit_requested.emit(_wall_selected_index, original.copy(), restyled)


func clear_selection() -> void:
	selection = AtlasSelection.new()
	selection_changed.emit()
	queue_redraw()


func select_all_artwork() -> void:
	cancel_edit()
	selection = AtlasSelectionGeometry.select_all(floor.layer_by_id(active_layer_id)) if editing_target_is_presented() else AtlasSelection.new()
	selection_changed.emit()
	queue_redraw()


func _update_manipulation(position: Vector2) -> void:
	_gesture_end = position
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	if _manipulation == Manipulation.MOVE:
		var movement: Vector2 = AtlasGridSnap.move_delta(map.grid, _gesture_start, position) if _gesture_snap else position - _gesture_start
		_gesture_transform = Transform2D(0.0, movement)
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
	var valid_preview: bool = _preview_layer != null
	_manipulation = Manipulation.NONE
	_preview_layer = null
	if mode == Manipulation.MARQUEE:
		var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
		var next: AtlasSelection
		if _gesture_start.distance_to(_gesture_end) < 3.0 / camera_zoom:
			next = AtlasSelectionGeometry.select_point(layer, _gesture_end, 5.0 / camera_zoom)
		else:
			next = AtlasSelectionGeometry.select_rect(layer, Rect2(_gesture_start, _gesture_end - _gesture_start).abs())
		selection = AtlasSelectionGeometry.combined(layer, selection, next, _selection_mode)
		selection_changed.emit()
	elif valid_preview and _gesture_transform != Transform2D.IDENTITY:
		# Never commit an invalid (masked/locked) preview or a click without movement.
		transform_requested.emit(selection, _gesture_transform)
	queue_redraw()
	interaction_finished.emit()


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
	if not transparent_background:
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
		group.visible = layer.visible and layer.opacity > 0.0 and layer.detail_level == presented_detail_level
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
		for index: int in range(artwork.size()):
			var stroke: AtlasStroke = artwork[index]
			_draw_stroke(_wall_preview if id == active_layer_id and _wall_preview != null and index == _wall_selected_index else stroke, item)
		if id == active_layer_id and tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
			var guide: PackedVector2Array = _wall_vertices.duplicate()
			if guide[-1].distance_squared_to(_wall_pointer) > 0.0001:
				guide.append(_wall_pointer)
			if guide.size() > 1:
				item.draw_polyline(guide, Color(0.96, 0.72, 0.32, 0.65), brush_width, true)
		if previewing and not _erasing:
			if _draft_stroke.filled:
				if edit_scope.contains_rect(AtlasSelectionGeometry.stroke_bounds(_draft_stroke)):
					_draw_stroke(_draft_stroke, item)
			else:
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
	if references != null:
		references.draw_children(item)
	if has_selected_cell and map.grid.kind != AtlasGrid.Kind.GRIDLESS:
		var outline: PackedVector2Array = map.grid.cell_polygon(selected_cell)
		_stroke_polygon(outline, Color("#f9cc65"), 2.5 / camera_zoom, item)
	if not _moving_link_id.is_empty():
		var link: AtlasMapLink = campaign.link_by_id(_moving_link_id)
		if link != null:
			var placement: AtlasPlacement = campaign.placement_by_id(link.placement_id)
			var offset: Vector2 = _link_move_end - _link_move_start
			if placement != null:
				var points: PackedVector2Array = placement.corners()
				for index: int in range(points.size()):
					points[index] += offset
				_stroke_polygon(points, Color("#f9cc65"), 2.0 / camera_zoom, item)
			else:
				item.draw_arc(link.anchor + offset, link.hit_radius, 0, TAU, 48, Color("#f9cc65"), 2.0 / camera_zoom)
	if _manipulation == Manipulation.MARQUEE:
		item.draw_rect(Rect2(_gesture_start, _gesture_end - _gesture_start).abs(), Color(0.3, 0.7, 1.0, 0.15))
		item.draw_rect(Rect2(_gesture_start, _gesture_end - _gesture_start).abs(), Color("#4dabf2"), false, 1.0 / camera_zoom)
	if editing_target_is_presented() and not selection.is_empty() and selection.matches(floor.layer_by_id(active_layer_id)):
		var bounds: Rect2 = selection.bounds
		var color: Color = Color("#4dabf2")
		if _manipulation in [Manipulation.MOVE, Manipulation.RESIZE]:
			if _preview_layer != null:
				bounds = AtlasSelectionGeometry.select_indices(_preview_layer, selection.stroke_indices).bounds
			else:
				color = Color("#f48771")
		item.draw_rect(bounds, color, false, 1.5 / camera_zoom)
		item.draw_rect(Rect2(bounds.end - Vector2.ONE * 4.0 / camera_zoom, Vector2.ONE * 8.0 / camera_zoom), color)
	if not _polygon_vertices.is_empty():
		var guide: PackedVector2Array = _polygon_vertices.duplicate()
		guide.append(_polygon_pointer)
		if guide.size() >= 2:
			item.draw_polyline(guide, Color("#f9cc65"), 1.5 / camera_zoom, true)
		for vertex: Vector2 in _polygon_vertices:
			item.draw_circle(vertex, 3.0 / camera_zoom, Color("#f9cc65"))
	if tool == Tool.WALL_PATH and editing_target_is_presented():
		var active: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
		if active != null and _wall_selected_index >= 0 and _wall_selected_index < active.strokes.size():
			var wall: AtlasStroke = _wall_preview if _wall_preview != null else active.strokes[_wall_selected_index]
			if wall.editable_path:
				for vertex: Vector2 in wall.points:
					item.draw_circle(vertex, 4.0 / camera_zoom, Color("#4dabf2"))
		if not _wall_vertices.is_empty():
			for vertex: Vector2 in _wall_vertices:
				item.draw_circle(vertex, 3.5 / camera_zoom, Color("#f9cc65"))
	_draw_brush_cursor(item)


## A pointer ring shows the active Brush or Eraser diameter at any zoom.
## Keep it out of authored ink/raster, captured references and saved scenes.
func _draw_brush_cursor(item: Node2D) -> void:
	if not _brush_cursor_inside or tool not in [Tool.PEN, Tool.ERASER] or not editing_target_is_presented():
		return
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	if not (layer is AtlasInkLayer or layer is AtlasRasterLayer) or not layer.is_editable():
		return
	var center: Vector2 = local_to_document(_brush_cursor_local)
	var radius: float = brush_width * 0.5
	if radius <= 0.0:
		return
	# Dual outline stays visible against both dark and light artwork.
	item.draw_arc(center, radius, 0.0, TAU, 64, Color(0, 0, 0, 0.85), 2.5 / camera_zoom, true)
	item.draw_arc(center, radius, 0.0, TAU, 64,
		Color(1.0, 0.53, 0.45, 0.95) if tool == Tool.ERASER else Color(1, 1, 1, 0.95),
		1.0 / camera_zoom, true)


func _clear_brush_cursor() -> void:
	# Do not leave a release-to-commit fill pending after the pointer exits.
	if _fill_pending:
		cancel_edit()
	_brush_cursor_inside = false
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_parent_reference() -> void:
	if show_reference and references != null:
		references.draw_parent(self)


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
			var cell: Vector2i = Vector2i(x, y)
			var polygon: PackedVector2Array = grid.cell_polygon(cell)
			_stroke_polygon(polygon, Color(0.77, 0.84, 0.78, 0.20), 0.8 / camera_zoom, item)


func _draw_stroke(stroke: AtlasStroke, item: Node2D) -> void:
	if stroke.filled:
		var interior: PackedVector2Array = stroke.points.duplicate()
		interior.remove_at(interior.size() - 1)
		item.draw_colored_polygon(interior, stroke.color)
		return
	var centers: PackedVector2Array = AtlasStrokeGeometry.centers(AtlasEditablePath.render_points(stroke) if stroke.editable_path else stroke.points)
	if centers.size() == 1:
		item.draw_circle(centers[0], stroke.width * 0.5, stroke.color, true, -1.0, true)
	elif centers.size() > 1:
		var outlines: Array[PackedVector2Array] = AtlasStrokeGeometry.outline(centers, stroke.width)
		if outlines.size() == 1 and outlines[0].size() >= 3:
			item.draw_colored_polygon(outlines[0], stroke.color)
		else:
			# Closed or looping paths can have holes; polygon fills cannot cut them.
			# Keep the old outline drawing in that case rather than fill a shape.
			item.draw_polyline(centers, stroke.color, stroke.width, true)
			for point: Vector2 in centers:
				item.draw_circle(point, stroke.width * 0.5, stroke.color)


func _append_stroke_point(local_position: Vector2, shift_pressed: bool = false, alt_pressed: bool = false) -> void:
	if not Rect2(Vector2.ZERO, size).has_point(local_position):
		_stroke_left_canvas = true
	if (_draft_stroke == null and _shape_kind.is_empty()) or _stroke_left_canvas:
		return
	var point: Vector2 = local_to_document(local_position)
	if not _shape_kind.is_empty():
		if _gesture_snap:
			point = AtlasGridSnap.point(map.grid, point)
		if _shape_kind == "LINE":
			var endpoints: PackedVector2Array = AtlasShapes.line_endpoints(_gesture_start, point, shift_pressed, alt_pressed)
			_draft_stroke = AtlasShapes.stroke(_shape_kind, endpoints[0], endpoints[1], brush_color, brush_width)
		else:
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
		var target: AtlasMapDocument = campaign.get_map(link.target_map_id)
		if target == null:
			continue
		if not link.placement_id.is_empty():
			var placement: AtlasPlacement = campaign.placement_by_id(link.placement_id)
			if placement == null or placement.parent_map_id != link.source_map_id or placement.child_map_id != link.target_map_id:
				continue
			var corners: PackedVector2Array = placement.corners()
			var fill: Color = Color(0.24, 0.70, 0.82, 0.15)
			item.draw_colored_polygon(corners, fill)
			_stroke_polygon(corners, Color("#f9cc65") if link.id == selected_link_id else Color("#63d3e5"), 2.0 / camera_zoom, item)
			item.draw_string(ThemeDB.fallback_font, placement.origin, target.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		else:
			item.draw_circle(link.anchor, 18.0 / camera_zoom, Color("#efd797"))
			item.draw_arc(link.anchor, 18.0 / camera_zoom, 0.0, TAU, 24,
				Color("#395760"), 2.0 / camera_zoom)
			item.draw_string(ThemeDB.fallback_font, link.anchor + Vector2(20.0 / camera_zoom, 0.0),
				target.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _stroke_polygon(polygon: PackedVector2Array, color: Color, width: float, item: Node2D) -> void:
	if polygon.size() < 2:
		return
	var outline: PackedVector2Array = polygon.duplicate()
	outline.append(polygon[0])
	item.draw_polyline(outline, color, width, true)


func _terrain_color(palette: int) -> Color:
	if palette < 0 or palette >= TERRAIN_COLORS.size():
		return TERRAIN_COLORS[0]
	return TERRAIN_COLORS[palette]


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if _handle_gesture(event):
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_handle_wall_key(event as InputEventKey)
	elif event is InputEventKey and tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					commit_edit()
					accept_event()
				KEY_BACKSPACE:
					_polygon_vertices.remove_at(_polygon_vertices.size() - 1)
					if _polygon_vertices.is_empty():
						cancel_edit()
					else:
						_update_polygon_preview(_brush_cursor_local)
					accept_event()
				KEY_ESCAPE:
					cancel_edit()
					accept_event()
	elif event is InputEventKey and _shape_kind == "LINE" and _draft_stroke != null:
		var key: InputEventKey = event as InputEventKey
		if key.keycode in [KEY_SHIFT, KEY_ALT] and not key.echo:
			_append_stroke_point(_brush_cursor_local, key.shift_pressed, key.alt_pressed)


func _handle_gesture(event: InputEvent) -> bool:
	if event is InputEventPanGesture:
		if not is_editing() and event.delta.y != 0.0:
			_consume_wheel(-1 if event.delta.y > 0 else 1, absf(event.delta.y), event.position)
		accept_event()
		return true
	if event is InputEventMagnifyGesture:
		if not is_editing():
			magnify_requested.emit(event.factor, event.position)
		accept_event()
		return true
	return false


func _handle_mouse_button(mouse: InputEventMouseButton) -> void:
	match mouse.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			_handle_wheel_button(mouse)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			if mouse.button_index == MOUSE_BUTTON_RIGHT and tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
				if mouse.pressed:
					_finish_wall_path(_wall_vertices.size() >= 3)
				accept_event()
				return
			if mouse.button_index == MOUSE_BUTTON_RIGHT and tool == Tool.POLYGON and not _polygon_vertices.is_empty():
				if mouse.pressed:
					commit_edit()
				accept_event()
				return
			if mouse.pressed:
				cancel_edit()
				interaction_started.emit()
			_panning = mouse.pressed
			accept_event()
		MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_begin_left_press(mouse)
			else:
				_finish_left_release(mouse)
			accept_event()


func _handle_wheel_button(mouse: InputEventMouseButton) -> void:
	if not is_editing() and mouse.pressed:
		var magnitude: float = mouse.factor if mouse.factor > 0.0 else 1.0
		var direction: int = 1 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		_consume_wheel(direction, magnitude, mouse.position)
	accept_event()


func _begin_left_press(mouse: InputEventMouseButton) -> void:
	interaction_started.emit()
	grab_focus()
	var position: Vector2 = local_to_document(mouse.position)
	if _begin_link_press(mouse, position):
		return
	match tool:
		Tool.POLYGON:
			_begin_polygon_vertex(mouse, position)
		Tool.WALL_PATH:
			_begin_wall_point(mouse, position)
		Tool.PEN, Tool.ERASER:
			if not editing_target_is_presented():
				return
			var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
			if not (layer is AtlasInkLayer or layer is AtlasRasterLayer) or not layer.is_editable():
				return
			_erasing = tool == Tool.ERASER
			_stroke_left_canvas = false
			_draft_stroke = AtlasStroke.new(PackedVector2Array([position]), brush_color, brush_width)
			_append_stroke_point(mouse.position)
		Tool.LINE, Tool.RECTANGLE, Tool.ELLIPSE:
			if not editing_target_is_presented():
				return
			var layer: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
			if layer != null and layer.is_editable():
				_shape_kind = Tool.keys()[tool]
				_gesture_snap = snap_to_grid
				_gesture_start = AtlasGridSnap.point(map.grid, position) if snap_to_grid else position
				_brush_cursor_local = mouse.position
				_stroke_left_canvas = false
				_draft_stroke = AtlasShapes.stroke("LINE", _gesture_start, _gesture_start, brush_color, brush_width)
		Tool.MOVE:
			_begin_artwork_move(position)
		Tool.ART_SELECT:
			if not editing_target_is_presented():
				return
			var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
			_gesture_start = position
			_gesture_snap = snap_to_grid
			_gesture_end = position
			_gesture_transform = Transform2D.IDENTITY
			_selection_mode = AtlasSelectionGeometry.CombineMode.SUBTRACT if mouse.alt_pressed else (
				AtlasSelectionGeometry.CombineMode.ADD if mouse.ctrl_pressed or mouse.meta_pressed else AtlasSelectionGeometry.CombineMode.REPLACE)
			if _selection_mode == AtlasSelectionGeometry.CombineMode.REPLACE and selection.matches(layer) and not selection.is_empty() and layer.is_editable():
				if position.distance_to(selection.bounds.end) <= 8.0 / camera_zoom:
					_manipulation = Manipulation.RESIZE
				elif selection.bounds.has_point(position):
					_manipulation = Manipulation.MOVE
			if _manipulation == Manipulation.NONE:
				_manipulation = Manipulation.MARQUEE
		Tool.FILL:
			if editing_target_is_presented():
				_fill_pending = true
				fill_preview_requested.emit(position, mouse.shift_pressed)
		Tool.PAINT:
			if editing_target_is_presented():
				_tile_painting = true
				_request_cell_paint(position)
		Tool.SELECT:
			selection_requested.emit(map.grid.document_to_cell(position))


## Move acts on selected objects without a marquee. A click on a new object
## selects it on the active layer, and a drag moves it in one history entry.
## Existing multi-object selections are retained when the pointer starts
## inside their bounds; no other layer or detail level is implicitly targeted.
func _begin_artwork_move(position: Vector2) -> void:
	if not editing_target_is_presented():
		return
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	if layer == null or not (layer is AtlasInkLayer or layer is AtlasRasterLayer):
		return
	if selection.is_empty() or not selection.matches(layer) or not selection.bounds.has_point(position):
		selection = AtlasSelectionGeometry.select_point(layer, position, 5.0 / camera_zoom)
		selection_changed.emit()
		queue_redraw()
	if selection.is_empty() or not layer.is_editable():
		return
	_gesture_start = position
	_gesture_end = position
	_gesture_snap = snap_to_grid
	_gesture_transform = Transform2D.IDENTITY
	_preview_layer = null
	_manipulation = Manipulation.MOVE


func _begin_link_press(mouse: InputEventMouseButton, position: Vector2) -> bool:
	if campaign == null or tool != Tool.SELECT:
		return false
	var links: Array[AtlasMapLink] = campaign.find_links_at(map.id, position, floor.id)
	if mouse.double_click and not links.is_empty():
		link_candidates_requested.emit(links)
		return true
	selected_link_id = links[0].id if links.size() == 1 else ""
	link_selected.emit(selected_link_id)
	if not selected_link_id.is_empty():
		_moving_link_id = selected_link_id
		_link_move_start = position
		_link_move_end = position
	# Selecting a link still falls through to grid-cell selection; entering does not.
	return false


func _finish_left_release(mouse: InputEventMouseButton) -> void:
	if _fill_pending:
		_fill_pending = false
		fill_requested.emit()
		_preview_layer = null
		_raster_textures.clear()
		queue_redraw()
		interaction_finished.emit()
	elif tool == Tool.WALL_PATH and _wall_drag_vertex >= 0:
		_update_wall_drag(local_to_document(mouse.position))
		_finish_wall_drag()
	elif tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_update_wall_pointer(mouse.position)
	elif tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		# Vertices are placed by clicks; mouse release never finishes a shape.
		_update_polygon_preview(mouse.position)
	elif _tile_painting:
		_tile_painting = false
		interaction_finished.emit()
	elif not _moving_link_id.is_empty():
		_link_move_end = local_to_document(mouse.position)
		commit_edit()
	elif _manipulation != Manipulation.NONE:
		_update_manipulation(local_to_document(mouse.position))
		_finish_manipulation()
	elif is_editing():
		_append_stroke_point(mouse.position, mouse.shift_pressed, mouse.alt_pressed)
		commit_edit()


func _handle_mouse_motion(motion: InputEventMouseMotion) -> void:
	_brush_cursor_local = motion.position
	_brush_cursor_inside = Rect2(Vector2.ZERO, size).has_point(motion.position)
	_overlay.queue_redraw()
	pointer_moved.emit(motion.position)
	if _panning:
		camera_center -= motion.relative / camera_zoom
		queue_redraw()
	elif not _moving_link_id.is_empty():
		_link_move_end = local_to_document(motion.position)
		queue_redraw()
	elif _manipulation != Manipulation.NONE:
		_update_manipulation(local_to_document(motion.position))
	elif tool == Tool.WALL_PATH and _wall_drag_vertex >= 0:
		_update_wall_drag(local_to_document(motion.position))
	elif tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_update_wall_pointer(motion.position)
	elif tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		_update_polygon_preview(motion.position)
	elif tool == Tool.PAINT and _tile_painting:
		_request_cell_paint(local_to_document(motion.position))
	elif is_editing():
		_append_stroke_point(motion.position, motion.shift_pressed, motion.alt_pressed)
	else:
		return
	accept_event()


func _request_cell_paint(position: Vector2) -> void:
	var layer: AtlasTileLayer = floor.layer_by_id(active_layer_id) as AtlasTileLayer
	if layer == null:
		return
	var grid: AtlasGrid = layer.grid if layer.grid != null else map.get_terrain_grid(floor.id)
	if grid.kind != AtlasGrid.Kind.GRIDLESS:
		paint_requested.emit(grid.document_to_cell(position))


func _consume_wheel(direction: int, magnitude: float, position: Vector2) -> void:
	if direction == 0 or not is_finite(magnitude) or magnitude <= 0.0:
		return
	var now: int = Time.get_ticks_msec()
	if _wheel_dispatch_direction != direction or (_last_wheel_dispatch_ms >= 0 and now - _last_wheel_dispatch_ms > AtlasZoomGate.RESET_TIMEOUT_MS):
		_pending_wheel_fraction = 0.0
		zoom_interrupted.emit()
	_wheel_dispatch_direction = direction
	_last_wheel_dispatch_ms = now
	_pending_wheel_fraction += minf(magnitude, 1.0)
	if _pending_wheel_fraction >= 1.0:
		# One dispatch emits at most one logical step, discarding any remainder.
		_pending_wheel_fraction = 0.0
		wheel_step.emit(direction, position)


## Construct and edit independently typed wall paths on the selected ink layer.
## Normal click selects an existing edge or drags its vertex. Shift+click
## inserts a vertex, Alt+click deletes one; an explicit inspector action restyles.
func _begin_wall_point(mouse: InputEventMouseButton, position: Vector2) -> void:
	if not editing_target_is_presented():
		return
	var layer: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
	if layer == null or not layer.is_editable():
		return
	if not _wall_vertices.is_empty():
		var point: Vector2 = AtlasGridSnap.point(map.grid, position) if _gesture_snap else position
		if mouse.double_click:
			_finish_wall_path(false)
			return
		if _wall_vertices.size() >= 3 and point.distance_to(_wall_vertices[0]) <= 8.0 / camera_zoom:
			_finish_wall_path(true)
			return
		if _wall_vertices.size() < AtlasEditablePath.MAX_VERTICES and point.distance_squared_to(_wall_vertices[-1]) > 0.0001:
			_wall_vertices.append(point)
		_update_wall_pointer(mouse.position)
		return
	var radius: float = 8.0 / camera_zoom
	for index: int in range(layer.strokes.size() - 1, -1, -1):
		var path: AtlasStroke = layer.strokes[index]
		if not path.editable_path:
			continue
		var vertex: int = AtlasEditablePath.vertex_at(path, position, radius)
		var segment: int = AtlasEditablePath.segment_at(path, position, radius)
		if vertex < 0 and segment < 0:
			continue
		_wall_selected_index = index
		_gesture_snap = snap_to_grid
		_wall_before = path.copy()
		if mouse.alt_pressed and vertex >= 0:
			var removed: AtlasStroke = AtlasEditablePath.deleted_vertex(path, vertex)
			if removed != null:
				path_edit_requested.emit(index, path.copy(), removed)
			_wall_before = null
		elif mouse.shift_pressed and segment >= 0:
			var inserted_at: Vector2 = AtlasGridSnap.point(map.grid, position) if snap_to_grid else position
			var inserted: AtlasStroke = AtlasEditablePath.inserted_vertex(path, segment, inserted_at)
			if inserted != null:
				path_edit_requested.emit(index, path.copy(), inserted)
			_wall_before = null
		elif vertex >= 0:
			_wall_drag_origin = position
			_wall_drag_vertex = vertex
			_wall_preview = path.copy()
		else:
			_wall_before = null
		queue_redraw()
		return
	_wall_selected_index = -1
	_wall_before = null
	_gesture_snap = snap_to_grid
	_wall_vertices = PackedVector2Array([AtlasGridSnap.point(map.grid, position) if _gesture_snap else position])
	_update_wall_pointer(mouse.position)


func _update_wall_pointer(local_position: Vector2) -> void:
	_wall_pointer = local_to_document(local_position)
	if _gesture_snap:
		_wall_pointer = AtlasGridSnap.point(map.grid, _wall_pointer)
	queue_redraw()


func _finish_wall_path(closed: bool) -> void:
	var path: AtlasStroke = AtlasEditablePath.make(_wall_vertices, brush_color, brush_width, closed)
	_wall_vertices.clear()
	_wall_before = null
	_gesture_snap = false
	if path != null:
		path_edit_requested.emit(-1, null, path)
	queue_redraw()
	interaction_finished.emit()


func _update_wall_drag(position: Vector2) -> void:
	if _wall_before == null:
		return
	# A simple click selects a vertex. It must not snap an existing off-grid
	# vertex into a new position unless the pointer really moves.
	if position.distance_squared_to(_wall_drag_origin) <= 0.000001:
		_wall_preview = _wall_before.copy()
		queue_redraw()
		return
	var point: Vector2 = AtlasGridSnap.point(map.grid, position) if _gesture_snap else position
	_wall_preview = AtlasEditablePath.moved_vertex(_wall_before, _wall_drag_vertex, point)
	queue_redraw()


func _finish_wall_drag() -> void:
	var index: int = _wall_selected_index
	var before: AtlasStroke = _wall_before
	var after: AtlasStroke = _wall_preview
	_wall_drag_vertex = -1
	_wall_before = null
	_wall_preview = null
	if before != null and after != null and before.to_dict() != after.to_dict():
		path_edit_requested.emit(index, before, after)
	queue_redraw()
	interaction_finished.emit()


func _handle_wall_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_finish_wall_path(false)
			accept_event()
		KEY_BACKSPACE:
			_wall_vertices.remove_at(_wall_vertices.size() - 1)
			if _wall_vertices.is_empty():
				cancel_edit()
			else:
				_update_wall_pointer(_brush_cursor_local)
			accept_event()
		KEY_ESCAPE:
			cancel_edit()
			accept_event()


## Each click fixes a vertex. Click near the first point, double-click, Enter,
## or right-click to close. Backspace removes the last vertex; Escape cancels.
func _begin_polygon_vertex(mouse: InputEventMouseButton, position: Vector2) -> void:
	if not editing_target_is_presented():
		return
	var layer: AtlasInkLayer = floor.layer_by_id(active_layer_id) as AtlasInkLayer
	if layer == null or not layer.is_editable():
		return
	if _polygon_vertices.is_empty():
		_gesture_snap = snap_to_grid
	var point: Vector2 = AtlasGridSnap.point(map.grid, position) if _gesture_snap else position
	if mouse.double_click:
		if _polygon_vertices.size() >= 3:
			commit_edit()
		return
	if _polygon_vertices.size() >= 3 and point.distance_to(_polygon_vertices[0]) <= 8.0 / camera_zoom:
		commit_edit()
		return
	if _polygon_vertices.size() >= AtlasShapes.MAX_POLYGON_VERTICES or (not _polygon_vertices.is_empty() and
			point.distance_squared_to(_polygon_vertices[-1]) <= 0.0001):
		return
	_polygon_vertices.append(point)
	_update_polygon_preview(mouse.position)


func _update_polygon_preview(local_position: Vector2) -> void:
	if _polygon_vertices.is_empty():
		return
	_polygon_pointer = local_to_document(local_position)
	if _gesture_snap:
		_polygon_pointer = AtlasGridSnap.point(map.grid, _polygon_pointer)
	var candidates: PackedVector2Array = _polygon_vertices.duplicate()
	# Once at least three vertices are fixed, Enter/close commits exactly this
	# preview; the pointer's next edge remains a gold guide, not a phantom fill.
	if candidates.size() < 3 and candidates[-1].distance_squared_to(_polygon_pointer) > 0.0001:
		candidates.append(_polygon_pointer)
	_draft_stroke = AtlasShapes.polygon(candidates, brush_color, brush_width, polygon_solid_fill)
	queue_redraw()
