extends Control
## Standalone Drawing shell: no campaign, map or Atlas plugin dependencies.

const CANVAS_SCRIPT: Script = preload("res://scripts/canvas.gd")

var tabs: Array[Dictionary] = []
var active_tab: int = -1
var active_tool: String = "Brush"
var active_color: Color = Color(0.12, 0.20, 0.35)
var canvas: Control
var tab_bar: TabBar
var layers: Tree
var status: Label
var width_spin: SpinBox
var snap_toggle: CheckButton
var history_label: Label
var open_dialog: FileDialog
var save_dialog: FileDialog
var new_counter: int = 0
## Application preference; existing selection entries survive toggling it off.
var record_selection_history: bool = false
var _before_gesture: DrawingHistoryContext
var _last_selection_context: DrawingHistoryContext
var _restoring_context: bool = false


func _ready() -> void:
	_build_interface()
	new_drawing()


func _build_interface() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var menu: HBoxContainer = HBoxContainer.new()
	root.add_child(menu)
	_add_menu(menu, "File", ["New", "Open…", "Save", "Save As…"],
		[Callable(self, "new_drawing"), Callable(self, "_ask_open"),
		Callable(self, "_save"), Callable(self, "_ask_save")])
	_add_menu(menu, "Edit", ["Undo", "Redo"],
		[Callable(self, "_undo"), Callable(self, "_redo")])
	_add_menu(menu, "Layer", ["Add group", "Add raster layer", "Remove selected", "Toggle visibility"],
		[Callable(self, "_add_group"), Callable(self, "_add_layer"),
		Callable(self, "_remove_layer"), Callable(self, "_toggle_visibility")])
	_add_menu(menu, "View", ["Zoom in", "Zoom out", "Reset view"],
		[func() -> void: _zoom(1.25), func() -> void: _zoom(0.8), func() -> void: _reset_view()])
	var divider: VSeparator = VSeparator.new()
	divider.custom_minimum_size.x = 14
	menu.add_child(divider)
	var label: Label = Label.new()
	label.text = "Options"
	menu.add_child(label)
	var option_scroll: ScrollContainer = ScrollContainer.new()
	option_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	option_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(option_scroll)
	var options: HBoxContainer = HBoxContainer.new()
	option_scroll.add_child(options)
	width_spin = SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 96
	width_spin.value = 3
	width_spin.prefix = "Brush px"
	width_spin.custom_minimum_size.x = 150
	width_spin.value_changed.connect(func(value: float) -> void: canvas.brush_width = value)
	options.add_child(width_spin)
	snap_toggle = CheckButton.new()
	snap_toggle.text = "Snap (8 px)"
	snap_toggle.toggled.connect(func(enabled: bool) -> void: canvas.grid_spacing = 8 if enabled else 0)
	options.add_child(snap_toggle)
	var selection_history_toggle: CheckButton = CheckButton.new()
	selection_history_toggle.text = "Record selection changes in Undo History"
	selection_history_toggle.button_pressed = false
	selection_history_toggle.toggled.connect(_selection_history_preference_changed)
	options.add_child(selection_history_toggle)
	var tabs_line: HBoxContainer = HBoxContainer.new()
	root.add_child(tabs_line)
	tab_bar = TabBar.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.tab_changed.connect(_activate)
	tabs_line.add_child(tab_bar)
	var add_tab: Button = Button.new()
	add_tab.text = "+"
	add_tab.pressed.connect(new_drawing)
	tabs_line.add_child(add_tab)
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size.x = 98
	content.add_child(rail)
	for name: String in ["Brush", "Eraser", "Select", "Move", "Pan"]:
		var button: Button = Button.new()
		button.text = name
		button.tooltip_text = "Drawing tool: " + name
		button.pressed.connect(_change_tool.bind(name))
		rail.add_child(button)
	canvas = CANVAS_SCRIPT.new() as Control
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(400, 280)
	canvas.gesture_started.connect(_gesture_started)
	canvas.gesture_committed.connect(_canvas_changed)
	canvas.selection_changed.connect(_selection_changed)
	canvas.canvas_error.connect(_show_error)
	canvas.view_changed.connect(_update_status)
	content.add_child(canvas)
	canvas.color_rgba = _pack_color(active_color)
	var inspector: TabContainer = TabContainer.new()
	inspector.custom_minimum_size.x = 260
	content.add_child(inspector)
	var color_pane: VBoxContainer = VBoxContainer.new()
	color_pane.name = "Colors"
	inspector.add_child(color_pane)
	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.text = "Brush color"
	picker.color = active_color
	picker.color_changed.connect(func(value: Color) -> void:
		active_color = value
		canvas.color_rgba = _pack_color(value))
	color_pane.add_child(picker)
	var layer_pane: VBoxContainer = VBoxContainer.new()
	layer_pane.name = "Layers"
	inspector.add_child(layer_pane)
	var layer_actions: HBoxContainer = HBoxContainer.new()
	layer_pane.add_child(layer_actions)
	for entry: Dictionary in [{"label": "+ Group", "handler": Callable(self, "_add_group")},
		{"label": "+ Layer", "handler": Callable(self, "_add_layer")}]:
		var action: Button = Button.new()
		action.text = entry["label"]
		action.pressed.connect(entry["handler"])
		layer_actions.add_child(action)
	layers = Tree.new()
	layers.hide_root = true
	layers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layers.item_selected.connect(_layer_selected)
	layer_pane.add_child(layers)
	var history_pane: VBoxContainer = VBoxContainer.new()
	history_pane.name = "History"
	inspector.add_child(history_pane)
	history_label = Label.new()
	history_label.text = "Raster gestures: Undo / Redo"
	history_pane.add_child(history_label)
	status = Label.new()
	status.text = "Ready"
	root.add_child(status)
	open_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.file_selected.connect(_open_file)
	save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.file_selected.connect(_save_file)


func _make_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.drawing ; Drawing document"])
	dialog.size = Vector2i(850, 540)
	add_child(dialog)
	return dialog


func _add_menu(bar: HBoxContainer, name: String, labels: Array[String], handlers: Array[Callable]) -> void:
	var menu: MenuButton = MenuButton.new()
	menu.text = name
	bar.add_child(menu)
	var popup: PopupMenu = menu.get_popup()
	for index: int in range(labels.size()):
		popup.add_item(labels[index], index)
	popup.id_pressed.connect(func(index: int) -> void: handlers[index].call())


func _pack_color(value: Color) -> int:
	return clampi(roundi(value.r * 255.0), 0, 255) | (clampi(roundi(value.g * 255.0), 0, 255) << 8) | (clampi(roundi(value.b * 255.0), 0, 255) << 16) | (clampi(roundi(value.a * 255.0), 0, 255) << 24)


func current_document() -> DrawingDocument:
	return tabs[active_tab]["document"] as DrawingDocument if active_tab >= 0 else null


func current_layer() -> String:
	return String(tabs[active_tab]["layer"]) if active_tab >= 0 else ""


func new_drawing() -> void:
	new_counter += 1
	var document: DrawingDocument = DrawingDocument.new()
	document.record_selection_history = record_selection_history
	var group: DrawingResult = document.create_layer(DrawingLayerNode.GROUP, "Group 1")
	var raster: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1", String(group.value))
	tabs.append({"document": document, "path": "", "title": "Untitled %d" % new_counter,
		"layer": raster.value, "saved": -1})
	tab_bar.add_tab("Untitled %d *" % new_counter)
	_activate(tabs.size() - 1)


func _activate(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	active_tab = index
	tab_bar.current_tab = index
	canvas.document = current_document()
	canvas.layer_id = current_layer()
	canvas.selected = Rect2i()
	canvas.session = null
	canvas.queue_redraw()
	_refresh_layers()
	_last_selection_context = _capture_context()
	_update_status()


func _refresh_layers() -> void:
	layers.clear()
	var root: TreeItem = layers.create_item()
	if current_document() != null:
		_append_layers(root, DrawingDocument.ROOT_ID)


func _append_layers(parent: TreeItem, group_id: String) -> void:
	for node_id: String in current_document().list_children(group_id):
		var info: Dictionary = current_document().node_metadata(node_id)
		var item: TreeItem = layers.create_item(parent)
		item.set_text(0, ("◉ " if info["visible"] else "○ ") + info["name"])
		item.set_metadata(0, node_id)
		if info["kind"] == DrawingLayerNode.GROUP:
			_append_layers(item, node_id)
		if node_id == current_layer():
			item.select(0)


func _layer_selected() -> void:
	var before: DrawingHistoryContext = _capture_context()
	var selected_item: TreeItem = layers.get_selected()
	if selected_item == null:
		return
	var node_id: String = String(selected_item.get_metadata(0))
	if current_document().node_metadata(node_id).get("kind") == DrawingLayerNode.RASTER:
		tabs[active_tab]["layer"] = node_id
		canvas.layer_id = node_id
	_record_selection_context(before)
	_update_status()


func _add_group() -> void:
	if active_tab < 0:
		return
	var added: DrawingResult = current_document().create_layer(DrawingLayerNode.GROUP, "Group %d" % current_document().layer_count())
	if added.ok:
		_after_edit()
	else:
		_show_error(added.message)


func _add_layer() -> void:
	if active_tab < 0:
		return
	var existing: DrawingLayerNode = current_document().inspect_node(current_layer())
	var parent: String = existing.parent_id if existing != null else DrawingDocument.ROOT_ID
	var added: DrawingResult = current_document().create_layer(DrawingLayerNode.RASTER,
		"Layer %d" % current_document().layer_count(), parent)
	if added.ok:
		tabs[active_tab]["layer"] = added.value
		canvas.layer_id = String(added.value)
		_after_edit()
	else:
		_show_error(added.message)


func _remove_layer() -> void:
	if active_tab < 0:
		return
	var removed: DrawingResult = current_document().remove_subtree(current_layer())
	if removed.ok:
		var replacement: DrawingResult = current_document().create_layer(DrawingLayerNode.RASTER, "Layer")
		tabs[active_tab]["layer"] = replacement.value
		canvas.layer_id = String(replacement.value)
		_after_edit()
	else:
		_show_error(removed.message)


func _toggle_visibility() -> void:
	if active_tab < 0:
		return
	var info: Dictionary = current_document().node_metadata(current_layer())
	var changed: DrawingResult = current_document().set_visibility(current_layer(), not info.get("visible", true))
	if changed.ok:
		_after_edit()
	else:
		_show_error(changed.message)


func _change_tool(name: String) -> void:
	active_tool = name
	canvas.tool = name
	_update_status()


func _capture_context() -> DrawingHistoryContext:
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	if current_document() == null:
		return context
	context.document_id = current_document().id
	if not current_layer().is_empty():
		context.selected_layer_ids.append(current_layer())
	context.editor_mode = active_tool
	context.selected_rect = canvas.selected
	return context


func _selection_history_preference_changed(enabled: bool) -> void:
	record_selection_history = enabled
	for tab: Dictionary in tabs:
		(tab["document"] as DrawingDocument).record_selection_history = enabled


func _gesture_started() -> void:
	_before_gesture = _capture_context()


func _selection_changed(_area: Rect2i) -> void:
	_record_selection_context(_last_selection_context)
	_update_status()


func _record_selection_context(before: DrawingHistoryContext) -> void:
	if active_tab < 0 or _restoring_context:
		return
	var after: DrawingHistoryContext = _capture_context()
	if before != null:
		current_document().record_selection_change(before, after)
	_last_selection_context = after


func _restore_context(context: DrawingHistoryContext) -> void:
	if context == null or context.document_id != current_document().id:
		return
	_restoring_context = true
	if not context.selected_layer_ids.is_empty() and current_document().has_node(context.selected_layer_ids[0]):
		tabs[active_tab]["layer"] = context.selected_layer_ids[0]
		canvas.layer_id = context.selected_layer_ids[0]
	canvas.selected = context.selected_rect
	if context.editor_mode in ["Brush", "Eraser", "Select", "Move", "Pan"]:
		_change_tool(context.editor_mode)
	_last_selection_context = _capture_context()
	_restoring_context = false


func _canvas_changed(_result: DrawingResult) -> void:
	if _before_gesture != null:
		current_document().annotate_latest_gesture(_before_gesture, _capture_context())
	_before_gesture = null
	_last_selection_context = _capture_context()
	_after_edit()


func _after_edit() -> void:
	_refresh_layers()
	_update_status()
	canvas.queue_redraw()


func _update_status() -> void:
	if active_tab < 0:
		return
	var document: DrawingDocument = current_document()
	var dirty: bool = document.is_dirty()
	tab_bar.set_tab_title(active_tab, String(tabs[active_tab]["title"]) + (" *" if dirty else ""))
	status.text = "%s | %s | zoom %.0f%% | revision %d | %s" % [active_tool,
		current_layer(), canvas.zoom * 100.0, document.revision,
		"Unsaved changes" if dirty else "Saved"]


func _undo() -> void:
	if active_tab < 0:
		return
	var result: DrawingResult = current_document().undo()
	if result.ok:
		_restore_context(result.value as DrawingHistoryContext)
		_after_edit()
	else:
		_show_error(result.message)


func _redo() -> void:
	if active_tab < 0:
		return
	var result: DrawingResult = current_document().redo()
	if result.ok:
		_restore_context(result.value as DrawingHistoryContext)
		_after_edit()
	else:
		_show_error(result.message)


func _zoom(factor: float) -> void:
	canvas.zoom = clampf(canvas.zoom * factor, 0.5, 24.0)
	canvas.queue_redraw()
	_update_status()


func _reset_view() -> void:
	canvas.zoom = 4.0
	canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	_update_status()


func _ask_open() -> void:
	open_dialog.popup_centered()


func _ask_save() -> void:
	if active_tab >= 0:
		save_dialog.popup_centered()


func _save() -> void:
	if active_tab < 0:
		return
	var path: String = tabs[active_tab]["path"]
	if path.is_empty():
		_ask_save()
	else:
		_save_file(path)


func _save_file(path: String) -> void:
	if active_tab < 0:
		return
	if not path.to_lower().ends_with(".drawing"):
		path += ".drawing"
	var result: DrawingResult = DrawingFileIO.save(current_document(), path)
	if result.ok:
		tabs[active_tab]["path"] = path
		tabs[active_tab]["title"] = path.get_file()
		_update_status()
	else:
		_show_error(result.message)


func _open_file(path: String) -> void:
	var opened: DrawingResult = DrawingFileIO.open(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var document: DrawingDocument = opened.value as DrawingDocument
	document.record_selection_history = record_selection_history
	var raster: String = _first_raster(document, DrawingDocument.ROOT_ID)
	if raster.is_empty():
		var added: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1")
		raster = added.value
	tabs.append({"document": document, "path": path, "title": path.get_file(), "layer": raster})
	tab_bar.add_tab(path.get_file())
	_activate(tabs.size() - 1)


func _first_raster(document: DrawingDocument, parent: String) -> String:
	for node_id: String in document.list_children(parent):
		var info: Dictionary = document.node_metadata(node_id)
		if info["kind"] == DrawingLayerNode.RASTER:
			return node_id
		if info["kind"] == DrawingLayerNode.GROUP:
			var nested: String = _first_raster(document, node_id)
			if not nested.is_empty():
				return nested
	return ""


func _show_error(message: String) -> void:
	status.text = "Error: " + message
	push_warning("Drawing: " + message)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed):
		return
	match key.keycode:
		KEY_N: new_drawing()
		KEY_O: _ask_open()
		KEY_S: _save()
		KEY_Z:
			if key.shift_pressed:
				_redo()
			else:
				_undo()
		KEY_Y: _redo()
		_: return
	get_viewport().set_input_as_handled()
