class_name AtlasCampaignBrowser
extends VBoxContainer
## Campaign discovery reads the workspace context; navigation and edits are
## intents so the parent retains command history, camera and document ownership.

signal map_requested(map_id: String, floor_id: String)
signal source_focus_requested(entry: AtlasOverviewEntry)
signal metadata_requested(name: String, tags: Array[String])

@onready var map_list: ItemList = $MapList
@onready var map_name_input: LineEdit = $MapNameInput
@onready var map_tags_input: LineEdit = $MapTagsInput
@onready var map_preview: AtlasPreviewPanel = $MapPreview

var map_list_ids: Array[String] = []
var search_map_ids: Array[String] = []

var _campaign: AtlasCampaign
var _sidebar: Sidebar
var _overview: AtlasOverviewPanel
var _canvas: AtlasCanvas
var _views: AtlasViewSession
var _search_entries: Array[AtlasOverviewEntry] = []
var _spatial_refresh_queued: bool = false


func _ready() -> void:
	map_list.item_activated.connect(activate_map)
	map_list.item_selected.connect(_preview_map_index)
	map_name_input.text_submitted.connect(_on_metadata_submitted)
	map_tags_input.text_submitted.connect(_on_metadata_submitted)
	$ApplyMetadata.pressed.connect(_apply_map_metadata)


## Bind after both panels are ready; the overview remains in the Search view.
func bind_context(sidebar: Sidebar, overview: AtlasOverviewPanel, canvas: AtlasCanvas,
		views: AtlasViewSession) -> void:
	if _sidebar != null:
		_sidebar.search_changed.disconnect(refresh_search)
		_sidebar.view_selected.disconnect(_on_sidebar_view_selected)
	if _overview != null:
		_overview.query_changed.disconnect(_on_query_changed)
		_overview.entry_activated.disconnect(_open_overview_entry)
		_overview.source_focus_requested.disconnect(_focus_overview_source)
	if _canvas != null:
		_canvas.view_region_changed.disconnect(_on_view_region_changed)

	_sidebar = sidebar
	_overview = overview
	_canvas = canvas
	_views = views
	_sidebar.search_changed.connect(refresh_search)
	_sidebar.view_selected.connect(_on_sidebar_view_selected)
	_overview.query_changed.connect(_on_query_changed)
	_overview.entry_activated.connect(_open_overview_entry)
	_overview.source_focus_requested.connect(_focus_overview_source)
	_canvas.view_region_changed.connect(_on_view_region_changed)


func refresh(campaign: AtlasCampaign) -> void:
	_campaign = campaign
	map_list.clear()
	map_list_ids.clear()
	if _campaign == null:
		search_map_ids.clear()
		return
	var ids: Array[String] = []
	ids.assign(_campaign.maps.keys())
	ids.sort()
	for map_id: String in ids:
		var map: AtlasMapDocument = _campaign.get_map(map_id)
		map_list_ids.append(map_id)
		map_list.add_item("%s — %s · %d floors" % [map.display_name, map.kind, map.floors.size()])
		if _canvas.map != null and _canvas.map.id == map_id:
			map_list.select(map_list.item_count - 1)
	refresh_search(_sidebar.get_search_query())
	var selected: PackedInt32Array = map_list.get_selected_items()
	if not selected.is_empty() and _sidebar.get_view_content(&"Maps").is_visible_in_tree():
		_preview_map_index(selected[0])


## Keep metadata refresh explicit so list/search updates do not erase draft text.
func refresh_metadata() -> void:
	map_name_input.text = _canvas.map.display_name
	map_tags_input.text = ", ".join(_canvas.map.tags)


func refresh_search(query: String) -> void:
	search_map_ids.clear()
	if _campaign == null or _canvas.map == null or _canvas.floor == null:
		return
	var mode: AtlasOverview.Filter = _overview.mode_picker.selected as AtlasOverview.Filter
	var region: PackedVector2Array = PackedVector2Array()
	if mode == AtlasOverview.Filter.VISIBLE:
		for corner: Vector2 in [Vector2.ZERO, Vector2(_canvas.size.x, 0), _canvas.size, Vector2(0, _canvas.size.y)]:
			region.append(_canvas.local_to_document(corner))
	elif mode == AtlasOverview.Filter.CELL and _canvas.has_selected_cell:
		region = _canvas.map.grid.cell_polygon(_canvas.selected_cell)
	var result: AtlasOverviewResult = AtlasOverview.query(_campaign, _canvas.map.id, _canvas.floor.id,
		mode, query, region, _overview.recursive_checkbox.button_pressed)
	_search_entries = result.entries
	for entry: AtlasOverviewEntry in result.entries:
		search_map_ids.append(entry.map_id)
	_overview.set_results(_campaign, result)


func activate_search(index: int) -> void:
	if index >= 0 and index < _search_entries.size():
		_open_overview_entry(_search_entries[index])


func activate_map(index: int) -> void:
	if index < 0 or index >= map_list_ids.size():
		return
	map_requested.emit(map_list_ids[index], "")


## Cancel pending captures as well as cached images when replacing a campaign.
## Resetting navigation preferences remains the parent's responsibility.
func reset_previews() -> void:
	map_preview.clear_preview()
	map_preview.cache.invalidate()
	_overview.preview.clear_preview()
	_overview.preview.cache.invalidate()


func _open_overview_entry(entry: AtlasOverviewEntry) -> void:
	if entry.broken_reason.is_empty():
		map_requested.emit(entry.map_id, entry.floor_id)


func _focus_overview_source(entry: AtlasOverviewEntry) -> void:
	if entry.can_focus:
		source_focus_requested.emit(entry)


func _preview_map_index(index: int) -> void:
	if index < 0 or index >= map_list_ids.size():
		return
	# Match opening's last-visited-floor resolution rather than the saved default.
	var state: AtlasViewState = _views.resolve(_campaign, map_list_ids[index])
	if state != null:
		map_preview.request_preview(_campaign, state.map_id, state.floor_id)


func _on_query_changed() -> void:
	refresh_search(_sidebar.get_search_query())


func _on_view_region_changed() -> void:
	if _spatial_refresh_queued or not _overview.is_visible_in_tree():
		return
	if _overview.mode_picker.selected != AtlasOverview.Filter.VISIBLE:
		return
	# One zoom changes both center and scale, and layout can resize repeatedly.
	# Query the final region once, without polling or serializing artwork.
	_spatial_refresh_queued = true
	_refresh_visible_region.call_deferred()


func _refresh_visible_region() -> void:
	_spatial_refresh_queued = false
	if (is_inside_tree() and _overview.is_visible_in_tree()
			and _overview.mode_picker.selected == AtlasOverview.Filter.VISIBLE):
		refresh_search(_sidebar.get_search_query())


func _on_sidebar_view_selected(id: StringName) -> void:
	if _campaign == null or _canvas.map == null:
		return
	if id == &"Search":
		refresh_search(_sidebar.get_search_query())
		_overview.refresh_preview()
	elif id == &"Maps":
		var selected: PackedInt32Array = map_list.get_selected_items()
		if not selected.is_empty():
			_preview_map_index(selected[0])


func _on_metadata_submitted(_text: String) -> void:
	_apply_map_metadata()


func _apply_map_metadata() -> void:
	var tags: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for part: String in map_tags_input.text.split(",", false):
		var tag: String = part.strip_edges().trim_prefix("#")
		if not tag.is_empty() and not seen.has(tag.to_lower()):
			seen[tag.to_lower()] = true
			tags.append(tag)
	metadata_requested.emit(map_name_input.text, tags)
