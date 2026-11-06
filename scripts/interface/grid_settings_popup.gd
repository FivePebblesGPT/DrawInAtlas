class_name AtlasGridSettingsPopup
extends CanvasLayer
## In-workspace popover keeps the shared grid form bounded on compact screens.

@onready var panel: Panel = $Panel
@onready var done_button: Button = $Panel/Margin/Layout/DoneButton


func _ready() -> void:
	$DismissArea.gui_input.connect(_on_outside_input)
	done_button.pressed.connect(hide)


func open_from(button: Control) -> void:
	show()
	var anchor: Vector2 = button.global_position
	var available: Vector2 = get_viewport().get_visible_rect().size
	var width: float = minf(340.0, maxf(220.0, available.x - 16.0))
	var left: float = clampf(anchor.x, 8.0, maxf(8.0, available.x - width - 8.0))
	var top: float = anchor.y + button.size.y + 4.0
	var height: float = minf(520.0, maxf(150.0, available.y - top - 8.0))
	panel.position = Vector2(left, top)
	panel.size = Vector2(width, height)
	panel.get_node("Margin/Layout/Scroll").scroll_vertical = 0


func _on_outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
