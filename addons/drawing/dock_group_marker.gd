class_name DrawingDockGroupMarker
extends Button
## Compact vector triangle shared by collapse, whole-group drag and context menu.
## The label stays in the tooltip/accessibility name, never the visual dock chrome.

var collapsed: bool = false:
	set(next):
		collapsed = next
		queue_redraw()


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(24, 45)


func _draw() -> void:
	var point: Vector2 = size * 0.5
	var vertices: PackedVector2Array = PackedVector2Array()
	if collapsed:
		vertices = PackedVector2Array([
			point + Vector2(-3, -6), point + Vector2(4, 0), point + Vector2(-3, 6)])
	else:
		vertices = PackedVector2Array([
			point + Vector2(-6, -3), point + Vector2(6, -3), point + Vector2(0, 4)])
	var tint: Color = get_theme_color("font_color", "Button")
	if disabled:
		tint = get_theme_color("font_disabled_color", "Button")
	draw_colored_polygon(vertices, tint)
