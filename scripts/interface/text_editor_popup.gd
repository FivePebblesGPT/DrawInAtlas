class_name AtlasTextEditorPopup
extends Control
## In-editor modal: keyboard input never leaks into canvas tool shortcuts.

signal text_confirmed(index: int, expected: AtlasStroke, replacement: AtlasStroke,
	map_id: String, floor_id: String, layer_id: String)

var text_input: TextEdit
var family_picker: OptionButton
var size_input: SpinBox
var bold_toggle: CheckBox
var italic_toggle: CheckBox
var color_picker: ColorPickerButton
var apply_button: Button
var error_label: Label
var _panel: PanelContainer
var _index: int = -1
var _original: AtlasStroke
var _anchor: Vector2
var _map_id: String = ""
var _floor_id: String = ""
var _layer_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.08, 0.68)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_panel = PanelContainer.new()
	add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_panel.add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var title: Label = Label.new()
	title.text = "EDIT TEXT  ·  editable after saving"
	stack.add_child(title)
	text_input = TextEdit.new()
	text_input.placeholder_text = "Type a label or multiline note"
	text_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_input.custom_minimum_size = Vector2(1, 90)
	stack.add_child(text_input)
	var row: HBoxContainer = HBoxContainer.new()
	stack.add_child(row)
	family_picker = OptionButton.new()
	family_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for family: String in AtlasTextLayout.FAMILIES:
		family_picker.add_item(family)
	row.add_child(family_picker)
	size_input = SpinBox.new()
	size_input.min_value = AtlasTextLayout.MIN_SIZE
	size_input.max_value = AtlasTextLayout.MAX_SIZE
	size_input.step = 1
	size_input.value = 20
	size_input.tooltip_text = "Font size in board units"
	row.add_child(size_input)
	var style: HBoxContainer = HBoxContainer.new()
	stack.add_child(style)
	bold_toggle = CheckBox.new()
	bold_toggle.text = "Bold"
	style.add_child(bold_toggle)
	italic_toggle = CheckBox.new()
	italic_toggle.text = "Italic"
	style.add_child(italic_toggle)
	color_picker = ColorPickerButton.new()
	color_picker.color = Color.WHITE
	color_picker.custom_minimum_size = Vector2(40, 26)
	color_picker.tooltip_text = "Text color and opacity"
	style.add_child(color_picker)
	error_label = Label.new()
	error_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.5))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.custom_minimum_size.x = 1.0
	stack.add_child(error_label)
	error_label.hide()
	var foot: HBoxContainer = HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	stack.add_child(foot)
	var cancel: Button = Button.new()
	cancel.text = "Cancel (Esc)"
	cancel.pressed.connect(close_editor)
	foot.add_child(cancel)
	apply_button = Button.new()
	apply_button.text = "Place text"
	apply_button.pressed.connect(confirm_text)
	foot.add_child(apply_button)
	resized.connect(_layout_panel)
	hide()


func _layout_panel() -> void:
	if _panel == null:
		return
	var panel_size: Vector2 = Vector2(minf(445.0, maxf(180.0, size.x - 24.0)),
		minf(340.0, maxf(180.0, size.y - 16.0)))
	_panel.position = (size - panel_size) * 0.5
	_panel.size = panel_size


func open_editor(anchor: Vector2, original: AtlasStroke = null, index: int = -1,
		default_color: Color = Color.WHITE, map_id: String = "", floor_id: String = "",
		layer_id: String = "") -> void:
	_index = index
	_original = original.copy() if original != null else null
	_anchor = original.points[0] if original != null else anchor
	_map_id = map_id
	_floor_id = floor_id
	_layer_id = layer_id
	error_label.hide()
	text_input.text = original.text if original != null else ""
	family_picker.select(AtlasTextLayout.FAMILIES.find(original.font_family) if original != null else 0)
	size_input.value = original.width if original != null else 20.0
	bold_toggle.button_pressed = original.text_bold if original != null else false
	italic_toggle.button_pressed = original.text_italic if original != null else false
	color_picker.color = original.color if original != null else default_color
	apply_button.text = "Update text" if original != null else "Place text"
	show()
	move_to_front()
	_layout_panel()
	text_input.grab_focus()


func confirm_text() -> void:
	var next: AtlasStroke = AtlasTextLayout.make(_anchor, text_input.text,
		AtlasTextLayout.FAMILIES[family_picker.selected], float(size_input.value), color_picker.color,
		bold_toggle.button_pressed, italic_toggle.button_pressed)
	if next == null:
		show_error("Enter 1–2048 characters of nonblank text with a valid font and size.")
		text_input.grab_focus()
		return
	if _original != null:
		next.text_rotation = _original.text_rotation
	# The owner closes this dialog only after the history command succeeds.
	# An obsolete target or rejected mask must not silently discard the draft.
	text_confirmed.emit(_index, _original, next, _map_id, _floor_id, _layer_id)


func show_error(message: String) -> void:
	error_label.text = message
	error_label.show()


func close_editor() -> void:
	hide()
	_original = null
	_index = -1
	_map_id = ""
	_floor_id = ""
	_layer_id = ""
	error_label.hide()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and key.keycode == KEY_ESCAPE:
		close_editor()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.pressed and key.keycode == KEY_ESCAPE:
		close_editor()
	get_viewport().set_input_as_handled()
