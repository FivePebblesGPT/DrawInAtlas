extends Control
## Bounded framebuffer rendering and native mouse gestures, without Atlas UI types.

signal gesture_started()
signal gesture_committed(result: DrawingResult)
signal selection_changed(area: Rect2i)
signal canvas_error(message: String)
signal view_changed()
## Used by the shared workspace status bar; never creates history or content edits.
signal cursor_moved()
signal text_requested(pixel: Vector2i)

var document: DrawingDocument:
	set(value):
		if (session != null or _move_preview != null) and value != document:
			cancel_gesture()
		if document != value:
			set_selection_mask(null, false)
		document = value
		queue_redraw()
var layer_id: String = "":
	set(value):
		if (session != null or _move_preview != null) and value != layer_id:
			cancel_gesture()
		layer_id = value
var tool: String = "Brush":
	set(value):
		if (session != null or _move_preview != null) and value != tool:
			cancel_gesture()
		tool = value
var color_rgba: int = 0xff202020
var brush_width: float = 3.0
## Workspace presentation, independent of the unbounded document. Atlas hosts
## leave image_bounds empty unless they explicitly want an authoring frame.
var image_bounds: Rect2i = Rect2i()
var show_grid: bool = false
var snap_to_grid: bool = false
var grid_spacing: int = 8
var grid_origin: Vector2i = Vector2i.ZERO
var _checker_texture: ImageTexture
var zoom: float = 4.0:
	set(value):
		if (session != null or _move_preview != null) and value != zoom:
			cancel_gesture()
		zoom = value
var camera: Vector2 = Vector2.ZERO
## Legacy rectangular projection for hosts and history. The actual mask may
## contain islands/holes; assigning selected directly replaces it by a rect.
var selection_mask: DrawingSelection = DrawingSelection.new()
var selection_mode: String = "Replace"
var _updating_selection_bounds: bool = false
var selected: Rect2i = Rect2i():
	set(value):
		selected = value
		if not _updating_selection_bounds:
			selection_mask.set_rectangle(value)
var _marquee: Rect2i = Rect2i()
var _marquee_dragged: bool = false
var _marquee_start_screen: Vector2 = Vector2.ZERO
var _move_preview: DrawingEditSession
var _move_target: Vector2i = Vector2i.ZERO
var _move_preview_offset: Vector2i = Vector2i.ZERO
## Object Editor authoring guides only. Neither changes raster pixels nor clips
## the infinite sparse canvas; the origin and optional bounds are source-local.
var asset_origin: Vector2i = Vector2i.ZERO
var asset_bounds: Rect2i = Rect2i()
var session: DrawingEditSession
var dragging: bool = false
var panning: bool = false
var selecting: bool = false
var moving: bool = false
var gesture_start: Vector2i
var last_mouse: Vector2 = Vector2.ZERO
## Latest delivered canvas-relative input, including synthetic native test events.
var last_pointer_position: Vector2 = Vector2.ZERO
var pointer_known: bool = false
## Display tiles are source-space aligned, independent of camera and zoom.
## The bounded LRU owns every retained texture; a draw call need not create any.
const DISPLAY_TILE_SIZE: int = 128
const MAX_DISPLAY_TILES: int = 144
const MAX_OCCUPANCY_ENTRIES: int = 40000
var _display_tiles: Dictionary[String, Dictionary] = {}
## Keep evicted draw-command RIDs alive through the submitted frame. This is
## transient and separate from the bounded retained LRU (see instrumentation).
var _frame_references: Array[ImageTexture] = []
var _cache_document: DrawingDocument
var _cache_revision: int = -1
var _cache_source_epoch: int = -1
var _cache_access: int = 0
var _occupied_display_tiles: Dictionary[String, bool] = {}
var _occupancy_unknown: bool = false
var last_frame_metrics: Dictionary[String, Variant] = {}
var _last_frame_submit_us: int = 0
var _reported_render_errors: Dictionary[String, bool] = {}
## Motion handlers append raw canvas-source positions only. Bounded pieces are
## staged on idle frames, keeping the input path free of long raster sweeps.
const MAX_SEGMENTS_PER_FRAME: int = 12
const MAX_SEGMENT_LENGTH: float = 24.0
var _samples: Array[Vector2] = []
var _sample_times_us: Array[int] = []
var _sample_index: int = 0
var _target_arrival_us: int = 0
var _segment_target: Vector2 = Vector2.ZERO
var _has_segment_target: bool = false
var _staged_position: Vector2 = Vector2.ZERO
var _finish_requested: bool = false
var _stroke_color: int = 0
var _stroke_width: float = 1.0
var _stroke_erase: bool = false
var _previous_accumulated_input: bool = true
var _owns_accumulated_input: bool = false
var _metrics: Dictionary[String, Variant] = {}
var last_gesture_metrics: Dictionary[String, Variant] = {}


## Replace the channel without collapsing its boolean operations into bounds.
func set_selection_mask(value: DrawingSelection, notify: bool = true) -> void:
	selection_mask = value.detached_copy() if value != null else DrawingSelection.new()
	_updating_selection_bounds = true
	selected = selection_mask.bounds if selection_mask.enabled else Rect2i()
	_updating_selection_bounds = false
	queue_redraw()
	if notify:
		selection_changed.emit(selected)


func clear_selection() -> void:
	set_selection_mask(null)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	set_process_input(true)
	set_process(true)
	var checker: Image = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in range(32):
		for x: int in range(32):
			checker.set_pixel(x, y, Color8(207, 211, 218) if ((x / 16 + y / 16) % 2 == 0) else Color8(164, 170, 180))
	_checker_texture = ImageTexture.create_from_image(checker)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _exit_tree() -> void:
	cancel_gesture()
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _restore_input_accumulation() -> void:
	if _owns_accumulated_input:
		Input.use_accumulated_input = _previous_accumulated_input
		_owns_accumulated_input = false


func _on_frame_post_draw() -> void:
	last_frame_metrics["post_draw_us"] = Time.get_ticks_usec()
	if session != null and int(_metrics.get("first_preview_submit_us", 0)) > 0 \
			and int(_metrics.get("first_frame_post_draw_us", 0)) == 0:
		_metrics["first_frame_post_draw_us"] = Time.get_ticks_usec()


func source_position(position: Vector2) -> Vector2:
	var local: Vector2 = (position - size * 0.5) / zoom + camera
	if snap_to_grid and grid_spacing > 0:
		var snapped: Vector2i = position_to_pixel(position)
		return Vector2(snapped) + Vector2(0.5, 0.5)
	return local


func position_to_pixel(position: Vector2) -> Vector2i:
	var local: Vector2 = (position - size * 0.5) / zoom + camera
	if snap_to_grid and grid_spacing > 0:
		local = DrawingSnap.point(local, Vector2(grid_spacing, grid_spacing),
			Vector2(grid_origin), PackedFloat32Array(), PackedFloat32Array(),
			PackedVector2Array(), float(grid_spacing) * 0.5)
	return Vector2i(floori(local.x), floori(local.y))


func pixel_to_position(pixel: Vector2) -> Vector2:
	return (pixel - camera) * zoom + size * 0.5


## Source-space occupancy means a sparse document at 25% zoom does not
## allocate thousands of fully transparent textures. If the occupancy index
## would exceed its cap, conservatively render instead of omitting content.
func _mark_occupied(area: Rect2i) -> void:
	if _occupancy_unknown or not area.has_area():
		return
	var start_x: int = DrawingDocument.TILES.floor_div(area.position.x, DISPLAY_TILE_SIZE)
	var start_y: int = DrawingDocument.TILES.floor_div(area.position.y, DISPLAY_TILE_SIZE)
	var end_x: int = DrawingDocument.TILES.floor_div(area.end.x - 1, DISPLAY_TILE_SIZE)
	var end_y: int = DrawingDocument.TILES.floor_div(area.end.y - 1, DISPLAY_TILE_SIZE)
	if (end_x - start_x + 1) * (end_y - start_y + 1) > MAX_OCCUPANCY_ENTRIES:
		_occupancy_unknown = true
		_occupied_display_tiles.clear()
		return
	for y: int in range(start_y, end_y + 1):
		for x: int in range(start_x, end_x + 1):
			_occupied_display_tiles["%d,%d" % [x, y]] = true
			if _occupied_display_tiles.size() > MAX_OCCUPANCY_ENTRIES:
				_occupancy_unknown = true
				_occupied_display_tiles.clear()
				return


func _rebuild_occupancy() -> void:
	_occupied_display_tiles.clear()
	_occupancy_unknown = false
	var visible: Array[String] = []
	DrawingRenderer._collect_visible(document, DrawingDocument.ROOT_ID, visible)
	for node_id: String in visible:
		var metadata: Dictionary = document.node_metadata(node_id)
		if metadata["kind"] == DrawingLayerNode.TEXT:
			var text_node: DrawingLayerNode = document.inspect_node(node_id)
			if text_node.text_element != null:
				var measured: DrawingResult = DrawingTextRaster.bounds(text_node.text_element)
				if not measured.ok:
					_occupancy_unknown = true
					_occupied_display_tiles.clear()
					return
				_mark_occupied(measured.value as Rect2i)
		else:
			for tile_key: String in document.tile_keys(node_id):
				var coords: PackedStringArray = tile_key.split(",")
				if coords.size() != 2:
					_occupancy_unknown = true
					_occupied_display_tiles.clear()
					return
				var stride: int = document.tile_stride
				var world_x: int = int(coords[0]) * stride
				var world_y: int = int(coords[1]) * stride
				if absi(world_x) >= 1073741824 or absi(world_y) >= 1073741824:
					_occupancy_unknown = true
					_occupied_display_tiles.clear()
					return
				_mark_occupied(Rect2i(world_x, world_y, stride, stride))
		if _occupancy_unknown:
			return


func _sync_display_cache() -> void:
	var rebuild_occupancy: bool = false
	if _cache_document != document:
		_cache_document = document
		_cache_revision = -1
		_cache_source_epoch = -1
		_display_tiles.clear()
		_reported_render_errors.clear()
	if _cache_source_epoch != document.display_source_epoch:
		_display_tiles.clear()
		_cache_source_epoch = document.display_source_epoch
		_cache_revision = -1
	if _cache_revision == document.revision:
		return
	if _cache_revision < 0:
		rebuild_occupancy = true
	else:
		var changed: Dictionary = document.display_changes_since(_cache_revision)
		if changed["full"]:
			_display_tiles.clear()
			rebuild_occupancy = true
		else:
			for region: DrawingDirtyRegion in changed["regions"]:
				# Extending the occupancy index on pixel changes is safe even
				# for erased tiles. Periodic structural changes rebuild it.
				if absi(region.x) >= 1073741824 or absi(region.y) >= 1073741824:
					_occupancy_unknown = true
					_occupied_display_tiles.clear()
				else:
					_mark_occupied(Rect2i(region.x, region.y, region.width, region.height))
				for key: String in _display_tiles:
					var tile_area: Rect2i = _display_tiles[key]["area"] as Rect2i
					if tile_area.position.x < region.x + region.width \
						and tile_area.end.x > region.x \
						and tile_area.position.y < region.y + region.height \
						and tile_area.end.y > region.y:
						_display_tiles[key]["dirty"] = true
	_cache_revision = document.revision
	if rebuild_occupancy:
		_rebuild_occupancy()

## Retain tiles that remain in the current viewport when it exceeds the
## persistent limit. Evict off-screen entries first; render overflow entries
## transiently so the next redraw can still hit the retained in-view tiles.
## Unconditionally evicting the oldest tile churns *every* tile on each frame
## whenever a dense viewport needs MAX_DISPLAY_TILES + 1 textures.
func _reserve_display_slot(visible_tile_range: Rect2i) -> bool:
	if _display_tiles.size() < MAX_DISPLAY_TILES:
		return true
	var oldest_offscreen_key: String = ""
	var oldest_access: int = 9223372036854775807
	for key: String in _display_tiles:
		var tile_area: Rect2i = _display_tiles[key]["area"] as Rect2i
		var tile_x: int = DrawingDocument.TILES.floor_div(tile_area.position.x, DISPLAY_TILE_SIZE)
		var tile_y: int = DrawingDocument.TILES.floor_div(tile_area.position.y, DISPLAY_TILE_SIZE)
		if visible_tile_range.has_point(Vector2i(tile_x, tile_y)):
			continue
		var access: int = int(_display_tiles[key]["last_used"])
		if access < oldest_access:
			oldest_access = access
			oldest_offscreen_key = key
	if oldest_offscreen_key.is_empty():
		return false
	_display_tiles.erase(oldest_offscreen_key)
	return true


## Draw the transparency guide in fixed *screen* pixels, not source pixels.
## It is a backdrop only: sparse tiles outside this frame are still visible.
func _draw_image_backdrop() -> void:
	if not image_bounds.has_area() or _checker_texture == null:
		return
	var frame: Rect2 = Rect2(pixel_to_position(Vector2(image_bounds.position)),
		Vector2(image_bounds.size) * zoom)
	var visible: Rect2 = frame.intersection(Rect2(Vector2.ZERO, size))
	if visible.has_area():
		draw_texture_rect(_checker_texture, visible, true)


func _draw_grid_overlay() -> void:
	if not show_grid or grid_spacing < 2 or not image_bounds.has_area():
		return
	var frame: Rect2 = Rect2(pixel_to_position(Vector2(image_bounds.position)),
		Vector2(image_bounds.size) * zoom)
	var visible: Rect2 = frame.intersection(Rect2(Vector2.ZERO, size))
	if not visible.has_area():
		return
	var source_start: Vector2 = (visible.position - size * 0.5) / zoom + camera
	var source_end: Vector2 = (visible.end - size * 0.5) / zoom + camera
	# A zoomed-out canvas must never draw thousands of subpixel lines. Every
	# displayed line still falls on an actual editable grid intersection.
	var stride: int = maxi(1, ceili(9.0 / (float(grid_spacing) * zoom)))
	var step: int = grid_spacing * stride
	var first_x: int = ceili((source_start.x - grid_origin.x) / float(step))
	var first_y: int = ceili((source_start.y - grid_origin.y) / float(step))
	var end_x: int = floori((source_end.x - grid_origin.x) / float(step))
	var end_y: int = floori((source_end.y - grid_origin.y) / float(step))
	var line_color: Color = Color(0.13, 0.26, 0.35, 0.44)
	var origin_color: Color = Color(0.03, 0.48, 0.59, 0.8)
	for index: int in range(first_x, mini(first_x + 500, end_x + 1)):
		var world: int = grid_origin.x + index * step
		var x: float = pixel_to_position(Vector2(world, 0)).x
		draw_line(Vector2(x, visible.position.y), Vector2(x, visible.end.y),
			origin_color if world == grid_origin.x else line_color, 1.0)
	for index: int in range(first_y, mini(first_y + 500, end_y + 1)):
		var world: int = grid_origin.y + index * step
		var y: float = pixel_to_position(Vector2(0, world)).y
		draw_line(Vector2(visible.position.x, y), Vector2(visible.end.x, y),
			origin_color if world == grid_origin.y else line_color, 1.0)


func _draw() -> void:
	_frame_references.clear()
	var draw_start: int = Time.get_ticks_usec()
	var metrics: Dictionary[String, Variant] = {"zoom": zoom, "tiles_visible": 0,
		"cache_hits": 0, "tiles_composited": 0, "source_pixels_rendered": 0,
		"visible_layer_plan_builds": 0,
		"textures_created": 0, "textures_updated": 0, "textures_transient": 0,
		"bytes_uploaded": 0,
		"compose_cpu_us": 0, "texture_cpu_us": 0, "empty_skipped": 0,
		"cache_limit_bytes": MAX_DISPLAY_TILES * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4}
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.16, 0.18))
	if document == null or size.x <= 0 or size.y <= 0 or zoom <= 0:
		last_frame_metrics = metrics
		return
	_draw_image_backdrop()
	_sync_display_cache()
	var left_top: Vector2i = Vector2i(floori(camera.x - size.x / zoom * 0.5),
		floori(camera.y - size.y / zoom * 0.5))
	var dimensions: Vector2i = Vector2i(ceili(size.x / zoom) + 2, ceili(size.y / zoom) + 2)
	var start_x: int = DrawingDocument.TILES.floor_div(left_top.x, DISPLAY_TILE_SIZE)
	var start_y: int = DrawingDocument.TILES.floor_div(left_top.y, DISPLAY_TILE_SIZE)
	var end_x: int = DrawingDocument.TILES.floor_div(left_top.x + dimensions.x - 1, DISPLAY_TILE_SIZE)
	var end_y: int = DrawingDocument.TILES.floor_div(left_top.y + dimensions.y - 1, DISPLAY_TILE_SIZE)
	var visible_tiles: Rect2i = Rect2i(start_x, start_y,
		end_x - start_x + 1, end_y - start_y + 1)
	# Resolve visible layers lazily: an idle redraw consisting entirely of
	# cached texture hits must not traverse the document tree at all.
	var visible_plan: Dictionary = {}
	var preview_session: DrawingEditSession = session if session != null else _move_preview
	for y: int in range(start_y, end_y + 1):
		for x: int in range(start_x, end_x + 1):
			metrics["tiles_visible"] = int(metrics["tiles_visible"]) + 1
			var key: String = "%d,%d" % [x, y]
			var area: Rect2i = Rect2i(x * DISPLAY_TILE_SIZE, y * DISPLAY_TILE_SIZE,
				DISPLAY_TILE_SIZE, DISPLAY_TILE_SIZE)
			var preview_stamp: int = preview_session.preview_stamp_for_area(area) if preview_session != null else 0
			if not _occupancy_unknown and not _occupied_display_tiles.has(key) and preview_stamp == 0:
				metrics["empty_skipped"] = int(metrics["empty_skipped"]) + 1
				continue
			_cache_access += 1
			var entry: Dictionary = _display_tiles.get(key, {})
			var preview_owner: DrawingEditSession = preview_session if preview_stamp > 0 else null
			if not entry.is_empty() and not bool(entry["dirty"]) \
					and int(entry["preview_stamp"]) == preview_stamp \
					and entry["preview_owner"] == preview_owner:
				metrics["cache_hits"] = int(metrics["cache_hits"]) + 1
			else:
				if visible_plan.is_empty():
					visible_plan = DrawingRenderer.prepare_visible_layers(document)
					metrics["visible_layer_plan_builds"] = int(metrics["visible_layer_plan_builds"]) + 1
				var start_compose: int = Time.get_ticks_usec()
				var composite: DrawingResult = DrawingRenderer.render(document, area,
					0, 0, 1048576, preview_session, visible_plan)
				metrics["compose_cpu_us"] = int(metrics["compose_cpu_us"]) + Time.get_ticks_usec() - start_compose
				if not composite.ok or composite.code == "GLYPH_FALLBACK":
					if not _reported_render_errors.has(composite.code):
						_reported_render_errors[composite.code] = true
						canvas_error.emit(composite.message)
					if not composite.ok:
						continue
				var image: Image = composite.value as Image
				var start_texture: int = Time.get_ticks_usec()
				var retain: bool = true
				if entry.is_empty():
					retain = _reserve_display_slot(visible_tiles)
					entry = {"texture": ImageTexture.create_from_image(image)}
					metrics["textures_created"] = int(metrics["textures_created"]) + 1
					if not retain:
						metrics["textures_transient"] = int(metrics["textures_transient"]) + 1
				else:
					(entry["texture"] as ImageTexture).update(image)
					metrics["textures_updated"] = int(metrics["textures_updated"]) + 1
				metrics["texture_cpu_us"] = int(metrics["texture_cpu_us"]) + Time.get_ticks_usec() - start_texture
				metrics["bytes_uploaded"] = int(metrics["bytes_uploaded"]) + DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
				metrics["source_pixels_rendered"] = int(metrics["source_pixels_rendered"]) + DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE
				metrics["tiles_composited"] = int(metrics["tiles_composited"]) + 1
				entry["area"] = area
				entry["preview_stamp"] = preview_stamp
				entry["preview_owner"] = preview_owner
				entry["dirty"] = false
				if retain:
					_display_tiles[key] = entry
			entry["last_used"] = _cache_access
			_frame_references.append(entry["texture"] as ImageTexture)
			draw_texture_rect(entry["texture"] as ImageTexture,
				Rect2(pixel_to_position(Vector2(area.position)), Vector2(area.size) * zoom), false)
	metrics["cache_tiles"] = _display_tiles.size()
	metrics["cache_bytes_estimate"] = _display_tiles.size() * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
	metrics["frame_reference_bytes_upper_bound"] = _frame_references.size() * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
	metrics["draw_cpu_us"] = Time.get_ticks_usec() - draw_start
	metrics["submit_us"] = Time.get_ticks_usec()
	last_frame_metrics = metrics
	_last_frame_submit_us = int(metrics["submit_us"])

	_draw_grid_overlay()
	if image_bounds.has_area():
		draw_rect(Rect2(pixel_to_position(Vector2(image_bounds.position)),
			Vector2(image_bounds.size) * zoom), Color(0.92, 0.94, 0.96), false, 1.5)
	if asset_bounds.has_area():
		draw_rect(Rect2(pixel_to_position(Vector2(asset_bounds.position)),
			Vector2(asset_bounds.size) * zoom), Color(0.2, 0.8, 0.5, 0.8), false, 1.5)
	if asset_origin != Vector2i.ZERO or asset_bounds.has_area():
		var anchor: Vector2 = pixel_to_position(Vector2(asset_origin))
		draw_line(anchor + Vector2(-6, 0), anchor + Vector2(6, 0), Color(1, 0.75, 0.3), 1.0)
		draw_line(anchor + Vector2(0, -6), anchor + Vector2(0, 6), Color(1, 0.75, 0.3), 1.0)
	_draw_selection_outline()
	if selecting and _marquee_dragged:
		draw_rect(Rect2(pixel_to_position(Vector2(_marquee.position)),
			Vector2(_marquee.size) * zoom), Color(0.95, 0.8, 0.24), false, 2.0)
	if pointer_known and tool in ["Brush", "Eraser"] and Rect2(Vector2.ZERO, size).has_point(last_pointer_position):
		var radius: float = maxf(1.0, brush_width * zoom * 0.5)
		draw_arc(last_pointer_position, radius + 1.0, 0.0, TAU, 40, Color(0.05, 0.05, 0.05), 1.5)
		draw_arc(last_pointer_position, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 1.0)
	if session != null and session.change_count() > 0 and int(_metrics.get("first_preview_submit_us", 0)) == 0:
		_metrics["first_preview_submit_us"] = Time.get_ticks_usec()


## Trace the actual mask for small selections, including islands/holes.
## Large selections use a bounded fallback (outer guide plus operation rects),
## never O(number of source pixels) work for unbounded sparse documents.
func _draw_selection_outline() -> void:
	if not selection_mask.enabled or not selected.has_area():
		return
	var highlight: Color = Color(0.2, 0.65, 1.0, 0.95)
	var count: int = selected.size.x * selected.size.y
	if count <= 4096 and zoom >= 0.5:
		var edges: PackedVector2Array = PackedVector2Array()
		for y: int in range(selected.position.y, selected.end.y):
			for x: int in range(selected.position.x, selected.end.x):
				var at: Vector2i = Vector2i(x, y)
				if not selection_mask.allows(at):
					continue
				var top_left: Vector2 = pixel_to_position(Vector2(at))
				var bottom_right: Vector2 = top_left + Vector2.ONE * zoom
				if not selection_mask.allows(at + Vector2i.LEFT):
					edges.append(top_left)
					edges.append(Vector2(top_left.x, bottom_right.y))
				if not selection_mask.allows(at + Vector2i.RIGHT):
					edges.append(Vector2(bottom_right.x, top_left.y))
					edges.append(bottom_right)
				if not selection_mask.allows(at + Vector2i.UP):
					edges.append(top_left)
					edges.append(Vector2(bottom_right.x, top_left.y))
				if not selection_mask.allows(at + Vector2i.DOWN):
					edges.append(Vector2(top_left.x, bottom_right.y))
					edges.append(bottom_right)
		if not edges.is_empty():
			draw_multiline(edges, highlight, 1.5)
		return
	draw_rect(Rect2(pixel_to_position(Vector2(selected.position)),
		Vector2(selected.size) * zoom), highlight, false, 1.5)
	# Disclose known add/subtract/intersect contours even when the exact
	# channel is too big to trace this frame. The crop/holes are never
	# simulated by a filled bounding-box overlay.
	for op: Dictionary in selection_mask._operations:
		var region: Rect2i = op["rect"] as Rect2i
		var accent: Color = Color(1.0, 0.47, 0.4, 0.85) if op["mode"] == "Subtract" \
			else Color(0.35, 1.0, 0.7, 0.85)
		draw_rect(Rect2(pixel_to_position(Vector2(region.position)),
			Vector2(region.size) * zoom), accent, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		last_pointer_position = button.position
		pointer_known = true
		cursor_moved.emit()
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var before: Vector2 = (button.position - size * 0.5) / zoom + camera
				zoom = clampf(zoom * (1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.25, 24.0)
				camera = before - (button.position - size * 0.5) / zoom
				queue_redraw()
				view_changed.emit()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE or (tool == "Pan" and button.button_index == MOUSE_BUTTON_LEFT):
			if button.pressed and session != null:
				cancel_gesture()
			panning = button.pressed
			last_mouse = button.position
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				start_gesture(button.position)
			else:
				finish_gesture(button.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		last_pointer_position = motion.position
		pointer_known = true
		if panning:
			camera -= (motion.position - last_mouse) / zoom
			last_mouse = motion.position
			queue_redraw()
			view_changed.emit()
		elif dragging:
			update_gesture(motion.position)
		cursor_moved.emit()
		if tool in ["Brush", "Eraser"]:
			queue_redraw()
		accept_event()


## Canvas exit is not a paint cancellation: raw viewport events outside the
## Control continue a captured stroke, including its eventual button release.
func _input(event: InputEvent) -> void:
	if session == null and not (dragging and (selecting or moving)):
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE:
			cancel_gesture()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if dragging and not get_global_rect().has_point(motion.position):
			update_gesture(get_global_transform().affine_inverse() * motion.position)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if dragging and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed \
				and not get_global_rect().has_point(button.position):
			finish_gesture(get_global_transform().affine_inverse() * button.position)


func _process(_delta: float) -> void:
	if session != null:
		if document == null or document.revision != session.expected_revision:
			cancel_gesture()
			return
		_drain_segments(MAX_SEGMENTS_PER_FRAME)
	if moving and _move_target != _move_preview_offset:
		_stage_move_preview(_move_target)
	if _move_preview != null and document.revision != _move_preview.expected_revision:
		cancel_gesture()


func start_gesture(position: Vector2) -> void:
	if document == null or session != null:
		return
	gesture_start = position_to_pixel(position)
	grab_focus()
	if tool == "Text":
		text_requested.emit(gesture_start)
		return
	dragging = true
	selecting = tool == "Select"
	moving = tool == "Move"
	if selecting or moving:
		if selecting:
			_marquee_start_screen = position
			_marquee = Rect2i()
			_marquee_dragged = false
		if moving:
			_move_target = Vector2i.ZERO
			_move_preview_offset = Vector2i.ZERO
			gesture_started.emit()
		return
	if tool not in ["Brush", "Eraser"]:
		dragging = false
		return
	var result: DrawingResult = document.begin_edit(layer_id, document.revision)
	if not result.ok:
		canvas_error.emit(result.message)
		dragging = false
		return
	session = result.value as DrawingEditSession
	# Avoid Godot combining OS motion events during a captured paint gesture.
	# This global option must be restored on all commit/cancel/exit paths.
	_previous_accumulated_input = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_owns_accumulated_input = true
	_stroke_color = color_rgba
	_stroke_width = brush_width
	_stroke_erase = tool == "Eraser"
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	_has_segment_target = false
	_finish_requested = false
	_staged_position = source_position(position)
	_metrics = {"down_us": Time.get_ticks_usec(), "first_stage_us": 0,
		"first_preview_submit_us": 0, "first_frame_post_draw_us": 0,
		"release_us": 0, "commit_us": 0, "samples_received": 0,
		"segments_staged": 0, "stage_cpu_us": 0, "max_pending": 0,
		"sample_to_stage_us": []}
	gesture_started.emit()
	_enqueue_sample(_staged_position)
	# A stationary dab does not wait for the first motion or mouse-up event.
	_drain_segments(1)


func update_gesture(position: Vector2) -> void:
	if not dragging:
		return
	var current: Vector2i = position_to_pixel(position)
	if selecting:
		if position.distance_to(_marquee_start_screen) >= 4.0:
			_marquee_dragged = true
			_marquee = Rect2i(Vector2i(mini(gesture_start.x, current.x), mini(gesture_start.y, current.y)),
				Vector2i(absi(current.x - gesture_start.x) + 1, absi(current.y - gesture_start.y) + 1))
		queue_redraw()
	elif moving:
		_move_target = current - gesture_start
	elif session != null:
		_enqueue_sample(source_position(position))


func paint_to(point: Vector2i) -> void:
	if session != null:
		_enqueue_sample(Vector2(point) + Vector2(0.5, 0.5))


func _enqueue_sample(position: Vector2) -> void:
	if session == null or _finish_requested:
		return
	_samples.append(position)
	_sample_times_us.append(Time.get_ticks_usec())
	_metrics["samples_received"] = int(_metrics["samples_received"]) + 1
	_metrics["max_pending"] = maxi(int(_metrics["max_pending"]), _samples.size() - _sample_index)


func _drain_segments(budget: int) -> void:
	if session == null:
		return
	var changed: bool = false
	for index: int in range(budget):
		if not _has_segment_target:
			if _sample_index == _samples.size():
				break
			_segment_target = _samples[_sample_index]
			_target_arrival_us = _sample_times_us[_sample_index]
			_sample_index += 1
			_has_segment_target = true
		var next: Vector2 = _staged_position.move_toward(_segment_target, MAX_SEGMENT_LENGTH)
		var start_us: int = Time.get_ticks_usec()
		var stage: DrawingResult = session.paint_path(PackedVector2Array([next]),
			_stroke_color, _stroke_width, _stroke_erase,
			selection_mask if selection_mask.enabled else null)
		_metrics["stage_cpu_us"] = int(_metrics["stage_cpu_us"]) + Time.get_ticks_usec() - start_us
		if not stage.ok:
			canvas_error.emit(stage.message)
			cancel_gesture()
			return
		if int(_metrics["first_stage_us"]) == 0:
			_metrics["first_stage_us"] = Time.get_ticks_usec()
		_metrics["segments_staged"] = int(_metrics["segments_staged"]) + 1
		_staged_position = next
		changed = true
		if _staged_position == _segment_target:
			var arrival_to_stage: Array = _metrics["sample_to_stage_us"] as Array
			arrival_to_stage.append(maxi(0, Time.get_ticks_usec() - _target_arrival_us))
			_has_segment_target = false
	if _sample_index == _samples.size():
		_samples.clear()
		_sample_times_us.clear()
		_sample_index = 0
	if changed:
		queue_redraw()
	if _finish_requested and _samples.is_empty() and not _has_segment_target:
		_commit_stroke()


func _commit_stroke() -> void:
	if session == null:
		return
	var active: DrawingEditSession = session
	session = null
	if active.change_count() > 0:
		_publish(active.commit())
	else:
		active.cancel()
	_metrics["commit_us"] = Time.get_ticks_usec()
	last_gesture_metrics = _metrics.duplicate(true)
	_restore_input_accumulation()
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	_has_segment_target = false
	_finish_requested = false
	queue_redraw()


## Explicit abort, including Esc/tool/layer/document/zoom changes. No history.
func cancel_gesture() -> void:
	if session != null:
		session.cancel()
		session = null
	if _move_preview != null:
		_move_preview.cancel()
		_move_preview = null
	dragging = false
	selecting = false
	moving = false
	_marquee_dragged = false
	_move_target = Vector2i.ZERO
	_move_preview_offset = Vector2i.ZERO
	_finish_requested = false
	_restore_input_accumulation()
	_has_segment_target = false
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	queue_redraw()


## The document remains immutable until release. The composited renderer reads
## these detached source-clear/target-paste pixels at the correct layer depth.
func _stage_move_preview(offset: Vector2i) -> void:
	if _move_preview != null:
		_move_preview.cancel()
		_move_preview = null
	_move_preview_offset = offset
	if not selected.has_area() or offset == Vector2i.ZERO or document == null:
		queue_redraw()
		return
	var started: DrawingResult = document.begin_edit(layer_id, document.revision)
	if not started.ok:
		canvas_error.emit(started.message)
		queue_redraw()
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var staged: DrawingResult = DrawingClipboard.move_selection(edit, selected, offset, selection_mask)
	if not staged.ok:
		edit.cancel()
		canvas_error.emit(staged.message)
	else:
		_move_preview = edit
	queue_redraw()


func finish_gesture(position: Vector2) -> void:
	if not dragging:
		return
	if selecting:
		update_gesture(position)
		if _marquee_dragged:
			var next: DrawingSelection = selection_mask.detached_copy()
			if next.combine_rectangle(_marquee, selection_mode):
				set_selection_mask(next)
			else:
				canvas_error.emit("Selection operation limit reached")
		elif selection_mask.enabled and not selection_mask.allows(gesture_start):
			clear_selection()
	elif moving:
		var displacement: Vector2i = position_to_pixel(position) - gesture_start
		if displacement != _move_preview_offset:
			_stage_move_preview(displacement)
		if _move_preview != null and displacement != Vector2i.ZERO:
			var edit: DrawingEditSession = _move_preview
			_move_preview = null
			if edit.change_count() > 0:
				var committed: DrawingResult = edit.commit()
				if committed.ok:
					set_selection_mask(selection_mask.translated(displacement), false)
				_publish(committed)
			else:
				edit.cancel()
		elif _move_preview != null:
			_move_preview.cancel()
			_move_preview = null
	else:
		_enqueue_sample(source_position(position))
		_metrics["release_us"] = Time.get_ticks_usec()
		_finish_requested = true
		# Finish small clicks synchronously; long queued strokes are drained
		# across frames without blocking the input loop.
		_drain_segments(MAX_SEGMENTS_PER_FRAME)
	dragging = false
	selecting = false
	moving = false
	_marquee_dragged = false
	_move_target = Vector2i.ZERO
	_move_preview_offset = Vector2i.ZERO
	queue_redraw()

func _publish(result: DrawingResult) -> void:
	if result.ok:
		gesture_committed.emit(result)
	else:
		canvas_error.emit(result.message)
