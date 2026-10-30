class_name AtlasLayerPanel
extends VBoxContainer

signal layer_selected(id: String)
signal layers_changed(layers: Array[AtlasLayer], selected_id: String)
signal import_requested
signal presented_detail_selected(level: int)
signal automatic_detail_toggled(enabled: bool)
signal show_editing_detail_requested
signal object_selected(layer_id: String, stroke_index: int)
signal link_action_requested(link_id: String, action: StringName)

const LINK_FOCUS: int = 1
const LINK_EDIT: int = 2
const LINK_ENTER: int = 3
const LAYER_SETTINGS: int = 4
const MAX_STROKE_ROWS: int = 80
const ICON_FOCUS: Texture2D = preload("res://img/sidebar/maps.svg")
const ICON_EDIT: Texture2D = preload("res://img/controls/rename.svg")
const ICON_ENTER: Texture2D = preload("res://img/controls/raise.svg")

@onready var layer_list: ItemList = $LayerList # Legacy test/integration view, never shown.
@onready var hierarchy: Tree = $Hierarchy
@onready var layer_settings_button: Button = $LayerSettingsButton
@onready var visibility_checkbox: CheckBox = $VisibilityCheckbox
@onready var lock_checkbox: CheckBox = $LockCheckbox
@onready var opacity_spinner: SpinBox = $OpacitySpinner
@onready var name_input: LineEdit = $NameInput
@onready var layer_detail_spinner: SpinBox = $LayerDetailSpinner
@onready var view_detail_spinner: SpinBox = $ViewDetailSpinner
@onready var auto_detail_checkbox: CheckBox = $AutoDetailCheckbox
@onready var detail_status: Label = $DetailStatus
@onready var show_editing_detail: Button = $ShowEditingDetail
@onready var _up: Button = $Order/RaiseButton
@onready var _down: Button = $Order/LowerButton
var _floor: AtlasFloor
var _selected: String = ""
var _ids: Array[String] = []
var _campaign: AtlasCampaign
var _map: AtlasMapDocument
var _collapsed: Dictionary[String, bool] = {}
var _building: bool = false
var _settings_open: bool = false
var _layer_rows: Dictionary[String, TreeItem] = {}
var _stroke_rows: Dictionary[String, TreeItem] = {}


func _ready() -> void:
	layer_list.item_selected.connect(_on_selected)
	hierarchy.item_selected.connect(_on_hierarchy_selected)
	hierarchy.button_clicked.connect(_on_hierarchy_button)
	hierarchy.item_collapsed.connect(_on_hierarchy_collapsed)
	$NewLinkButton.pressed.connect(func() -> void: link_action_requested.emit("", &"edit"))
	layer_settings_button.pressed.connect(_toggle_layer_settings)
	_update_layer_settings()
	name_input.text_submitted.connect(_rename)
	name_input.focus_exited.connect(func() -> void: _rename(name_input.text))
	visibility_checkbox.toggled.connect(_set_property.bind(&"visible"))
	lock_checkbox.toggled.connect(_set_property.bind(&"locked"))
	opacity_spinner.value_changed.connect(_set_property.bind(&"opacity"))
	layer_detail_spinner.value_changed.connect(func(value: float) -> void:
		_set_property(int(value), &"detail_level"))
	view_detail_spinner.value_changed.connect(func(value: float) -> void:
		presented_detail_selected.emit(int(value)))
	auto_detail_checkbox.toggled.connect(automatic_detail_toggled.emit)
	show_editing_detail.pressed.connect(show_editing_detail_requested.emit)
	_up.pressed.connect(_move.bind(1))
	_down.pressed.connect(_move.bind(-1))
	$Order/NewInkButton.pressed.connect(_add_ink)
	$Order/NewTerrainButton.pressed.connect(_add_tiles)
	$Order/NewRasterButton.pressed.connect(_add_raster)
	$Order/ImportButton.pressed.connect(import_requested.emit)


func set_floor(floor: AtlasFloor, selected_id: String, view_level: int = 0, automatic: bool = true) -> void:
	_floor = floor
	_selected = selected_id
	view_detail_spinner.set_value_no_signal(view_level)
	auto_detail_checkbox.set_pressed_no_signal(automatic)
	view_detail_spinner.editable = not automatic
	layer_list.clear()
	_ids.clear()
	for index: int in range(floor.layers.size() - 1, -1, -1):
		var layer: AtlasLayer = floor.layers[index]
		_ids.append(layer.id)
		var flags: String = ""
		if layer.locked:
			flags += " [locked]"
		if not layer.visible:
			flags += " [hidden]"
		layer_list.add_item(layer.display_name + " · D%d · " % layer.detail_level + layer.kind + flags)
		if layer.id == _selected:
			layer_list.select(layer_list.item_count - 1)
	var current: AtlasLayer = floor.layer_by_id(_selected)
	var hidden_target: bool = current != null and current.detail_level != view_level
	detail_status.text = ("Viewing D%d · Editing %s (D%d, hidden)" % [view_level, current.display_name, current.detail_level]
		if hidden_target else "Viewing D%d · Editing %s" % [view_level, current.display_name if current != null else "none"])
	show_editing_detail.visible = hidden_target
	name_input.editable = current != null
	visibility_checkbox.disabled = current == null
	lock_checkbox.disabled = current == null
	opacity_spinner.editable = current != null
	layer_detail_spinner.editable = current != null
	if current != null:
		name_input.text = current.display_name
		visibility_checkbox.set_pressed_no_signal(current.visible)
		lock_checkbox.set_pressed_no_signal(current.locked)
		opacity_spinner.set_value_no_signal(current.opacity)
		layer_detail_spinner.set_value_no_signal(current.detail_level)
	else:
		name_input.text = ""
		layer_detail_spinner.set_value_no_signal(0)
	_rebuild_hierarchy()
	var index: int = _index()
	_up.disabled = index < 0 or index == floor.layers.size() - 1
	_down.disabled = index <= 0


func _index() -> int:
	if _floor != null:
		for index: int in range(_floor.layers.size()):
			if _floor.layers[index].id == _selected:
				return index
	return -1


func _on_selected(index: int) -> void:
	if index >= 0 and index < _ids.size():
		layer_selected.emit(_ids[index])


func _set_property(value: Variant, property: StringName) -> void:
	var index: int = _index()
	if index < 0 or _floor.layers[index].get(property) == value:
		return
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_floor.layers)
	layers[index].set(property, value)
	layers_changed.emit(layers, _selected)


func _rename(value: String) -> void:
	if value.strip_edges().is_empty():
		if _floor != null:
			set_floor(_floor, _selected)
		return
	_set_property(value.strip_edges(), &"display_name")


func _move(direction: int) -> void:
	var index: int = _index()
	var destination: int = index + direction
	if index < 0 or destination < 0 or destination >= _floor.layers.size():
		return
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_floor.layers)
	var moved: AtlasLayer = layers[index]
	layers.remove_at(index)
	layers.insert(destination, moved)
	layers_changed.emit(layers, _selected)


func _add_ink() -> void:
	var layer: AtlasInkLayer = AtlasInkLayer.new("ink-" + Crypto.new().generate_random_bytes(16).hex_encode(), "Ink")
	_add(layer)


func _add_tiles() -> void:
	var layer: AtlasTileLayer = AtlasTileLayer.new("tiles-" + Crypto.new().generate_random_bytes(16).hex_encode(), "Terrain")
	_add(layer)


func _add_raster() -> void:
	var layer: AtlasRasterLayer = AtlasRasterLayer.new("raster-" + Crypto.new().generate_random_bytes(16).hex_encode(), "Raster")
	_add(layer)


func _add(layer: AtlasLayer) -> void:
	if _floor == null:
		return
	var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(_floor.layers)
	layer.detail_level = int(view_detail_spinner.value)
	layers.append(layer)
	layers_changed.emit(layers, layer.id)


func set_navigation_context(campaign: AtlasCampaign, map: AtlasMapDocument) -> void:
	_campaign = campaign
	_map = map
	_rebuild_hierarchy()


func sync_object_selection(selection: AtlasSelection) -> void:
	# A cleared or multi-object selection must not leave one stale stroke highlighted.
	if selection == null or selection.is_empty() or selection.stroke_indices.size() != 1:
		if _layer_rows.has(_selected):
			_building = true
			(_layer_rows[_selected] as TreeItem).select(0)
			_building = false
		return
	var key: String = "%s:%d" % [selection.layer_id, selection.stroke_indices[0]]
	if not _stroke_rows.has(key):
		return
	var row: TreeItem = _stroke_rows[key]
	_building = true
	var layer_row: TreeItem = row.get_parent()
	var group: TreeItem = layer_row.get_parent()
	group.collapsed = false
	layer_row.collapsed = false
	_collapsed["layer:" + selection.layer_id] = false
	var selected_layer: AtlasLayer = _floor.layer_by_id(selection.layer_id)
	if selected_layer != null:
		_collapsed["detail:%d" % selected_layer.detail_level] = false
	row.select(0)
	_building = false


func _toggle_layer_settings() -> void:
	_settings_open = not _settings_open
	_update_layer_settings()


func _update_layer_settings() -> void:
	layer_settings_button.text = "Layer settings %s" % ("▾" if _settings_open else "▸")
	for name: String in ["NameInput", "VisibilityCheckbox", "LockCheckbox", "LayerDetailLabel",
			"LayerDetailSpinner", "OpacityLabel", "OpacitySpinner"]:
		get_node(name).visible = _settings_open


func _make_row(parent: TreeItem, label: String, metadata: Dictionary, tooltip: String = "") -> TreeItem:
	var row: TreeItem = hierarchy.create_item(parent)
	row.set_text(0, label)
	row.set_metadata(0, metadata)
	if not tooltip.is_empty():
		row.set_tooltip_text(0, tooltip)
	return row


func _rebuild_hierarchy() -> void:
	if hierarchy == null or _floor == null:
		return
	_building = true
	hierarchy.clear()
	_layer_rows.clear()
	_stroke_rows.clear()
	var root: TreeItem = hierarchy.create_item()
	var levels: Array[int] = []
	for layer: AtlasLayer in _floor.layers:
		if not levels.has(layer.detail_level):
			levels.append(layer.detail_level)
	levels.sort()
	for level: int in levels:
		var group_key: String = "detail:%d" % level
		var group: TreeItem = _make_row(root, "D%d · %s" % [level,
			"overview" if level == 0 else "authored detail"], {"kind": "group", "key": group_key},
			"Shared board coordinates; a detail level is not a separate map")
		group.set_selectable(0, false)
		group.collapsed = _collapsed.get(group_key, false)
		for index: int in range(_floor.layers.size() - 1, -1, -1):
			var layer: AtlasLayer = _floor.layers[index]
			if layer.detail_level != level:
				continue
			var badges: String = (" ◉" if layer.id == _selected else "")
			if layer.locked:
				badges += " [locked]"
			if not layer.visible:
				badges += " [hidden]"
			var entry: TreeItem = _make_row(group, "%s · %s%s" % [layer.display_name,
				layer.kind.to_lower(), badges], {"kind": "layer", "id": layer.id},
				"%s · D%d · %s\nSelect to edit on the continuous board." % [layer.display_name, level, layer.kind])
			_layer_rows[layer.id] = entry
			entry.add_button(0, ICON_EDIT, LAYER_SETTINGS, false, "Select layer and open its settings")
			entry.collapsed = _collapsed.get("layer:" + layer.id, true)
			if layer is AtlasInkLayer:
				var ink: AtlasInkLayer = layer as AtlasInkLayer
				for stroke_index: int in range(mini(ink.strokes.size(), MAX_STROKE_ROWS)):
					var stroke: AtlasStroke = ink.strokes[stroke_index]
					var title: String = ("Wall path %d%s · %d pts" % [stroke_index + 1,
						" (closed)" if stroke.closed_path else "", stroke.points.size()]
						if stroke.editable_path else "Stroke %d · %d pts" % [stroke_index + 1, stroke.points.size()])
					var item: TreeItem = _make_row(entry, title, {"kind": "stroke", "id": layer.id,
						"index": stroke_index}, "Select this object for whole-object edits")
					_stroke_rows["%s:%d" % [layer.id, stroke_index]] = item
				if ink.strokes.size() > MAX_STROKE_ROWS:
					var more: TreeItem = _make_row(entry, "… %d more strokes (use Select tool)" %
						(ink.strokes.size() - MAX_STROKE_ROWS), {"kind": "summary"})
					more.set_selectable(0, false)
			elif layer is AtlasRasterLayer:
				var raster: AtlasRasterLayer = layer as AtlasRasterLayer
				if not raster.chunks.is_empty():
					_make_row(entry, "Raster pixels · %d chunks" % raster.chunks.size(),
						{"kind": "raster", "id": layer.id}, "Whole-layer raster selection")
			elif layer is AtlasTileLayer:
				var terrain: AtlasTileLayer = layer as AtlasTileLayer
				var summary: TreeItem = _make_row(entry, "%d painted cells" % terrain.terrain.size(),
					{"kind": "summary"}, "Terrain cells belong to this layer, not separate maps")
				summary.set_selectable(0, false)
	var links_key: String = "links"
	var links: Array[AtlasMapLink] = []
	if _campaign != null and _map != null:
		links = _campaign.outgoing_links(_map.id, _floor.id)
	var heading: TreeItem = _make_row(root, "MAP LINKS · %d" % links.size(),
		{"kind": "group", "key": links_key}, "Navigation only; no separate map per hex")
	heading.set_selectable(0, false)
	heading.collapsed = _collapsed.get(links_key, false)
	for link: AtlasMapLink in links:
		var target: AtlasMapDocument = _campaign.get_map(link.target_map_id)
		var label: String = "%s / %s" % [target.display_name if target != null else "Missing destination",
			link.target_floor_id]
		var row: TreeItem = _make_row(heading, label,
			{"kind": "link", "id": link.id}, "Independent destination: %s / %s\nEntrance at %s\nLinks navigate documents; they are not detail layers" % [target.display_name if target != null else "Missing map", link.target_floor_id, link.anchor])
		row.add_button(0, ICON_FOCUS, LINK_FOCUS, false, "Locate on this board")
		row.add_button(0, ICON_EDIT, LINK_EDIT, false, "Edit link")
		row.add_button(0, ICON_ENTER, LINK_ENTER, target == null or target.floor_by_id(link.target_floor_id) == null, "Enter destination map")
	if _layer_rows.has(_selected):
		(_layer_rows[_selected] as TreeItem).select(0)
	_building = false


func _on_hierarchy_collapsed(item: TreeItem) -> void:
	if _building:
		return
	var data: Dictionary = item.get_metadata(0) if item.get_metadata(0) is Dictionary else {}
	if data.get("kind") == "group":
		_collapsed[str(data.get("key"))] = item.collapsed
	elif data.get("kind") == "layer":
		_collapsed["layer:" + str(data.get("id"))] = item.collapsed


func _on_hierarchy_selected() -> void:
	if _building:
		return
	var row: TreeItem = hierarchy.get_selected()
	if row == null:
		return
	var data: Dictionary = row.get_metadata(0) if row.get_metadata(0) is Dictionary else {}
	match str(data.get("kind", "")):
		"layer":
			layer_selected.emit(str(data.get("id", "")))
		"stroke":
			object_selected.emit(str(data.get("id", "")), int(data.get("index", -1)))
		"raster":
			object_selected.emit(str(data.get("id", "")), -1)


func _on_hierarchy_button(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	var data: Dictionary = item.get_metadata(0) if item.get_metadata(0) is Dictionary else {}
	if data.get("kind") == "layer" and id == LAYER_SETTINGS:
		layer_selected.emit(str(data.get("id", "")))
		_settings_open = true
		_update_layer_settings()
		return
	if data.get("kind") != "link":
		return
	var link_id: String = str(data.get("id", ""))
	match id:
		LINK_FOCUS:
			link_action_requested.emit(link_id, &"focus")
		LINK_EDIT:
			link_action_requested.emit(link_id, &"edit")
		LINK_ENTER:
			link_action_requested.emit(link_id, &"enter")
