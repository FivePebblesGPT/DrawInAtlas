extends Button
## T-251: a keyboard-focusable half-circle inside the dock, in a fixed
## minimized rail slot or as a non-scrolling overlay in the expanded gutter.
## All geometry is vector drawn, so it survives Godot/OS UI scaling without
## pre-rasterized, blurry assets. The actual hit area is only 30×56 logical px.

var minimized: bool = false


func _ready() -> void:
	flat = true
	clip_contents = true
	custom_minimum_size = Vector2(30, 56)
	size = custom_minimum_size
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	z_index = 60
	for property: Dictionary in get_property_list():
		if property["name"] == "accessibility_name":
			set("accessibility_name", "Expand or minimize panel dock")
			break


func _draw() -> void:
	var radius: float = size.y * 0.5
	var center: Vector2 = Vector2(size.x, radius)
	var curve: PackedVector2Array = PackedVector2Array()
	for step: int in range(33):
		var angle: float = -PI * 0.5 - PI * float(step) / 32.0
		curve.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var fill: Color = Color(0.09, 0.15, 0.22, 0.66 if is_hovered() or has_focus() else 0.48)
	var surface: PackedVector2Array = PackedVector2Array([center])
	surface.append_array(curve)
	draw_colored_polygon(surface, fill)
	draw_polyline(curve, Color(0.78, 0.88, 0.97, 0.65), 1.4, true)
	var arrow_x: float = size.x * 0.55
	# Right-side dock: > means collapse toward the window edge, < means
	# expand back into the canvas. The previous mapping reversed both.
	var sign: float = -1.0 if minimized else 1.0
	var mark: Color = Color(1.0, 1.0, 1.0, 0.95)
	draw_line(Vector2(arrow_x - sign * 4.0, center.y - 7.0),
		Vector2(arrow_x + sign * 3.0, center.y), mark, 2.0, true)
	draw_line(Vector2(arrow_x + sign * 3.0, center.y),
		Vector2(arrow_x - sign * 4.0, center.y + 7.0), mark, 2.0, true)
	if has_focus():
		draw_arc(center, radius - 3.0, PI * 0.5, PI * 1.5, 28,
			Color(0.42, 0.82, 1.0), 1.5, true)
