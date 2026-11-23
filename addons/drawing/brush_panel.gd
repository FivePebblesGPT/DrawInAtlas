class_name DrawingBrushPanel
extends VBoxContainer
## Compact view of the workspace's one native Brush/Eraser configuration.
## Preset images are Hokusai-rendered strokes; the labels live in accessibility
## names and tooltips rather than consuming the 190px dock's useful width.

signal preset_selected(preset: String)
signal width_changed(px: float)
signal opacity_changed(ratio: float)
signal hardness_changed(ratio: float)
signal density_changed(dabs_per_radius: float)
signal reset_requested()

const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")

var preset_buttons: Dictionary = {} # stable preset ID -> Button
var preset_grid: GridContainer
var width_input: SpinBox
var opacity_input: SpinBox
var hardness_input: SpinBox
var density_input: SpinBox
var reset_button: Button


func _init() -> void:
	name = "Brushes"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)
	preset_grid = GridContainer.new()
	preset_grid.name = "PresetGrid"
	preset_grid.columns = 2
	preset_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_grid.add_theme_constant_override("h_separation", 3)
	preset_grid.add_theme_constant_override("v_separation", 3)
	add_child(preset_grid)
	for i: int in range(SETTINGS.PRESETS.size()):
		var preset: String = SETTINGS.PRESETS[i]
		var button: Button = Button.new()
		button.name = "Preset_" + preset
		button.text = ""
		button.accessibility_name = SETTINGS.NAMES[i] + " brush preset"
		button.tooltip_text = SETTINGS.NAMES[i] + " — " + SETTINGS.DESCRIPTIONS[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(78, 38)
		var preview_path: String = SETTINGS.PREVIEW_ROOT + preset + ".png"
		var texture: Texture2D = (load(preview_path) as Texture2D) if ResourceLoader.exists(preview_path) else null
		button.icon = texture
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(func() -> void: preset_selected.emit(preset))
		preset_buttons[preset] = button
		preset_grid.add_child(button)
	width_input = _spin("Width", "Drawing pixels (1–96); nominal native dab diameter", 1.0, 96.0, 1.0)
	width_input.value_changed.connect(func(value: float) -> void: width_changed.emit(value))
	opacity_input = _spin("Opacity", "% of preset's native base pigment; preserves pressure curves", 0.0, 100.0, 1.0)
	opacity_input.value_changed.connect(func(value: float) -> void: opacity_changed.emit(value / 100.0))
	hardness_input = _spin("Edge", "MyPaint hardness (%); preserves pressure and speed dynamics", 0.0, 100.0, 1.0)
	hardness_input.value_changed.connect(func(value: float) -> void: hardness_changed.emit(value / 100.0))
	density_input = _spin("Dabs/r", "Native dabs per actual radius (1–8). Higher fills gaps but costs more raster work; not a flow or spray control", SETTINGS.DENSITY_MIN, SETTINGS.DENSITY_MAX, 0.25)
	density_input.value_changed.connect(func(value: float) -> void: density_changed.emit(value))
	reset_button = Button.new()
	reset_button.name = "ResetPreset"
	reset_button.text = "Reset"
	reset_button.accessibility_name = "Reset selected brush settings"
	reset_button.tooltip_text = "Reset width to 3px, opacity to 100%, and selected preset's native edge and dab density"
	reset_button.focus_mode = Control.FOCUS_ALL
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	add_child(reset_button)


func _spin(short_label: String, description: String, low: float, high: float, step: float) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var label_control: Label = Label.new()
	label_control.text = short_label
	label_control.custom_minimum_size.x = 58
	label_control.tooltip_text = description
	row.add_child(label_control)
	var spin: SpinBox = SpinBox.new()
	spin.name = short_label.replace("/", "") + "Input"
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.focus_mode = Control.FOCUS_ALL
	spin.accessibility_name = short_label + ": " + description
	spin.tooltip_text = description + "; affects only subsequent strokes"
	row.add_child(spin)
	return spin


func display(preset: String, width: float, opacity: float, hardness: float,
		density: float = -1.0) -> void:
	for key: String in preset_buttons:
		(preset_buttons[key] as Button).set_pressed_no_signal(key == preset)
	width_input.set_value_no_signal(width)
	opacity_input.set_value_no_signal(opacity * 100.0)
	hardness_input.set_value_no_signal(hardness * 100.0)
	density_input.set_value_no_signal(
		SETTINGS.default_density(preset) if density == -1.0 else density)
