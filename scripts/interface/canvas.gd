class_name AtlasCanvas
extends Control

## Document-space renderer and gesture input, not the campaign's source of
## truth. The static editor shell lives in .tscn; per-layer draw nodes are
## runtime-created because their count/order depends on the open document.

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
signal line_rejected(reason: String)
signal polygon_rejected(reason: String)
signal wall_rejected(reason: String)
signal path_edit_requested(index: int, expected: AtlasStroke, replacement: AtlasStroke)
signal text_requested(anchor: Vector2, index: int)
signal selection_changed
signal transform_requested(selection: AtlasSelection, transform: Transform2D)
signal fill_requested
signal fill_preview_requested(position: Vector2, invert_global: bool)
signal fill_cancel_requested
signal view_region_changed
signal projector_frame_changed
signal token_edit_requested(before: AtlasToken, after: AtlasToken)
signal fog_edit_requested(bounds: Rect2, reveal: bool)

enum Tool { PEN, ERASER, SELECT, LINE, RECTANGLE, ELLIPSE, ART_SELECT, FILL, MOVE, POLYGON, WALL_PATH, TEXT, TOKEN, FOG }
enum Preview { OFF, MARKERS, THUMBNAILS, OVERLAY }
enum Manipulation { NONE, MARQUEE, MOVE, RESIZE }
enum FrameDrag { NONE, MOVE, RESIZE }

var campaign: AtlasCampaign
var map: AtlasMapDocument
var floor: AtlasFloor
var active_layer_id: String = "raster"
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

## View-only document-board point at the center of the widget's viewport.
var camera_center: Vector2 = Vector2.ZERO:
	set(value):
		if camera_center == value:
			return
		camera_center = value
		view_region_changed.emit()
## View-only scale (screen pixels per board unit); not a D-level selector.
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
var brush_color: Color = Color("#f5b545"):
	set(value):
		brush_color = value
		_refresh_shape_style()
## Brush/eraser/shape diameter in document units; pointer ring converts with
## camera_zoom. Never store a screen-pixel width in a stroke.
var brush_width: float = 8.0:
	set(value):
		brush_width = value
		_refresh_shape_style()
## Session-only; grid changes never rewrite existing artwork.
var snap_to_grid: bool = false
var polygon_solid_fill: bool = false
## Session-only normalized [0, 1] premultiplied-RGBA fill tolerance.
var fill_tolerance: float = 0.0
var fill_global: bool = false

## Opt-in GM chrome, never placed in artwork layers or editor captures.
var projector_frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
var projector_frame_active: bool = false
var _frame_drag: FrameDrag = FrameDrag.NONE
var _frame_drag_start: Vector2 = Vector2.ZERO
var _frame_original_center: Vector2 = Vector2.ZERO
var _frame_original_width: float = 0.0
var _frame_resize_anchor: Vector2 = Vector2.ZERO

## Selected GM token and uncommitted drag. No source resource is changed until release.
var token_label: String = "Token"
var token_radius: float = 16.0
var selected_token_id: String = ""
var _token_drag_before: AtlasToken
var _token_drag_preview: AtlasToken
var _token_drag_start: Vector2 = Vector2.ZERO
## GM-only rectangle draft; not a saved artwork layer or captured overlay.
var _fog_drag_active: bool = false
var _fog_start: Vector2 = Vector2.ZERO
var _fog_end: Vector2 = Vector2.ZERO
var _fog_reveal: bool = true
var _panning: bool = false
var _fill_pending: bool = false
var _pending_wheel_fraction: float = 0.0
var _wheel_dispatch_direction: int = 0
var _last_wheel_dispatch_ms: int = -1
var _draft_stroke: AtlasStroke
const CoverageMask = preload("res://scripts/interface/coverage_mask.gd")
var _raster_brush: AtlasRasterBrush
var _preview_samples: int = 0
var _preview_dirty: bool = false
var _restore_accumulated_input: bool = true
var _capturing_freehand: bool = false
var _erasing: bool = false
var _stroke_left_canvas: bool = false
var _brush_cursor_local: Vector2 = Vector2.ZERO
var _brush_cursor_inside: bool = false
## Derived per-layer render nodes keyed by stable layer ID; never saved as art.
var _layer_groups: Dictionary[String, CanvasGroup] = {}
var _layer_drawers: Dictionary[String, Node2D] = {}
var _render_states: Dictionary[String, Array] = {}
var _ink_masks: Dictionary[AtlasStroke, CoverageMask] = {}
var _ink_mask_view: Array = []
## Rebuildable GPU cache; raster pixel ownership remains with AtlasRasterChunk.
var _raster_textures: Dictionary[String, ImageTexture] = {}
var _preview_textures: Dictionary[String, ImageTexture] = {}
var _prop_textures: Dictionary[String, ImageTexture] = {}
var _overlay: Node2D
var _manipulation: Manipulation = Manipulation.NONE
## Transient gesture endpoints in board units, not raw pointer pixels.
var _gesture_start: Vector2
var _gesture_end: Vector2
## Frozen at gesture start so a toggle cannot desynchronize draft and commit.
var _gesture_snap: bool = false
var _shape_kind: String = ""
## A Line draft is valid only for its original floor, raster and edit-mask
## footprint. Release must not silently paint under a different authorization.
var _line_scope_at_press: AtlasEditScope
var _line_map_at_press: String = ""
var _line_floor_at_press: String = ""
var _line_layer_at_press: String = ""
## The Polygon is a multi-click gesture; its first vertex freezes the exact
## editable target and cell mask until a valid close or explicit cancellation.
var _polygon_scope_at_start: AtlasEditScope
var _polygon_map_at_start: AtlasMapDocument
var _polygon_floor_at_start: AtlasFloor
var _polygon_layer_at_start: AtlasRasterLayer
var _polygon_vertices: PackedVector2Array = PackedVector2Array()
var _polygon_pointer: Vector2 = Vector2.ZERO
## Session-only vertex editing; resources remain in the ink layer and history.
var _wall_vertices: PackedVector2Array = PackedVector2Array()
var _wall_pointer: Vector2 = Vector2.ZERO
## Completed draft edges use the same vector renderer as saved wall paths.
var _wall_draft: AtlasStroke
var _wall_selected_index: int = -1
var _wall_drag_vertex: int = -1
var _wall_drag_origin: Vector2 = Vector2.ZERO
var _wall_before: AtlasStroke
var _wall_preview: AtlasStroke
## The first vertex/press fixes both the Objects target and the effective edit
## mask for the entire path draft or vertex drag. A later mask change cannot
## silently authorize a different whole-path edit at finish/release.
var _wall_scope_at_start: AtlasEditScope
var _wall_map_at_start: AtlasMapDocument
var _wall_floor_at_start: AtlasFloor
var _wall_layer_at_start: AtlasObjectsLayer
## Detached candidate rendered during editing; history owns the actual commit.
var _preview_layer: AtlasLayer
## Selection transform in board units, not a camera or raster-pixel transform.
var _gesture_transform: Transform2D = Transform2D.IDENTITY
var _selection_mode: AtlasSelectionGeometry.CombineMode = AtlasSelectionGeometry.CombineMode.REPLACE
var _moving_link_id: String = ""
var _link_move_start: Vector2
var _link_move_end: Vector2

const EMPTY_COLOR: Color = Color("#212c34")


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
	selected_token_id = ""
	# Frames are not persistent or transferable to a different map/floor.
	projector_frame_active = false
	map = value
	campaign = current_campaign
	floor = selected_floor
	presented_detail_level = 0
	_clear_raster_textures()
	_prop_textures.clear()
	_clear_ink_masks()
	clear_selection()
	has_selected_cell = false
	selected_link_id = ""
	queue_redraw()
	return true


func choose_tool(value: Tool) -> void:
	cancel_edit()
	if value != Tool.TOKEN:
		selected_token_id = ""
	tool = value
	_overlay.queue_redraw()


func is_editing() -> bool:
	return _fog_drag_active or _token_drag_before != null or _frame_drag != FrameDrag.NONE \
		or not _moving_link_id.is_empty() or _draft_stroke != null or _fill_pending \
		or _manipulation != Manipulation.NONE or not _shape_kind.is_empty() \
		or not _polygon_vertices.is_empty() or not _wall_vertices.is_empty() or _wall_drag_vertex >= 0


func cancel_edit() -> void:
	_fog_drag_active = false
	_token_drag_before = null
	_token_drag_preview = null
	cancel_projector_frame_drag()
	_end_freehand()
	if _fill_pending:
		_fill_pending = false
		fill_cancel_requested.emit()
	_draft_stroke = null
	_panning = false
	_manipulation = Manipulation.NONE
	_shape_kind = ""
	_clear_line_context()
	_clear_polygon_context()
	_polygon_vertices.clear()
	_wall_vertices.clear()
	_wall_draft = null
	_wall_drag_vertex = -1
	_wall_before = null
	_wall_preview = null
	_clear_wall_context()
	_wall_selected_index = -1
	_gesture_snap = false
	_preview_layer = null
	_pending_wheel_fraction = 0.0
	_wheel_dispatch_direction = 0
	_last_wheel_dispatch_ms = -1
	_moving_link_id = ""
	queue_redraw()
	interaction_finished.emit()


func commit_edit() -> void:
	if _shape_kind == "LINE" and not _line_context_matches():
		cancel_edit()
		line_rejected.emit("Line target or edit mask changed since preview; nothing painted.")
		return
	if not _polygon_vertices.is_empty() and not _polygon_context_matches():
		_reject_stale_polygon()
		return
	if not _wall_vertices.is_empty() or _wall_drag_vertex >= 0:
		if not _wall_context_matches():
			_reject_stale_wall()
			return
	if not _wall_vertices.is_empty():
		_finish_wall_path(false)
		return
	if _wall_drag_vertex >= 0:
		_finish_wall_drag()
		return
	if not _polygon_vertices.is_empty():
		var shape: AtlasStroke = AtlasShapes.polygon(_polygon_vertices, brush_color, brush_width, polygon_solid_fill)
		_polygon_vertices.clear()
		_clear_polygon_context()
		_draft_stroke = null
		_preview_layer = null
		_preview_dirty = false
		_clear_raster_textures()
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
	_end_freehand()
	_draft_stroke = null
	_shape_kind = ""
	_clear_line_context()
	_preview_layer = null
	_clear_raster_textures()
	stroke_requested.emit(stroke, erasing)
	queue_redraw()
	interaction_finished.emit()


func restyle_selected_wall() -> void:
	if floor == null or not editing_target_is_presented() or _wall_selected_index < 0:
		return
	var layer: AtlasObjectsLayer = floor.layer_by_id(active_layer_id) as AtlasObjectsLayer
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
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	selection = AtlasSelectionGeometry.select_all(layer) if editing_target_is_presented() and layer is AtlasObjectsLayer else AtlasSelection.new()
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
## Brush widths and link hit radii use document units.
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
	var view: Array = [size, camera_center, camera_zoom]
	if _ink_mask_view != view:
		_clear_ink_masks()
		_ink_mask_view = view
	var present: Dictionary[String, bool] = {}
	var present_strokes: Dictionary[AtlasStroke, bool] = {}
	for index: int in range(floor.layers.size()):
		var layer: AtlasLayer = floor.layers[index]
		present[layer.id] = true
		if not _layer_groups.has(layer.id):
			var group: CanvasGroup = CanvasGroup.new()
			var drawer: Node2D = Node2D.new()
			drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		# Retain completed artwork draw commands while only the pointer/draft changes.
		var state: Array = [layer, _preview_layer if layer.id == active_layer_id else null, view]
		if layer is AtlasObjectsLayer:
			for stroke: AtlasStroke in layer.strokes:
				present_strokes[stroke] = true
			state.append(layer.strokes.duplicate())
			if layer.id == active_layer_id:
				state.append_array([_wall_preview, _wall_draft,
					_wall_vertices.duplicate(), _wall_pointer, tool])
		elif layer is AtlasTokenLayer:
			state.append((layer as AtlasTokenLayer).tokens.duplicate())
			if layer.id == active_layer_id:
				state.append(_token_drag_preview)
				state.append(_token_drag_preview.position if _token_drag_preview != null else null)
		elif layer is AtlasRasterLayer:
			state.append_array([layer.transform, layer.pixels_per_unit, layer.chunks.duplicate()])
		if _render_states.get(layer.id, []) != state:
			_render_states[layer.id] = state
			_layer_drawers[layer.id].queue_redraw()
	for stroke: AtlasStroke in [_draft_stroke, _wall_preview, _wall_draft]:
		if stroke != null:
			present_strokes[stroke] = true
	for stroke: AtlasStroke in _ink_masks.keys():
		if not present_strokes.has(stroke):
			_ink_masks[stroke].queue_free()
			_ink_masks.erase(stroke)
	for id: String in _layer_groups.keys():
		if not present.has(id):
			_layer_groups[id].hide()
			_layer_groups[id].queue_free()
			_layer_groups.erase(id)
			_layer_drawers.erase(id)
			_render_states.erase(id)
	_overlay.position = size * 0.5 - camera_center * camera_zoom
	_overlay.scale = Vector2.ONE * camera_zoom
	_overlay.queue_redraw()


func _draw_content_layer(item: Node2D, id: String) -> void:
	if floor == null:
		return
	var layer: AtlasLayer = floor.layer_by_id(id)
	if id == active_layer_id and _preview_layer != null:
		layer = _preview_layer
	if layer is AtlasObjectsLayer:
		var artwork: Array[AtlasStroke] = layer.strokes
		for index: int in range(artwork.size()):
			var stroke: AtlasStroke = artwork[index]
			_draw_stroke(_wall_preview if id == active_layer_id and _wall_preview != null and index == _wall_selected_index else stroke, item)
		if id == active_layer_id and tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
			# Completed edges match the actual committed wall rendering, including
			# round joins and RGBA. Only the uncommitted pointer leg is a guide.
			if _wall_draft != null:
				_draw_stroke(_wall_draft, item)
			var last: Vector2 = _wall_vertices[-1]
			if last.distance_squared_to(_wall_pointer) > 0.0001:
				item.draw_line(last, _wall_pointer, Color("#f9cc65"), 1.5 / camera_zoom, true)
	elif layer is AtlasTokenLayer:
		for token: AtlasToken in (layer as AtlasTokenLayer).tokens:
			var shown: AtlasToken = token
			if id == active_layer_id and _token_drag_preview != null and token.id == _token_drag_preview.id:
				shown = _token_drag_preview
			_draw_token(item, shown)
	elif layer is AtlasRasterLayer:
		item.draw_set_transform_matrix(layer.transform)
		var textures: Dictionary[String, ImageTexture] = _preview_textures if layer == _preview_layer else _raster_textures
		for chunk: AtlasRasterChunk in layer.chunks.values():
			if chunk.image == null:
				continue
			var asset: String = chunk.asset_id
			if not textures.has(asset):
				textures[asset] = ImageTexture.create_from_image(chunk.image)
			var origin: Vector2 = Vector2(chunk.coord) * AtlasRasterChunk.SIZE / layer.pixels_per_unit
			var dimensions: Vector2 = Vector2(chunk.width, chunk.height) / layer.pixels_per_unit
			item.draw_texture_rect(textures[asset], Rect2(origin, dimensions), false)


func _draw_token(item: Node2D, token: AtlasToken) -> void:
	item.draw_circle(token.position, token.radius, token.tint)
	item.draw_arc(token.position, token.radius, 0, TAU, 48, Color(0.95, 0.97, 1.0), 1.5)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	var caption: String = token.label
	var caption_width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	item.draw_string(font, token.position + Vector2(-caption_width * 0.5, token.radius + font_size + 4),
		caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func delete_selected_token() -> bool:
	var layer: AtlasTokenLayer = floor.layer_by_id(active_layer_id) as AtlasTokenLayer if floor != null else null
	if layer == null or not editing_target_is_presented() or not layer.is_editable():
		return false
	var selected: AtlasToken = layer.token_by_id(selected_token_id)
	if selected == null or not edit_scope.contains_rect(Rect2(selected.position - Vector2.ONE * selected.radius,
			Vector2.ONE * selected.radius * 2.0)):
		return false
	token_edit_requested.emit(selected.copy(), null)
	selected_token_id = ""
	queue_redraw()
	return true


func _begin_token_press(position: Vector2) -> void:
	var layer: AtlasTokenLayer = floor.layer_by_id(active_layer_id) as AtlasTokenLayer if floor != null else null
	if layer == null or not editing_target_is_presented() or not layer.is_editable():
		return
	for index: int in range(layer.tokens.size() - 1, -1, -1):
		var candidate: AtlasToken = layer.tokens[index]
		if candidate.position.distance_to(position) <= candidate.radius + 5.0 / camera_zoom:
			if not edit_scope.contains_rect(Rect2(candidate.position - Vector2.ONE * candidate.radius,
					Vector2.ONE * candidate.radius * 2.0)):
				return
			selected_token_id = candidate.id
			_token_drag_before = candidate.copy()
			_token_drag_preview = candidate.copy()
			_token_drag_start = position
			queue_redraw()
			return
	if layer.tokens.size() >= AtlasTokenLayer.MAX_TOKENS or token_label.strip_edges().is_empty():
		return
	var center: Vector2 = AtlasGridSnap.point(map.grid, position) if snap_to_grid else position
	var created: AtlasToken = AtlasToken.new("token-" + Crypto.new().generate_random_bytes(16).hex_encode(),
		center, token_label.strip_edges())
	created.radius = token_radius
	created.tint = brush_color
	if created.is_valid() and edit_scope.contains_rect(Rect2(created.position - Vector2.ONE * created.radius,
			Vector2.ONE * created.radius * 2.0)):
		token_edit_requested.emit(null, created)
		selected_token_id = created.id
		queue_redraw()


func _update_token_drag(position: Vector2) -> void:
	if _token_drag_before == null:
		return
	var target: Vector2 = _token_drag_before.position + position - _token_drag_start
	_token_drag_preview.position = AtlasGridSnap.point(map.grid, target) if snap_to_grid else target
	queue_redraw()


func _finish_token_drag(position: Vector2) -> void:
	if _token_drag_before == null:
		return
	_update_token_drag(position)
	var before: AtlasToken = _token_drag_before
	var after: AtlasToken = _token_drag_preview
	_token_drag_before = null
	_token_drag_preview = null
	if before.position != after.position:
		token_edit_requested.emit(before, after)
	queue_redraw()
	interaction_finished.emit()


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
	if tool == Tool.FOG:
		for region: AtlasFogRegion in floor.fog_regions:
			item.draw_rect(region.bounds, Color(0.2, 0.9, 0.85, 0.16) if region.reveal else Color(1, 0.3, 0.3, 0.2))
			item.draw_rect(region.bounds, Color("#63d9d1") if region.reveal else Color("#f07474"), false, 1.0 / camera_zoom)
		if _fog_drag_active:
			var candidate: Rect2 = Rect2(_fog_start, _fog_end - _fog_start).abs()
			item.draw_rect(candidate, Color(0.2, 0.9, 0.85, 0.27) if _fog_reveal else Color(1, 0.3, 0.3, 0.27))
			item.draw_rect(candidate, Color("#63d9d1") if _fog_reveal else Color("#f07474"), false, 2.0 / camera_zoom)
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
	var token_layer: AtlasTokenLayer = floor.layer_by_id(active_layer_id) as AtlasTokenLayer
	if tool == Tool.TOKEN and token_layer != null and token_layer.visible \
			and token_layer.opacity > 0.0 and token_layer.detail_level == presented_detail_level:
		var selected_token: AtlasToken = _token_drag_preview if _token_drag_preview != null \
			else token_layer.token_by_id(selected_token_id)
		if selected_token != null:
			item.draw_arc(selected_token.position, selected_token.radius + 4.0 / camera_zoom,
				0, TAU, 48, Color("#f9cc65"), 2.0 / camera_zoom)
	if not _polygon_vertices.is_empty():
		var guide: PackedVector2Array = _polygon_vertices.duplicate()
		guide.append(_polygon_pointer)
		if guide.size() >= 2:
			item.draw_polyline(guide, Color("#f9cc65"), 1.5 / camera_zoom, true)
		for vertex: Vector2 in _polygon_vertices:
			item.draw_circle(vertex, 3.0 / camera_zoom, Color("#f9cc65"))
	if tool == Tool.WALL_PATH and editing_target_is_presented():
		var active: AtlasObjectsLayer = floor.layer_by_id(active_layer_id) as AtlasObjectsLayer
		if active != null and _wall_selected_index >= 0 and _wall_selected_index < active.strokes.size():
			var wall: AtlasStroke = _wall_preview if _wall_preview != null else active.strokes[_wall_selected_index]
			if wall.editable_path:
				for vertex: Vector2 in wall.points:
					item.draw_circle(vertex, 4.0 / camera_zoom, Color("#4dabf2"))
		if not _wall_vertices.is_empty():
			for vertex: Vector2 in _wall_vertices:
				item.draw_circle(vertex, 3.5 / camera_zoom, Color("#f9cc65"))
	if projector_frame_active:
		_draw_projector_frame(item)
	else:
		_draw_brush_cursor(item)


## A pointer ring shows the active Brush or Eraser diameter at any zoom.
## Keep it out of authored ink/raster, captured references and saved scenes.
func _draw_brush_cursor(item: Node2D) -> void:
	if not _brush_cursor_inside or tool not in [Tool.PEN, Tool.ERASER] or not editing_target_is_presented():
		return
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	if not layer is AtlasRasterLayer or not layer.is_editable():
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
	if stroke.is_prop():
		var hash: HashingContext = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(stroke.prop_webp)
		var key: String = hash.finish().hex_encode()
		if not _prop_textures.has(key):
			var image: Image = AtlasWebPStore.decode_lossless(stroke.prop_webp, stroke.prop_size.x, stroke.prop_size.y)
			if image == null:
				return
			_prop_textures[key] = ImageTexture.create_from_image(image)
		item.draw_set_transform(stroke.points[0], stroke.prop_rotation)
		item.draw_texture_rect(_prop_textures[key], Rect2(Vector2.ZERO, stroke.prop_dimensions()), false, stroke.color)
		item.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	if stroke.is_text():
		if AtlasTextLayout.readable(stroke, camera_zoom):
			item.draw_set_transform(stroke.points[0], stroke.text_rotation)
			item.draw_multiline_string(AtlasTextLayout.font_for(stroke), Vector2.ZERO, stroke.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(stroke.width), -1, stroke.color)
			item.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	if stroke.filled:
		var interior: PackedVector2Array = stroke.points.duplicate()
		interior.remove_at(interior.size() - 1)
		item.draw_colored_polygon(interior, stroke.color)
		return
	var centers: PackedVector2Array = AtlasStrokeGeometry.centers(AtlasEditablePath.render_points(stroke) if stroke.editable_path else stroke.points)
	if centers.size() == 1:
		item.draw_circle(centers[0], stroke.width * 0.5, stroke.color, true, -1.0, true)
	elif centers.size() > 1:
		if centers.size() > 128:
			_draw_ink_mask(stroke, item)
			return
		var outlines: Array[PackedVector2Array] = AtlasStrokeGeometry.outline(centers, stroke.width)
		if outlines.size() == 1 and outlines[0].size() >= 3:
			item.draw_colored_polygon(outlines[0], stroke.color)
		else:
			# A coverage mask preserves holes and composites self-overlaps only once.
			_draw_ink_mask(stroke, item)


func _draw_ink_mask(stroke: AtlasStroke, item: Node2D) -> void:
	if not _ink_masks.has(stroke):
		var bounds: Rect2 = AtlasSelectionGeometry.stroke_bounds(stroke).grow(2.0 / camera_zoom)
		var pixels: Rect2 = Rect2(document_to_local(bounds.position), bounds.size * camera_zoom).intersection(Rect2(Vector2.ZERO, size))
		if not pixels.has_area():
			return
		pixels = Rect2(pixels.position.floor(), pixels.end.ceil() - pixels.position.floor())
		var mask: CoverageMask = CoverageMask.new()
		add_child(mask)
		mask.configure(pixels.size, camera_zoom, local_to_document(pixels.get_center()))
		var coverage: AtlasStroke = stroke.copy()
		if stroke.editable_path:
			coverage.points = AtlasEditablePath.render_points(stroke)
		mask.update_stroke(coverage, AtlasEditScope.new())
		_ink_masks[stroke] = mask
	item.draw_texture_rect(_ink_masks[stroke].texture(), _ink_masks[stroke].document_rect, false, stroke.color)


func _clear_ink_masks() -> void:
	for mask: CoverageMask in _ink_masks.values():
		mask.queue_free()
	_ink_masks.clear()
	for id: String in _layer_drawers:
		if floor != null and floor.layer_by_id(id) is AtlasObjectsLayer:
			_render_states.erase(id)


## Clear authorization captured for this unfinished Line on commit or cancel.
func _clear_line_context() -> void:
	_line_scope_at_press = null
	_line_map_at_press = ""
	_line_floor_at_press = ""
	_line_layer_at_press = ""


## Compare the current editable target and effective mask with the press-time
## copy. An unlocked mask is always an empty polygon, regardless of cell focus.
func _line_context_matches() -> bool:
	return _line_scope_at_press != null and map != null and floor != null \
		and map.id == _line_map_at_press and floor.id == _line_floor_at_press \
		and active_layer_id == _line_layer_at_press \
		and edit_scope.enabled == _line_scope_at_press.enabled \
		and edit_scope.polygon == _line_scope_at_press.polygon


## Do not allow a multi-click Polygon to silently change its target or
## eligibility mask between the first vertex and closure.
func _clear_polygon_context() -> void:
	_polygon_scope_at_start = null
	_polygon_map_at_start = null
	_polygon_floor_at_start = null
	_polygon_layer_at_start = null


func _polygon_context_matches() -> bool:
	return _polygon_scope_at_start != null and map != null and floor != null \
		and map == _polygon_map_at_start and floor == _polygon_floor_at_start \
		and floor.layer_by_id(active_layer_id) == _polygon_layer_at_start \
		and _polygon_layer_at_start.is_editable() and editing_target_is_presented() \
		and edit_scope.enabled == _polygon_scope_at_start.enabled \
		and edit_scope.polygon == _polygon_scope_at_start.polygon


func _reject_stale_polygon() -> void:
	cancel_edit()
	polygon_rejected.emit("Polygon target or edit mask changed since first vertex; nothing painted.")


func _capture_wall_context(layer: AtlasObjectsLayer) -> void:
	_wall_scope_at_start = AtlasEditScope.new(edit_scope.polygon, edit_scope.enabled)
	_wall_map_at_start = map
	_wall_floor_at_start = floor
	_wall_layer_at_start = layer


func _clear_wall_context() -> void:
	_wall_scope_at_start = null
	_wall_map_at_start = null
	_wall_floor_at_start = null
	_wall_layer_at_start = null


func _wall_context_matches() -> bool:
	return _wall_scope_at_start != null and map != null and floor != null \
		and map == _wall_map_at_start and floor == _wall_floor_at_start \
		and floor.layer_by_id(active_layer_id) == _wall_layer_at_start \
		and _wall_layer_at_start.is_editable() and editing_target_is_presented() \
		and edit_scope.enabled == _wall_scope_at_start.enabled \
		and edit_scope.polygon == _wall_scope_at_start.polygon


func _reject_stale_wall() -> void:
	cancel_edit()
	wall_rejected.emit("Wall path target or edit mask changed during editing; nothing changed.")


## Shape and wall previews follow live style controls without pointer motion.
## Freehand Brush/Eraser instead retain the style captured at gesture start.
func _refresh_shape_style() -> void:
	if tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_refresh_wall_draft()
		return
	if tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		_update_polygon_preview(_brush_cursor_local)
		return
	if _shape_kind != "LINE" or _draft_stroke == null:
		return
	_draft_stroke.color = brush_color
	_draft_stroke.width = brush_width
	_preview_dirty = true
	queue_redraw()


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
		_preview_dirty = true
		queue_redraw()
		return
	if _draft_stroke.points[-1].distance_squared_to(point) >= 0.01:
		_draft_stroke.points.append(point)
		_preview_dirty = true
	elif _preview_samples == 0:
		_preview_dirty = true
	queue_redraw()


func _process(_delta: float) -> void:
	if not _preview_dirty or _draft_stroke == null:
		return
	var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
	var samples: PackedVector2Array = _draft_stroke.points.slice(_preview_samples)
	if layer is AtlasRasterLayer:
		var result: AtlasFillResult = (_raster_brush.append(samples) if _raster_brush != null
			else AtlasRasterBrush.paint_stroke(layer, _draft_stroke, false, edit_scope))
		_preview_layer = result.layer if result.ok else null
		# Preview images mutate in their detached session; never retain old texture generations.
		_preview_textures.clear()
	_preview_samples = _draft_stroke.points.size()
	# Raster sessions mutate in place, so identity alone cannot invalidate their drawer.
	if layer is AtlasRasterLayer:
		_render_states.erase(layer.id)
	_preview_dirty = false
	queue_redraw()


func _end_freehand() -> void:
	if _capturing_freehand:
		Input.use_accumulated_input = _restore_accumulated_input
	_capturing_freehand = false
	_preview_dirty = false
	_preview_samples = 0
	_raster_brush = null
	_preview_textures.clear()
	_render_states.erase(active_layer_id)


func _clear_raster_textures() -> void:
	_raster_textures.clear()
	_preview_textures.clear()
	# Retained draw commands contain RIDs, not owning references to ImageTexture.
	# Releasing a texture requires rebuilding every drawer that used that RID.
	for id: String in _layer_drawers:
		if floor != null and floor.layer_by_id(id) is AtlasRasterLayer:
			_render_states.erase(id)


func _exit_tree() -> void:
	_end_freehand()


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


## T-013 framing mode deliberately supersedes artwork hit-testing. The frame
## is a local GM overlay; no player output is published by these operations.
func set_projector_frame_active(active: bool) -> void:
	if active == projector_frame_active:
		return
	cancel_edit()
	projector_frame_active = active and map != null
	if projector_frame_active:
		var initial_width: float = clampf(size.x * 0.7 / maxf(camera_zoom, 0.0001),
			AtlasProjectorFrame.MIN_WIDTH, AtlasProjectorFrame.MAX_WIDTH)
		projector_frame.set_view(camera_center, initial_width)
		projector_frame_changed.emit()
	_overlay.queue_redraw()


func configure_projector_output_size(dimensions: Vector2i) -> bool:
	cancel_projector_frame_drag()
	if not projector_frame.set_output_size(dimensions):
		return false
	_overlay.queue_redraw()
	projector_frame_changed.emit()
	return true


func cancel_projector_frame_drag() -> void:
	if _frame_drag == FrameDrag.NONE:
		return
	projector_frame.set_view(_frame_original_center, _frame_original_width)
	_frame_drag = FrameDrag.NONE
	_overlay.queue_redraw()


func _draw_projector_frame(item: Node2D) -> void:
	var bounds: Rect2 = projector_frame.bounds()
	var line_width: float = 2.0 / camera_zoom
	var color: Color = Color("#5ee1ff")
	item.draw_rect(bounds, Color(0.1, 0.75, 0.95, 0.08), true)
	item.draw_rect(bounds, Color(0.03, 0.08, 0.12, 0.8), false, 4.0 / camera_zoom)
	item.draw_rect(bounds, color, false, line_width)
	var handle_size: float = 10.0 / camera_zoom
	item.draw_rect(Rect2(bounds.end - Vector2.ONE * handle_size * 0.5,
		Vector2.ONE * handle_size), Color("#ffd276"))
	item.draw_line(bounds.get_center() - Vector2(7.0, 0.0) / camera_zoom,
		bounds.get_center() + Vector2(7.0, 0.0) / camera_zoom, color, line_width)
	item.draw_line(bounds.get_center() - Vector2(0.0, 7.0) / camera_zoom,
		bounds.get_center() + Vector2(0.0, 7.0) / camera_zoom, color, line_width)
	var tag: String = "GM frame · %d:%d" % [projector_frame.output_size.x, projector_frame.output_size.y]
	item.draw_string(ThemeDB.fallback_font, bounds.position + Vector2(8.0, -6.0) / camera_zoom,
		tag, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(12.0 / camera_zoom)), color)


func _handle_projector_frame_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE and _frame_drag != FrameDrag.NONE:
			cancel_projector_frame_drag()
			accept_event()
			return true
		return false
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				grab_focus()
				var position: Vector2 = local_to_document(button.position)
				var bounds: Rect2 = projector_frame.bounds()
				var handle_radius: float = 11.0 / camera_zoom
				if position.distance_to(bounds.end) <= handle_radius:
					_frame_drag = FrameDrag.RESIZE
					_frame_resize_anchor = bounds.position
				elif bounds.has_point(position):
					_frame_drag = FrameDrag.MOVE
				_frame_drag_start = position
				_frame_original_center = projector_frame.center
				_frame_original_width = projector_frame.width
				if _frame_drag != FrameDrag.NONE:
					interaction_started.emit()
			else:
				if _frame_drag != FrameDrag.NONE:
					_update_projector_frame_drag(local_to_document(button.position))
					_frame_drag = FrameDrag.NONE
					projector_frame_changed.emit()
					interaction_finished.emit()
			accept_event()
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			cancel_projector_frame_drag()
			accept_event()
			return true
		# Middle drag and wheel retain their ordinary GM navigation behavior.
		return false
	if event is InputEventMouseMotion and _frame_drag != FrameDrag.NONE:
		_update_projector_frame_drag(local_to_document(event.position))
		accept_event()
		return true
	return false


func _update_projector_frame_drag(position: Vector2) -> void:
	if _frame_drag == FrameDrag.MOVE:
		projector_frame.set_view(_frame_original_center + position - _frame_drag_start,
			_frame_original_width)
	elif _frame_drag == FrameDrag.RESIZE:
		projector_frame.resize_from_top_left(_frame_resize_anchor, position)
	_overlay.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if projector_frame_active and _handle_projector_frame_input(event):
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
		Tool.FOG:
			_fog_start = position
			_fog_end = position
			_fog_reveal = not mouse.shift_pressed
			_fog_drag_active = true
			_overlay.queue_redraw()
		Tool.TEXT:
			_begin_text_edit(position)
		Tool.TOKEN:
			_begin_token_press(position)
		Tool.POLYGON:
			_begin_polygon_vertex(mouse, position)
		Tool.WALL_PATH:
			_begin_wall_point(mouse, position)
		Tool.PEN, Tool.ERASER:
			if not editing_target_is_presented():
				return
			var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
			if not layer is AtlasRasterLayer or not layer.is_editable():
				return
			_erasing = tool == Tool.ERASER
			_restore_accumulated_input = Input.use_accumulated_input
			Input.use_accumulated_input = false
			_capturing_freehand = true
			_preview_samples = 0
			_raster_brush = AtlasRasterBrush.new(layer, brush_color, brush_width, _erasing, edit_scope)
			_stroke_left_canvas = false
			_draft_stroke = AtlasStroke.new(PackedVector2Array([position]), brush_color, brush_width)
			_append_stroke_point(mouse.position)
		Tool.LINE, Tool.RECTANGLE, Tool.ELLIPSE:
			if not editing_target_is_presented():
				return
			var layer: AtlasRasterLayer = floor.layer_by_id(active_layer_id) as AtlasRasterLayer
			if layer != null and layer.is_editable():
				_erasing = false
				_shape_kind = Tool.keys()[tool]
				if tool == Tool.LINE:
					_line_scope_at_press = AtlasEditScope.new(edit_scope.polygon, edit_scope.enabled)
					_line_map_at_press = map.id
					_line_floor_at_press = floor.id
					_line_layer_at_press = active_layer_id
				_gesture_snap = snap_to_grid
				_gesture_start = AtlasGridSnap.point(map.grid, position) if snap_to_grid else position
				_brush_cursor_local = mouse.position
				_stroke_left_canvas = false
				_draft_stroke = AtlasShapes.stroke("LINE", _gesture_start, _gesture_start, brush_color, brush_width)
				_preview_dirty = true
		Tool.MOVE:
			_begin_artwork_move(position)
		Tool.ART_SELECT:
			if not editing_target_is_presented():
				return
			var layer: AtlasLayer = floor.layer_by_id(active_layer_id)
			if not layer is AtlasObjectsLayer:
				return
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
	if not layer is AtlasObjectsLayer:
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
	if _fog_drag_active:
		_fog_end = local_to_document(mouse.position)
		var bounds: Rect2 = Rect2(_fog_start, _fog_end - _fog_start).abs()
		var reveal: bool = _fog_reveal
		_fog_drag_active = false
		_overlay.queue_redraw()
		if bounds.size.x > 0.001 and bounds.size.y > 0.001:
			fog_edit_requested.emit(bounds, reveal)
		interaction_finished.emit()
	elif _token_drag_before != null:
		_finish_token_drag(local_to_document(mouse.position))
	elif _fill_pending:
		_fill_pending = false
		fill_requested.emit()
		_preview_layer = null
		_clear_raster_textures()
		queue_redraw()
		interaction_finished.emit()
	elif tool == Tool.WALL_PATH and _wall_drag_vertex >= 0:
		_update_wall_drag(local_to_document(mouse.position))
		# Updating the preview can reject a stale gesture and clear its context.
		if _wall_drag_vertex >= 0:
			_finish_wall_drag()
	elif tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_update_wall_pointer(mouse.position)
	elif tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		# Vertices are placed by clicks; mouse release never finishes a shape.
		_update_polygon_preview(mouse.position)
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
	elif _fog_drag_active:
		_fog_end = local_to_document(motion.position)
		_overlay.queue_redraw()
	elif _token_drag_before != null:
		_update_token_drag(local_to_document(motion.position))
	elif _manipulation != Manipulation.NONE:
		_update_manipulation(local_to_document(motion.position))
	elif tool == Tool.WALL_PATH and _wall_drag_vertex >= 0:
		_update_wall_drag(local_to_document(motion.position))
	elif tool == Tool.WALL_PATH and not _wall_vertices.is_empty():
		_update_wall_pointer(motion.position)
	elif tool == Tool.POLYGON and not _polygon_vertices.is_empty():
		_update_polygon_preview(motion.position)
	elif is_editing():
		_append_stroke_point(motion.position, motion.shift_pressed, motion.alt_pressed)
	else:
		return
	accept_event()


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


## Clicking existing text reopens the same object; empty space places new text.
func _begin_text_edit(position: Vector2) -> void:
	if not editing_target_is_presented():
		return
	var layer: AtlasObjectsLayer = floor.layer_by_id(active_layer_id) as AtlasObjectsLayer
	if layer == null or not layer.is_editable():
		return
	for index: int in range(layer.strokes.size() - 1, -1, -1):
		var candidate: AtlasStroke = layer.strokes[index]
		if candidate.is_text() and AtlasTextLayout.bounds(candidate).grow(5.0 / camera_zoom).has_point(position):
			text_requested.emit(position, index)
			interaction_finished.emit()
			return
	var anchor: Vector2 = AtlasGridSnap.point(map.grid, position) if snap_to_grid else position
	text_requested.emit(anchor, -1)
	interaction_finished.emit()


## Construct and edit independently typed wall paths on the selected ink layer.
## Normal click selects an existing edge or drags its vertex. Shift+click
## inserts a vertex, Alt+click deletes one; an explicit inspector action restyles.
func _begin_wall_point(mouse: InputEventMouseButton, position: Vector2) -> void:
	if not editing_target_is_presented():
		return
	var layer: AtlasObjectsLayer = floor.layer_by_id(active_layer_id) as AtlasObjectsLayer
	if layer == null or not layer.is_editable():
		return
	if not _wall_vertices.is_empty():
		if not _wall_context_matches():
			_reject_stale_wall()
			return
		var point: Vector2 = AtlasGridSnap.point(map.grid, position) if _gesture_snap else position
		if mouse.double_click:
			_finish_wall_path(false)
			return
		if _wall_vertices.size() >= 3 and point.distance_to(_wall_vertices[0]) <= 8.0 / camera_zoom:
			_finish_wall_path(true)
			return
		if _wall_vertices.size() < AtlasEditablePath.MAX_VERTICES and point.distance_squared_to(_wall_vertices[-1]) > 0.0001:
			_wall_vertices.append(point)
			_refresh_wall_draft()
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
			_capture_wall_context(layer)
			_wall_drag_origin = position
			_wall_drag_vertex = vertex
			_wall_preview = path.copy()
		else:
			_wall_before = null
		queue_redraw()
		return
	_wall_selected_index = -1
	_wall_before = null
	_capture_wall_context(layer)
	_gesture_snap = snap_to_grid
	_wall_vertices = PackedVector2Array([AtlasGridSnap.point(map.grid, position) if _gesture_snap else position])
	_refresh_wall_draft()
	_update_wall_pointer(mouse.position)


func _refresh_wall_draft() -> void:
	if not _wall_vertices.is_empty() and not _wall_context_matches():
		_reject_stale_wall()
		return
	_wall_draft = AtlasEditablePath.make(_wall_vertices, brush_color, brush_width) if _wall_vertices.size() >= 2 else null
	queue_redraw()


func _update_wall_pointer(local_position: Vector2) -> void:
	if not _wall_vertices.is_empty() and not _wall_context_matches():
		_reject_stale_wall()
		return
	_wall_pointer = local_to_document(local_position)
	if _gesture_snap:
		_wall_pointer = AtlasGridSnap.point(map.grid, _wall_pointer)
	queue_redraw()


func _finish_wall_path(closed: bool) -> void:
	if not _wall_context_matches():
		_reject_stale_wall()
		return
	var path: AtlasStroke = AtlasEditablePath.make(_wall_vertices, brush_color, brush_width, closed)
	_wall_vertices.clear()
	_wall_draft = null
	_wall_before = null
	_clear_wall_context()
	_gesture_snap = false
	if path != null:
		path_edit_requested.emit(-1, null, path)
	queue_redraw()
	interaction_finished.emit()


func _update_wall_drag(position: Vector2) -> void:
	if _wall_drag_vertex >= 0 and not _wall_context_matches():
		_reject_stale_wall()
		return
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
	if not _wall_context_matches():
		_reject_stale_wall()
		return
	var index: int = _wall_selected_index
	var before: AtlasStroke = _wall_before
	var after: AtlasStroke = _wall_preview
	_wall_drag_vertex = -1
	_wall_before = null
	_wall_preview = null
	_clear_wall_context()
	if before != null and after != null and before.to_dict() != after.to_dict():
		path_edit_requested.emit(index, before, after)
	queue_redraw()
	interaction_finished.emit()


func _handle_wall_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE and not _wall_context_matches():
		_reject_stale_wall()
		accept_event()
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
				_refresh_wall_draft()
				_update_wall_pointer(_brush_cursor_local)
			accept_event()
		KEY_ESCAPE:
			cancel_edit()
			accept_event()


## Each click fixes a vertex. Click near the first point, double-click, Enter,
## or right-click to close. Backspace removes the last vertex; Escape cancels.
func _begin_polygon_vertex(mouse: InputEventMouseButton, position: Vector2) -> void:
	if not _polygon_vertices.is_empty() and not _polygon_context_matches():
		_reject_stale_polygon()
		return
	if not editing_target_is_presented():
		return
	var layer: AtlasRasterLayer = floor.layer_by_id(active_layer_id) as AtlasRasterLayer
	if layer == null or not layer.is_editable():
		return
	if _polygon_vertices.is_empty():
		_erasing = false
		_gesture_snap = snap_to_grid
		_polygon_scope_at_start = AtlasEditScope.new(edit_scope.polygon, edit_scope.enabled)
		_polygon_map_at_start = map
		_polygon_floor_at_start = floor
		_polygon_layer_at_start = layer
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
	if not _polygon_context_matches():
		_reject_stale_polygon()
		return
	_polygon_pointer = local_to_document(local_position)
	if _gesture_snap:
		_polygon_pointer = AtlasGridSnap.point(map.grid, _polygon_pointer)
	var candidates: PackedVector2Array = _polygon_vertices.duplicate()
	# Once at least three vertices are fixed, Enter/close commits exactly this
	# preview; the pointer's next edge remains a gold guide, not a phantom fill.
	if candidates.size() < 3 and candidates[-1].distance_squared_to(_polygon_pointer) > 0.0001:
		candidates.append(_polygon_pointer)
	var next: AtlasStroke = AtlasShapes.polygon(candidates, brush_color, brush_width, polygon_solid_fill)
	if next == null or _draft_stroke == null or next.points != _draft_stroke.points \
			or next.filled != _draft_stroke.filled or next.color != _draft_stroke.color or next.width != _draft_stroke.width:
		_draft_stroke = next
		_preview_dirty = next != null
		if next == null:
			_preview_layer = null
			_preview_textures.clear()
			_render_states.erase(active_layer_id)
	queue_redraw()
