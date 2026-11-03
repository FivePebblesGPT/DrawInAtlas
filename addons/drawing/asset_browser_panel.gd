class_name DrawingAssetBrowserPanel
extends VBoxContainer
## Optional T-065 dock peer; selection is read-only until an explicit Open.

signal open_requested(path: String)
signal place_requested(source: Dictionary)
signal refresh_requested

const INDEX_SCRIPT: Script = preload("res://addons/drawing/asset_browser_index.gd")
const THUMBNAILS_SCRIPT: Script = preload("res://addons/drawing/asset_browser_thumbnails.gd")
const TRANSFER_SCRIPT: Script = preload("res://addons/drawing/asset_browser_transfer.gd")
const DRAG_LIST_SCRIPT: Script = preload("res://addons/drawing/asset_browser_drag_list.gd")
var thumbnails: DrawingAssetBrowserThumbnails
var index: DrawingAssetBrowserIndex
var search: LineEdit
var assets: DrawingAssetBrowserDragList
var atlas_host_mode: bool = false
var place_button: Button
var message: Label
var open_button: Button
var import_dialog: FileDialog
var export_dialog: FileDialog
var _pending_export: Dictionary = {}
var _visible_entries: Array[Dictionary] = []


func _ready() -> void:
	name = "AssetBrowser"
	index = INDEX_SCRIPT.new() as DrawingAssetBrowserIndex
	thumbnails = THUMBNAILS_SCRIPT.new() as DrawingAssetBrowserThumbnails
	var heading: Label = Label.new()
	heading.text = "Object Assets"
	add_child(heading)
	search = LineEdit.new()
	search.name = "AssetSearch"
	search.placeholder_text = "Search name or source ID…"
	search.text_changed.connect(func(_query: String) -> void: _refresh_view())
	add_child(search)
	assets = DRAG_LIST_SCRIPT.new() as DrawingAssetBrowserDragList
	assets.drag_entry_provider = Callable(self, "_drag_entry_for_row")
	assets.name = "AssetList"
	assets.fixed_icon_size = Vector2i(48, 48)
	assets.icon_mode = ItemList.ICON_MODE_LEFT
	assets.max_text_lines = 1
	assets.get_v_scroll_bar().value_changed.connect(func(_offset: float) -> void: _queue_thumbnails())
	assets.resized.connect(_queue_thumbnails)
	assets.custom_minimum_size.y = 205
	assets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	assets.item_selected.connect(func(_i: int) -> void:
		_update_open_button()
		_queue_thumbnails())
	assets.item_activated.connect(func(_i: int) -> void: open_selected())
	add_child(assets)
	var actions: HFlowContainer = HFlowContainer.new()
	add_child(actions)
	var refresh: Button = Button.new()
	refresh.name = "RefreshAssets"
	refresh.text = "Refresh"
	refresh.pressed.connect(refresh_assets)
	actions.add_child(refresh)
	open_button = Button.new()
	open_button.name = "OpenAsset"
	open_button.text = "Edit Source"
	open_button.tooltip_text = "Open the selected published source in an Object Editor tab"
	open_button.pressed.connect(open_selected)
	actions.add_child(open_button)
	place_button = Button.new()
	place_button.name = "PlaceAsset"
	place_button.text = "Place at view center"
	place_button.tooltip_text = "Place the selected published Object in the current Atlas map"
	place_button.pressed.connect(_request_place)
	place_button.visible = atlas_host_mode
	actions.add_child(place_button)
	var import_button: Button = Button.new()
	import_button.name = "ImportAsset"
	import_button.text = "Import…"
	import_button.tooltip_text = "Copy a separate portable .drawing source into this Objects/ folder; does not register Atlas placements"
	import_button.pressed.connect(func() -> void: import_dialog.popup_centered_ratio(0.7))
	actions.add_child(import_button)
	import_button.visible = not atlas_host_mode
	var export_button: Button = Button.new()
	export_button.name = "ExportAsset"
	export_button.text = "Export…"
	export_button.tooltip_text = "Copy the selected source to a new portable .drawing file (no overwrite)"
	export_button.pressed.connect(_ask_export)
	actions.add_child(export_button)
	export_button.visible = not atlas_host_mode
	import_dialog = FileDialog.new()
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.filters = PackedStringArray(["*.drawing ; Drawing Object sources"])
	import_dialog.file_selected.connect(_import_file)
	add_child(import_dialog)
	export_dialog = FileDialog.new()
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.drawing ; Drawing Object sources"])
	export_dialog.file_selected.connect(_export_file)
	add_child(export_dialog)
	message = Label.new()
	message.name = "AssetIndexStatus"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	_refresh_view()


func set_objects_root(path: String) -> DrawingResult:
	if index == null:
		index = INDEX_SCRIPT.new() as DrawingAssetBrowserIndex
	var result: DrawingResult = index.scan(path)
	if result.ok:
		if thumbnails == null:
			thumbnails = THUMBNAILS_SCRIPT.new() as DrawingAssetBrowserThumbnails
		thumbnails.reconcile(index.entries)
	if is_node_ready():
		_refresh_view()
		if not result.ok:
			message.text = result.message
	return result


## Atlas supplies published asset records from its authoritative registry.
## Their published IDs intentionally differ from the embedded document IDs.
## The generic browser only displays and transfers these records.
func set_published_entries(objects_root: String, records: Array[Dictionary], issues: Array[String] = []) -> void:
	if index == null:
		index = INDEX_SCRIPT.new() as DrawingAssetBrowserIndex
	if thumbnails == null:
		thumbnails = THUMBNAILS_SCRIPT.new() as DrawingAssetBrowserThumbnails
	index.root_path = objects_root
	index.entries = records.duplicate(true)
	index.warnings = issues.duplicate()
	thumbnails.reconcile(index.entries)
	if is_node_ready():
		_refresh_view()


func refresh_assets() -> void:
	if atlas_host_mode:
		refresh_requested.emit()
		return
	if index == null or index.root_path.is_empty():
		return
	set_objects_root(index.root_path)


## Only a successful publication from this workspace automatically refreshes.
## External changes must be explicitly refreshed and stale files fail closed.
func notify_source_published(path: String) -> void:
	if index != null and not index.root_path.is_empty() and \
			path.simplify_path().begins_with(index.root_path + "/"):
		refresh_assets()


func _refresh_view() -> void:
	if assets == null or index == null:
		return
	var selected_id: String = selected_asset_id()
	_visible_entries = index.filtered(search.text)
	assets.clear()
	var selection: int = -1
	for i: int in range(_visible_entries.size()):
		var entry: Dictionary = _visible_entries[i]
		var text_label: String = "%s  (v%d)" % [entry["name"], entry["revision"]]
		if entry.has("usage"):
			text_label += " · " + String(entry["usage"])
		assets.add_item(text_label)
		assets.set_item_tooltip(i, "%s\n%s" % [entry["id"], entry["path"]])
		if entry["id"] == selected_id:
			selection = i
	if selection >= 0:
		assets.select(selection)
	_update_open_button()
	_queue_thumbnails()
	message.text = "%d sources; %d warnings" % [index.entries.size(), index.warnings.size()]
	if index.root_path.is_empty():
		message.text = "Choose a portable Objects/ folder from Window → Asset Browser…"


func selected_asset_id() -> String:
	if assets == null:
		return ""
	var selected: PackedInt32Array = assets.get_selected_items()
	if selected.is_empty() or selected[0] >= _visible_entries.size():
		return ""
	return String(_visible_entries[selected[0]]["id"])


func _update_open_button() -> void:
	if open_button != null:
		open_button.disabled = selected_asset_id().is_empty()
	if place_button != null:
		place_button.disabled = selected_asset_id().is_empty()


func open_selected() -> void:
	if assets == null:
		return
	var selected: PackedInt32Array = assets.get_selected_items()
	if selected.is_empty() or selected[0] >= _visible_entries.size():
		return
	# Revalidate the exact source identity before opening a stale listing.
	var entry: Dictionary = _visible_entries[selected[0]]
	if not index.safe_to_open(entry):
		message.text = "Source moved or changed; refresh the Asset Browser before opening"
		return
	var fresh: DrawingResult = DrawingObjectEditorFile.open(entry["path"])
	if not fresh.ok or String(fresh.value["source_id"]) != String(entry.get("embedded_id", entry["id"])) or \
			int(fresh.value["source_revision"]) != int(entry.get("embedded_revision", entry["revision"])):
		message.text = "Source changed; refresh the Asset Browser before opening"
		return
	open_requested.emit(String(entry["path"]))


## Defer preview work to active visible rows, at most two expensive decodes
## per frame. Selection/filter/scroll can reorder items without caching UI IDs.
var _preview_queued: bool = false
var _visible_icon_rows: Array[int] = []


func _queue_thumbnails() -> void:
	_preview_queued = true


func _process(_delta: float) -> void:
	if _preview_queued:
		_preview_queued = false
		_render_visible_thumbnails()


func _render_visible_thumbnails() -> void:
	if not is_visible_in_tree() or assets == null or thumbnails == null or _visible_entries.is_empty():
		return
	var first: int = assets.get_item_at_position(Vector2(5, 5), true)
	var last: int = assets.get_item_at_position(Vector2(5, maxf(5.0, assets.size.y - 5.0)), true)
	if first < 0:
		return
	if last < first:
		# A short list can leave empty space below its last item.
		last = mini(_visible_entries.size() - 1, first + ceili(assets.size.y / 48.0))
	last = mini(last, first + DrawingAssetBrowserThumbnails.CAPACITY - 1)
	for previous: int in _visible_icon_rows:
		if previous < first or previous > last:
			if previous < assets.item_count:
				assets.set_item_icon(previous, null)
	_visible_icon_rows.clear()
	var added: int = 0
	for i: int in range(first, mini(last + 1, _visible_entries.size())):
		if assets.get_item_icon(i) != null:
			_visible_icon_rows.append(i)
			continue
		var result: DrawingResult = thumbnails.preview(index, _visible_entries[i])
		if result.ok:
			assets.set_item_icon(i, ImageTexture.create_from_image(result.value))
			_visible_icon_rows.append(i)
		else:
			assets.set_item_tooltip(i, "%s\nPreview unavailable: %s" % [
				_visible_entries[i]["id"], result.message])
		added += 1
		if added >= 2:
			_queue_thumbnails() # Work continues on a subsequent process frame.
			break


## Deliberate file copies only. Atlas source registration/instance binding
## is separate; no namesake IDs, silent overwrites or source-file deletions.
func _import_file(path: String) -> void:
	var imported: DrawingResult = TRANSFER_SCRIPT.import_file(index, path)
	if not imported.ok:
		message.text = imported.message
		return
	var refreshed: DrawingResult = set_objects_root(index.root_path)
	message.text = "Imported portable source: " + String(imported.value).get_file() if refreshed.ok \
		else "Imported file, but could not refresh Objects/: " + refreshed.message


func _ask_export() -> void:
	var selected: PackedInt32Array = assets.get_selected_items()
	if selected.is_empty() or selected[0] >= _visible_entries.size():
		message.text = "Select an Object source to export"
		return
	_pending_export = _visible_entries[selected[0]].duplicate(true)
	export_dialog.current_file = String(_pending_export["id"]) + ".drawing"
	export_dialog.popup_centered_ratio(0.7)


func _export_file(path: String) -> void:
	if _pending_export.is_empty():
		return
	var entry: Dictionary = _pending_export
	_pending_export = {}
	var exported: DrawingResult = TRANSFER_SCRIPT.export_file(index, entry, path)
	message.text = "Exported: " + String(exported.value).get_file() if exported.ok else exported.message


## This transport token is not an authorization to publish. Atlas validates it
## against the active registry and its exact published path/hash at drop time.
func _drag_entry_for_row(row: int) -> Dictionary:
	if index == null or row < 0 or row >= _visible_entries.size():
		return {}
	var entry: Dictionary = _visible_entries[row]
	if not index.safe_to_open(entry):
		if message != null:
			message.text = "Source changed; refresh before dragging"
		return {}
	return {"kind": "drawing-object-source-v1", "id": entry["id"],
		"name": entry["name"], "revision": entry["revision"],
		"path": entry["path"], "sha256": entry["sha256"],
		"embedded_id": entry.get("embedded_id", entry["id"]),
		"embedded_revision": entry.get("embedded_revision", entry["revision"])}


func _request_place() -> void:
	var selection: PackedInt32Array = assets.get_selected_items() if assets != null else PackedInt32Array()
	if selection.is_empty():
		return
	var token: Dictionary = _drag_entry_for_row(selection[0])
	if not token.is_empty():
		place_requested.emit(token)
