extends Control
## Shared Drawing shell; the host supplies Object Asset publication callbacks.
## No campaign, map, Atlas registry or history imports in this UI.

const CANVAS_SCRIPT: Script = preload("res://addons/drawing/canvas.gd")
const TOP_BAR_SCRIPT: Script = preload("res://addons/drawing/editor_top_bar.gd")

signal object_tab_closed(session: DrawingObjectEditorSession)

var start_blank_document: bool = true
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
var top_bar: HBoxContainer
var inspector: TabContainer
var dock_split: HSplitContainer
var selection_history_toggle: CheckButton
var history_label: Label
var open_dialog: FileDialog
var save_dialog: FileDialog
var new_counter: int = 0
## Application preference; existing selection entries survive toggling it off.
var record_selection_history: bool = false
var _before_gesture: DrawingHistoryContext
var _last_selection_context: DrawingHistoryContext
var _restoring_context: bool = false
var text_dialog: ConfirmationDialog
var text_edit: TextEdit
var text_font: OptionButton
var text_size: SpinBox
var text_angle: SpinBox
var text_alignment: OptionButton
var text_color: ColorPickerButton
var text_target: String = ""
var text_position: Vector2i = Vector2i.ZERO
var layer_search: LineEdit
var layer_page: int = 0
var layer_page_label: Label
var object_open_dialog: FileDialog
var close_dialog: ConfirmationDialog
var rename_dialog: ConfirmationDialog
var rename_field: LineEdit
var frame_dialog: ConfirmationDialog
var frame_fields: Array[SpinBox] = []
var variant_dialog: ConfirmationDialog
var variant_name: LineEdit
var _closing_index: int = -1
var _close_after_save: bool = false
var _local_save_as: bool = false
const ROW_PAGE: int = 200



func _ready() -> void:
	_build_interface()
	if start_blank_document:
		new_drawing()


func _build_interface() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	top_bar = TOP_BAR_SCRIPT.new() as HBoxContainer
	root.add_child(top_bar)
	# Eight application menus; object-source commands remain accessible in File,
	# Image and Window without a redundant ninth menu or action toolbar.
	top_bar.add_menu_spec("File", ["New  Ctrl+N", "Open…  Ctrl+O", "Save  Ctrl+S",
		"Save As…  Ctrl+Shift+S", "New Object source", "Open Object source…"],
		[Callable(self, "new_drawing"), Callable(self, "_ask_open"),
		Callable(self, "_save"), Callable(self, "_ask_save"),
		Callable(self, "new_object"), Callable(self, "_ask_open_object")])
	top_bar.add_menu_spec("Edit", ["Undo  Ctrl+Z", "Redo  Ctrl+Y",
		"Record selection changes in Undo History"],
		[Callable(self, "_undo"), Callable(self, "_redo"),
		Callable(self, "_toggle_selection_history")])
	top_bar.add_menu_spec("View", ["Zoom in", "Zoom out", "Reset view"],
		[func() -> void: _zoom(1.25), func() -> void: _zoom(0.8),
		func() -> void: _reset_view()])
	top_bar.add_menu_spec("Image", ["Rasterize text layer", "Object frame…"],
		[Callable(self, "_rasterize_text"), Callable(self, "_ask_object_frame")])
	top_bar.add_menu_spec("Layers", ["Add group", "Add raster layer",
		"Remove selected", "Toggle visibility"],
		[Callable(self, "_add_group"), Callable(self, "_add_layer"),
		Callable(self, "_remove_layer"), Callable(self, "_toggle_visibility")])
	top_bar.add_menu_spec("Select", ["Rectangle selection", "Move selected pixels"],
		[Callable(self, "_change_tool").bind("Select"),
		Callable(self, "_change_tool").bind("Move")])
	top_bar.add_menu_spec("Window", ["Show/hide panel dock", "Reset panel width",
		"Rename Object…", "Save Object As…", "Close tab  Ctrl+W"],
		[Callable(self, "_toggle_dock"), Callable(self, "_reset_dock_width"),
		Callable(self, "_ask_rename_object"), Callable(self, "_ask_save"),
		Callable(self, "_request_close_current")])
	top_bar.add_menu_spec("Help", ["About Drawing workspace"],
		[Callable(self, "_show_about_workspace")])
	top_bar.set_menu_checked("Edit", 2, record_selection_history)
	width_spin = SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 96
	width_spin.value = 3
	width_spin.prefix = "Brush px"
	width_spin.tooltip_text = "Stroke width in Drawing pixels"
	width_spin.custom_minimum_size.x = 170
	width_spin.value_changed.connect(func(value: float) -> void: canvas.brush_width = value)
	width_spin.gui_input.connect(func(event: InputEvent) -> void:
		top_bar.consume_option_wheel(event, width_spin))
	snap_toggle = CheckButton.new()
	snap_toggle.text = "Snap (8 px)"
	snap_toggle.tooltip_text = "Generic Drawing grid snap"
	snap_toggle.toggled.connect(func(enabled: bool) -> void: canvas.grid_spacing = 8 if enabled else 0)
	_refresh_tool_options()
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
	var close_tab: Button = Button.new()
	close_tab.text = "×"
	close_tab.tooltip_text = "Close current tab (with unsaved-changes prompt)"
	close_tab.pressed.connect(_request_close_current)
	tabs_line.add_child(close_tab)
	dock_split = HSplitContainer.new()
	dock_split.name = "WorkspaceSplit"
	dock_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(dock_split)
	var edit_region: HBoxContainer = HBoxContainer.new()
	edit_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_split.add_child(edit_region)
	var rail: VBoxContainer = VBoxContainer.new()
	rail.custom_minimum_size.x = 76
	edit_region.add_child(rail)
	for name: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]:
		var button: Button = Button.new()
		button.text = name
		button.tooltip_text = "Drawing tool: " + name
		button.pressed.connect(_change_tool.bind(name))
		rail.add_child(button)
	canvas = CANVAS_SCRIPT.new() as Control
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(125, 190)
	canvas.gesture_started.connect(_gesture_started)
	canvas.gesture_committed.connect(_canvas_changed)
	canvas.selection_changed.connect(_selection_changed)
	canvas.canvas_error.connect(_show_error)
	canvas.view_changed.connect(_update_status)
	canvas.cursor_moved.connect(_update_status)
	canvas.resized.connect(_update_status)
	canvas.text_requested.connect(_edit_text_at)
	canvas.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_update_status())
	edit_region.add_child(canvas)
	canvas.color_rgba = _pack_color(active_color)
	inspector = TabContainer.new()
	inspector.name = "PanelDock"
	inspector.custom_minimum_size.x = 160
	dock_split.add_child(inspector)
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
	layer_search = LineEdit.new()
	layer_search.placeholder_text = "Find layers and text labels…"
	layer_search.text_changed.connect(func(_value: String) -> void:
		layer_page = 0
		_refresh_layers())
	layer_pane.add_child(layer_search)
	var pages: HBoxContainer = HBoxContainer.new()
	layer_pane.add_child(pages)
	for entry: Dictionary in [{"text": "‹", "dir": -1}, {"text": "›", "dir": 1}]:
		var page_button: Button = Button.new()
		page_button.text = entry["text"]
		page_button.pressed.connect(_change_layer_page.bind(entry["dir"]))
		pages.add_child(page_button)
	layer_page_label = Label.new()
	pages.add_child(layer_page_label)
	layers = Tree.new()
	layers.hide_root = true
	layers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layers.item_selected.connect(_layer_selected)
	layer_pane.add_child(layers)
	var history_pane: VBoxContainer = VBoxContainer.new()
	history_pane.name = "History"
	inspector.add_child(history_pane)
	history_label = Label.new()
	history_label.text = "Content gestures: Undo / Redo"
	history_pane.add_child(history_label)
	selection_history_toggle = CheckButton.new()
	selection_history_toggle.text = "Record selection changes in Undo History"
	selection_history_toggle.tooltip_text = "Workspace preference; OFF by default, never marks a document dirty"
	selection_history_toggle.button_pressed = record_selection_history
	selection_history_toggle.toggled.connect(_selection_history_preference_changed)
	history_pane.add_child(selection_history_toggle)
	status = Label.new()
	status.name = "WorkspaceStatus"
	status.text = "Ready"
	# Status contains unbounded cursor/asset IDs; never let it force the whole
	# workspace wider than a narrow window.
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(status)
	var about: AcceptDialog = AcceptDialog.new()
	about.name = "WorkspaceAbout"
	about.title = "Drawing workspace"
	about.dialog_text = "Independent Drawing / Object Editor workspace.\nHelp: File, Edit, View, Image, Layers, Select, Window."
	add_child(about)
	open_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	open_dialog.file_selected.connect(_open_file)
	save_dialog = _make_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	save_dialog.file_selected.connect(_save_file)
	save_dialog.canceled.connect(_cancel_pending_close)
	object_open_dialog = _make_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	object_open_dialog.file_selected.connect(_open_object_file)
	close_dialog = ConfirmationDialog.new()
	close_dialog.title = "Unsaved Object/Drawing changes"
	close_dialog.dialog_text = "Save changes before closing this tab?"
	add_child(close_dialog)
	close_dialog.confirmed.connect(_save_and_close)
	close_dialog.add_button("Discard", false, "discard")
	close_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard":
			close_dialog.hide()
			_close_index(_closing_index))
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.title = "Object source name"
	add_child(rename_dialog)
	rename_field = LineEdit.new()
	rename_field.custom_minimum_size.x = 310
	rename_dialog.add_child(rename_field)
	rename_dialog.confirmed.connect(_rename_object)
	frame_dialog = ConfirmationDialog.new()
	frame_dialog.title = "Object-local origin and bounds"
	add_child(frame_dialog)
	var frame_grid: GridContainer = GridContainer.new()
	frame_grid.columns = 2
	frame_dialog.add_child(frame_grid)
	for entry: Dictionary in [{"label": "Origin X", "nonnegative": false},
		{"label": "Origin Y", "nonnegative": false},
		{"label": "Bounds X", "nonnegative": false},
		{"label": "Bounds Y", "nonnegative": false},
		{"label": "Bounds width", "nonnegative": true},
		{"label": "Bounds height", "nonnegative": true}]:
		var field_label: Label = Label.new()
		field_label.text = entry["label"]
		frame_grid.add_child(field_label)
		var field: SpinBox = SpinBox.new()
		field.step = 1.0
		field.min_value = 0 if entry["nonnegative"] else -1000000000
		field.max_value = 1000000000
		field.custom_minimum_size.x = 240
		frame_grid.add_child(field)
		frame_fields.append(field)
	var frame_info: Label = Label.new()
	frame_info.text = "Empty bounds = unrestricted sparse canvas; guides never clip pixels."
	frame_dialog.add_child(frame_info)
	frame_dialog.confirmed.connect(_change_object_frame)
	variant_dialog = ConfirmationDialog.new()
	variant_dialog.title = "Save Object as independent asset"
	add_child(variant_dialog)
	var variant_form: VBoxContainer = VBoxContainer.new()
	variant_dialog.add_child(variant_form)
	var destination: Label = Label.new()
	destination.text = "Target: campaign/Objects/<new asset ID>/v000001.drawing"
	variant_form.add_child(destination)
	variant_name = LineEdit.new()
	variant_name.placeholder_text = "New Object name"
	variant_name.custom_minimum_size.x = 400
	variant_form.add_child(variant_name)
	variant_dialog.confirmed.connect(_save_as_named_object)
	_build_text_dialog()


func _make_dialog(mode: FileDialog.FileMode) -> FileDialog:
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.drawing ; Drawing document"])
	dialog.size = Vector2i(850, 540)
	add_child(dialog)
	return dialog


func _pack_color(value: Color) -> int:
	return clampi(roundi(value.r * 255.0), 0, 255) | (clampi(roundi(value.g * 255.0), 0, 255) << 8) | (clampi(roundi(value.b * 255.0), 0, 255) << 16) | (clampi(roundi(value.a * 255.0), 0, 255) << 24)


func current_object() -> DrawingObjectEditorSession:
	return tabs[active_tab].get("object") as DrawingObjectEditorSession if active_tab >= 0 else null


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


## Atlas host opens a captured, detached Object Asset draft through this API.
## The very same Drawing canvas, text editor and layer panel edit the object.
func attach_object_session(session: DrawingObjectEditorSession) -> DrawingResult:
	if session == null or session.document == null:
		return DrawingResult.failure("OBJECT", "Missing Object Editor session")
	session.document.record_selection_history = record_selection_history
	var layer: String = _first_editable(session.document, DrawingDocument.ROOT_ID)
	var tab_name: String = "Object: " + session.name
	tabs.append({"document": session.document, "object": session,
		"path": "", "title": tab_name, "layer": layer})
	tab_bar.add_tab(tab_name)
	_activate(tabs.size() - 1)
	return DrawingResult.success(active_tab)


## Standalone authoring uses ordinary portable .drawing assets; no Atlas
## instance can be rebound by this local-file publisher.
func new_object() -> void:
	new_counter += 1
	var document: DrawingDocument = DrawingDocument.new()
	var group: DrawingResult = document.create_layer(DrawingLayerNode.GROUP, "Group 1")
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1", String(group.value))
	var session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(document, "", 0,
		"New object %d" % new_counter)
	session.save_publisher = _local_publish.bind(false)
	session.save_as_publisher = _local_publish.bind(true)
	attach_object_session(session)
	tabs[active_tab]["local_object"] = true
	tabs[active_tab]["layer"] = layer.value
	canvas.layer_id = String(layer.value)
	_update_status()


func _ask_open_object() -> void:
	object_open_dialog.popup_centered()


func _open_object_file(path: String) -> void:
	var opened: DrawingResult = DrawingObjectEditorFile.open(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var data: Dictionary = opened.value
	var session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(data["document"],
		data["source_id"], data["source_revision"], data["name"], "", "",
		data["origin"], data["bounds"])
	session.save_publisher = _local_publish.bind(false)
	session.save_as_publisher = _local_publish.bind(true)
	attach_object_session(session)
	tabs[active_tab]["local_object"] = true
	tabs[active_tab]["path"] = path
	_update_status()


func _local_publish(session: DrawingObjectEditorSession, as_variant: bool) -> DrawingResult:
	var index: int = _find_object_tab(session)
	if index < 0:
		return DrawingResult.failure("TAB", "Object Editor tab was closed")
	var path: String = String(tabs[index].get("_target_path", tabs[index].get("path", "")))
	if path.is_empty() or (as_variant and path == tabs[index].get("path", "")):
		return DrawingResult.failure("PATH", "Choose a different target path for Save As")
	var source: DrawingDocument = session.document
	if as_variant:
		var copied: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(),
			source.tile_stride, source.density_numerator, source.density_denominator)
		for node_id: String in source.list_children():
			var exported: DrawingResult = source.export_subtree(node_id)
			if not exported.ok:
				return exported
			var imported: DrawingResult = copied.import_subtree(exported.value, DrawingDocument.ROOT_ID)
			if not imported.ok:
				return imported
		source = copied
	var written: DrawingResult = DrawingObjectEditorFile.save(source, path, session.name,
		session.origin, session.bounds, 1 if as_variant else session.source_revision + 1)
	if not written.ok:
		return written
	var reopened: DrawingResult = DrawingObjectEditorFile.open(path)
	if not reopened.ok:
		return reopened
	tabs[index]["path"] = path
	tabs[index].erase("_target_path")
	var snapshot: Dictionary = reopened.value
	snapshot["detach_origin"] = true
	return DrawingResult.success(snapshot)


func _find_object_tab(session: DrawingObjectEditorSession) -> int:
	for index: int in range(tabs.size()):
		if tabs[index].get("object") == session:
			return index
	return -1


func _ask_rename_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		_show_error("Select an Object Editor tab")
		return
	rename_field.text = session.name
	rename_dialog.popup_centered()


func _rename_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var changed: DrawingResult = session.set_name(rename_field.text)
	if changed.ok:
		_update_status()
	else:
		_show_error(changed.message)


func _ask_object_frame() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		_show_error("Select an Object Editor tab")
		return
	var values: Array[int] = [session.origin.x, session.origin.y,
		session.bounds.position.x, session.bounds.position.y,
		session.bounds.size.x, session.bounds.size.y]
	for index: int in range(frame_fields.size()):
		frame_fields[index].value = values[index]
	frame_dialog.popup_centered()


func _change_object_frame() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var origin: Vector2i = Vector2i(int(frame_fields[0].value), int(frame_fields[1].value))
	var bounds: Rect2i = Rect2i(int(frame_fields[2].value), int(frame_fields[3].value),
		int(frame_fields[4].value), int(frame_fields[5].value))
	var changed: DrawingResult = session.set_frame(origin, bounds)
	if not changed.ok:
		_show_error(changed.message)
		return
	canvas.asset_origin = session.origin
	canvas.asset_bounds = session.bounds
	canvas.queue_redraw()
	_update_status()


func _save_as_named_object() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var title: String = variant_name.text.strip_edges()
	if title.is_empty() or title.length() > 128 or "\n" in title or "\r" in title:
		_show_error("Choose a 1–128 character Object Asset name")
		return
	session.variant_name = title
	_publish_object(true)


func _request_close_current() -> void:
	_request_close_tab(active_tab)


func _request_close_tab(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	_closing_index = index
	_close_after_save = false
	var session: DrawingObjectEditorSession = tabs[index].get("object") as DrawingObjectEditorSession
	if session != null and session.is_dirty() or (session == null and
		(tabs[index]["document"] as DrawingDocument).is_dirty()):
		close_dialog.popup_centered()
	else:
		_close_index(index)


func _cancel_pending_close() -> void:
	_closing_index = -1
	_close_after_save = false
	_local_save_as = false


func _save_and_close() -> void:
	if _closing_index < 0:
		return
	_close_after_save = true
	_activate(_closing_index)
	_save()


func _close_index(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	var session: DrawingObjectEditorSession = tabs[index].get("object") as DrawingObjectEditorSession
	if session != null:
		object_tab_closed.emit(session)
	tabs.remove_at(index)
	tab_bar.remove_tab(index)
	_closing_index = -1
	_close_after_save = false
	active_tab = -1
	if tabs.is_empty():
		canvas.document = null
		canvas.layer_id = ""
		layers.clear()
		status.text = "No document open"
	else:
		_activate(mini(index, tabs.size() - 1))


func _close_if_saved() -> void:
	if not _close_after_save or _closing_index != active_tab:
		return
	var session: DrawingObjectEditorSession = current_object()
	if session == null or not session.is_dirty():
		if not current_document().is_dirty():
			_close_index(active_tab)


func _sync_object_tab() -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	tabs[active_tab]["document"] = session.document
	tabs[active_tab]["title"] = "Object: " + session.name
	var selected: String = current_layer()
	if not session.document.has_node(selected):
		tabs[active_tab]["layer"] = _first_editable(session.document, DrawingDocument.ROOT_ID)
	canvas.document = session.document
	canvas.layer_id = current_layer()
	canvas.asset_origin = session.origin
	canvas.asset_bounds = session.bounds
	_after_edit()


func _activate(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	active_tab = index
	tab_bar.current_tab = index
	canvas.document = current_document()
	canvas.layer_id = current_layer()
	var object_session: DrawingObjectEditorSession = current_object()
	canvas.asset_origin = object_session.origin if object_session != null else Vector2i.ZERO
	canvas.asset_bounds = object_session.bounds if object_session != null else Rect2i()
	canvas.selected = Rect2i()
	canvas.session = null
	canvas.queue_redraw()
	_refresh_layers()
	_last_selection_context = _capture_context()
	_update_status()


func _flatten_layer_ids(parent: String, depth: int, output: Array[Dictionary]) -> void:
	for node_id: String in current_document().list_children(parent):
		var info: Dictionary = current_document().node_metadata(node_id)
		output.append({"id": node_id, "depth": depth, "info": info})
		if info["kind"] == DrawingLayerNode.GROUP:
			_flatten_layer_ids(node_id, depth + 1, output)


func _refresh_layers() -> void:
	layers.clear()
	var root: TreeItem = layers.create_item()
	if current_document() == null:
		return
	var all_rows: Array[Dictionary] = []
	_flatten_layer_ids(DrawingDocument.ROOT_ID, 0, all_rows)
	var matches: Array[Dictionary] = []
	var query: String = layer_search.text.strip_edges().to_lower()
	for row: Dictionary in all_rows:
		var info: Dictionary = row["info"]
		var content: String = ""
		if info["kind"] == DrawingLayerNode.TEXT and not query.is_empty():
			var preview: DrawingLayerNode = current_document().inspect_node(row["id"])
			content = preview.text_value
		if query.is_empty() or String(info["name"]).to_lower().contains(query) or content.to_lower().contains(query):
			matches.append(row)
	var page_count: int = maxi(1, ceili(float(matches.size()) / ROW_PAGE))
	layer_page = clampi(layer_page, 0, page_count - 1)
	layer_page_label.text = "%d/%d · %d labels/layers" % [layer_page + 1, page_count, matches.size()]
	var first: int = layer_page * ROW_PAGE
	for index: int in range(first, mini(first + ROW_PAGE, matches.size())):
		var row: Dictionary = matches[index]
		var info: Dictionary = row["info"]
		var item: TreeItem = layers.create_item(root)
		var kind_marker: String = "▸ " if info["kind"] == DrawingLayerNode.GROUP else ("T " if info["kind"] == DrawingLayerNode.TEXT else "◉ ")
		item.set_text(0, "  ".repeat(mini(int(row["depth"]), 12)) + (kind_marker if info["visible"] else "○ ") + info["name"])
		item.set_metadata(0, row["id"])
		if row["id"] == current_layer():
			item.select(0)
			layers.scroll_to_item(item)


func _change_layer_page(direction: int) -> void:
	layer_page = maxi(0, layer_page + direction)
	_refresh_layers()


func _layer_selected() -> void:
	var before: DrawingHistoryContext = _capture_context()
	var selected_item: TreeItem = layers.get_selected()
	if selected_item == null:
		return
	var node_id: String = String(selected_item.get_metadata(0))
	if current_document().node_metadata(node_id).get("kind") in [DrawingLayerNode.RASTER, DrawingLayerNode.TEXT]:
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


func _build_text_dialog() -> void:
	text_dialog = ConfirmationDialog.new()
	text_dialog.title = "Editable text (one element per layer)"
	text_dialog.size = Vector2i(470, 350)
	add_child(text_dialog)
	var form: VBoxContainer = VBoxContainer.new()
	text_dialog.add_child(form)
	var font_label: Label = Label.new()
	font_label.text = "Bundled Lato · OFL 1.1"
	form.add_child(font_label)
	text_font = OptionButton.new()
	for entry: String in ["Regular", "Bold", "Italic"]:
		text_font.add_item(entry)
	form.add_child(text_font)
	text_edit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(420, 110)
	form.add_child(text_edit)
	var controls: HBoxContainer = HBoxContainer.new()
	form.add_child(controls)
	text_size = SpinBox.new()
	text_size.min_value = 6
	text_size.max_value = 256
	text_size.value = 24
	text_size.prefix = "Size"
	controls.add_child(text_size)
	text_angle = SpinBox.new()
	text_angle.min_value = -360
	text_angle.max_value = 360
	text_angle.prefix = "Angle °"
	controls.add_child(text_angle)
	text_alignment = OptionButton.new()
	for name: String in ["left", "center", "right"]:
		text_alignment.add_item(name.capitalize())
	controls.add_child(text_alignment)
	text_color = ColorPickerButton.new()
	text_color.text = "Color"
	form.add_child(text_color)
	text_dialog.confirmed.connect(_commit_text_dialog)


func _edit_text_at(point: Vector2i) -> void:
	if active_tab < 0:
		return
	var node: DrawingLayerNode = current_document().inspect_node(current_layer())
	text_target = current_layer() if node != null and node.kind == DrawingLayerNode.TEXT else ""
	text_position = point
	var existing: DrawingTextElement = node.text_element if not text_target.is_empty() else null
	text_edit.text = existing.content if existing != null else ""
	text_font.select(["lato-regular-v1", "lato-bold-v1", "lato-italic-v1"].find(existing.font_id) if existing != null else 0)
	text_size.value = existing.font_size if existing != null else 24
	text_angle.value = rad_to_deg(existing.angle) if existing != null else 0.0
	text_alignment.select(["left", "center", "right"].find(existing.alignment) if existing != null else 0)
	text_color.color = Color8(32, 40, 64) if existing == null else Color(
		float(existing.color_rgba & 255) / 255.0,
		float((existing.color_rgba >> 8) & 255) / 255.0,
		float((existing.color_rgba >> 16) & 255) / 255.0,
		float((existing.color_rgba >> 24) & 255) / 255.0)
	if existing != null:
		text_position = existing.position
	text_dialog.popup_centered()
	text_edit.grab_focus()


func _commit_text_dialog() -> void:
	if active_tab < 0:
		return
	var document: DrawingDocument = current_document()
	var draft: DrawingTextElement = DrawingTextElement.new()
	draft.content = text_edit.text
	draft.font_id = ["lato-regular-v1", "lato-bold-v1", "lato-italic-v1"][text_font.selected]
	draft.position = text_position
	draft.font_size = int(text_size.value)
	draft.angle = deg_to_rad(text_angle.value)
	draft.alignment = ["left", "center", "right"][text_alignment.selected]
	draft.color_rgba = _pack_color(text_color.color)
	var selected_node: DrawingLayerNode = document.inspect_node(current_layer())
	var parent: String = selected_node.parent_id if selected_node != null else DrawingDocument.ROOT_ID
	var before: DrawingHistoryContext = _capture_context()
	var committed: DrawingResult = document.commit_text(text_target, draft, document.revision, parent)
	if not committed.ok:
		_show_error(committed.message)
		return
	tabs[active_tab]["layer"] = committed.value
	canvas.layer_id = String(committed.value)
	document.annotate_latest_gesture(before, _capture_context())
	_after_edit()


func _rasterize_text() -> void:
	if active_tab < 0:
		return
	var before: DrawingHistoryContext = _capture_context()
	var converted: DrawingResult = current_document().rasterize_text(current_layer(), current_document().revision)
	if not converted.ok:
		_show_error(converted.message)
		return
	current_document().annotate_latest_gesture(before, _capture_context())
	_after_edit()


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
	_refresh_tool_options()
	_update_status()


func _refresh_tool_options() -> void:
	if top_bar == null:
		return
	var controls: Array[Control] = []
	if active_tool in ["Brush", "Eraser"]:
		controls.append(width_spin)
	if active_tool in ["Brush", "Eraser", "Select", "Move", "Text"]:
		controls.append(snap_toggle)
	top_bar.set_tool_controls(active_tool, controls)


func _toggle_selection_history() -> void:
	_selection_history_preference_changed(not record_selection_history)
	if selection_history_toggle != null:
		selection_history_toggle.set_pressed_no_signal(record_selection_history)


func _toggle_dock() -> void:
	inspector.visible = not inspector.visible


func _reset_dock_width() -> void:
	inspector.visible = true
	dock_split.split_offset = maxi(0, int(dock_split.size.x) - 270)


func _show_about_workspace() -> void:
	(get_node("WorkspaceAbout") as AcceptDialog).popup_centered()


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
	if top_bar != null:
		top_bar.set_menu_checked("Edit", 2, enabled)
	for tab: Dictionary in tabs:
		(tab["document"] as DrawingDocument).record_selection_history = enabled
	if selection_history_toggle != null and selection_history_toggle.button_pressed != enabled:
		selection_history_toggle.set_pressed_no_signal(enabled)


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
	if context.editor_mode in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]:
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
	var session: DrawingObjectEditorSession = current_object()
	var dirty: bool = session.is_dirty() if session != null else document.is_dirty()
	tab_bar.set_tab_title(active_tab, String(tabs[active_tab]["title"]) + (" *" if dirty else ""))
	var origin: String = " | instance %s @ %s" % [session.origin_instance_id,
		session.origin_map_id] if session != null and not session.origin_instance_id.is_empty() else ""
	var source: String = "Object %s (%s) rev %d%s | " % [session.name,
		session.source_id if not session.source_id.is_empty() else "new", session.source_revision,
		origin] if session != null else ""
	var cursor: Vector2i = canvas.position_to_pixel(
		canvas.last_pointer_position if canvas.pointer_known else canvas.size * 0.5)
	var canvas_pixels: Vector2i = Vector2i(ceili(canvas.size.x / canvas.zoom),
		ceili(canvas.size.y / canvas.zoom))
	status.text = "%s%s | cursor %d,%d | view %d×%d px | zoom %.0f%% | revision %d | %s" % [
		source, active_tool, cursor.x, cursor.y, canvas_pixels.x, canvas_pixels.y,
		canvas.zoom * 100.0, document.revision,
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
	if active_tab < 0:
		return
	var session: DrawingObjectEditorSession = current_object()
	if session != null and not session.save_as_publisher.is_valid():
		_show_error("No Object Asset publisher is connected")
		return
	if session != null and not bool(tabs[active_tab].get("local_object", false)):
		variant_name.text = session.name + " copy"
		variant_dialog.popup_centered()
	else:
		_local_save_as = session != null
		save_dialog.popup_centered()


func _save() -> void:
	if active_tab < 0:
		return
	var session: DrawingObjectEditorSession = current_object()
	if session != null:
		if not session.save_publisher.is_valid():
			_show_error("No Object Asset publisher is connected")
			return
		if session.source_id.is_empty() and tabs[active_tab]["path"].is_empty():
			_local_save_as = false
			save_dialog.popup_centered()
		else:
			_publish_object(false)
		return
	var path: String = tabs[active_tab]["path"]
	if path.is_empty():
		_ask_save()
	else:
		_save_file(path)


func _publish_object(as_variant: bool) -> void:
	var session: DrawingObjectEditorSession = current_object()
	if session == null:
		return
	var result: DrawingResult = session.save_as() if as_variant else session.save()
	if not result.ok:
		if active_tab >= 0:
			tabs[active_tab].erase("_target_path")
		_cancel_pending_close()
		_show_error(result.message)
		return
	_sync_object_tab()
	_close_if_saved()


func _save_file(path: String) -> void:
	if active_tab < 0:
		return
	if not path.to_lower().ends_with(".drawing"):
		path += ".drawing"
	if current_object() != null:
		tabs[active_tab]["_target_path"] = path
		_publish_object(_local_save_as)
		_local_save_as = false
		return
	var result: DrawingResult = DrawingFileIO.save(current_document(), path)
	if result.ok:
		tabs[active_tab]["path"] = path
		tabs[active_tab]["title"] = path.get_file()
		_update_status()
		_close_if_saved()
	else:
		_cancel_pending_close()
		_show_error(result.message)


func _open_file(path: String) -> void:
	var opened: DrawingResult = DrawingFileIO.open(path)
	if not opened.ok:
		_show_error(opened.message)
		return
	var document: DrawingDocument = opened.value as DrawingDocument
	document.record_selection_history = record_selection_history
	var raster: String = _first_editable(document, DrawingDocument.ROOT_ID)
	if raster.is_empty():
		var added: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Layer 1")
		raster = added.value
	tabs.append({"document": document, "path": path, "title": path.get_file(), "layer": raster})
	tab_bar.add_tab(path.get_file())
	_activate(tabs.size() - 1)


func _first_editable(document: DrawingDocument, parent: String) -> String:
	for node_id: String in document.list_children(parent):
		var info: Dictionary = document.node_metadata(node_id)
		if info["kind"] in [DrawingLayerNode.RASTER, DrawingLayerNode.TEXT]:
			return node_id
		if info["kind"] == DrawingLayerNode.GROUP:
			var nested: String = _first_editable(document, node_id)
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
		KEY_S:
			if key.shift_pressed:
				_ask_save()
			else:
				_save()
		KEY_Z:
			if key.shift_pressed:
				_redo()
			else:
				_undo()
		KEY_Y: _redo()
		KEY_W: _request_close_current()
		_: return
	get_viewport().set_input_as_handled()
