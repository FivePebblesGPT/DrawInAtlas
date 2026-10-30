class_name AtlasInspector
extends PanelContainer
## Keep form state local so editor commands remain the only document-edit boundary.

signal floor_selected(id: String)
signal floor_created(name: String)
signal floor_renamed(name: String)
signal floor_moved(direction: int)
signal floor_default_requested()
signal floor_removed()
signal scope_toggled(enabled: bool)
signal selection_transform_requested(offset: Vector2, factor: float, radians: float)
signal brush_color_changed(color: Color)
signal brush_width_changed(value: float)
signal grid_snapping_toggled(enabled: bool)
signal palette_selected(index: int)
signal preview_changed(index: int)
signal reference_toggled(enabled: bool)
signal reference_opacity_changed(value: float)
signal automatic_navigation_toggled(enabled: bool)
signal linked_maps_requested
signal back_requested
signal reference_source_changed(link_id: String, floor_id: String)
signal reference_freeze_toggled(enabled: bool)

@onready var preview_picker: OptionButton = %PreviewPicker
@onready var lock_checkbox: CheckBox = %LockCheckbox
@onready var reference_checkbox: CheckBox = %ReferenceCheckbox
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var brush_color_picker: ColorPickerButton = %BrushColorPicker
@onready var brush_width_spinner: SpinBox = %BrushWidthSpinner
@onready var selection_label: Label = %SelectionLabel
@onready var move_x_spinner: SpinBox = %MoveXSpinner
@onready var move_y_spinner: SpinBox = %MoveYSpinner
@onready var scale_spinner: SpinBox = %ScaleSpinner
@onready var artwork_rotation_spinner: SpinBox = %ArtworkRotationSpinner
@onready var floor_picker: OptionButton = %FloorPicker
@onready var floor_name_input: LineEdit = %FloorNameInput

@onready var snap_checkbox: CheckBox = %SnapCheckbox
@onready var _snap_section: VBoxContainer = %SnapSection
@onready var _ink_section: VBoxContainer = %InkSection
@onready var _ink_heading: Label = $Scroll/Margin/Sections/InkSection/Heading
@onready var _ink_color_label: Label = $Scroll/Margin/Sections/InkSection/ColorLabel
@onready var _eraser_hint: Label = %EraserHint
@onready var _terrain_section: VBoxContainer = %TerrainSection
@onready var _selection_section: VBoxContainer = %SelectionSection
@onready var _transform_button: Button = %TransformButton
@onready var _floor_add: Button = %FloorAdd
@onready var _floor_rename: Button = %FloorRename
@onready var _floor_up: Button = %FloorUp
@onready var _floor_down: Button = %FloorDown
@onready var _floor_remove: Button = %FloorRemove
@onready var _floor_default: Button = %FloorDefault
@onready var _palette_picker: OptionButton = %PalettePicker
@onready var _navigation_toggle: CheckBox = %NavigationToggle
@onready var reference_source_picker: OptionButton = %ReferenceSourcePicker
@onready var reference_floor_picker: OptionButton = %ReferenceFloorPicker
@onready var freeze_checkbox: CheckBox = %FreezeReference

@onready var _active_tool_label: Label = %ActiveToolLabel

var _floor_ids: Array[String] = []
var _reference_ids: Array[String] = []
var _reference_floors: Array[String] = []
var _reference_campaign: AtlasCampaign
var _automatic_reference: String = ""
var _current_tool: AtlasCanvas.Tool = AtlasCanvas.Tool.PEN


func _ready() -> void:
	floor_picker.item_selected.connect(_on_floor_selected)
	floor_name_input.text_submitted.connect(func(_text: String) -> void: floor_renamed.emit(floor_name_input.text))
	_floor_add.pressed.connect(func() -> void: floor_created.emit(floor_name_input.text))
	_floor_rename.pressed.connect(func() -> void: floor_renamed.emit(floor_name_input.text))
	_floor_up.pressed.connect(floor_moved.emit.bind(1))
	_floor_down.pressed.connect(floor_moved.emit.bind(-1))
	_floor_default.pressed.connect(floor_default_requested.emit)
	_floor_remove.pressed.connect(floor_removed.emit)
	lock_checkbox.toggled.connect(scope_toggled.emit)
	snap_checkbox.toggled.connect(grid_snapping_toggled.emit)
	_transform_button.pressed.connect(_on_transform_requested)
	brush_color_picker.color_changed.connect(brush_color_changed.emit)
	brush_width_spinner.value_changed.connect(brush_width_changed.emit)
	# SpinBox has an inner LineEdit; both it and the arrows receive wheel input separately.
	brush_width_spinner.gui_input.connect(_on_brush_width_wheel)
	brush_width_spinner.get_line_edit().gui_input.connect(_on_brush_width_wheel)
	_palette_picker.item_selected.connect(palette_selected.emit)
	preview_picker.item_selected.connect(preview_changed.emit)
	reference_checkbox.toggled.connect(reference_toggled.emit)
	opacity_slider.value_changed.connect(reference_opacity_changed.emit)
	_navigation_toggle.toggled.connect(automatic_navigation_toggled.emit)
	%ManageLinks.pressed.connect(linked_maps_requested.emit)
	%BackButton.pressed.connect(back_requested.emit)
	reference_source_picker.item_selected.connect(_on_reference_source)
	reference_floor_picker.item_selected.connect(func(index: int) -> void:
		reference_source_changed.emit(_reference_ids[reference_source_picker.selected], _reference_floors[index])
		freeze_checkbox.set_pressed_no_signal(false))
	freeze_checkbox.toggled.connect(reference_freeze_toggled.emit)


func refresh_floors(map: AtlasMapDocument, floor: AtlasFloor) -> void:
	floor_picker.clear()
	_floor_ids.clear()
	var selected: int = -1
	for index: int in range(map.floors.size()):
		var candidate: AtlasFloor = map.floors[index]
		_floor_ids.append(candidate.id)
		var caption: String = "%d · %s" % [index + 1, candidate.display_name]
		if candidate.id == map.default_floor_id:
			caption += " (default)"
		floor_picker.add_item(caption)
		floor_picker.get_popup().set_item_tooltip(index, candidate.display_name)
		if candidate.id == floor.id:
			selected = index
	floor_picker.select(selected)
	floor_name_input.text = floor.display_name
	_floor_up.disabled = selected == map.floors.size() - 1
	_floor_down.disabled = selected <= 0
	_floor_remove.disabled = map.floors.size() <= 1
	_floor_default.disabled = floor.id == map.default_floor_id


func refresh_tool(tool: AtlasCanvas.Tool, grid_available: bool) -> void:
	_current_tool = tool
	_active_tool_label.text = "Active: %s · Tools in left sidebar" % AtlasToolPalette.description_for(tool)
	lock_checkbox.disabled = not grid_available
	_ink_section.visible = tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER, AtlasCanvas.Tool.LINE,
		AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.FILL]
	var erasing: bool = tool == AtlasCanvas.Tool.ERASER
	_ink_heading.text = "ERASER" if erasing else "BRUSH & STROKE"
	_eraser_hint.visible = erasing
	_ink_color_label.visible = not erasing
	brush_color_picker.visible = not erasing
	brush_color_picker.disabled = erasing
	brush_width_spinner.editable = tool != AtlasCanvas.Tool.FILL
	_terrain_section.visible = tool in [AtlasCanvas.Tool.PAINT, AtlasCanvas.Tool.FILL]
	_selection_section.visible = tool in [AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE]
	_snap_section.visible = tool in [AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE,
		AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.ART_SELECT, AtlasCanvas.Tool.MOVE]
	snap_checkbox.disabled = not grid_available


func refresh_selection(selection: AtlasSelection, can_modify: bool) -> void:
	selection_label.text = ("Move: click an object and drag; V selects groups. Escape cancels."
		if _current_tool == AtlasCanvas.Tool.MOVE else
		"Active layer only. Drag or click; Ctrl add, Alt subtract, Ctrl+D clear. Raster selects the whole layer.")
	if not selection.is_empty():
		var count: int = selection.stroke_indices.size()
		var object_name: String = "Raster asset" if selection.raster_selected else "%d ink stroke%s" % [count, "" if count == 1 else "s"]
		selection_label.text = ("%s selected · drag to move" % object_name
			if _current_tool == AtlasCanvas.Tool.MOVE else "%s selected" % object_name)
	move_x_spinner.set_value_no_signal(0.0)
	move_y_spinner.set_value_no_signal(0.0)
	scale_spinner.set_value_no_signal(1.0)
	artwork_rotation_spinner.set_value_no_signal(0.0)
	_transform_button.disabled = not can_modify


func sync_brush(color: Color, width: float) -> void:
	var signals_blocked: bool = brush_color_picker.is_blocking_signals()
	brush_color_picker.set_block_signals(true)
	brush_color_picker.color = color
	brush_color_picker.set_block_signals(signals_blocked)
	brush_width_spinner.set_value_no_signal(width)


func _on_brush_width_wheel(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if not brush_width_spinner.editable:
		return
	var direction: float = 1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
	# Consume only wheel events over the field, so the parent ScrollContainer never scrolls here.
	brush_width_spinner.value = clampf(brush_width_spinner.value + direction * brush_width_spinner.step,
		brush_width_spinner.min_value, brush_width_spinner.max_value)
	get_viewport().set_input_as_handled()


func _on_floor_selected(index: int) -> void:
	if index >= 0 and index < _floor_ids.size():
		floor_selected.emit(_floor_ids[index])


func _on_transform_requested() -> void:
	selection_transform_requested.emit(Vector2(move_x_spinner.value, move_y_spinner.value),
		scale_spinner.value, deg_to_rad(artwork_rotation_spinner.value))


func refresh_references(campaign: AtlasCampaign, map: AtlasMapDocument, floor: AtlasFloor,
		link_id: String, floor_id: String, frozen: bool, can_back: bool) -> void:
	_reference_campaign = campaign
	var incoming: Array[AtlasMapLink] = campaign.incoming_links(map.id, floor.id)
	_automatic_reference = incoming[0].id if incoming.size() == 1 else ""
	reference_source_picker.clear()
	_reference_ids = [""]
	reference_source_picker.add_item("Automatic (one entrance only)")
	for link: AtlasMapLink in incoming:
		var source: AtlasMapDocument = campaign.get_map(link.source_map_id)
		_reference_ids.append(link.id)
		reference_source_picker.add_item((source.display_name if source != null else "Missing source") + " / " + link.source_floor_id + " · " + link.id)
	reference_source_picker.select(maxi(0, _reference_ids.find(link_id)))
	_refresh_reference_floors(floor_id)
	freeze_checkbox.set_pressed_no_signal(frozen)
	%BackButton.disabled = not can_back


func _refresh_reference_floors(preferred: String = "") -> void:
	reference_floor_picker.clear()
	_reference_floors.clear()
	var id: String = _reference_ids[reference_source_picker.selected]
	var link: AtlasMapLink = _reference_campaign.link_by_id(_automatic_reference if id.is_empty() else id)
	var source: AtlasMapDocument = _reference_campaign.get_map(link.source_map_id) if link != null else null
	if source != null:
		for floor: AtlasFloor in source.floors:
			_reference_floors.append(floor.id)
			reference_floor_picker.add_item(floor.display_name + " · " + floor.id)
		var selected: String = preferred if not preferred.is_empty() else link.source_floor_id
		reference_floor_picker.select(_reference_floors.find(selected))
	reference_floor_picker.disabled = source == null
	freeze_checkbox.disabled = source == null


func _on_reference_source(_index: int) -> void:
	_refresh_reference_floors()
	var selected: int = reference_floor_picker.selected
	reference_source_changed.emit(_reference_ids[reference_source_picker.selected],
		_reference_floors[selected] if selected >= 0 else "")
	freeze_checkbox.set_pressed_no_signal(false)
