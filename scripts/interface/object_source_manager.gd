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
var children_button: Button
var child_inspector: AtlasObjectChildInspector
var import_button: Button
var export_button: Button
var import_dialog: FileDialog
var export_dialog: FileDialog
var _pending_export: Dictionary = {}
var _pending_import_library: AtlasObjectLibrary
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
	children_button = _action(actions, "Nested children…", "EditChildren", _open_children)
	import_button = _action(actions, "Import portable…", "ImportPortable", _ask_import)
	export_button = _action(actions, "Export portable…", "ExportPortable", _ask_export)
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
	import_dialog = FileDialog.new()
	import_dialog.name = "ImportPortableDialog"
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = PackedStringArray(["*.drawing ; Portable Drawing Object"])
	import_dialog.file_selected.connect(_import_portable)
	import_dialog.canceled.connect(func() -> void: _pending_import_library = null)
	add_child(import_dialog)
	export_dialog = FileDialog.new()
	export_dialog.name = "ExportPortableDialog"
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.drawing ; Portable Drawing Object"])
	export_dialog.file_selected.connect(_export_portable)
	export_dialog.canceled.connect(func() -> void: _pending_export = {})
	add_child(export_dialog)
	child_inspector = AtlasObjectChildInspector.new()
	add_child(child_inspector)
	child_inspector.edit_source_requested.connect(func(id: String) -> void:
		open_source_requested.emit(id))
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
	_pending_export = {}
	_pending_import_library = null
	if child_inspector != null:
		child_inspector.hide()
		child_inspector.bind_parent(null, "")
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
	children_button.disabled = not available
	import_button.disabled = library == null
	export_button.disabled = not available
	repair_button.disabled = not available or selected_null_id().is_empty()


func _open_children() -> void:
	if library == null or selected_source_id().is_empty() or not library.asset_exists(selected_source_id()):
		return
	child_inspector.bind_parent(library, selected_source_id())
	child_inspector.popup_centered()


## Canvas selection uses this same inspector; never creates a second editor.
## Re-selecting a child of the same parent retains its local Undo timeline.
func focus_child_from_canvas(parent_id: String, child_id: String) -> DrawingResult:
	if library == null or not library.asset_exists(parent_id):
		return DrawingResult.failure("CHILD", "The nested parent source is unavailable")
	if child_inspector == null:
		return DrawingResult.failure("CHILD", "Nested child inspector is unavailable")
	if child_inspector.session.library != library or \
			child_inspector.session.parent_source_id != parent_id:
		child_inspector.bind_parent(library, parent_id)
	if child_inspector.session.is_stale():
		child_inspector.refresh("Parent changed; Reload parent before editing")
		child_inspector.popup_centered()
		return DrawingResult.failure("STALE_CHILDREN", "Reload the nested parent before selecting another child")
	var selected: DrawingResult = child_inspector.session.select_child(child_id)
	if not selected.ok:
		return selected
	var index: int = _source_ids.find(parent_id)
	if index >= 0:
		sources.select(index)
		_update_actions()
	child_inspector.refresh()
	popup_centered()
	child_inspector.popup_centered()
	return DrawingResult.success()


func _request_edit() -> void:
	if not selected_source_id().is_empty():
		open_source_requested.emit(selected_source_id())


func _request_place() -> void:
	if not selected_source_id().is_empty():
		place_source_requested.emit(selected_source_id())


func _ask_import() -> void:
	if library != null:
		_pending_import_library = library
		import_dialog.popup_centered_ratio(0.7)


func _import_portable(path: String) -> void:
	var frozen_library: AtlasObjectLibrary = _pending_import_library
	_pending_import_library = null
	if library == null or frozen_library != library:
		return # A new campaign was bound or the dialog was cancelled.
	var imported: DrawingResult = library.import_portable_source(path)
	refresh()
	if imported.ok:
		registry_mutated.emit("Imported portable Object %s" % String(imported.value))
	else:
		details.text = imported.message


func _ask_export() -> void:
	if library == null or selected_source_id().is_empty():
		return
	var asset_id: String = selected_source_id()
	var record: Dictionary = library.asset_info(asset_id)
	if record.is_empty() or not library.asset_exists(asset_id):
		refresh()
		return
	_pending_export = {"id": asset_id, "revision": record["revision"]}
	export_dialog.popup_centered_ratio(0.7)


func _export_portable(path: String) -> void:
	if library == null or _pending_export.is_empty():
		return
	var frozen: Dictionary = _pending_export
	_pending_export = {}
	var exported: DrawingResult = library.export_portable_source(String(frozen["id"]),
		path, int(frozen["revision"]))
	if exported.ok:
		details.text = "Exported %s (no Atlas binding changed)" % path.get_file()
	else:
		details.text = exported.message


func _ask_delete() -> void:
	if library == null or selected_source_id().is_empty():
		return
	var preview: DrawingResult = library.preview_delete_asset(selected_source_id())
	if not preview.ok:
		refresh()
		details.text = preview.message
		return
	_pending_delete = (preview.value as Dictionary).duplicate(true)
	delete_confirmation.dialog_text = "Delete %s? %d map instance(s) and %d nested child reference(s) use this source.\n\n" % [
		_pending_delete["asset_id"], _pending_delete["bindings"].size(),
		_pending_delete.get("child_bindings", []).size()] + \
		"Remove all references permanently from the registry, or keep NULL proxies retaining their identity and transform. Source bytes are retained for recovery."
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
