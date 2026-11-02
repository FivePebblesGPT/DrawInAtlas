extends Control
## Bounded framebuffer rendering and native mouse gestures, without Atlas UI types.

signal gesture_started()
signal gesture_committed(result: DrawingResult)
signal selection_changed(area: Rect2i)
signal canvas_error(message: String)
signal view_changed()
signal text_requested(pixel: Vector2i)

var document: DrawingDocument
var layer_id: String = ""
var tool: String = "Brush"
var color_rgba: int = 0xff202020
var brush_width: float = 3.0
var grid_spacing: int = 0
var zoom: float = 4.0
var camera: Vector2 = Vector2.ZERO
var selected: Rect2i = Rect2i()
var session: DrawingEditSession
var dragging: bool = false
var panning: bool = false
var selecting: bool = false
var moving: bool = false
var gesture_start: Vector2i
var last_mouse: Vector2 = Vector2.ZERO
var _frame_textures: Array[ImageTexture] = []
var _reported_render_errors: Dictionary[String, bool] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	set_process_input(true)


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
			var composite: DrawingResult = DrawingRenderer.render(document, area)
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
	if selected.has_area():
		draw_rect(Rect2(pixel_to_position(Vector2(selected.position)),
			Vector2(selected.size) * zoom), Color(0.2, 0.6, 1.0), false, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
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
		if panning:
			camera -= (motion.position - last_mouse) / zoom
			last_mouse = motion.position
			queue_redraw()
			view_changed.emit()
		elif dragging:
			update_gesture(motion.position)
		accept_event()


func start_gesture(position: Vector2) -> void:
	if document == null:
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
	gesture_started.emit()
	paint_to(gesture_start)


func update_gesture(position: Vector2) -> void:
	if not dragging:
		return
	var current: Vector2i = position_to_pixel(position)
	if selecting:
		selected = Rect2i(Vector2i(mini(gesture_start.x, current.x), mini(gesture_start.y, current.y)),
			Vector2i(absi(current.x - gesture_start.x) + 1, absi(current.y - gesture_start.y) + 1))
		queue_redraw()
	elif not moving:
		paint_to(current)


func paint_to(point: Vector2i) -> void:
	if session == null:
		return
	var result: DrawingResult = session.paint_path(PackedVector2Array([Vector2(point) + Vector2(0.5, 0.5)]),
		color_rgba, brush_width, tool == "Eraser")
	if not result.ok:
		canvas_error.emit(result.message)
		session.cancel()
		session = null
		dragging = false


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
		paint_to(position_to_pixel(position))
		if session != null:
			if session.change_count() > 0:
				_publish(session.commit())
			else:
				session.cancel()
			session = null
	dragging = false
	queue_redraw()


func _publish(result: DrawingResult) -> void:
	if result.ok:
		gesture_committed.emit(result)
	else:
		canvas_error.emit(result.message)
