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
		if session != null and value != document:
			cancel_gesture()
		document = value
		queue_redraw()
var layer_id: String = "":
	set(value):
		if session != null and value != layer_id:
			cancel_gesture()
		layer_id = value
var tool: String = "Brush":
	set(value):
		if session != null and value != tool:
			cancel_gesture()
		tool = value
var color_rgba: int = 0xff202020
var brush_width: float = 3.0
var grid_spacing: int = 0
var zoom: float = 4.0:
	set(value):
		if session != null and value != zoom:
			cancel_gesture()
		zoom = value
var camera: Vector2 = Vector2.ZERO
var selected: Rect2i = Rect2i()
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
var _frame_textures: Array[ImageTexture] = []
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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	set_process_input(true)
	set_process(true)
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
	if session != null and int(_metrics.get("first_preview_submit_us", 0)) > 0 \
			and int(_metrics.get("first_frame_post_draw_us", 0)) == 0:
		_metrics["first_frame_post_draw_us"] = Time.get_ticks_usec()


func source_position(position: Vector2) -> Vector2:
	var local: Vector2 = (position - size * 0.5) / zoom + camera
	if grid_spacing > 0:
		var snapped: Vector2i = position_to_pixel(position)
		return Vector2(snapped) + Vector2(0.5, 0.5)
	return local


func position_to_pixel(position: Vector2) -> Vector2i:
	var local: Vector2 = (position - size * 0.5) / zoom + camera
	if grid_spacing > 0:
		local = DrawingSnap.point(local, Vector2(grid_spacing, grid_spacing),
			Vector2.ZERO, PackedFloat32Array(), PackedFloat32Array(),
			PackedVector2Array(), float(grid_spacing) * 0.5)
	return Vector2i(floori(local.x), floori(local.y))


func pixel_to_position(pixel: Vector2) -> Vector2:
	return (pixel - camera) * zoom + size * 0.5


func _draw() -> void:
	_frame_textures.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.16, 0.18))
	if document == null:
		return
	var left_top: Vector2i = Vector2i(floori(camera.x - size.x / zoom * 0.5),
		floori(camera.y - size.y / zoom * 0.5))
	var dimensions: Vector2i = Vector2i(ceili(size.x / zoom) + 2, ceili(size.y / zoom) + 2)
	# Bounded viewport reads; never turn a huge zoom-out into a full-canvas allocation.
	for y: int in range(0, dimensions.y, 192):
		for x: int in range(0, dimensions.x, 192):
			var area: Rect2i = Rect2i(left_top + Vector2i(x, y),
				Vector2i(mini(192, dimensions.x - x), mini(192, dimensions.y - y)))
			var composite: DrawingResult = DrawingRenderer.render(document, area,
				0, 0, 1048576, session)
			if not composite.ok or composite.code == "GLYPH_FALLBACK":
				if not _reported_render_errors.has(composite.code):
					_reported_render_errors[composite.code] = true
					canvas_error.emit(composite.message)
				if not composite.ok:
					continue
			var image: Image = composite.value as Image
			var texture: ImageTexture = ImageTexture.create_from_image(image)
			_frame_textures.append(texture)
			draw_texture_rect(texture, Rect2(pixel_to_position(Vector2(area.position)),
				Vector2(area.size) * zoom), false)
	if asset_bounds.has_area():
		draw_rect(Rect2(pixel_to_position(Vector2(asset_bounds.position)),
			Vector2(asset_bounds.size) * zoom), Color(0.2, 0.8, 0.5, 0.8), false, 1.5)
	if asset_origin != Vector2i.ZERO or asset_bounds.has_area():
		var anchor: Vector2 = pixel_to_position(Vector2(asset_origin))
		draw_line(anchor + Vector2(-6, 0), anchor + Vector2(6, 0), Color(1, 0.75, 0.3), 1.0)
		draw_line(anchor + Vector2(0, -6), anchor + Vector2(0, 6), Color(1, 0.75, 0.3), 1.0)
	if selected.has_area():
		draw_rect(Rect2(pixel_to_position(Vector2(selected.position)),
			Vector2(selected.size) * zoom), Color(0.2, 0.6, 1.0), false, 1.5)
	if pointer_known and tool in ["Brush", "Eraser"] and Rect2(Vector2.ZERO, size).has_point(last_pointer_position):
		var radius: float = maxf(1.0, brush_width * zoom * 0.5)
		draw_arc(last_pointer_position, radius + 1.0, 0.0, TAU, 40, Color(0.05, 0.05, 0.05), 1.5)
		draw_arc(last_pointer_position, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 1.0)
	if session != null and session.change_count() > 0 and int(_metrics.get("first_preview_submit_us", 0)) == 0:
		_metrics["first_preview_submit_us"] = Time.get_ticks_usec()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		last_pointer_position = button.position
		pointer_known = true
		cursor_moved.emit()
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var before: Vector2 = (button.position - size * 0.5) / zoom + camera
				zoom = clampf(zoom * (1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.5, 24.0)
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
	if session == null:
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


func start_gesture(position: Vector2) -> void:
	if document == null or session != null:
		return
	gesture_start = position_to_pixel(position)
	if tool == "Text":
		text_requested.emit(gesture_start)
		return
	dragging = true
	selecting = tool == "Select"
	moving = tool == "Move"
	if selecting or moving:
		if moving:
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
		selected = Rect2i(Vector2i(mini(gesture_start.x, current.x), mini(gesture_start.y, current.y)),
			Vector2i(absi(current.x - gesture_start.x) + 1, absi(current.y - gesture_start.y) + 1))
		queue_redraw()
	elif not moving and session != null:
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
			_stroke_color, _stroke_width, _stroke_erase)
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
	dragging = false
	selecting = false
	moving = false
	_finish_requested = false
	_restore_input_accumulation()
	_has_segment_target = false
	_samples.clear()
	_sample_times_us.clear()
	_sample_index = 0
	queue_redraw()


func finish_gesture(position: Vector2) -> void:
	if not dragging:
		return
	if selecting:
		update_gesture(position)
		selection_changed.emit(selected)
	elif moving:
		if selected.has_area():
			var displacement: Vector2i = position_to_pixel(position) - gesture_start
			if displacement != Vector2i.ZERO:
				var started: DrawingResult = document.begin_edit(layer_id, document.revision)
				if started.ok:
					var edit: DrawingEditSession = started.value as DrawingEditSession
					var staged: DrawingResult = DrawingClipboard.move_selection(edit, selected, displacement)
					if staged.ok and edit.change_count() > 0:
						var committed: DrawingResult = edit.commit()
						if committed.ok:
							selected.position += displacement
						_publish(committed)
					else:
						edit.cancel()
						if not staged.ok:
							canvas_error.emit(staged.message)
	else:
		_enqueue_sample(source_position(position))
		_metrics["release_us"] = Time.get_ticks_usec()
		_finish_requested = true
		# Finish small clicks synchronously; long queued strokes are drained
		# across frames without blocking the input loop.
		_drain_segments(MAX_SEGMENTS_PER_FRAME)
	dragging = false
	queue_redraw()


func _publish(result: DrawingResult) -> void:
	if result.ok:
		gesture_committed.emit(result)
	else:
		canvas_error.emit(result.message)
