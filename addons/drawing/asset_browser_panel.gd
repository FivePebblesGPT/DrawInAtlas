class_name DrawingAssetBrowserPanel
extends VBoxContainer
## Optional T-065 dock peer; selection is read-only until an explicit Open.

signal open_requested(path: String)

const INDEX_SCRIPT: Script = preload("res://addons/drawing/asset_browser_index.gd")
var index: DrawingAssetBrowserIndex
var search: LineEdit
var assets: ItemList
var message: Label
var open_button: Button
var _visible_entries: Array[Dictionary] = []


func _ready() -> void:
	name = "AssetBrowser"
	index = INDEX_SCRIPT.new() as DrawingAssetBrowserIndex
	var heading: Label = Label.new()
	heading.text = "Object Assets"
	add_child(heading)
	search = LineEdit.new()
	search.name = "AssetSearch"
	search.placeholder_text = "Search name or source ID…"
	search.text_changed.connect(func(_query: String) -> void: _refresh_view())
	add_child(search)
	assets = ItemList.new()
	assets.name = "AssetList"
	assets.custom_minimum_size.y = 205
	assets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	assets.item_selected.connect(func(_i: int) -> void: _update_open_button())
	assets.item_activated.connect(func(_i: int) -> void: open_selected())
	add_child(assets)
	var actions: HBoxContainer = HBoxContainer.new()
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
	message = Label.new()
	message.name = "AssetIndexStatus"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	_refresh_view()


func set_objects_root(path: String) -> DrawingResult:
	if index == null:
		index = INDEX_SCRIPT.new() as DrawingAssetBrowserIndex
	var result: DrawingResult = index.scan(path)
	if is_node_ready():
		_refresh_view()
		if not result.ok:
			message.text = result.message
	return result


func refresh_assets() -> void:
	if index == null or index.root_path.is_empty():
		return
	set_objects_root(index.root_path)


func _refresh_view() -> void:
	if assets == null or index == null:
		return
	var selected_id: String = selected_asset_id()
	_visible_entries = index.filtered(search.text)
	assets.clear()
	var selection: int = -1
	for i: int in range(_visible_entries.size()):
		var entry: Dictionary = _visible_entries[i]
		assets.add_item("%s  (v%d)" % [entry["name"], entry["revision"]])
		assets.set_item_tooltip(i, "%s\n%s" % [entry["id"], entry["path"]])
		if entry["id"] == selected_id:
			selection = i
	if selection >= 0:
		assets.select(selection)
	_update_open_button()
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
	if not fresh.ok or fresh.value["source_id"] != entry["id"] or fresh.value["source_revision"] != entry["revision"]:
		message.text = "Source changed; refresh the Asset Browser before opening"
		return
	open_requested.emit(String(entry["path"]))
