class_name AtlasLinkDialog
extends ConfirmationDialog
## Scene-owned entrance/footprint form. Submitted Resources are drafts, never
## objects borrowed from the mutable campaign.

signal submitted(link: AtlasMapLink, placement: AtlasPlacement, new_map: AtlasMapDocument)
signal remove_requested(id: String)
signal enter_requested(id: String)
signal focus_requested(id: String)

enum LinkMode { SPATIAL, SYMBOLIC, MARKER }

@onready var source_label: Label = %SourceLabel
@onready var link_list: ItemList = %LinkList
@onready var target_picker: OptionButton = %TargetPicker
@onready var target_floor_picker: OptionButton = %TargetFloorPicker
@onready var mode_picker: OptionButton = %ModePicker
@onready var origin_x: SpinBox = %OriginX
@onready var origin_y: SpinBox = %OriginY
@onready var angle: SpinBox = %Angle
@onready var columns: SpinBox = %Columns
@onready var rows: SpinBox = %Rows
@onready var parent_pitch: SpinBox = %ParentPitch
@onready var child_pitch: SpinBox = %ChildPitch
@onready var radius: SpinBox = %Radius
@onready var arrival_x: SpinBox = %ArrivalX
@onready var arrival_y: SpinBox = %ArrivalY
@onready var arrival_zoom: SpinBox = %ArrivalZoom
@onready var center_arrival: CheckBox = %CenterArrival
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
	mode_picker.item_selected.connect(func(_index: int) -> void: _sync_fields())
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
	_load_geometry(link, placement)
	_load_arrival(link)
	_remember_displayed_values()
	center_arrival.set_pressed_no_signal(link == null)
	_select_destination(link)
	remove_button.disabled = link == null
	focus_button.disabled = link == null
	enter_button.disabled = not _can_enter(link, placement)
	get_ok_button().text = "Create link" if link == null else "Apply link"
	_sync_fields()


func _populate_targets() -> void:
	target_picker.clear()
	_target_ids.clear()
	var ids: Array = _campaign.maps.keys()
	ids.sort()
	for id: String in ids:
		_target_ids.append(id)
		target_picker.add_item(_campaign.get_map(id).display_name + " · " + id)


func _load_geometry(link: AtlasMapLink, placement: AtlasPlacement) -> void:
	var origin: Vector2 = _original_origin(link, placement, _center)
	origin_x.value = origin.x
	origin_y.value = origin.y
	if placement != null:
		mode_picker.select(LinkMode.SYMBOLIC if placement.symbolic else LinkMode.SPATIAL)
	elif link != null:
		mode_picker.select(LinkMode.MARKER)
	else:
		mode_picker.select(LinkMode.MARKER)
	var geometry: AtlasPlacement = placement
	if geometry == null:
		geometry = AtlasPlacement.new()
	angle.value = rad_to_deg(geometry.rotation)
	columns.value = geometry.columns
	rows.value = geometry.rows
	parent_pitch.value = geometry.parent_units_per_cell
	child_pitch.value = geometry.child_units_per_cell


func _load_arrival(link: AtlasMapLink) -> void:
	var values: AtlasMapLink = link
	if values == null:
		values = AtlasMapLink.new()
	radius.value = values.hit_radius
	arrival_x.value = values.target_focus.x
	arrival_y.value = values.target_focus.y
	arrival_zoom.value = values.target_zoom


func _remember_displayed_values() -> void:
	_displayed_values = {"x": origin_x.value, "y": origin_y.value, "angle": angle.value,
		"columns": columns.value, "rows": rows.value,
		"parent_pitch": parent_pitch.value, "child_pitch": child_pitch.value, "radius": radius.value,
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
	_sync_fields()


func _sync_fields() -> void:
	var existing: AtlasMapLink = _campaign.link_by_id(selected_id) if _campaign != null else null
	var legacy_placement: bool = existing != null and not existing.placement_id.is_empty()
	# No new footprint can be selected, including for existing marker-only links.
	mode_picker.disabled = not legacy_placement
	%FootprintFields.visible = legacy_placement and mode_picker.selected != LinkMode.MARKER
	%MarkerFields.visible = mode_picker.selected == LinkMode.MARKER


func draft() -> Array[Resource]:
	if target_picker.selected < 0 or target_picker.selected >= _target_ids.size() or target_floor_picker.selected < 0:
		return []
	var previous: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if not _expected_link.is_empty() else null
	var old_placement: AtlasPlacement = AtlasPlacement.from_dict(_expected_placement) if not _expected_placement.is_empty() else null
	# The form can edit old footprints, not create a new footprint or document.
	if old_placement == null and mode_picker.selected != LinkMode.MARKER:
		return []
	var link: AtlasMapLink = _draft_link(previous, old_placement)
	var placement: AtlasPlacement
	if mode_picker.selected != LinkMode.MARKER:
		placement = _draft_placement(link, old_placement)
		link.placement_id = placement.id
		if previous != null and old_placement != null and placement.origin == old_placement.origin:
			link.anchor = previous.anchor
		else:
			link.anchor = placement.origin
		if center_arrival.button_pressed:
			link.target_focus = placement.child_bounds().get_center()
	return [link, placement, null]


func _draft_link(previous: AtlasMapLink, old_placement: AtlasPlacement) -> AtlasMapLink:
	var link: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if previous != null else AtlasMapLink.new()
	link.id = selected_id if not selected_id.is_empty() else _id("link")
	link.source_map_id = _source_id
	link.source_floor_id = _source_floor
	link.target_map_id = _target_ids[target_picker.selected]
	link.target_floor_id = _floor_ids[target_floor_picker.selected]
	var origin: Vector2 = _original_origin(previous, old_placement, Vector2(origin_x.value, origin_y.value))
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


func _draft_placement(link: AtlasMapLink, snapshot_placement: AtlasPlacement) -> AtlasPlacement:
	var current_link: AtlasMapLink = _campaign.link_by_id(selected_id)
	var placement: AtlasPlacement = AtlasPlacement.new()
	if current_link != null and not current_link.placement_id.is_empty():
		placement.id = current_link.placement_id
	else:
		placement.id = _id("placement")
	placement.parent_map_id = _source_id
	placement.child_map_id = link.target_map_id
	placement.origin = link.anchor
	placement.rotation = deg_to_rad(angle.value)
	placement.columns = int(columns.value)
	placement.rows = int(rows.value)
	placement.parent_units_per_cell = parent_pitch.value
	placement.child_units_per_cell = child_pitch.value
	if snapshot_placement != null:
		if angle.value == _displayed_values.angle:
			placement.rotation = snapshot_placement.rotation
		if columns.value == _displayed_values.columns:
			placement.columns = snapshot_placement.columns
		if rows.value == _displayed_values.rows:
			placement.rows = snapshot_placement.rows
		placement.parent_units_per_cell = _preserved_number(parent_pitch, "parent_pitch", snapshot_placement.parent_units_per_cell)
		placement.child_units_per_cell = _preserved_number(child_pitch, "child_pitch", snapshot_placement.child_units_per_cell)
	placement.symbolic = mode_picker.selected == LinkMode.SYMBOLIC
	return placement


func _original_origin(link: AtlasMapLink, placement: AtlasPlacement, fallback: Vector2) -> Vector2:
	if placement != null:
		return placement.origin
	if link != null:
		return link.anchor
	return fallback


func _submit() -> void:
	var values: Array[Resource] = draft()
	if values.size() != 3:
		error_label.text = "Choose an existing destination and floor; new footprints are unavailable."
		return
	submitted.emit(values[0] as AtlasMapLink, values[1] as AtlasPlacement, values[2] as AtlasMapDocument)


static func _id(prefix: String) -> String:
	return prefix + "-" + Crypto.new().generate_random_bytes(16).hex_encode()


func is_current(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	return ((link.to_dict() if link != null else {}) == _expected_link
		and (placement.to_dict() if placement != null else {}) == _expected_placement)


func _preserved_number(control: SpinBox, key: String, original: float) -> float:
	# Display precision must not round untouched native settings on Apply.
	return original if control.value == _displayed_values.get(key, control.value) else control.value


func is_marker_mode() -> bool:
	return mode_picker.selected == LinkMode.MARKER


func get_parent_pitch() -> float:
	return parent_pitch.value


func show_error(text: String) -> void:
	error_label.text = text
