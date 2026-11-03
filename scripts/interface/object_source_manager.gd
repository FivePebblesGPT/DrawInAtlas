class_name AtlasObjectSourceManager
extends Window
## Atlas-only source and NULL binding manager. The standalone Drawing package
## never imports an Atlas registry or interprets a selected source as a map edit.

signal open_source_requested(source_id: String)
signal place_source_requested(source_id: String)
signal registry_mutated(summary: String)

var library: AtlasObjectLibrary
var sources: ItemList
var missing: ItemList
var details: Label
var edit_button: Button
var place_button: Button
var delete_button: Button
var repair_button: Button
var delete_confirmation: ConfirmationDialog
var _source_ids: Array[String] = []
var _null_ids: Array[String] = []
var _pending_delete: Dictionary = {}


func _ready() -> void:
	name = "ObjectSourceManager"
	title = "Object Assets and missing instances"
	min_size = Vector2i(520, 470)
	size = Vector2i(620, 550)
	close_requested.connect(hide)
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var close_button: Button = _action(root, "Close", "CloseManager", hide)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var heading: Label = Label.new()
	heading.text = "Published sources · unused assets are retained"
	root.add_child(heading)
	sources = ItemList.new()
	sources.name = "PublishedSources"
	sources.custom_minimum_size.y = 160
	sources.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sources.item_selected.connect(func(_row: int) -> void: _update_actions())
	root.add_child(sources)
	var actions: HFlowContainer = HFlowContainer.new()
	root.add_child(actions)
	edit_button = _action(actions, "Edit Source", "EditSource", _request_edit)
	place_button = _action(actions, "Place at view center", "PlaceSource", _request_place)
	delete_button = _action(actions, "Delete Source…", "DeleteSource", _ask_delete)
	var null_heading: Label = Label.new()
	null_heading.text = "Missing / NULL instances · choose a replacement source explicitly"
	root.add_child(null_heading)
	missing = ItemList.new()
	missing.name = "MissingInstances"
	missing.custom_minimum_size.y = 110
	missing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	missing.item_selected.connect(func(_row: int) -> void: _update_actions())
	root.add_child(missing)
	repair_button = _action(root, "Repair selected NULL with selected source", "RepairNull", _repair_selected)
	details = Label.new()
	details.name = "SourceManagerStatus"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(details)
	delete_confirmation = ConfirmationDialog.new()
	delete_confirmation.name = "DeleteSourceConfirmation"
	delete_confirmation.title = "Choose source deletion policy"
	delete_confirmation.get_ok_button().text = "Remove all references"
	delete_confirmation.get_cancel_button().text = "Cancel"
	delete_confirmation.add_button("Keep NULL placeholders", true, "null")
	delete_confirmation.confirmed.connect(func() -> void: _delete_with_policy("remove"))
	delete_confirmation.custom_action.connect(func(action: StringName) -> void:
		if action == &"null":
			delete_confirmation.hide()
			_delete_with_policy("null"))
	delete_confirmation.canceled.connect(func() -> void: _pending_delete = {})
	add_child(delete_confirmation)
	refresh()


func _action(parent: Node, caption: String, identifier: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = identifier
	button.text = caption
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func bind_library(next_library: AtlasObjectLibrary) -> void:
	if library != null:
		if library.asset_published.is_connected(_source_changed):
			library.asset_published.disconnect(_source_changed)
		if library.instances_changed.is_connected(_instances_changed):
			library.instances_changed.disconnect(_instances_changed)
	library = next_library
	_pending_delete = {}
	if delete_confirmation != null:
		delete_confirmation.hide()
	if library != null:
		library.asset_published.connect(_source_changed)
		library.instances_changed.connect(_instances_changed)
	if is_node_ready():
		refresh()


func _source_changed(_asset_id: String, _revision: int) -> void:
	refresh()


func _instances_changed(_ids: Array) -> void:
	refresh()


func selected_source_id() -> String:
	if sources == null:
		return ""
	var selected: PackedInt32Array = sources.get_selected_items()
	return _source_ids[selected[0]] if not selected.is_empty() and selected[0] < _source_ids.size() else ""


func selected_null_id() -> String:
	if missing == null:
		return ""
	var selected: PackedInt32Array = missing.get_selected_items()
	return _null_ids[selected[0]] if not selected.is_empty() and selected[0] < _null_ids.size() else ""


func refresh() -> void:
	if sources == null or missing == null:
		return
	var selected_source: String = selected_source_id()
	var selected_null: String = selected_null_id()
	_source_ids.clear()
	_null_ids.clear()
	sources.clear()
	missing.clear()
	if library == null:
		details.text = "No Atlas Object library is open"
		_update_actions()
		return
	for source_id: String in library.asset_ids():
		var entry: Dictionary = library.asset_info(source_id)
		var usage: Dictionary = library.source_usage(source_id)
		var count: int = int(usage["total"])
		var state: String = "unused" if count == 0 else "%d in use" % count
		if not library.asset_exists(source_id):
			state = "SOURCE UNAVAILABLE · %s" % state
		var row: int = sources.add_item("%s · %s · v%d · %s" % [entry["name"], source_id,
			entry["revision"], state])
		_source_ids.append(source_id)
		sources.set_item_tooltip(row, "%s\n%s" % [source_id, entry["path"]])
		if source_id == selected_source:
			sources.select(row)
	for instance_id: String in library.instance_ids():
		var item: Dictionary = library.instance_info(instance_id)
		if item["status"] != "NULL":
			continue
		var row: int = missing.add_item("%s · %s / %s / %s" % [
			item["source_id"], item["map_id"], item["floor_id"], item["detail_id"]])
		_null_ids.append(instance_id)
		missing.set_item_tooltip(row, "Instance: %s\nOriginal source: %s" % [instance_id, item["source_id"]])
		if instance_id == selected_null:
			missing.select(row)
	details.text = "%d published sources · %d missing placements. Unused sources are never deleted automatically." % [
		_source_ids.size(), _null_ids.size()]
	_update_actions()


func _update_actions() -> void:
	if edit_button == null:
		return
	var has_source: bool = not selected_source_id().is_empty()
	var available: bool = has_source and library != null and library.asset_exists(selected_source_id())
	edit_button.disabled = not available
	place_button.disabled = not available
	delete_button.disabled = not has_source
	repair_button.disabled = not available or selected_null_id().is_empty()


func _request_edit() -> void:
	if not selected_source_id().is_empty():
		open_source_requested.emit(selected_source_id())


func _request_place() -> void:
	if not selected_source_id().is_empty():
		place_source_requested.emit(selected_source_id())


func _ask_delete() -> void:
	if library == null or selected_source_id().is_empty():
		return
	var preview: DrawingResult = library.preview_delete_asset(selected_source_id())
	if not preview.ok:
		refresh()
		details.text = preview.message
		return
	_pending_delete = (preview.value as Dictionary).duplicate(true)
	delete_confirmation.dialog_text = "Delete %s? %d instance(s) reference this source.\n\n" % [
		_pending_delete["asset_id"], _pending_delete["bindings"].size()] + \
		"Remove all references permanently from the registry, or keep selectable NULL proxies retaining their identity and transform. Source bytes are retained for recovery."
	delete_confirmation.popup_centered()


func _delete_with_policy(policy: String) -> void:
	if library == null or _pending_delete.is_empty():
		return
	var preview: Dictionary = _pending_delete
	_pending_delete = {}
	var saved: DrawingResult = library.delete_asset(String(preview["asset_id"]), policy, preview)
	if not saved.ok:
		refresh()
		details.text = saved.message
		return
	refresh()
	registry_mutated.emit("Source deleted using '%s' policy" % policy)


func _repair_selected() -> void:
	if library == null or selected_source_id().is_empty() or selected_null_id().is_empty():
		return
	var null_id: String = selected_null_id()
	var target_id: String = selected_source_id()
	var item: Dictionary = library.instance_info(null_id)
	if item.is_empty() or item.get("status") != "NULL":
		refresh()
		return
	var repaired: DrawingResult = library.repair_placeholder(null_id,
		String(item["generation"]), int(item["revision"]), target_id)
	refresh()
	if repaired.ok:
		registry_mutated.emit("Repaired NULL instance %s to source %s" % [null_id, target_id])
	else:
		details.text = repaired.message
