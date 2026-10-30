class_name Sidebar
extends HBoxContainer
## Activity rail and view container. Place inside an HSplitContainer to resize it.

signal view_selected(view_id: StringName)
signal panel_toggled(expanded: bool)
signal search_changed(query: String)

var active_view: StringName = &"Maps"

@onready var _panel: PanelContainer = %ViewPanel
@onready var _title: Label = %ViewTitle
@onready var _search: LineEdit = %SearchInput
@onready var _buttons: Array[Button] = [%MapsButton, %SearchButton, %LayersButton, %ToolsButton]
@onready var _views: Dictionary[StringName, Control] = {
	&"Maps": %Maps,
	&"Search": %Search,
	&"Layers": %Layers,
	&"Tools": %Tools,
}


func _ready() -> void:
	for button: Button in _buttons:
		button.pressed.connect(_on_view_pressed.bind(StringName(button.name.trim_suffix("Button"))))
	%ToggleButton.pressed.connect(toggle_panel)
	%CloseButton.pressed.connect(set_panel_expanded.bind(false))
	_search.text_changed.connect(search_changed.emit)
	select_view(active_view)


func get_view_content(view_id: StringName) -> Control:
	return _views.get(view_id)


func get_search_query() -> String:
	return _search.text


func select_view(view_id: StringName) -> void:
	if not _views.has(view_id):
		push_warning("Unknown sidebar view: %s" % view_id)
		return
	active_view = view_id
	_title.text = String(view_id).to_upper()
	for id: StringName in _views:
		_views[id].visible = id == active_view
	set_panel_expanded(true)
	_update_buttons()
	if active_view == &"Search":
		_search.grab_focus()
	view_selected.emit(active_view)


func is_panel_expanded() -> bool:
	return _panel.visible


func set_panel_expanded(expanded: bool) -> void:
	if _panel.visible == expanded:
		return
	# Return keyboard focus to the rail before hiding the focused view.
	if not expanded:
		for button: Button in _buttons:
			if StringName(button.name.trim_suffix("Button")) == active_view:
				button.grab_focus()
	_panel.visible = expanded
	_update_buttons()
	panel_toggled.emit(expanded)


func toggle_panel() -> void:
	set_panel_expanded(not is_panel_expanded())


func _on_view_pressed(view_id: StringName) -> void:
	if active_view == view_id and is_panel_expanded():
		set_panel_expanded(false)
	else:
		select_view(view_id)


func _update_buttons() -> void:
	for button: Button in _buttons:
		var selected: bool = StringName(button.name.trim_suffix("Button")) == active_view
		button.set_pressed_no_signal(selected and is_panel_expanded())
