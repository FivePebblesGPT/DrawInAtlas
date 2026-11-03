class_name AtlasLinkDialog
extends ConfirmationDialog
## Marker-only navigation editor. Submitted Resources are detached snapshots,
## never objects borrowed from the mutable campaign.

signal submitted(link: AtlasMapLink, placement: AtlasPlacement, new_map: AtlasMapDocument)
signal remove_requested(id: String)
signal enter_requested(id: String)
signal focus_requested(id: String)

@onready var source_label: Label = %SourceLabel
@onready var link_list: ItemList = %LinkList
@onready var target_picker: OptionButton = %TargetPicker
@onready var target_floor_picker: OptionButton = %TargetFloorPicker
@onready var origin_x: SpinBox = %OriginX
@onready var origin_y: SpinBox = %OriginY
@onready var radius: SpinBox = %Radius
@onready var arrival_x: SpinBox = %ArrivalX
@onready var arrival_y: SpinBox = %ArrivalY
@onready var arrival_zoom: SpinBox = %ArrivalZoom
@onready var error_label: Label = %ErrorLabel
@onready var remove_button: Button = %RemoveButton
@onready var enter_button: Button = %EnterButton
@onready var focus_button: Button = %FocusButton
var selected_id: String = ""
var _campaign: AtlasCampaign
var _source_id: String
var _source_floor: String
var _center: Vector2
var _link_ids: Array[String] = []
var _target_ids: Array[String] = []
var _floor_ids: Array[String] = []
var _expected_link: Dictionary = {}
var _expected_placement: Dictionary = {}
var _displayed_values: Dictionary[String, float] = {}


func _ready() -> void:
	confirmed.connect(_submit)
	link_list.item_selected.connect(_select)
	target_picker.item_selected.connect(_target_changed)
	remove_button.pressed.connect(func() -> void: remove_requested.emit(selected_id))
	enter_button.pressed.connect(func() -> void: enter_requested.emit(selected_id))
	focus_button.pressed.connect(func() -> void: focus_requested.emit(selected_id))


func open(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor, center: Vector2, selected: String = "") -> void:
	configure(campaign, map, floor, center, selected)
	popup_centered_clamped(Vector2i(520, 680), 0.92)


func configure(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor, center: Vector2, selected: String = "") -> void:
	_campaign = campaign
	_source_id = map.id
	_source_floor = floor.id
	_center = center
	source_label.text = "Source: %s / %s" % [map.display_name, floor.display_name]
	link_list.clear()
	_link_ids = [""]
	link_list.add_item("+ New marker to an existing map")
	for link: AtlasMapLink in campaign.outgoing_links(map.id, floor.id):
		_link_ids.append(link.id)
		var target: AtlasMapDocument = campaign.get_map(link.target_map_id)
		link_list.add_item("%d · %s / %s · %s" % [_link_ids.size() - 1,
			target.display_name if target != null else "Missing map", link.target_floor_id, link.anchor])
		link_list.set_item_tooltip(_link_ids.size() - 1, "Entrance %s\nArrival: %s · zoom %.3f" % [link.id, link.target_focus, link.target_zoom])
	var index: int = maxi(0, _link_ids.find(selected))
	link_list.select(index)
	_select(index)


func _select(index: int) -> void:
	selected_id = _link_ids[index]
	error_label.text = ""
	_populate_targets()
	var link: AtlasMapLink = _campaign.link_by_id(selected_id)
	var placement: AtlasPlacement
	if link != null:
		placement = _campaign.placement_by_id(link.placement_id)
	_expected_link = link.to_dict().duplicate(true) if link != null else {}
	_expected_placement = placement.to_dict().duplicate(true) if placement != null else {}
	_load_geometry(link)
	_load_arrival(link)
	_remember_displayed_values()
	_select_destination(link)
	remove_button.disabled = link == null
	focus_button.disabled = link == null
	enter_button.disabled = not _can_enter(link, placement)
	get_ok_button().text = "Create link" if link == null else "Apply link"


func _populate_targets() -> void:
	target_picker.clear()
	_target_ids.clear()
	var ids: Array = _campaign.maps.keys()
	ids.sort()
	for id: String in ids:
		_target_ids.append(id)
		target_picker.add_item(_campaign.get_map(id).display_name + " · " + id)


func _load_geometry(link: AtlasMapLink) -> void:
	var origin: Vector2 = link.anchor if link != null else _center
	origin_x.value = origin.x
	origin_y.value = origin.y


func _load_arrival(link: AtlasMapLink) -> void:
	var values: AtlasMapLink = link
	if values == null:
		values = AtlasMapLink.new()
	radius.value = values.hit_radius
	arrival_x.value = values.target_focus.x
	arrival_y.value = values.target_focus.y
	arrival_zoom.value = values.target_zoom


func _remember_displayed_values() -> void:
	_displayed_values = {"x": origin_x.value, "y": origin_y.value, "radius": radius.value,
		"arrival_x": arrival_x.value, "arrival_y": arrival_y.value, "zoom": arrival_zoom.value}


func _select_destination(link: AtlasMapLink) -> void:
	var target_index: int = _target_ids.find(link.target_map_id) if link != null else 0
	if link == null:
		for candidate_index: int in range(_target_ids.size()):
			if _target_ids[candidate_index] != _source_id:
				target_index = candidate_index
				break
	if target_index < 0 or target_picker.item_count == 0:
		return
	target_picker.select(target_index)
	_target_changed(target_index)
	if link != null:
		target_floor_picker.select(_floor_ids.find(link.target_floor_id))


func _can_enter(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	if link == null:
		return false
	var destination: AtlasMapDocument = _campaign.get_map(link.target_map_id)
	if destination == null or destination.floor_by_id(link.target_floor_id) == null:
		return false
	if link.placement_id.is_empty():
		return true
	return placement != null and placement.parent_map_id == link.source_map_id and placement.child_map_id == link.target_map_id


func _target_changed(index: int) -> void:
	target_floor_picker.clear()
	_floor_ids.clear()
	var target: AtlasMapDocument = _campaign.get_map(_target_ids[index]) if index >= 0 and index < _target_ids.size() else null
	if target != null:
		for floor: AtlasFloor in target.floors:
			_floor_ids.append(floor.id)
			target_floor_picker.add_item(floor.display_name + " · " + floor.id)
		target_floor_picker.select(_floor_ids.find(target.default_floor_id))


func draft() -> Array[Resource]:
	if target_picker.selected < 0 or target_picker.selected >= _target_ids.size() \
			or target_floor_picker.selected < 0 or target_floor_picker.selected >= _floor_ids.size():
		return []
	var previous: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if not _expected_link.is_empty() else null
	# Historical footprints are never silently flattened on Apply.
	if not _expected_placement.is_empty() or (previous != null and not previous.placement_id.is_empty()):
		return []
	return [_draft_link(previous), null, null]


func _draft_link(previous: AtlasMapLink) -> AtlasMapLink:
	var link: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if previous != null else AtlasMapLink.new()
	link.id = selected_id if not selected_id.is_empty() else _id("link")
	link.source_map_id = _source_id
	link.source_floor_id = _source_floor
	link.target_map_id = _target_ids[target_picker.selected]
	link.target_floor_id = _floor_ids[target_floor_picker.selected]
	var origin: Vector2 = previous.anchor if previous != null else Vector2(origin_x.value, origin_y.value)
	link.anchor = Vector2(_preserved_number(origin_x, "x", origin.x), _preserved_number(origin_y, "y", origin.y))
	if previous == null:
		link.hit_radius = radius.value
		link.target_focus = Vector2(arrival_x.value, arrival_y.value)
		link.target_zoom = arrival_zoom.value
	else:
		link.hit_radius = _preserved_number(radius, "radius", previous.hit_radius)
		link.target_focus = Vector2(
			_preserved_number(arrival_x, "arrival_x", previous.target_focus.x),
			_preserved_number(arrival_y, "arrival_y", previous.target_focus.y))
		link.target_zoom = _preserved_number(arrival_zoom, "zoom", previous.target_zoom)
	link.placement_id = ""
	return link


func _submit() -> void:
	var values: Array[Resource] = draft()
	if values.size() != 3:
		error_label.text = "Choose an existing destination and floor; legacy footprint links cannot be edited."
		return
	submitted.emit(values[0] as AtlasMapLink, values[1] as AtlasPlacement, values[2] as AtlasMapDocument)


static func _id(prefix: String) -> String:
	return prefix + "-" + Crypto.new().generate_random_bytes(16).hex_encode()


func is_current(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	return ((link.to_dict() if link != null else {}) == _expected_link
		and (placement.to_dict() if placement != null else {}) == _expected_placement)


func source_matches(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor) -> bool:
	return _campaign == campaign and _source_id == map.id and _source_floor == floor.id


func _preserved_number(control: SpinBox, key: String, original: float) -> float:
	# Display precision must not round untouched native settings on Apply.
	return original if control.value == _displayed_values.get(key, control.value) else control.value


func show_error(text: String) -> void:
	error_label.text = text
