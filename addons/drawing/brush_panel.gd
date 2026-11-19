class_name DrawingBrushPanel
extends VBoxContainer
## Controls are views of the workspace's one Canvas brush configuration.
## All previews were rendered by the native Hokusai path, not hand-drawn icons.

signal preset_selected(preset: String)
signal width_changed(px: float)
signal opacity_changed(ratio: float)
signal hardness_changed(ratio: float)
signal reset_requested()

const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")

var preset_buttons: Dictionary = {} # preset ID -> Button
var width_input: SpinBox
var opacity_input: SpinBox
var hardness_input: SpinBox
var reset_button: Button


func _init() -> void:
	name = "Brushes"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading: Label = Label.new()
	heading.text = "Native MyPaint brushes"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(heading)
	for i: int in range(SETTINGS.PRESETS.size()):
		var preset: String = SETTINGS.PRESETS[i]
		var button: Button = Button.new()
		button.name = "Preset_" + preset
		button.text = SETTINGS.NAMES[i]
		button.tooltip_text = SETTINGS.DESCRIPTIONS[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		var preview_path: String = SETTINGS.PREVIEW_ROOT + preset + ".png"
		var texture: Texture2D = (load(preview_path) as Texture2D) if ResourceLoader.exists(preview_path) else null
		button.icon = texture
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: preset_selected.emit(preset))
		preset_buttons[preset] = button
		add_child(button)
	add_child(HSeparator.new())
	width_input = _spin("Width (Drawing px)", 1.0, 96.0, 1.0)
	width_input.value_changed.connect(func(value: float) -> void: width_changed.emit(value))
	opacity_input = _spin("Opacity (% of preset)", 0.0, 100.0, 1.0)
	opacity_input.value_changed.connect(func(value: float) -> void: opacity_changed.emit(value / 100.0))
	hardness_input = _spin("Hardness (MyPaint %)", 0.0, 100.0, 1.0)
	hardness_input.value_changed.connect(func(value: float) -> void: hardness_changed.emit(value / 100.0))
	var guidance: Label = Label.new()
	guidance.text = "Opacity scales native base pigment; hardness shapes the dab edge. Stylus dynamics remain active."
	guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(guidance)
	reset_button = Button.new()
	reset_button.name = "ResetPreset"
	reset_button.text = "Reset selected brush"
	reset_button.tooltip_text = "Width 3 px, opacity 100%, selected preset's native hardness"
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	add_child(reset_button)


func _spin(label_text: String, low: float, high: float, step: float) -> SpinBox:
	var label_control: Label = Label.new()
	label_control.text = label_text
	label_control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label_control)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.focus_mode = Control.FOCUS_ALL
	spin.tooltip_text = label_text + "; input is clamped and applies to the next stroke"
	add_child(spin)
	return spin


func display(preset: String, width: float, opacity: float, hardness: float) -> void:
	for key: String in preset_buttons:
		(preset_buttons[key] as Button).set_pressed_no_signal(key == preset)
	width_input.set_value_no_signal(width)
	opacity_input.set_value_no_signal(opacity * 100.0)
	hardness_input.set_value_no_signal(hardness * 100.0)
