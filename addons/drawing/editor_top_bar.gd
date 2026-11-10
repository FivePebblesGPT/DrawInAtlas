extends HBoxContainer
## Drawing-owned compact workspace chrome. The host binds commands and controls;
## no document edits, Atlas types, or pixels live in this component.

var menu_region: HBoxContainer
var divider: VSeparator
var options_scroll: ScrollContainer
var options_region: HBoxContainer
var left_cue: Button
var right_cue: Button
var more_menu: MenuButton
var _menus: Array[MenuButton] = []
var _entries: Array[Dictionary] = []
var _more_actions: Array[Callable] = []
# Map original menu/item coordinates to the corresponding More popup item.
var _more_item_ids: Dictionary = {}
var _unused_options: Control
var active_options: String = ""
const OPTION_STEP: int = 96
const RESERVED_OPTIONS_WIDTH: float = 175.0


func _ready() -> void:
	name = "EditorTopBar"
	custom_minimum_size.y = 34
	clip_contents = true
	# Keep inactive controls owned by this UI rather than orphaning nodes when
	# tools change. The hidden stash has no effect on the horizontal layout.
	_unused_options = Control.new()
	_unused_options.name = "InactiveToolOptions"
	_unused_options.visible = false
	add_child(_unused_options)
	menu_region = HBoxContainer.new()
	menu_region.name = "MenuRegion"
	add_child(menu_region)
	more_menu = MenuButton.new()
	more_menu.text = "More ▾"
	more_menu.tooltip_text = "Additional application menus"
	more_menu.focus_mode = Control.FOCUS_ALL
	more_menu.visible = false
	more_menu.get_popup().id_pressed.connect(_more_selected)
	divider = VSeparator.new()
	divider.name = "BarDivider"
	divider.custom_minimum_size.x = 10
	add_child(divider)
	left_cue = _cue("‹", -1)
	options_scroll = ScrollContainer.new()
	options_scroll.name = "ToolOptionsRegion"
	options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_scroll.custom_minimum_size.x = 96
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(options_scroll)
	options_region = HBoxContainer.new()
	options_region.name = "ActiveToolOptions"
	options_scroll.add_child(options_region)
	right_cue = _cue("›", 1)
	options_scroll.get_h_scroll_bar().value_changed.connect(func(_value: float) -> void:
		_refresh_scroll_state())
	resized.connect(_refresh_layout)
	get_viewport().size_changed.connect(_refresh_layout)
	options_region.resized.connect(_refresh_scroll_state)
	# The scroll viewport can shrink without changing the option content size;
	# update overflow cues when its own width changes too.
	options_scroll.resized.connect(_refresh_scroll_state)
	call_deferred("_refresh_layout")


func _cue(glyph: String, direction: int) -> Button:
	var button: Button = Button.new()
	button.text = glyph
	button.tooltip_text = "Scroll tool settings %s" % ("left" if direction < 0 else "right")
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.x = 28
	button.visible = false
	button.pressed.connect(func() -> void: scroll_options(direction * OPTION_STEP))
	add_child(button)
	return button


func add_menu_spec(title: String, labels: Array, handlers: Array) -> void:
	assert(labels.size() == handlers.size())
	var menu: MenuButton = MenuButton.new()
	menu.text = title
	menu.tooltip_text = "%s commands" % title
	menu.focus_mode = Control.FOCUS_ALL
	menu_region.add_child(menu)
	var popup: PopupMenu = menu.get_popup()
	for index: int in range(labels.size()):
		popup.add_item(labels[index], index)
	popup.id_pressed.connect(func(index: int) -> void:
		if index >= 0 and index < handlers.size():
			handlers[index].call())
	_menus.append(menu)
	_entries.append({"title": title, "labels": labels, "handlers": handlers})
	if more_menu.get_parent() == null:
		menu_region.add_child(more_menu)
	else:
		menu_region.move_child(more_menu, menu_region.get_child_count() - 1)
	call_deferred("_refresh_layout")


func set_menu_checked(menu_name: String, index: int, enabled: bool) -> void:
	for menu_index: int in range(_menus.size()):
		if _menus[menu_index].text != menu_name:
			continue
		var popup: PopupMenu = _menus[menu_index].get_popup()
		if index >= 0 and index < popup.item_count:
			popup.set_item_as_checkable(index, true)
			popup.set_item_checked(index, enabled)
			# The visible command can live in the overflow popup. Keep its
			# checkmark up to date without rebuilding an open native popup.
			var more_id: int = int(_more_item_ids.get(Vector2i(menu_index, index), -1))
			if more_id >= 0:
				var more_popup: PopupMenu = more_menu.get_popup()
				more_popup.set_item_as_checkable(more_id, true)
				more_popup.set_item_checked(more_id, enabled)
		return


func set_tool_controls(tool_name: String, controls: Array[Control]) -> void:
	active_options = tool_name
	for child: Node in options_region.get_children():
		options_region.remove_child(child)
		_unused_options.add_child(child)
	for control: Control in controls:
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		options_region.add_child(control)
		if not control.focus_entered.is_connected(_focus_option.bind(control)):
			control.focus_entered.connect(_focus_option.bind(control))
	options_scroll.scroll_horizontal = 0
	call_deferred("_refresh_layout")
	call_deferred("_refresh_scroll_state")


func _focus_option(control: Control) -> void:
	options_scroll.ensure_control_visible.call_deferred(control)
	call_deferred("_refresh_scroll_state")


func scroll_options(amount: int) -> void:
	options_scroll.scroll_horizontal = maxi(0, options_scroll.scroll_horizontal + amount)
	call_deferred("_refresh_scroll_state")


## Shift+vertical wheel scrolls crowded options. Ordinary wheel adjusts a numeric field.
func consume_option_wheel(event: InputEvent, source: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index not in [MOUSE_BUTTON_WHEEL_UP,
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return
	var direction: int = -1 if mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1
	if mouse.shift_pressed or mouse.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		scroll_options(direction * OPTION_STEP)
		source.accept_event()
	elif source is SpinBox:
		# Explicitly handle the hovered field: relying on the SpinBox focus state
		# makes the first wheel event inconsistent across Godot/theme versions.
		var spin: SpinBox = source as SpinBox
		spin.value = clampf(spin.value - direction * spin.step, spin.min_value, spin.max_value)
		source.accept_event()


func _refresh_layout() -> void:
	if menu_region == null:
		return
	# Reserve a real viewport for tool options. This uses measured Godot menu
	# minimum widths rather than a fixed set of guessed window breakpoints;
	# theme scaling, translation and platform fonts all affect these widths.
	var space: float = maxf(0.0, size.x - RESERVED_OPTIONS_WIDTH - divider.custom_minimum_size.x - 20.0)
	var menu_width: float = 0.0
	var visible_count: int = 0
	for menu: MenuButton in _menus:
		var required: float = menu.get_combined_minimum_size().x + 5.0
		var more_reserve: float = more_menu.get_combined_minimum_size().x + 10.0
		if menu_width + required + more_reserve > space and visible_count >= 2:
			break
		visible_count += 1
		menu_width += required
	var more: PopupMenu = more_menu.get_popup()
	more.clear()
	_more_actions.clear()
	_more_item_ids.clear()
	for index: int in range(_menus.size()):
		_menus[index].visible = index < visible_count
		if index < visible_count:
			continue
		var spec: Dictionary = _entries[index]
		var labels: Array = spec["labels"]
		var handlers: Array = spec["handlers"]
		var original: PopupMenu = _menus[index].get_popup()
		for command: int in range(labels.size()):
			var item_id: int = _more_actions.size()
			more.add_item("%s › %s" % [spec["title"], labels[command]], item_id)
			_more_actions.append(handlers[command])
			_more_item_ids[Vector2i(index, command)] = item_id
			# A narrow window must not lose the state of View/Window toggles.
			# Consult the real PopupMenu so a later resize preserves updates.
			if original.is_item_checkable(command):
				more.set_item_as_checkable(item_id, true)
				more.set_item_checked(item_id, original.is_item_checked(command))
			more.set_item_disabled(item_id, original.is_item_disabled(command))
	more_menu.visible = not _more_actions.is_empty()
	call_deferred("_refresh_scroll_state")

func _more_selected(index: int) -> void:
	if index >= 0 and index < _more_actions.size():
		_more_actions[index].call()


func _refresh_scroll_state() -> void:
	if options_scroll == null:
		return
	var bar: HScrollBar = options_scroll.get_h_scroll_bar()
	var overflow: bool = options_region.size.x > options_scroll.size.x + 1.0
	left_cue.visible = overflow
	right_cue.visible = overflow
	left_cue.disabled = not overflow or options_scroll.scroll_horizontal <= 0
	right_cue.disabled = not overflow or options_scroll.scroll_horizontal >= int(maxf(0.0, bar.max_value - bar.page))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and (mouse.shift_pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
			scroll_options(-OPTION_STEP if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else OPTION_STEP)
			accept_event()
