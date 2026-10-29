class_name AtlasLinkDialog
extends ConfirmationDialog
## Scene-owned entrance/footprint form. Submitted Resources are drafts, never
## objects borrowed from the mutable campaign.

signal submitted(link: AtlasMapLink, placement: AtlasPlacement, new_map: AtlasMapDocument)
signal remove_requested(id: String)
signal enter_requested(id: String)
signal focus_requested(id: String)

@onready var source_label: Label = %SourceLabel
@onready var link_list: ItemList = %LinkList
@onready var target_picker: OptionButton = %TargetPicker
@onready var target_floor_picker: OptionButton = %TargetFloorPicker
@onready var mode_picker: OptionButton = %ModePicker
@onready var name_input: LineEdit = %NameInput
@onready var kind_picker: OptionButton = %KindPicker
@onready var native_distance: SpinBox = %NativeDistance
@onready var native_unit: OptionButton = %NativeUnit
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
var _shown: Dictionary[String, float] = {}


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


func prepare_new(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor, center: Vector2) -> void:
	if _campaign != campaign or _source_id != map.id or _source_floor != floor.id or not selected_id.is_empty():
		configure(campaign, map, floor, center)


func configure(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor, center: Vector2, selected: String = "") -> void:
	_campaign = campaign
	_source_id = map.id
	_source_floor = floor.id
	_center = center
	source_label.text = "Source: %s / %s" % [map.display_name, floor.display_name]
	link_list.clear()
	_link_ids = [""]
	link_list.add_item("+ New entrance / footprint")
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
	target_picker.clear()
	_target_ids = [""]
	target_picker.add_item("Create independent document")
	target_picker.set_item_disabled(0, not selected_id.is_empty())
	var ids: Array = _campaign.maps.keys()
	ids.sort()
	for id: String in ids:
		_target_ids.append(id)
		target_picker.add_item(_campaign.get_map(id).display_name + " · " + id)
	var link: AtlasMapLink = _campaign.link_by_id(selected_id)
	var placement: AtlasPlacement = _campaign.placement_by_id(link.placement_id) if link != null else null
	_expected_link = link.to_dict().duplicate(true) if link != null else {}
	_expected_placement = placement.to_dict().duplicate(true) if placement != null else {}
	var origin: Vector2 = placement.origin if placement != null else (link.anchor if link != null else _center)
	origin_x.value = origin.x
	origin_y.value = origin.y
	mode_picker.select(2 if link != null and placement == null else (1 if placement != null and placement.symbolic else 0))
	angle.value = rad_to_deg(placement.rotation) if placement != null else 0.0
	columns.value = placement.columns if placement != null else 10
	rows.value = placement.rows if placement != null else 10
	parent_pitch.value = placement.parent_units_per_cell if placement != null else 24.0
	child_pitch.value = placement.child_units_per_cell if placement != null else 64.0
	radius.value = link.hit_radius if link != null else 48.0
	arrival_x.value = link.target_focus.x if link != null else 0.0
	arrival_y.value = link.target_focus.y if link != null else 0.0
	arrival_zoom.value = link.target_zoom if link != null else 1.0
	_shown = {"x": origin_x.value, "y": origin_y.value, "angle": angle.value,
		"columns": columns.value, "rows": rows.value,
		"parent_pitch": parent_pitch.value, "child_pitch": child_pitch.value, "radius": radius.value,
		"arrival_x": arrival_x.value, "arrival_y": arrival_y.value, "zoom": arrival_zoom.value}
	center_arrival.set_pressed_no_signal(link == null)
	name_input.text = "Encounter %d" % _campaign.maps.size()
	kind_picker.select(0)
	native_distance.value = 5.0
	native_unit.select(0)
	var target_index: int = _target_ids.find(link.target_map_id) if link != null else 0
	target_picker.select(target_index)
	_target_changed(target_index)
	if link != null:
		target_floor_picker.select(_floor_ids.find(link.target_floor_id))
	remove_button.disabled = link == null
	focus_button.disabled = link == null
	var destination: AtlasMapDocument = _campaign.get_map(link.target_map_id) if link != null else null
	enter_button.disabled = destination == null or destination.floor_by_id(link.target_floor_id) == null \
		or (not link.placement_id.is_empty() and (placement == null or placement.parent_map_id != link.source_map_id or placement.child_map_id != link.target_map_id))
	get_ok_button().text = "Create link" if link == null else "Apply link"
	_sync_fields()


func _target_changed(index: int) -> void:
	target_floor_picker.clear()
	_floor_ids.clear()
	var target: AtlasMapDocument = _campaign.get_map(_target_ids[index]) if index > 0 else null
	if target == null:
		_floor_ids.append("ground")
		target_floor_picker.add_item("Ground (new document)")
	else:
		for floor: AtlasFloor in target.floors:
			_floor_ids.append(floor.id)
			target_floor_picker.add_item(floor.display_name + " · " + floor.id)
		target_floor_picker.select(_floor_ids.find(target.default_floor_id))
	_sync_fields()


func _sync_fields() -> void:
	%NewDocument.visible = target_picker.selected == 0
	%FootprintFields.visible = mode_picker.selected != 2
	%MarkerFields.visible = mode_picker.selected == 2


func draft(new_id: String = "", start: Vector2 = Vector2.INF, finish: Vector2 = Vector2.INF,
		radians: float = 0.0) -> Array[Resource]:
	if target_picker.selected < 0 or target_floor_picker.selected < 0:
		return []
	var previous: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if not _expected_link.is_empty() else null
	var old_placement: AtlasPlacement = AtlasPlacement.from_dict(_expected_placement) if not _expected_placement.is_empty() else null
	var link: AtlasMapLink = AtlasMapLink.from_dict(_expected_link) if previous != null else AtlasMapLink.new()
	link.id = selected_id if not selected_id.is_empty() else _id("link")
	link.source_map_id = _source_id
	link.source_floor_id = _source_floor
	link.target_map_id = _target_ids[target_picker.selected]
	link.target_floor_id = _floor_ids[target_floor_picker.selected]
	var original_origin: Vector2 = old_placement.origin if old_placement != null else (previous.anchor if previous != null else Vector2(origin_x.value, origin_y.value))
	var chosen_origin: Vector2 = Vector2(_value(origin_x, "x", original_origin.x), _value(origin_y, "y", original_origin.y))
	link.anchor = chosen_origin
	link.hit_radius = _value(radius, "radius", previous.hit_radius) if previous != null else radius.value
	link.target_focus = Vector2(_value(arrival_x, "arrival_x", previous.target_focus.x), _value(arrival_y, "arrival_y", previous.target_focus.y)) if previous != null else Vector2(arrival_x.value, arrival_y.value)
	link.target_zoom = _value(arrival_zoom, "zoom", previous.target_zoom) if previous != null else arrival_zoom.value
	link.placement_id = ""
	var child: AtlasMapDocument
	if target_picker.selected == 0:
		if name_input.text.strip_edges().is_empty():
			return []
		child = AtlasMapDocument.new(_id("map") if new_id.is_empty() else new_id, name_input.text.strip_edges())
		child.kind = kind_picker.get_item_text(kind_picker.selected)
		child.grid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS if mode_picker.selected == 2 else AtlasGrid.Kind.SQUARE, child_pitch.value)
		child.grid.distance_per_cell = native_distance.value
		child.grid.distance_unit = native_unit.get_item_text(native_unit.selected)
		child.terrain_grid = child.grid.copy()
		child.floors[0].terrain_layer().grid = child.grid.copy()
		link.target_map_id = child.id
	var placement: AtlasPlacement
	if mode_picker.selected != 2:
		var old: AtlasMapLink = _campaign.link_by_id(selected_id)
		placement = AtlasPlacement.new()
		placement.id = old.placement_id if old != null and not old.placement_id.is_empty() else _id("placement")
		placement.parent_map_id = _source_id
		placement.child_map_id = link.target_map_id
		placement.origin = link.anchor
		placement.rotation = old_placement.rotation if old_placement != null and angle.value == _shown.angle else deg_to_rad(angle.value)
		placement.columns = old_placement.columns if old_placement != null and columns.value == _shown.columns else int(columns.value)
		placement.rows = old_placement.rows if old_placement != null and rows.value == _shown.rows else int(rows.value)
		placement.parent_units_per_cell = _value(parent_pitch, "parent_pitch", old_placement.parent_units_per_cell) if old_placement != null else parent_pitch.value
		placement.child_units_per_cell = _value(child_pitch, "child_pitch", old_placement.child_units_per_cell) if old_placement != null else child_pitch.value
		placement.symbolic = mode_picker.selected == 1
		if start.is_finite() and finish.is_finite():
			var delta: Vector2 = (finish - start).rotated(-radians)
			if delta.length() < parent_pitch.value * 0.5:
				return []
			placement.rotation = radians
			placement.origin = start + Vector2(minf(0, delta.x), minf(0, delta.y)).rotated(radians)
			placement.columns = maxi(1, roundi(absf(delta.x) / parent_pitch.value))
			placement.rows = maxi(1, roundi(absf(delta.y) / parent_pitch.value))
		link.placement_id = placement.id
		link.anchor = previous.anchor if previous != null and old_placement != null and placement.origin == old_placement.origin else placement.origin
		if center_arrival.button_pressed:
			link.target_focus = placement.child_bounds().get_center()
	return [link, placement, child]


func _submit() -> void:
	var values: Array[Resource] = draft()
	if values.size() != 3:
		error_label.text = "Choose a valid target/floor and a name for a new document."
		return
	submitted.emit(values[0] as AtlasMapLink, values[1] as AtlasPlacement, values[2] as AtlasMapDocument)


static func _id(prefix: String) -> String:
	return prefix + "-" + Crypto.new().generate_random_bytes(16).hex_encode()


func is_current(link: AtlasMapLink, placement: AtlasPlacement) -> bool:
	return ((link.to_dict() if link != null else {}) == _expected_link
		and (placement.to_dict() if placement != null else {}) == _expected_placement)


func _value(control: SpinBox, key: String, original: float) -> float:
	# Display precision must not round untouched native settings on Apply.
	return original if control.value == _shown.get(key, control.value) else control.value
