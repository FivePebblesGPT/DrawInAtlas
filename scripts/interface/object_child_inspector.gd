class_name AtlasObjectChildInspector
extends Window
## Live parent-local child selection and transform history, never a raster editor.

signal edit_source_requested(source_id: String)

var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new()
var child_list: ItemList
var details: Label
var open_button: Button
var undo_button: Button
var redo_button: Button
var reload_button: Button
var _rows: Array[String] = []


func _ready() -> void:
	name = "NestedObjectInspector"
	title = "Nested Object instances"
	size = Vector2i(520, 480)
	min_size = Vector2i(390, 360)
	close_requested.connect(hide)
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var heading: Label = Label.new()
	heading.text = "Select a child instance · edits affect the parent layout, not source pixels"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(heading)
	child_list = ItemList.new()
	child_list.name = "ChildInstances"
	child_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child_list.item_selected.connect(_select_row)
	root.add_child(child_list)
	var actions: HFlowContainer = HFlowContainer.new()
	root.add_child(actions)
	open_button = _button(actions, "Edit child source…", "EditChildSource", _open_child)
	open_button.tooltip_text = "Open the referenced asset in its own Object Editor tab; Save publishes its pixels"
	_button(actions, "←", "MoveLeft", func() -> void: _translate(Vector2.LEFT))
	_button(actions, "→", "MoveRight", func() -> void: _translate(Vector2.RIGHT))
	_button(actions, "↑", "MoveUp", func() -> void: _translate(Vector2.UP))
	_button(actions, "↓", "MoveDown", func() -> void: _translate(Vector2.DOWN))
	_button(actions, "⟲ 15°", "RotateLeft", func() -> void: _rotate(-PI / 12.0))
	_button(actions, "⟳ 15°", "RotateRight", func() -> void: _rotate(PI / 12.0))
	undo_button = _button(actions, "Undo child transform", "UndoChild", _undo)
	redo_button = _button(actions, "Redo child transform", "RedoChild", _redo)
	undo_button.tooltip_text = "Ctrl+Z · child transform history (not Atlas map history)"
	redo_button.tooltip_text = "Ctrl+Shift+Z or Ctrl+Y · child transform history"
	reload_button = _button(actions, "Reload parent", "ReloadChildren", _reload)
	for direction: String in ["MoveLeft", "MoveRight", "MoveUp", "MoveDown"]:
		(actions.get_node(direction) as Button).tooltip_text = "Move by one parent-local unit · Alt+arrow key"
	details = Label.new()
	details.name = "NestedObjectStatus"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(details)
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: InputEventKey = event as InputEventKey
	if key.ctrl_pressed and not key.alt_pressed and key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
	elif key.ctrl_pressed and not key.alt_pressed and not key.shift_pressed and key.keycode == KEY_Y:
		_redo()
	elif key.alt_pressed and not key.ctrl_pressed and not key.shift_pressed:
		match key.keycode:
			KEY_LEFT: _translate(Vector2.LEFT)
			KEY_RIGHT: _translate(Vector2.RIGHT)
			KEY_UP: _translate(Vector2.UP)
			KEY_DOWN: _translate(Vector2.DOWN)
			_: return
	else:
		return
	set_input_as_handled()


func _button(parent: Control, caption: String, identifier: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.name = identifier
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func bind_parent(library: AtlasObjectLibrary, parent_id: String) -> void:
	session.bind_parent(library, parent_id)
	if is_node_ready():
		refresh()


func refresh(message: String = "") -> void:
	if child_list == null:
		return
	_rows.clear()
	child_list.clear()
	var valid: bool = session.library != null and not session.parent_source_id.is_empty()
	if valid:
		for child: Dictionary in session.library.children_for_asset(session.parent_source_id):
			var source_info: Dictionary = session.library.asset_info(String(child["source_id"]))
			var source_name: String = String(source_info.get("name", "Missing source"))
			var label: String = "%s · %s · %s" % [source_name,
				String(child["id"]).left(14), child["status"]]
			var index: int = child_list.add_item(label)
			_rows.append(String(child["id"]))
			child_list.set_item_tooltip(index, "Stable instance ID: %s\nChild source: %s" % [
				child["id"], child["source_id"]])
			if child["id"] == session.selected_child_id:
				child_list.select(index)
	var record: Dictionary = session.selected_record()
	var ready: bool = not session.is_stale() and not record.is_empty()
	open_button.disabled = not ready or record["status"] != "linked"
	undo_button.disabled = not session.can_undo()
	redo_button.disabled = not session.can_redo()
	reload_button.disabled = not valid
	for button_id: String in ["MoveLeft", "MoveRight", "MoveUp", "MoveDown", "RotateLeft", "RotateRight"]:
		(actions_node().get_node(button_id) as Button).disabled = not ready
	if not message.is_empty():
		details.text = message
	elif session.is_stale():
		details.text = "Parent changed; reload to avoid overwriting concurrent edits"
	elif record.is_empty():
		details.text = "%d child instance(s). Select one to transform." % _rows.size()
	else:
		var source_name: String = String(session.library.asset_info(String(record["source_id"])).get(
			"name", "Missing source"))
		details.text = "%s · local origin (%.1f, %.1f) · source pixels unchanged" % [
			source_name, record["transform"][4], record["transform"][5]]


func actions_node() -> Control:
	return open_button.get_parent() as Control


func _select_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var selected: DrawingResult = session.select_child(_rows[index])
	refresh("" if selected.ok else selected.message)


func _translate(delta: Vector2) -> void:
	var changed: DrawingResult = session.translate_selected(delta)
	refresh("" if changed.ok else changed.message)


func _rotate(angle: float) -> void:
	var changed: DrawingResult = session.rotate_selected(angle)
	refresh("" if changed.ok else changed.message)


func _undo() -> void:
	var changed: DrawingResult = session.undo()
	refresh("" if changed.ok else changed.message)


func _redo() -> void:
	var changed: DrawingResult = session.redo()
	refresh("" if changed.ok else changed.message)


func _reload() -> void:
	session.bind_parent(session.library, session.parent_source_id)
	refresh()


func _open_child() -> void:
	var record: Dictionary = session.selected_record()
	if not record.is_empty() and record["status"] == "linked" and \
			session.library.asset_exists(String(record["source_id"])):
		edit_source_requested.emit(String(record["source_id"]))
	else:
		refresh("Child source is unavailable; no editor was opened")
