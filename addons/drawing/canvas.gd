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
		if (session != null or dragging or _floating_source_selection != null) and value != document:
			cancel_gesture()
			canvas_error.emit("Stroke cancelled because the document changed")
		if document != value:
			set_selection_mask(null, false)
		document = value
		queue_redraw()
var layer_id: String = "":
	set(value):
		if (session != null or dragging or _floating_source_selection != null) and value != layer_id:
			cancel_gesture()
			canvas_error.emit("Stroke cancelled because the layer changed")
		layer_id = value
var tool: String = "Brush":
	set(value):
		# Once released, queued source-space samples and frozen brush settings
		# outlive a toolbar change (including selecting Pan).
		if ((session != null and _stroke_phase == StrokePhase.CAPTURING) or dragging \
				or _floating_source_selection != null) and value != tool:
			cancel_gesture()
			canvas_error.emit("Gesture cancelled because the tool changed during capture")
		tool = value
var color_rgba: int = 0xff202020
var brush_width: float = 3.0
## Explicit opt-in until coverage parity and owner-device profiling pass.
## "Hokusai" loads an actual bundled MyPaint .myb; "NativeHard" accelerates
## the legacy hard shape while retaining document-owned alpha/history.
var brush_backend: String = "Legacy"
var brush_preset: String = "hard"
const BUNDLED_PRESETS: Dictionary = {
    "hard": "res://addons/drawing/brushes/hard_round.myb",
    "soft": "res://addons/drawing/brushes/soft.myb",
    "ink": "res://addons/drawing/brushes/ink.myb",
    "airbrush": "res://addons/drawing/brushes/airbrush.myb",
}
## Workspace presentation, independent of the unbounded document. Atlas hosts
## leave image_bounds empty unless they explicitly want an authoring frame.
var image_bounds: Rect2i = Rect2i():
	set(value):
		if value != image_bounds and session != null:
			cancel_gesture()
			canvas_error.emit("Stroke cancelled because the image bounds changed")
		image_bounds = value
		queue_redraw()
## Only the standalone workspace enables this. Atlas can show a bounded guide
## without changing its intentionally unbounded authoring surface.
var clip_strokes_to_image_frame: bool = false:
	set(value):
		# Clipping is an edit-authorization policy, not a visual guide. A
		# queued Brush/Eraser stroke must not outlive a host policy change.
		if value != clip_strokes_to_image_frame and session != null:
			cancel_gesture()
			canvas_error.emit("Stroke cancelled because image clipping changed")
		clip_strokes_to_image_frame = value
var _stroke_clip: Rect2i = Rect2i()
## A stroke uses the exact mask present on pointer-down, not a later edit
## region that happens to share the same enclosing rectangle.
var _stroke_selection: DrawingSelection
var _native_brush: Object
var _active_brush_backend: String = "Legacy"
var show_grid: bool = false
## Pixel boundaries appear automatically when individual pixels become large.
var show_pixel_grid: bool = true
## A stroke/marquee/move drag must not mix two different input coordinate grids.
## Guide visibility is presentation-only and never cancels a gesture.
var snap_to_grid: bool = false:
	set(value):
		if value != snap_to_grid:
			_cancel_on_effective_snap_change()
		snap_to_grid = value
var grid_spacing: int = 8:
	set(value):
		if value != grid_spacing and snap_to_grid:
			_cancel_on_effective_snap_change()
		grid_spacing = value
var grid_origin: Vector2i = Vector2i.ZERO:
	set(value):
		if value != grid_origin and snap_to_grid:
			_cancel_on_effective_snap_change()
		grid_origin = value
var _checker_texture: ImageTexture
var zoom: float = 4.0:
	set(value):
		if value != zoom:
			# A released stroke no longer samples screen coordinates: viewport
			# navigation must never discard its already queued source positions.
			if (session != null and _stroke_phase == StrokePhase.CAPTURING) \
					or dragging or _floating_source_selection != null:
				cancel_gesture()
				canvas_error.emit("Gesture cancelled because zoom changed during capture")
		zoom = value
## Source coordinates depend on camera. Programmatic host pans during a held
## Brush/Eraser or marquee/Move drag must not splice two viewport mappings
## into one gesture. Idle panning and equivalent assignments remain harmless.
var camera: Vector2 = Vector2.ZERO:
	set(value):
		if value != camera and ((session != null and _stroke_phase == StrokePhase.CAPTURING) \
				or (dragging and (selecting or moving))):
			cancel_gesture()
			canvas_error.emit("Gesture cancelled because the camera moved during capture")
		camera = value
## Legacy rectangular projection for hosts and history. The actual mask may
## contain islands/holes; assigning selected directly replaces it by a rect.
var selection_mask: DrawingSelection = DrawingSelection.new()
var selection_mode: String = "Replace"
var _updating_selection_bounds: bool = false
var selected: Rect2i = Rect2i():
	set(value):
		if not _updating_selection_bounds and _floating_source_selection != null:
			cancel_gesture()
		selected = value
		if not _updating_selection_bounds:
			# Direct legacy rectangle writes must respect the same live-stroke
			# authorization boundary as set_selection_mask().
			var next_mask: DrawingSelection = DrawingSelection.new()
			next_mask.set_rectangle(value)
			_cancel_stroke_if_selection_changed(next_mask)
			selection_mask.set_rectangle(value)
			_mask_outline_cache.clear()
			_mask_outline_window = Rect2i()
var _marquee: Rect2i = Rect2i()
var _marquee_dragged: bool = false
var _marquee_start_screen: Vector2 = Vector2.ZERO
var _move_preview: DrawingEditSession
var _move_capture: DrawingClipboard
var last_move_metrics: Dictionary[String, Variant] = {}
var move_profile_samples: Array[Dictionary] = []
## Cached source-coordinate contour tiles only for explicit pixel masks.
## Expression-only masks are traced using cheap row intervals each frame.
const MASK_OUTLINE_TILE: int = 64
const MASK_OUTLINE_TILES_PER_FRAME: int = 4
const MAX_MASK_OUTLINE_CACHE: int = 4096
var _mask_outline_cache: Dictionary[Vector2i, PackedVector2Array] = {}
var _mask_outline_window: Rect2i = Rect2i()
var _move_target: Vector2i = Vector2i.ZERO
var _move_target_received_us: int = 0
var _move_preview_offset: Vector2i = Vector2i.ZERO
## A floating selected-pixel Move retains its *original* mask and source
## revision across multiple drags. The shifted mask is display context only:
## every preview is rebuilt against the same immutable source until Drop.
var _floating_source_selection: DrawingSelection
var _floating_source_revision: int = -1
var _floating_offset: Vector2i = Vector2i.ZERO
var _move_drag_base: Vector2i = Vector2i.ZERO
var _floating_active: bool = false
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
## Cursor/overlay redraws can happen without a detached pixel changing. Retain
## only the last bounded visible preview index; it is owned by this Canvas and
## never returned to external callers for mutation. Source edits advance the
## session epoch, and navigation changes the visible tile rectangle.
var _preview_index_owner: DrawingEditSession
var _preview_index_epoch: int = -1
var _preview_index_revision: int = -1
var _preview_index_window: Rect2i = Rect2i()
var _preview_index_result: Dictionary = {}
var _preview_index_reused: bool = false
var _last_frame_submit_us: int = 0
var _reported_render_errors: Dictionary[String, bool] = {}
## Motion handlers append raw canvas-source positions only. Bounded pieces are
## staged on idle frames, keeping the input path free of long raster sweeps.
## Do not let an arbitrary 12-segment cap leave hundreds of frames of backlog
## after release. Batch consecutive swept segments in one edit transaction call
## and stop at a measured CPU budget, including on the release input path.
const MAX_SEGMENTS_PER_FRAME: int = 256
const MAX_SEGMENTS_PER_BATCH: int = 16
const MAX_BATCH_ESTIMATED_PIXELS: float = 8192.0
const MAX_DRAIN_CPU_US: int = 6000
const MAX_SEGMENT_LENGTH: float = 24.0
# Discard only an already-consumed prefix of a sustained stroke. A paint
# backlog may never become entirely empty while fresh OS samples arrive.
const MIN_CONSUMED_SAMPLE_COMPACTION: int = 256
## Keep exact history for short gestures and a chronological, rolling tail for
## long ones. All-time count and worst age remain exact, including evicted ages.
const MAX_SAMPLE_STAGE_LATENCIES: int = 4096
const MAX_STAGE_BATCH_LATENCIES: int = 4096
# Preserve the latest real Canvas frames for per-phase p50/p95 on owner
# hardware without retaining an unbounded history on long pointer strokes.
const MAX_FRAME_PHASE_SAMPLES: int = 1024
var _samples: Array[Vector2] = []
var _sample_times_us: Array[int] = []
var _sample_index: int = 0
var _sample_latency_write_index: int = 0
var _batch_latency_write_index: int = 0
var _frame_phase_write_index: int = 0
## A frame_post_draw signal is not guaranteed for every Canvas draw. Associate
## only the latest actually submitted stroke frame with the next callback;
## never attach a callback from a completed/cancelled session to a new stroke.
var _pending_frame_phase_sample: Dictionary = {}
var _pending_frame_phase_session: DrawingEditSession
## First successful pixel-changing stage not yet represented by a Canvas draw.
## Monotonic Godot CPU time only; never interpret as device receipt or photons.
var _unsubmitted_preview_stage_us: int = 0
var _target_arrival_us: int = 0
var _segment_target: Vector2 = Vector2.ZERO
var _has_segment_target: bool = false
var _staged_position: Vector2 = Vector2.ZERO
## Capturing uses live screen->source mapping. Draining is source-only and
## camera-independent; committing publishes one atomic history entry.
enum StrokePhase { IDLE, CAPTURING, DRAINING, COMMITTING }
var _stroke_phase: int = StrokePhase.IDLE
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
	if _floating_source_selection != null:
		cancel_gesture()
	_cancel_stroke_if_selection_changed(value)
	_assign_selection_mask(value, notify)


## Changing the edit region during a queued stroke must not combine pixels
## authorized by two different masks in one document transaction. Equivalent
## copies are harmless (e.g. a UI refresh that republishes the same mask).
func _cancel_stroke_if_selection_changed(value: DrawingSelection) -> void:
	if session == null or _stroke_selection == null:
		return
	var next_mask: DrawingSelection = value if value != null else DrawingSelection.new()
	if not _stroke_selection.same_as(next_mask):
		cancel_gesture()
		canvas_error.emit("Stroke cancelled because the selection changed")


func _assign_selection_mask(value: DrawingSelection, notify: bool = true) -> void:
	selection_mask = value.detached_copy() if value != null else DrawingSelection.new()
	_mask_outline_cache.clear()
	_mask_outline_window = Rect2i()
	_updating_selection_bounds = true
	selected = selection_mask.bounds if selection_mask.enabled else Rect2i()
	_updating_selection_bounds = false
	queue_redraw()
	if notify:
		selection_changed.emit(selected)


## Snap settings participate in source-coordinate interpretation. Discard an
## in-flight transaction rather than stage a stroke or selection with samples
## from two unrelated grids. A finished floating Move can still be adjusted
## before the next drag, and changing guide visibility is always harmless.
func _cancel_on_effective_snap_change() -> void:
	if session != null or (dragging and (selecting or moving)):
		cancel_gesture()
		canvas_error.emit("Gesture cancelled because grid snapping changed")


func clear_selection() -> void:
	set_selection_mask(null)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# The checker and independently composed RGBA tiles must never interpolate.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	set_process_input(true)
	set_process(true)
	var checker: Image = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in range(32):
		for x: int in range(32):
			checker.set_pixel(x, y, Color8(207, 211, 218) if ((x / 16 + y / 16) % 2 == 0) else Color8(164, 170, 180))
	_checker_texture = ImageTexture.create_from_image(checker)
	# Screen-coordinate texture regions can wrap the fixed 32px checker; ordinary
	# source raster tiles still use their one-to-one texture coordinates.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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
	var callback_us: int = Time.get_ticks_usec()
	last_frame_metrics["post_draw_us"] = callback_us
	_finish_pending_frame_post_draw(callback_us)
	if session != null and int(_metrics.get("first_preview_submit_us", 0)) > 0 \
			and int(_metrics.get("first_frame_post_draw_us", 0)) == 0:
		_metrics["first_frame_post_draw_us"] = Time.get_ticks_usec()


## Godot's frame_post_draw callback is a renderer-side timing witness, NOT a
## display-scanout or input-to-photon timestamp. A callback can be missing,
## repeated, or delivered after a stroke was cancelled/published. Never
## synthesize a completed callback for those frames.
func _finish_pending_frame_post_draw(callback_us: int) -> void:
	if _pending_frame_phase_sample.is_empty():
		return
	var sample: Dictionary = _pending_frame_phase_sample
	var owner: DrawingEditSession = _pending_frame_phase_session
	_pending_frame_phase_sample = {}
	_pending_frame_phase_session = null
	if owner == null or owner != session:
		return
	var end_us: int = int(sample.get("frame_end_us", 0))
	if end_us <= 0:
		return
	var recorded_us: int = maxi(end_us, callback_us)
	var delay_us: int = recorded_us - end_us
	sample["frame_post_draw_callback_us"] = recorded_us
	sample["frame_end_to_post_draw_us"] = delay_us
	_metrics["frame_post_draw_matches"] = int(_metrics.get("frame_post_draw_matches", 0)) + 1
	_metrics["max_frame_end_to_post_draw_us"] = maxi(
		int(_metrics.get("max_frame_end_to_post_draw_us", 0)), delay_us)
	if sample.has("preview_stage_completed_us"):
		var stage_to_callback_us: int = maxi(0,
			recorded_us - int(sample["preview_stage_completed_us"]))
		sample["preview_stage_to_post_draw_us"] = stage_to_callback_us
		_metrics["preview_stage_post_draw_matches"] = int(
			_metrics.get("preview_stage_post_draw_matches", 0)) + 1
		_metrics["max_preview_stage_to_post_draw_us"] = maxi(
			int(_metrics.get("max_preview_stage_to_post_draw_us", 0)),
			stage_to_callback_us)


## A single Canvas draw may represent multiple completed edit batches. Retain
## the *earliest* pixel-changing stage until its first Canvas submission.
func _mark_unsubmitted_preview_stage(stage_completed_us: int) -> void:
	if _unsubmitted_preview_stage_us == 0:
		_unsubmitted_preview_stage_us = maxi(1, stage_completed_us)


func _tag_frame_preview_stage(frame: Dictionary, frame_end_us: int) -> void:
	if _unsubmitted_preview_stage_us <= 0:
		return
	frame["preview_stage_completed_us"] = _unsubmitted_preview_stage_us
	frame["preview_stage_to_frame_end_us"] = maxi(0,
		frame_end_us - _unsubmitted_preview_stage_us)
	_unsubmitted_preview_stage_us = 0


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


## A content-only erasure may retire an entire sparse storage chunk. The
## monotonic occupancy hint would otherwise keep composing its now-empty
## display tiles and uploading transparent textures on every visit. Probe
## *metadata*, not raster pixels: visible text uses measured bounds, raster
## probes conservatively include pending lazy source chunks. If the scan is
## too large or uncertain, keep the old over-approximation instead.
func _prune_erased_display_tiles(regions: Array) -> void:
	const MAX_PRUNE_CANDIDATES: int = 256
	if _occupancy_unknown or session != null or _move_preview != null:
		return
	var candidates: Dictionary[String, Vector2i] = {}
	for region: DrawingDirtyRegion in regions:
		if region.width <= 0 or region.height <= 0:
			continue
		var start_x: int = DrawingDocument.TILES.floor_div(region.x, DISPLAY_TILE_SIZE)
		var start_y: int = DrawingDocument.TILES.floor_div(region.y, DISPLAY_TILE_SIZE)
		var end_x: int = DrawingDocument.TILES.floor_div(region.x + region.width - 1, DISPLAY_TILE_SIZE)
		var end_y: int = DrawingDocument.TILES.floor_div(region.y + region.height - 1, DISPLAY_TILE_SIZE)
		if (end_x - start_x + 1) * (end_y - start_y + 1) > MAX_PRUNE_CANDIDATES:
			return
		for y: int in range(start_y, end_y + 1):
			for x: int in range(start_x, end_x + 1):
				var key: String = "%d,%d" % [x, y]
				if _occupied_display_tiles.has(key):
					# Most paint edits leave their own source chunk present;
					# avoid walking the entire visible layer tree for these.
					var tile_area: Rect2i = Rect2i(x * DISPLAY_TILE_SIZE,
						y * DISPLAY_TILE_SIZE, DISPLAY_TILE_SIZE, DISPLAY_TILE_SIZE)
					if document.raster_may_cover(region.layer_id, tile_area.position.x,
							tile_area.position.y, tile_area.size.x, tile_area.size.y):
						continue
					candidates[key] = Vector2i(x, y)
					if candidates.size() > MAX_PRUNE_CANDIDATES:
						return
	if candidates.is_empty():
		return
	var leaves: Array[String] = []
	DrawingRenderer._collect_visible(document, DrawingDocument.ROOT_ID, leaves)
	var raster_layers: Array[String] = []
	var text_areas: Array[Rect2i] = []
	for layer: String in leaves:
		var metadata: Dictionary = document.node_metadata(layer)
		if metadata.get("kind") == DrawingLayerNode.TEXT:
			var element: DrawingTextElement = document.inspect_node(layer).text_element
			if element != null:
				var measured: DrawingResult = DrawingTextRaster.bounds(element)
				if not measured.ok:
					return
				text_areas.append(measured.value as Rect2i)
		else:
			raster_layers.append(layer)
	for key: String in candidates:
		var tile: Vector2i = candidates[key]
		var area: Rect2i = Rect2i(tile * DISPLAY_TILE_SIZE,
			Vector2i(DISPLAY_TILE_SIZE, DISPLAY_TILE_SIZE))
		var may_contain_content: bool = false
		for text_area: Rect2i in text_areas:
			if area.intersects(text_area):
				may_contain_content = true
				break
		if may_contain_content:
			continue
		for layer: String in raster_layers:
			if document.raster_may_cover(layer, area.position.x, area.position.y,
					area.size.x, area.size.y):
				may_contain_content = true
				break
		if not may_contain_content:
			_occupied_display_tiles.erase(key)
			_display_tiles.erase(key)


func _sync_display_cache() -> void:
	var rebuild_occupancy: bool = false
	var changed_regions: Array = []
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
		changed_regions = changed["regions"] as Array
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
	if not rebuild_occupancy:
		# A stale source-occupancy hint is safe but causes needless texture
		# churn after an erasure. Recheck only the bounded changed footprints.
		_prune_erased_display_tiles(changed_regions)
	_cache_revision = document.revision
	if rebuild_occupancy:
		_rebuild_occupancy()

## Prefer the user's visible working area when a dense viewport contains
## more tiles than the persistent texture budget. Iteration still draws *all*
## tiles in source order; only which textures survive to the next frame changes.
## The distance ordering is stable for a fixed focal point and never evicts a
## nearer visible tile to cache a farther one. Previous frame references keep
## an evicted texture alive until that frame has been submitted.
func _display_cache_focus() -> Vector2:
	var source_focus: Vector2 = camera
	if pointer_known and zoom > 0.0 and Rect2(Vector2.ZERO, size).has_point(last_pointer_position):
		source_focus += (last_pointer_position - size * 0.5) / zoom
	return source_focus / float(DISPLAY_TILE_SIZE)


func _tile_focus_distance(tile: Vector2i, focus: Vector2) -> float:
	var delta: Vector2 = Vector2(tile) + Vector2(0.5, 0.5) - focus
	return delta.length_squared()


## Offscreen textures go first, preserving the old bounded-LRU behavior.
## For in-view overflow retain the 144 closest tiles to the current focus;
## transient edge textures are still drawn at full precision for this frame.
func _reserve_display_slot(visible_tile_range: Rect2i, candidate: Vector2i,
		focus: Vector2) -> bool:
	if _display_tiles.size() < MAX_DISPLAY_TILES:
		return true
	var oldest_offscreen_key: String = ""
	var oldest_access: int = 9223372036854775807
	var farthest_visible_key: String = ""
	var farthest_distance: float = -1.0
	for key: String in _display_tiles:
		var tile_area: Rect2i = _display_tiles[key]["area"] as Rect2i
		var tile_x: int = DrawingDocument.TILES.floor_div(tile_area.position.x, DISPLAY_TILE_SIZE)
		var tile_y: int = DrawingDocument.TILES.floor_div(tile_area.position.y, DISPLAY_TILE_SIZE)
		var existing_tile: Vector2i = Vector2i(tile_x, tile_y)
		if not visible_tile_range.has_point(existing_tile):
			var access: int = int(_display_tiles[key]["last_used"])
			if access < oldest_access:
				oldest_access = access
				oldest_offscreen_key = key
			continue
		var distance: float = _tile_focus_distance(existing_tile, focus)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest_visible_key = key
	if not oldest_offscreen_key.is_empty():
		_display_tiles.erase(oldest_offscreen_key)
		return true
	if not farthest_visible_key.is_empty() \
			and _tile_focus_distance(candidate, focus) + 0.0001 < farthest_distance:
		_display_tiles.erase(farthest_visible_key)
		return true
	return false


## Draw the transparency guide in fixed *screen* pixels, not source pixels.
## It is a backdrop only: sparse tiles outside this frame are still visible.
func _draw_image_backdrop() -> void:
	if not image_bounds.has_area() or _checker_texture == null:
		return
	var frame: Rect2 = Rect2(pixel_to_position(Vector2(image_bounds.position)),
		Vector2(image_bounds.size) * zoom)
	var visible: Rect2 = frame.intersection(Rect2(Vector2.ZERO, size))
	if visible.has_area():
		# A tiled rect starts its UVs at visible.position, which changes as the
		# image enters/leaves each edge. Source UVs must instead be anchored to
		# the viewport's origin (at all pan edges and fractional zoom values).
		draw_texture_rect_region(_checker_texture, visible,
			Rect2(visible.position, visible.size), Color.WHITE, false, false)


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


## An automatic 1px source grid is independent of the user-configured 8px
## drawing grid and snap. Limit work to visible image pixels at high zoom.
func _draw_pixel_grid_overlay() -> void:
	if not show_pixel_grid or zoom < 6.0 or not image_bounds.has_area():
		return
	var frame: Rect2 = Rect2(pixel_to_position(Vector2(image_bounds.position)),
		Vector2(image_bounds.size) * zoom)
	var visible: Rect2 = frame.intersection(Rect2(Vector2.ZERO, size))
	if not visible.has_area():
		return
	var source_start: Vector2 = (visible.position - size * 0.5) / zoom + camera
	var source_end: Vector2 = (visible.end - size * 0.5) / zoom + camera
	var first_x: int = maxi(image_bounds.position.x, ceili(source_start.x))
	var last_x: int = mini(image_bounds.end.x, floori(source_end.x))
	var first_y: int = maxi(image_bounds.position.y, ceili(source_start.y))
	var last_y: int = mini(image_bounds.end.y, floori(source_end.y))
	var line_color: Color = Color(0.08, 0.14, 0.20, 0.28)
	for x: int in range(first_x, last_x + 1):
		var screen_x: float = pixel_to_position(Vector2(x, 0)).x
		draw_line(Vector2(screen_x, visible.position.y),
			Vector2(screen_x, visible.end.y), line_color, 1.0)
	for y: int in range(first_y, last_y + 1):
		var screen_y: float = pixel_to_position(Vector2(0, y)).y
		draw_line(Vector2(visible.position.x, screen_y),
			Vector2(visible.end.x, screen_y), line_color, 1.0)


## Raster tiles are separate textures. Compute *both* corners from the same
## source-space boundary and snap them to integer viewport pixels. Rounding the
## position but scaling a width independently can leave a 1px gap (or overlap)
## at 786% / fractional camera positions; a gap exposes the checkerboard and
## cannot be removed by painting or selecting document pixels.
func _raster_screen_rect(area: Rect2i) -> Rect2:
	var begin: Vector2 = pixel_to_position(Vector2(area.position))
	var end: Vector2 = pixel_to_position(Vector2(area.end))
	var first: Vector2 = Vector2(roundf(begin.x), roundf(begin.y))
	var last: Vector2 = Vector2(roundf(end.x), roundf(end.y))
	return Rect2(first, last - first)


## Cache the expensive storage-to-display stamp projection only while its
## inputs are identical. The result is private to this Canvas: neither the
## edit session nor another consumer can mutate the cached stamp dictionary.
## A closed or revision-invalidated session always recomputes (and returns
## blank stamps), even if its last paint epoch happens to match.
func _preview_index_for_draw(edit: DrawingEditSession, window: Rect2i) -> Dictionary:
	_preview_index_reused = false
	if edit == null:
		_preview_index_owner = null
		_preview_index_result = {}
		return {}
	var revision: int = edit.document.revision
	if not edit._closed and _preview_index_owner == edit \
			and _preview_index_epoch == edit._preview_epoch \
			and _preview_index_revision == revision and _preview_index_window == window:
		_preview_index_reused = true
		return _preview_index_result
	var result: Dictionary = edit.preview_stamps_for_display_tiles(window, DISPLAY_TILE_SIZE)
	_preview_index_owner = edit
	_preview_index_epoch = edit._preview_epoch
	_preview_index_revision = revision
	_preview_index_window = window
	_preview_index_result = result
	return result


func _draw() -> void:
	_frame_references.clear()
	var draw_start: int = Time.get_ticks_usec()
	var metrics: Dictionary[String, Variant] = {"zoom": zoom, "tiles_visible": 0,
		"cache_hits": 0, "tiles_composited": 0, "source_pixels_rendered": 0,
		"visible_layer_plan_builds": 0, "source_chunks_shared": 0,
		"preview_index_built": 0, "preview_index_keys": 0, "preview_index_fallback": 0,
		"preview_index_cache_hit": 0,
		"textures_created": 0, "textures_updated": 0, "textures_transient": 0,
		"bytes_uploaded": 0,
		"compose_cpu_us": 0, "texture_cpu_us": 0, "preview_index_cpu_us": 0,
		"empty_skipped": 0,
		"transparent_tiles_culled": 0,
		"cache_limit_bytes": MAX_DISPLAY_TILES * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4}
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.16, 0.18))
	if document == null or size.x <= 0 or size.y <= 0 or zoom <= 0:
		_preview_index_for_draw(null, Rect2i())
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
	var cache_focus: Vector2 = _display_cache_focus()
	# Resolve visible layers lazily: an idle redraw consisting entirely of
	# cached texture hits must not traverse the document tree at all.
	var visible_plan: Dictionary = {}
	var preview_session: DrawingEditSession = session if session != null else _move_preview
	var preview_index: Dictionary = {}
	var indexed_stamps: Dictionary = {}
	var use_preview_index: bool = false
	if preview_session != null:
		var index_start_us: int = Time.get_ticks_usec()
		preview_index = _preview_index_for_draw(preview_session, visible_tiles)
		metrics["preview_index_cpu_us"] = Time.get_ticks_usec() - index_start_us
		metrics["preview_index_cache_hit"] = 1 if _preview_index_reused else 0
		use_preview_index = bool(preview_index["indexed"])
		if use_preview_index:
			indexed_stamps = preview_index["stamps"] as Dictionary
			metrics["preview_index_built"] = 1
			metrics["preview_index_keys"] = indexed_stamps.size()
		else:
			metrics["preview_index_fallback"] = 1
	else:
		# Release the last detached index after commit/cancel, and avoid
		# retaining an otherwise completed edit session from an idle Canvas.
		_preview_index_for_draw(null, visible_tiles)
	for y: int in range(start_y, end_y + 1):
		for x: int in range(start_x, end_x + 1):
			metrics["tiles_visible"] = int(metrics["tiles_visible"]) + 1
			var key: String = "%d,%d" % [x, y]
			var area: Rect2i = Rect2i(x * DISPLAY_TILE_SIZE, y * DISPLAY_TILE_SIZE,
				DISPLAY_TILE_SIZE, DISPLAY_TILE_SIZE)
			var preview_stamp: int = 0
			if preview_session != null:
				preview_stamp = int(indexed_stamps.get(key, 0)) if use_preview_index \
					else preview_session.preview_stamp_for_area(area)
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
				metrics["tiles_composited"] = int(metrics["tiles_composited"]) + 1
				metrics["source_pixels_rendered"] = int(metrics["source_pixels_rendered"]) + DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE
				# Sparse source chunks cover more than one display tile. A completed,
				# fully transparent composite (including hidden RGB at alpha zero)
				# needs no texture. Retire its conservative occupancy hint only when
				# all committed sources were actually rendered without a preview;
				# future edits republish their dirty footprint, while structure or
				# lazy-source changes rebuild the index. Unknown occupancy remains
				# conservative so that failed/oversized index builds never cull art.
				if not _occupancy_unknown and preview_stamp == 0 \
						and composite.code != "GLYPH_FALLBACK" and not image.get_used_rect().has_area():
					_occupied_display_tiles.erase(key)
					_display_tiles.erase(key)
					metrics["transparent_tiles_culled"] = int(metrics["transparent_tiles_culled"]) + 1
					continue
				var start_texture: int = Time.get_ticks_usec()
				var retain: bool = true
				if entry.is_empty():
					retain = _reserve_display_slot(visible_tiles, Vector2i(x, y), cache_focus)
					entry = {"texture": ImageTexture.create_from_image(image)}
					metrics["textures_created"] = int(metrics["textures_created"]) + 1
					if not retain:
						metrics["textures_transient"] = int(metrics["textures_transient"]) + 1
				else:
					(entry["texture"] as ImageTexture).update(image)
					metrics["textures_updated"] = int(metrics["textures_updated"]) + 1
				metrics["texture_cpu_us"] = int(metrics["texture_cpu_us"]) + Time.get_ticks_usec() - start_texture
				metrics["bytes_uploaded"] = int(metrics["bytes_uploaded"]) + DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
				entry["area"] = area
				entry["preview_stamp"] = preview_stamp
				entry["preview_owner"] = preview_owner
				entry["dirty"] = false
				if retain:
					_display_tiles[key] = entry
			entry["last_used"] = _cache_access
			_frame_references.append(entry["texture"] as ImageTexture)
			draw_texture_rect(entry["texture"] as ImageTexture,
				_raster_screen_rect(area), false)
	if not visible_plan.is_empty():
		metrics["source_chunks_shared"] = (visible_plan["source_chunks"] as Dictionary).size()
	metrics["cache_tiles"] = _display_tiles.size()
	metrics["cache_bytes_estimate"] = _display_tiles.size() * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
	metrics["frame_reference_bytes_upper_bound"] = _frame_references.size() * DISPLAY_TILE_SIZE * DISPLAY_TILE_SIZE * 4
	metrics["draw_cpu_us"] = Time.get_ticks_usec() - draw_start
	metrics["submit_us"] = Time.get_ticks_usec()
	last_frame_metrics = metrics
	_last_frame_submit_us = int(metrics["submit_us"])
	if session != null:
		# Capture per-gesture compositor/upload work before the next _draw
		# replaces last_frame_metrics. This is CPU submission, not photon time.
		_metrics["preview_frames"] = int(_metrics["preview_frames"]) + 1
		for key: String in ["compose_cpu_us", "texture_cpu_us", "preview_index_cpu_us", "bytes_uploaded"]:
			_metrics[key] = int(_metrics[key]) + int(metrics[key])

	_draw_grid_overlay()
	_draw_pixel_grid_overlay()
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
	var outline_started_us: int = Time.get_ticks_usec()
	_draw_selection_outline()
	last_frame_metrics["selection_outline_cpu_us"] = Time.get_ticks_usec() - outline_started_us
	if selecting and _marquee_dragged:
		draw_rect(Rect2(pixel_to_position(Vector2(_marquee.position)),
			Vector2(_marquee.size) * zoom), Color(0.95, 0.8, 0.24), false, 2.0)
	if pointer_known and tool in ["Brush", "Eraser"] and Rect2(Vector2.ZERO, size).has_point(last_pointer_position):
		var radius: float = maxf(1.0, brush_width * zoom * 0.5)
		draw_arc(last_pointer_position, radius + 1.0, 0.0, TAU, 40, Color(0.05, 0.05, 0.05), 1.5)
		draw_arc(last_pointer_position, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 1.0)
	if session != null and session.change_count() > 0 and int(_metrics.get("first_preview_submit_us", 0)) == 0:
		_metrics["first_preview_submit_us"] = Time.get_ticks_usec()
	# Unlike the earlier draw_cpu_us field, this includes grid, selection and
	# cursor overlays. Capture actual rendered preview frames only, not the
	# post-commit idle redraw. Frame callbacks do not measure photons.
	var frame_end_us: int = Time.get_ticks_usec()
	last_frame_metrics["full_draw_cpu_us"] = frame_end_us - draw_start
	if session != null:
		# Capture pending pointer age at the same instant as the draw phases.
		# A queued waypoint and a partly interpolated target are distinct input
		# samples; both count even when one was already dequeued for staging.
		last_frame_metrics["frame_end_us"] = frame_end_us
		last_frame_metrics.merge(_frame_input_backlog(frame_end_us), true)
		_tag_frame_preview_stage(last_frame_metrics, frame_end_us)
		_record_frame_phase(last_frame_metrics)


## The persistent selection always traces mask truth, never the conservative
## enclosing bounds. Only viewport-intersecting rows are evaluated; rectangle
## boolean expressions have a scanline cost independent of selected area.
func _draw_selection_outline() -> void:
	if not selection_mask.enabled or not selected.has_area():
		return
	var top_left: Vector2 = (Vector2.ZERO - size * 0.5) / zoom + camera
	var bottom_right: Vector2 = (size - size * 0.5) / zoom + camera
	var visible: Rect2i = Rect2i(Vector2i(floori(top_left.x), floori(top_left.y)),
		Vector2i(ceili(bottom_right.x) - floori(top_left.x),
			ceili(bottom_right.y) - floori(top_left.y)))
	var source_edges: PackedVector2Array = PackedVector2Array()
	if selection_mask._pixel_mask.is_empty():
		source_edges = selection_mask.contour_segments(visible)
	else:
		# Exact irregular masks may require millions of pixel probes at 25%.
		# Build at most four 64px tiles per frame and keep already traced tiles.
		var footprint: Rect2i = selected.intersection(visible.grow(1))
		if not footprint.has_area():
			return
		var left: int = DrawingDocument.TILES.floor_div(footprint.position.x, MASK_OUTLINE_TILE)
		var top: int = DrawingDocument.TILES.floor_div(footprint.position.y, MASK_OUTLINE_TILE)
		var right: int = DrawingDocument.TILES.floor_div(footprint.end.x - 1, MASK_OUTLINE_TILE)
		var bottom: int = DrawingDocument.TILES.floor_div(footprint.end.y - 1, MASK_OUTLINE_TILE)
		var tile_window: Rect2i = Rect2i(left, top, right - left + 1, bottom - top + 1)
		if tile_window != _mask_outline_window:
			_mask_outline_cache.clear()
			_mask_outline_window = tile_window
		var created: int = 0
		var pending: bool = false
		for tile_y: int in range(top, bottom + 1):
			for tile_x: int in range(left, right + 1):
				var tile: Vector2i = Vector2i(tile_x, tile_y)
				if not _mask_outline_cache.has(tile):
					if _mask_outline_cache.size() >= MAX_MASK_OUTLINE_CACHE:
						# At extreme zoom-out/display sizes, an explicit mask may
						# exceed the retained cache. Stop progressive redraw rather
						# than evict/rebuild forever; a changed view starts fresh.
						continue
					if created >= MASK_OUTLINE_TILES_PER_FRAME:
						pending = true
						continue
					created += 1
					_mask_outline_cache[tile] = selection_mask.contour_segments(
						Rect2i(tile * MASK_OUTLINE_TILE,
							Vector2i(MASK_OUTLINE_TILE, MASK_OUTLINE_TILE)))
				source_edges.append_array(_mask_outline_cache[tile])
		if pending:
			queue_redraw()
	var screen_edges: PackedVector2Array = PackedVector2Array()
	for source_point: Vector2 in source_edges:
		screen_edges.append(pixel_to_position(source_point))
	if not screen_edges.is_empty():
		draw_multiline(screen_edges, Color(0.2, 0.65, 1.0, 0.95), 1.5)


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
			if button.pressed and session != null and _stroke_phase == StrokePhase.CAPTURING:
				# We cannot remap later input while a paint button is held.
				cancel_gesture()
				canvas_error.emit("Stroke cancelled because panning began during capture")
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
	if session == null and not (dragging and (selecting or moving)) and not _floating_active:
		return
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE \
				and (dragging or session != null or has_focus()):
			cancel_gesture()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER] \
				and _floating_active and not dragging and has_focus():
			confirm_floating_move()
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
			canvas_error.emit("Stroke cancelled because the document revision changed")
			return
		_drain_segments(MAX_SEGMENTS_PER_FRAME)
	if moving and _move_target != _move_preview_offset:
		_stage_move_preview(_move_target)
	if _floating_source_revision >= 0 and (document == null \
			or document.revision != _floating_source_revision):
		cancel_gesture()


func start_gesture(position: Vector2) -> void:
	if session != null:
		canvas_error.emit("Previous stroke is still draining; wait for its commit")
		return
	if document == null:
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
			if _floating_active and not selection_mask.allows(gesture_start):
				# A click outside the floating piece is an explicit drop.
				moving = false
				dragging = false
				confirm_floating_move()
				return
			if not _floating_active:
				if not selection_mask.enabled or not selected.has_area() \
						or not selection_mask.allows(gesture_start):
					moving = false
					dragging = false
					return
				var captured_at: int = Time.get_ticks_usec()
				var captured: DrawingResult = DrawingClipboard.capture(document, layer_id,
					selection_mask.bounds, selection_mask)
				if not captured.ok:
					moving = false
					dragging = false
					canvas_error.emit(captured.message)
					return
				_move_capture = captured.value as DrawingClipboard
				last_move_metrics = {"capture_us": Time.get_ticks_usec() - captured_at,
					"pixels": _move_capture._pixels.size()}
				move_profile_samples.clear()
				_floating_source_selection = selection_mask.detached_copy()
				_floating_source_revision = document.revision
				gesture_started.emit()
			_move_drag_base = _floating_offset
			_move_target = _floating_offset
			_move_target_received_us = 0
		return
	if tool not in ["Brush", "Eraser"]:
		dragging = false
		return
	# The neutral workspace is not a paint target. An in-frame stroke may
	# cross the edge; its swept footprint is clipped when staging pixels.
	if clip_strokes_to_image_frame and image_bounds.has_area() \
			and not image_bounds.has_point(gesture_start):
		dragging = false
		return
	var result: DrawingResult = document.begin_edit(layer_id, document.revision)
	if not result.ok:
		canvas_error.emit(result.message)
		dragging = false
		return
	session = result.value as DrawingEditSession
	_stroke_phase = StrokePhase.CAPTURING
	# Avoid Godot combining OS motion events during a captured paint gesture.
	# This global option must be restored on all commit/cancel/exit paths.
	_previous_accumulated_input = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_owns_accumulated_input = true
	_stroke_color = color_rgba
	_stroke_width = brush_width
	_stroke_erase = tool == "Eraser"
	_stroke_clip = image_bounds if clip_strokes_to_image_frame else Rect2i()
	_stroke_selection = selection_mask.detached_copy()
	_native_brush = null
	_active_brush_backend = "Legacy"
	if brush_backend in ["NativeHard", "Hokusai"]:
		if ClassDB.class_exists("DrawingNativeBrush"):
			_native_brush = ClassDB.instantiate("DrawingNativeBrush")
			if brush_backend == "Hokusai" and not _stroke_erase:
				var preset_path: String = BUNDLED_PRESETS.get(brush_preset, "")
				var settings: String = FileAccess.get_file_as_string(preset_path) if not preset_path.is_empty() else ""
				# A pre-transaction native binary must fail over to Legacy;
				# otherwise a lazy-source failure could consume pigment on retry.
				var supports_transactions: bool = _native_brush.has_method("begin_preset_batch") and \
					_native_brush.has_method("commit_preset_batch") and \
					_native_brush.has_method("rollback_preset_batch")
				if supports_transactions and not settings.is_empty() and _native_brush.call(
						"configure_preset", settings, _stroke_width, _stroke_color):
					_active_brush_backend = "Hokusai"
				else:
					canvas_error.emit("Hokusai preset or batch rollback unavailable; using the legacy Brush")
			else:
				# Reject a pre-transaction binary at gesture start rather than
				# letting a failed source read consume native hard coverage.
				if _native_brush.has_method("begin_hard_batch") and \
						_native_brush.has_method("commit_hard_batch") and \
						_native_brush.has_method("rollback_hard_batch"):
					_native_brush.call("reset_hard")
					_active_brush_backend = "NativeHard"
				else:
					canvas_error.emit("Native hard rollback unavailable; using the legacy Brush")
		else:
			canvas_error.emit("Native brush unavailable; using the legacy Brush")
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	_sample_latency_write_index = 0
	_batch_latency_write_index = 0
	_frame_phase_write_index = 0
	_pending_frame_phase_sample = {}
	_pending_frame_phase_session = null
	_unsubmitted_preview_stage_us = 0
	_has_segment_target = false
	_finish_requested = false
	_staged_position = source_position(position)
	_metrics = {"down_us": Time.get_ticks_usec(), "first_stage_us": 0,
		"first_preview_submit_us": 0, "first_frame_post_draw_us": 0,
		"release_us": 0, "commit_us": 0, "samples_received": 0,
		"segments_staged": 0, "stage_cpu_us": 0, "max_pending": 0,
		"max_sample_buffer": 0, "sample_compactions": 0,
		"duplicate_drain_batched": 0, "drain_calls": 0, "max_drain_cpu_us": 0,
		"sample_to_stage_us": [], "sample_to_stage_total": 0,
		"max_sample_to_stage_us": 0, "stage_batches_us": [],
		"stage_batch_total": 0, "max_stage_batch_us": 0,
		"commit_cpu_us": 0, "preview_frames": 0,
		"compose_cpu_us": 0, "texture_cpu_us": 0,
		"preview_index_cpu_us": 0, "bytes_uploaded": 0,
		"frame_phase_total": 0, "frame_phases_us": [],
		"frame_post_draw_matches": 0, "max_frame_end_to_post_draw_us": 0,
		"frame_preview_stage_submissions": 0,
		"max_frame_preview_stage_to_frame_end_us": 0,
		"preview_stage_post_draw_matches": 0,
		"max_preview_stage_to_post_draw_us": 0,
		"max_frame_full_draw_cpu_us": 0, "max_frame_compose_cpu_us": 0,
		"max_frame_texture_cpu_us": 0, "max_frame_preview_index_cpu_us": 0,
		"max_frame_selection_outline_cpu_us": 0,
		"max_frame_pending_input_count": 0, "max_frame_oldest_pending_age_us": 0}
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
		_move_target = _move_drag_base + current - gesture_start
		_move_target_received_us = Time.get_ticks_usec()
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
	_metrics["max_sample_buffer"] = maxi(int(_metrics["max_sample_buffer"]), _samples.size())


func _drain_segments(budget: int) -> void:
	if session == null:
		return
	var drain_start_us: int = Time.get_ticks_usec()
	var segments: int = 0
	# Staging an already covered or selection-masked sample does not change
	# the detached preview. Avoid forcing an expensive canvas draw just
	# because an input sample was consumed; actual pixel mutations increment
	# the session preview generation (including edits that restore old bytes).
	var preview_before: int = session._preview_epoch
	# A wide brush can rasterize more candidates in one segment than a
	# narrow one does in 16. Limit the atomic batch by swept footprint so
	# the soft deadline is not defeated by one oversized paint_path call.
	var estimated_segment_pixels: float = maxf(1.0,
		_stroke_width * (_stroke_width + MAX_SEGMENT_LENGTH))
	var batch_limit: int = clampi(int(MAX_BATCH_ESTIMATED_PIXELS / estimated_segment_pixels),
		1, MAX_SEGMENTS_PER_BATCH)
	# Hokusai accumulates pigment natively: exporting every intermediate 60px
	# dab would repeatedly restage the same dirty tiles. Collapse up to sixteen
	# adjacent source samples into one atomic native call/preview update.
	if _active_brush_backend == "Hokusai":
		batch_limit = MAX_SEGMENTS_PER_BATCH
	while segments < budget:
		var batch: PackedVector2Array = PackedVector2Array()
		var completed_arrivals: Array[int] = []
		var next_position: Vector2 = _staged_position
		# A 60px stroke normally gets a one-segment atomic budget. Allow a
		# *consecutive identical* Legacy source position to extend that batch:
		# it adds no new candidate footprint, and paint_path already skips
		# duplicate waypoints exactly. Never collapse Hokusai pigment input or
		# enlarge a batch with a moving segment beyond the original budget.
		var batch_capacity: int = MAX_SEGMENTS_PER_BATCH \
			if _active_brush_backend == "Legacy" else batch_limit
		while batch.size() < batch_capacity and segments < budget:
			if not _has_segment_target:
				if _sample_index == _samples.size():
					break
				_segment_target = _samples[_sample_index]
				_target_arrival_us = _sample_times_us[_sample_index]
				_sample_index += 1
				_has_segment_target = true
			var candidate: Vector2 = next_position.move_toward(
				_segment_target, MAX_SEGMENT_LENGTH)
			if batch.size() >= batch_limit:
				if candidate != next_position:
					# Target is already dequeued, but remains pending. Do not
					# consume its timestamp or advance the staged position.
					break
				_metrics["duplicate_drain_batched"] = int(
					_metrics["duplicate_drain_batched"]) + 1
			next_position = candidate
			batch.append(next_position)
			segments += 1
			if next_position == _segment_target:
				completed_arrivals.append(_target_arrival_us)
				_has_segment_target = false
		if batch.is_empty():
			break
		var start_us: int = Time.get_ticks_usec()
		var preview_epoch_before_batch: int = session._preview_epoch
		var stage: DrawingResult
		if _active_brush_backend == "NativeHard":
			stage = session.paint_path_native_hard(batch, _stroke_color, _stroke_width,
				_stroke_erase, _stroke_selection if _stroke_selection.enabled else null,
				_native_brush, _stroke_clip)
		elif _active_brush_backend == "Hokusai":
			stage = session.paint_path_hokusai(batch, _stroke_color,
				_stroke_selection if _stroke_selection.enabled else null,
				_native_brush, _stroke_clip)
		else:
			stage = session.paint_path(batch, _stroke_color, _stroke_width, _stroke_erase,
				_stroke_selection if _stroke_selection.enabled else null, 1048576, _stroke_clip)
		var staged_at_us: int = Time.get_ticks_usec()
		var batch_cpu_us: int = staged_at_us - start_us
		_metrics["stage_cpu_us"] = int(_metrics["stage_cpu_us"]) + batch_cpu_us
		# Keep the latest batch timings, not just the first 4096 of a long
		# stroke. Lifetime count, total CPU and worst batch stay exact.
		_record_stage_batch(batch_cpu_us)
		if not stage.ok:
			canvas_error.emit(stage.message)
			cancel_gesture()
			return
		if int(_metrics["first_stage_us"]) == 0:
			_metrics["first_stage_us"] = staged_at_us
		_metrics["segments_staged"] = int(_metrics["segments_staged"]) + batch.size()
		if session._preview_epoch != preview_epoch_before_batch:
			_mark_unsubmitted_preview_stage(staged_at_us)
		_staged_position = next_position
		for arrival_us: int in completed_arrivals:
			_record_stage_latency(maxi(0, staged_at_us - arrival_us))
		# The deadline is checked between atomic batches, never during a
		# partially rasterized segment or while receiving a pointer event.
		if staged_at_us - drain_start_us >= MAX_DRAIN_CPU_US:
			break
	_metrics["drain_calls"] = int(_metrics["drain_calls"]) + 1
	_metrics["max_drain_cpu_us"] = maxi(int(_metrics["max_drain_cpu_us"]),
		Time.get_ticks_usec() - drain_start_us)
	_compact_sample_queue()
	# A failed batch cancels above; a finished stroke queues its own redraw
	# from _commit_stroke(). Do not dereference the discarded session.
	if session != null and session._preview_epoch != preview_before:
		queue_redraw()
	if _finish_requested and _samples.is_empty() and not _has_segment_target:
		_commit_stroke()


## Sample the oldest *outstanding* pointer timestamp, including the current
## interpolation target that has already been dequeued. Ignore consumed array
## prefixes, so queue compaction and long source-space segments do not skew
## frame age/depth. These are engine-receipt timestamps, not OS device times.
func _frame_input_backlog(now_us: int) -> Dictionary:
	var queued: int = maxi(0, _sample_times_us.size() - _sample_index)
	var oldest_us: int = now_us
	if queued > 0:
		oldest_us = mini(oldest_us, _sample_times_us[_sample_index])
	if _has_segment_target:
		queued += 1
		oldest_us = mini(oldest_us, _target_arrival_us)
	return {"pending_input_count": queued,
		"oldest_pending_age_us": maxi(0, now_us - oldest_us) if queued > 0 else 0}


## Keep an ordered, bounded per-frame profile instead of just cumulative
## compose/texture/index time. Total frame count and worst samples remain exact
## even when the oldest observations are evicted. Never infer physical
## input-to-photon latency from a Godot CPU draw callback.
func _record_frame_phase(frame: Dictionary) -> void:
	var sample: Dictionary = {}
	for key: String in ["full_draw_cpu_us", "compose_cpu_us", "texture_cpu_us",
			"preview_index_cpu_us", "selection_outline_cpu_us",
			"pending_input_count", "oldest_pending_age_us"]:
		var value: int = maxi(0, int(frame.get(key, 0)))
		sample[key] = value
		var max_key: String = "max_frame_" + key
		_metrics[max_key] = maxi(int(_metrics.get(max_key, 0)), value)
	if frame.has("preview_stage_completed_us"):
		var stage_us: int = maxi(0, int(frame["preview_stage_completed_us"]))
		var submit_delay_us: int = maxi(0, int(frame.get(
			"preview_stage_to_frame_end_us", 0)))
		sample["preview_stage_completed_us"] = stage_us
		sample["preview_stage_to_frame_end_us"] = submit_delay_us
		_metrics["frame_preview_stage_submissions"] = int(
			_metrics.get("frame_preview_stage_submissions", 0)) + 1
		_metrics["max_frame_preview_stage_to_frame_end_us"] = maxi(
			int(_metrics.get("max_frame_preview_stage_to_frame_end_us", 0)),
			submit_delay_us)
	# Monotonic engine time allows phase and backlog spikes to be correlated
	# without pretending to measure physical input-to-photon latency.
	sample["frame_end_us"] = maxi(0, int(frame.get("frame_end_us", 0)))
	_metrics["frame_phase_total"] = int(_metrics["frame_phase_total"]) + 1
	var records: Array = _metrics["frame_phases_us"] as Array
	if records.size() < MAX_FRAME_PHASE_SAMPLES:
		records.append(sample)
	else:
		# An evicted unmatched frame cannot be completed retroactively.
		_pending_frame_phase_sample = {}
		_pending_frame_phase_session = null
		records[_frame_phase_write_index] = sample
		_frame_phase_write_index = (_frame_phase_write_index + 1) % MAX_FRAME_PHASE_SAMPLES
	if session != null:
		_pending_frame_phase_sample = sample
		_pending_frame_phase_session = session


func _finalize_frame_phase_window() -> void:
	if int(_metrics["frame_phase_total"]) <= MAX_FRAME_PHASE_SAMPLES \
			or _frame_phase_write_index == 0:
		return
	var records: Array = _metrics["frame_phases_us"] as Array
	var ordered: Array = records.slice(_frame_phase_write_index)
	ordered.append_array(records.slice(0, _frame_phase_write_index))
	_metrics["frame_phases_us"] = ordered


## A long stroke must not freeze its batch latency profile at the first
## 4096 batches; later overloads matter most when diagnosing pointer lag.
## Record all-time count/worst with a fixed latest-window distribution.
func _record_stage_batch(duration_us: int) -> void:
	var batches: Array = _metrics["stage_batches_us"] as Array
	var duration: int = maxi(0, duration_us)
	_metrics["stage_batch_total"] = int(_metrics["stage_batch_total"]) + 1
	_metrics["max_stage_batch_us"] = maxi(int(_metrics["max_stage_batch_us"]), duration)
	if batches.size() < MAX_STAGE_BATCH_LATENCIES:
		batches.append(duration)
	else:
		batches[_batch_latency_write_index] = duration
		_batch_latency_write_index = (_batch_latency_write_index + 1) % MAX_STAGE_BATCH_LATENCIES


## Present the bounded latest-batch window in chronological order, matching
## the short-stroke metric consumers' existing expectations.
func _finalize_stage_batch_window() -> void:
	if int(_metrics["stage_batch_total"]) <= MAX_STAGE_BATCH_LATENCIES \
			or _batch_latency_write_index == 0:
		return
	var batches: Array = _metrics["stage_batches_us"] as Array
	var ordered: Array = batches.slice(_batch_latency_write_index)
	ordered.append_array(batches.slice(0, _batch_latency_write_index))
	_metrics["stage_batches_us"] = ordered


## An unbounded list of per-sample latencies defeats input queue compaction on
## sustained strokes and makes final deep-copy cost depend on stroke duration.
## The latest window stays bounded; the all-time maximum and count are exact.
func _record_stage_latency(latency_us: int) -> void:
	var samples: Array = _metrics["sample_to_stage_us"] as Array
	var age: int = maxi(0, latency_us)
	_metrics["sample_to_stage_total"] = int(_metrics["sample_to_stage_total"]) + 1
	_metrics["max_sample_to_stage_us"] = maxi(int(_metrics["max_sample_to_stage_us"]), age)
	if samples.size() < MAX_SAMPLE_STAGE_LATENCIES:
		samples.append(age)
	else:
		samples[_sample_latency_write_index] = age
		_sample_latency_write_index = (_sample_latency_write_index + 1) % MAX_SAMPLE_STAGE_LATENCIES


## Return latency samples in temporal order for the existing profiler and
## external consumers. Short strokes keep their original complete history.
func _finalize_stage_latency_window() -> void:
	if int(_metrics["sample_to_stage_total"]) <= MAX_SAMPLE_STAGE_LATENCIES \
			or _sample_latency_write_index == 0:
		return
	var samples: Array = _metrics["sample_to_stage_us"] as Array
	var ordered: Array = samples.slice(_sample_latency_write_index)
	ordered.append_array(samples.slice(0, _sample_latency_write_index))
	_metrics["sample_to_stage_us"] = ordered


## Bound retained input memory even when a long capture never catches up
## completely between OS motion events. Only already dequeued waypoints are
## discarded; the current interpolated target and its timestamp are separate.
func _compact_sample_queue() -> void:
	if _sample_index == _samples.size():
		_samples.clear()
		_sample_times_us.clear()
		_sample_index = 0
	elif _sample_index >= MIN_CONSUMED_SAMPLE_COMPACTION \
			and _sample_index * 2 >= _samples.size():
		_samples = _samples.slice(_sample_index)
		_sample_times_us = _sample_times_us.slice(_sample_index)
		_sample_index = 0
		_metrics["sample_compactions"] = int(_metrics["sample_compactions"]) + 1


func _commit_stroke() -> void:
	if session == null:
		return
	_stroke_phase = StrokePhase.COMMITTING
	# Most changes use set_selection_mask() and cancel synchronously. This
	# final comparison also rejects in-place changes to an exposed mask that
	# bypassed that setter while input samples were queued.
	if _stroke_selection == null or not _stroke_selection.same_as(selection_mask):
		cancel_gesture()
		canvas_error.emit("Stroke cancelled because the selection changed")
		return
	var active: DrawingEditSession = session
	_metrics["hokusai_perf"] = active.hokusai_perf.duplicate()
	_unsubmitted_preview_stage_us = 0
	session = null
	_stroke_selection = null
	_native_brush = null
	_active_brush_backend = "Legacy"
	var commit_start_us: int = Time.get_ticks_usec()
	if active.change_count() > 0:
		_publish(active.commit())
	else:
		active.cancel()
	_metrics["commit_cpu_us"] = Time.get_ticks_usec() - commit_start_us
	_metrics["commit_us"] = Time.get_ticks_usec()
	_finalize_stage_latency_window()
	_finalize_stage_batch_window()
	_finalize_frame_phase_window()
	last_gesture_metrics = _metrics.duplicate(true)
	_restore_input_accumulation()
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	_has_segment_target = false
	_finish_requested = false
	_stroke_phase = StrokePhase.IDLE
	queue_redraw()


## Escape, stale revision and direct host changes discard the entire floating
## transaction, even after several drags. No source/history publication.
func cancel_gesture() -> void:
	_unsubmitted_preview_stage_us = 0
	if session != null:
		session.cancel()
		session = null
	_stroke_selection = null
	_native_brush = null
	_active_brush_backend = "Legacy"
	if _move_preview != null:
		_move_preview.cancel()
		_move_preview = null
	if _floating_source_selection != null:
		_assign_selection_mask(_floating_source_selection, false)
	_floating_source_selection = null
	_move_capture = null
	_floating_source_revision = -1
	_floating_active = false
	_floating_offset = Vector2i.ZERO
	_move_drag_base = Vector2i.ZERO
	dragging = false
	selecting = false
	moving = false
	_marquee_dragged = false
	_move_target = Vector2i.ZERO
	_move_target_received_us = 0
	_move_preview_offset = Vector2i.ZERO
	_finish_requested = false
	_stroke_phase = StrokePhase.IDLE
	_restore_input_accumulation()
	_has_segment_target = false
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	queue_redraw()


func has_floating_move() -> bool:
	return _floating_active


## Drop commits at most one pixel delta, regardless of the number of drags.
## Even a pixel-identical move may translate the selected mask without a dirty
## document transaction. The owning workspace captured the original context on
## the FIRST drag and receives only one gesture_committed at this final drop.
func confirm_floating_move() -> bool:
	var drop_started_us: int = Time.get_ticks_usec()
	if not _floating_active or dragging or document == null:
		return false
	if document.revision != _floating_source_revision:
		cancel_gesture()
		return false
	var edit: DrawingEditSession = _move_preview
	var original_selection: DrawingSelection = _floating_source_selection
	_move_preview = null
	_floating_source_selection = null
	_move_capture = null
	_floating_source_revision = -1
	_floating_active = false
	_floating_offset = Vector2i.ZERO
	_move_drag_base = Vector2i.ZERO
	_move_target = Vector2i.ZERO
	_move_target_received_us = 0
	_move_preview_offset = Vector2i.ZERO
	if edit != null and edit.change_count() > 0:
		var result: DrawingResult = edit.commit()
		if not result.ok:
			_assign_selection_mask(original_selection, false)
			_publish(result)
			queue_redraw()
			return false
		_publish(result)
	else:
		if edit != null:
			edit.cancel()
		selection_changed.emit(selected)
	last_move_metrics["drop_cpu_us"] = Time.get_ticks_usec() - drop_started_us
	queue_redraw()
	return true


## Each stage always moves the original source into the accumulated offset;
## a subsequent drag must NOT sample the previous preview as its new source.
## Invalid targets retain the last good preview and mask without ghost pixels.
func _stage_move_preview(offset: Vector2i) -> void:
	if _floating_source_selection == null or document == null:
		return
	if document.revision != _floating_source_revision:
		cancel_gesture()
		return
	if offset == Vector2i.ZERO:
		if _move_preview != null:
			_move_preview.cancel()
			_move_preview = null
		_move_preview_offset = offset
		_floating_offset = offset
		_floating_active = false
		_assign_selection_mask(_floating_source_selection, false)
		queue_redraw()
		return
	var motion_start_us: int = Time.get_ticks_usec()
	var started: DrawingResult = document.begin_edit(layer_id, _floating_source_revision)
	if not started.ok:
		canvas_error.emit(started.message)
		return
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var session_us: int = Time.get_ticks_usec() - motion_start_us
	var staged: DrawingResult = DrawingClipboard.move_captured(edit, _move_capture, offset)
	var staging_us: int = Time.get_ticks_usec() - motion_start_us - session_us
	if not staged.ok:
		edit.cancel()
		canvas_error.emit(staged.message)
		return
	if _move_preview != null:
		_move_preview.cancel()
	_move_preview = edit
	_move_preview_offset = offset
	_floating_offset = offset
	_floating_active = true
	_assign_selection_mask(_floating_source_selection.translated(offset), false)
	last_move_metrics["session_us"] = session_us
	last_move_metrics["stage_us"] = staging_us
	last_move_metrics["selection_us"] = Time.get_ticks_usec() - motion_start_us - session_us - staging_us
	last_move_metrics["motion_to_preview_submit_us"] = Time.get_ticks_usec() - motion_start_us
	last_move_metrics["input_to_preview_submit_us"] = (Time.get_ticks_usec() -
		_move_target_received_us) if _move_target_received_us > 0 else -1
	if move_profile_samples.size() < 512:
		move_profile_samples.append(last_move_metrics.duplicate())
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
		var target: Vector2i = _move_drag_base + position_to_pixel(position) - gesture_start
		if target != _move_preview_offset:
			_move_target_received_us = Time.get_ticks_usec()
			_stage_move_preview(target)
		# Mouse-up completes only this drag. The detached source-clear/target-
		# paste preview and selection remain until Drop (Enter, outside click,
		# an explicit command) or Cancel (Escape).
		if not _floating_active:
			_floating_source_selection = null
			_move_capture = null
			_floating_source_revision = -1
	else:
		_enqueue_sample(source_position(position))
		_metrics["release_us"] = Time.get_ticks_usec()
		_stroke_phase = StrokePhase.DRAINING
		_finish_requested = true
		# Finish small clicks synchronously; long queued strokes are drained
		# across frames without blocking the input loop.
		_drain_segments(MAX_SEGMENTS_PER_FRAME)
	dragging = false
	selecting = false
	moving = false
	_marquee_dragged = false
	_move_target = Vector2i.ZERO
	queue_redraw()

func _publish(result: DrawingResult) -> void:
	if result.ok:
		gesture_committed.emit(result)
	else:
		canvas_error.emit(result.message)
