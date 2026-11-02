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
signal link_action_rejected
signal drawing_layer_selected(map_id: String, floor_id: String, level: int, layer_id: String)

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
var _drawing_registry: AtlasDrawingRegistry
var _drawing_library: AtlasObjectLibrary
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
var _pinned_stroke_layer: String = ""
var _pinned_stroke_index: int = -1


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
	$Order/NewObjectsButton.pressed.connect(_add_objects)
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
	var empty_label: String = " · empty" if not _has_authored_detail(floor, view_level) else ""
	detail_status.text = ("Viewing D%d%s · Editing %s (D%d, hidden)" % [view_level, empty_label, current.display_name, current.detail_level]
		if hidden_target else "Viewing D%d%s · Editing %s" % [view_level, empty_label, current.display_name if current != null else "none"])
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


## The composed Drawing tree is authoritative for new strokes. The older
## legacy tree remains visible during gradual compatibility extraction.
## An empty high detail is not missing/lost artwork: navigation/grid overlays
## are separate and remain interactive even without authored pixels.
func _has_authored_detail(floor: AtlasFloor, level: int) -> bool:
	for layer: AtlasLayer in floor.layers:
		if layer.detail_level != level:
			continue
		if layer is AtlasRasterLayer and not (layer as AtlasRasterLayer).chunks.is_empty():
			return true
		if layer is AtlasObjectsLayer and not (layer as AtlasObjectsLayer).strokes.is_empty():
			return true
		if layer is AtlasTokenLayer and not (layer as AtlasTokenLayer).tokens.is_empty():
			return true
	return false


func set_drawing_registry(registry: AtlasDrawingRegistry,
		library: AtlasObjectLibrary = null) -> void:
	_drawing_registry = registry
	_drawing_library = library
	_rebuild_hierarchy()


func _drawing_rows(parent: TreeItem, document: DrawingDocument,
		parent_id: String, map_id: String, floor_id: String, level: int) -> void:
	for layer_id: String in document.list_children(parent_id):
		var meta: Dictionary = document.node_metadata(layer_id)
		var entry: TreeItem = _make_row(parent, "%s · %s%s" % [meta["name"], meta["kind"],
			" [hidden]" if not meta["visible"] else ""],
			{"kind": "drawing-layer", "map": map_id, "floor": floor_id,
			"level": level, "id": layer_id}, "Canonical Drawing package layer")
		if meta["kind"] == DrawingLayerNode.GROUP:
			_drawing_rows(entry, document, layer_id, map_id, floor_id, level)


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


func _add_objects() -> void:
	var layer: AtlasObjectsLayer = AtlasObjectsLayer.new("objects-" + Crypto.new().generate_random_bytes(16).hex_encode(), "Objects")
	_add(layer)


func _add_raster() -> void:
	var layer: AtlasRasterLayer = AtlasRasterLayer.paint_layer("raster-" + Crypto.new().generate_random_bytes(16).hex_encode(), "Raster")
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
	var layer: AtlasLayer = _floor.layer_by_id(selection.layer_id) if _floor != null and selection != null else null
	var single_stroke: bool = (selection != null and selection.stroke_indices.size() == 1
		and not selection.is_empty() and layer is AtlasObjectsLayer and selection.matches(layer))
	var index: int = selection.stroke_indices[0] if single_stroke else -1
	var layer_id: String = selection.layer_id if single_stroke else ""
	var key: String = "%s:%d" % [layer_id, index]

	# The extra row is only needed while its exact live object is selected.
	# Dropping it on deselect or a stale snapshot prevents false highlights.
	if _pinned_stroke_index >= 0 and (_pinned_stroke_layer != layer_id or _pinned_stroke_index != index):
		_pinned_stroke_layer = ""
		_pinned_stroke_index = -1
		_rebuild_hierarchy()
	if not single_stroke:
		if _layer_rows.has(_selected):
			_building = true
			(_layer_rows[_selected] as TreeItem).select(0)
			_building = false
		return
	if not _stroke_rows.has(key):
		_pinned_stroke_layer = layer_id
		_pinned_stroke_index = index
		_rebuild_hierarchy()
	if not _stroke_rows.has(key):
		return

	var row: TreeItem = _stroke_rows[key]
	_building = true
	var layer_row: TreeItem = row.get_parent()
	var group: TreeItem = layer_row.get_parent()
	group.collapsed = false
	layer_row.collapsed = false
	_collapsed["layer:" + layer_id] = false
	_collapsed["detail:%d" % layer.detail_level] = false
	row.select(0)
	hierarchy.scroll_to_item(row)
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


func _visible_stroke_indices(total: int, layer_id: String) -> Array[int]:
	# Keep the hierarchy bounded while showing both old and newly added objects.
	# A canvas-selected object in the omitted middle gets one temporary row.
	var indices: Array[int] = []
	var head: int = mini(total, MAX_STROKE_ROWS / 2)
	var tail_start: int = maxi(head, total - (MAX_STROKE_ROWS - head))
	for index: int in range(head):
		indices.append(index)
	for index: int in range(tail_start, total):
		indices.append(index)
	if _pinned_stroke_layer == layer_id and _pinned_stroke_index >= head \
			and _pinned_stroke_index < tail_start:
		indices.append(_pinned_stroke_index)
		indices.sort()
	return indices


func _rebuild_hierarchy() -> void:
	if hierarchy == null or _floor == null:
		return
	_building = true
	hierarchy.clear()
	_layer_rows.clear()
	_stroke_rows.clear()
	var root: TreeItem = hierarchy.create_item()
	if _drawing_registry != null and _map != null:
		var map_group: TreeItem = _make_row(root, "DRAWING · MAP / FLOOR / DETAIL / LAYERS",
			{"kind": "group"}, "The canonical shared Drawing engine")
		map_group.set_selectable(0, false)
		for group: Dictionary in _drawing_registry.projection(_map.id):
			var floor_group: TreeItem = _make_row(map_group, "FLOOR · %s" % group["name"],
				{"kind": "group"})
			floor_group.set_selectable(0, false)
			for detail: Dictionary in group["details"]:
				var section: TreeItem = _make_row(floor_group, "%s%s" % [detail["id"],
					" · empty" if detail["blank"] else " · authored"], {"kind": "group"})
				section.set_selectable(0, false)
				var fetched: DrawingResult = _drawing_registry.document_at(_map.id, group["id"], detail["level"])
				if fetched.ok and fetched.value != null:
					_drawing_rows(section, fetched.value, DrawingDocument.ROOT_ID,
						_map.id, group["id"], detail["level"])
				if _drawing_library != null:
					for instance_id: String in _drawing_registry.visible_placements(_drawing_library,
							_map.id, group["id"], detail["level"]):
						_make_row(section, "Object · %s" % instance_id.substr(0, 18),
							{"kind": "object-instance", "id": instance_id})
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
			var entry: TreeItem = _make_row(group, "%s · %s%s" % [
				"Objects" if layer is AtlasObjectsLayer and layer.display_name == "Ink" else layer.display_name,
				"objects" if layer is AtlasObjectsLayer else "tokens" if layer is AtlasTokenLayer else "raster", badges], {"kind": "layer", "id": layer.id},
				"%s · D%d · %s\nSelect to edit on the continuous board." % [layer.display_name, level, layer.kind])
			_layer_rows[layer.id] = entry
			entry.add_button(0, ICON_EDIT, LAYER_SETTINGS, false, "Select layer and open its settings")
			entry.collapsed = _collapsed.get("layer:" + layer.id, true)
			if layer is AtlasObjectsLayer:
				var ink: AtlasObjectsLayer = layer as AtlasObjectsLayer
				var previous_index: int = -1
				for stroke_index: int in _visible_stroke_indices(ink.strokes.size(), layer.id):
					if stroke_index > previous_index + 1:
						var omitted: int = stroke_index - previous_index - 1
						var summary: TreeItem = _make_row(entry, "… %d objects (select on canvas)" % omitted,
							{"kind": "summary"})
						summary.set_selectable(0, false)
					previous_index = stroke_index
					var stroke: AtlasStroke = ink.strokes[stroke_index]
					var title: String
					if stroke.is_prop():
						title = "Image prop %d" % (stroke_index + 1)
					elif stroke.is_text():
						title = "Text %d · %s" % [stroke_index + 1, stroke.text.replace("\n", " ").substr(0, 22)]
					elif stroke.editable_path:
						title = "Wall path %d%s · %d pts" % [stroke_index + 1,
							" (closed)" if stroke.closed_path else "", stroke.points.size()]
					else:
						title = "Stroke %d · %d pts" % [stroke_index + 1, stroke.points.size()]
					var item: TreeItem = _make_row(entry, title, {"kind": "stroke", "id": layer.id,
						"index": stroke_index}, "Select this object for whole-object edits")
					_stroke_rows["%s:%d" % [layer.id, stroke_index]] = item
				# Omitted middle objects remain selectable directly on the canvas.
			elif layer is AtlasTokenLayer:
				var markers: AtlasTokenLayer = layer as AtlasTokenLayer
				_make_row(entry, "%d GM tokens · canvas selection" % markers.tokens.size(),
					{"kind": "summary"}, "Token placement, drag, and deletion use the Token tool")
			elif layer is AtlasRasterLayer:
				var raster: AtlasRasterLayer = layer as AtlasRasterLayer
				if not raster.chunks.is_empty():
					_make_row(entry, "Raster pixels · %d chunks" % raster.chunks.size(),
						{"kind": "raster", "id": layer.id}, "Whole-layer raster selection")
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
		var target_floor: AtlasFloor = target.floor_by_id(link.target_floor_id) if target != null else null
		var placement: AtlasPlacement = (
			_campaign.placement_by_id(link.placement_id) if not link.placement_id.is_empty() else null)
		var label: String = "%s / %s" % [target.display_name if target != null else "Missing destination",
			link.target_floor_id]
		# Tree rows survive until the next refresh, but their destinations may not.
		# Save immutable values and source identities so a stale click cannot act
		# on a different entrance or map with the same IDs.
		var snapshot: Dictionary = {"kind": "link", "id": link.id,
			"campaign": _campaign, "map": _map, "floor": _floor,
			"link_ref": link, "link": link.to_dict().duplicate(true),
			"placement_ref": placement, "placement": placement.to_dict().duplicate(true) if placement != null else {},
			"target": target, "target_floor": target_floor,
			"target_name": target.display_name if target != null else ""}
		var row: TreeItem = _make_row(heading, label, snapshot,
			"Independent destination: %s / %s\nEntrance at %s\nLinks navigate documents; they are not detail layers" % [target.display_name if target != null else "Missing map", link.target_floor_id, link.anchor])
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
	# Selection listeners can rebuild this Tree, which Godot forbids during mouse events.
	match str(data.get("kind", "")):
		"drawing-layer":
			drawing_layer_selected.emit.call_deferred(str(data.get("map", "")),
				str(data.get("floor", "")), int(data.get("level", 0)), str(data.get("id", "")))
		"layer":
			layer_selected.emit.call_deferred(str(data.get("id", "")))
		"stroke":
			object_selected.emit.call_deferred(str(data.get("id", "")), int(data.get("index", -1)))
		"raster":
			object_selected.emit.call_deferred(str(data.get("id", "")), -1)


## Link rows are action handles, not authority to navigate. The document and
## destination can change while the Tree is on screen, even without a redraw.
func _link_row_is_current(data: Dictionary) -> bool:
	if _campaign == null or _map == null or _floor == null or data.get("campaign") != _campaign \
			or data.get("map") != _map or data.get("floor") != _floor:
		return false
	if _campaign.get_map(_map.id) != _map or _map.floor_by_id(_floor.id) != _floor:
		return false
	var link: AtlasMapLink = _campaign.link_by_id(str(data.get("id", "")))
	if link == null or link != data.get("link_ref") or link.source_map_id != _map.id \
			or link.source_floor_id != _floor.id or link.to_dict() != data.get("link"):
		return false
	var placement: AtlasPlacement = (
		_campaign.placement_by_id(link.placement_id) if not link.placement_id.is_empty() else null)
	if placement != data.get("placement_ref") \
			or (placement.to_dict() if placement != null else {}) != data.get("placement"):
		return false
	var target: AtlasMapDocument = _campaign.get_map(link.target_map_id)
	if target != data.get("target"):
		return false
	if target != null:
		return target.display_name == data.get("target_name") \
			and target.floor_by_id(link.target_floor_id) == data.get("target_floor")
	return data.get("target_name") == "" and data.get("target_floor") == null


func _on_hierarchy_button(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	var data: Dictionary = item.get_metadata(0) if item.get_metadata(0) is Dictionary else {}
	if data.get("kind") == "layer" and id == LAYER_SETTINGS:
		layer_selected.emit.call_deferred(str(data.get("id", "")))
		_settings_open = true
		_update_layer_settings()
		return
	if data.get("kind") != "link":
		return
	if not _link_row_is_current(data):
		# Rebuilding inside a Tree button signal can invalidate the clicked item.
		_rebuild_hierarchy.call_deferred()
		link_action_rejected.emit()
		return
	var link_id: String = str(data.get("id", ""))
	match id:
		LINK_FOCUS:
			link_action_requested.emit(link_id, &"focus")
		LINK_EDIT:
			link_action_requested.emit(link_id, &"edit")
		LINK_ENTER:
			link_action_requested.emit(link_id, &"enter")
