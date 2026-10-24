class_name AtlasInspector
extends PanelContainer
## Keep form state local so editor commands remain the only document-edit boundary.

signal tool_selected(index: int)
signal floor_selected(id: String)
signal floor_created(name: String)
signal floor_renamed(name: String)
signal floor_moved(direction: int)
signal floor_default_requested()
signal floor_removed()
signal grid_changed(grid: AtlasGrid)
signal scope_toggled(enabled: bool)
signal selection_transform_requested(offset: Vector2, factor: float, radians: float)
signal brush_color_changed(color: Color)
signal brush_width_changed(value: float)
signal palette_selected(index: int)
signal placement_rotation_changed(radians: float)
signal preview_changed(index: int)
signal reference_toggled(enabled: bool)
signal reference_opacity_changed(value: float)
signal automatic_navigation_toggled(enabled: bool)

@onready var tool_picker: OptionButton = %ToolPicker
@onready var preview_picker: OptionButton = %PreviewPicker
@onready var angle_spinner: SpinBox = %AngleSpinner
@onready var lock_checkbox: CheckBox = %LockCheckbox
@onready var reference_checkbox: CheckBox = %ReferenceCheckbox
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var grid_controls: AtlasGridControls = %GridControls
@onready var brush_color_picker: ColorPickerButton = %BrushColorPicker
@onready var brush_width_spinner: SpinBox = %BrushWidthSpinner
@onready var selection_label: Label = %SelectionLabel
@onready var move_x_spinner: SpinBox = %MoveXSpinner
@onready var move_y_spinner: SpinBox = %MoveYSpinner
@onready var scale_spinner: SpinBox = %ScaleSpinner
@onready var artwork_rotation_spinner: SpinBox = %ArtworkRotationSpinner
@onready var floor_picker: OptionButton = %FloorPicker
@onready var floor_name_input: LineEdit = %FloorNameInput

@onready var _ink_section: VBoxContainer = %InkSection
@onready var _terrain_section: VBoxContainer = %TerrainSection
@onready var _placement_section: VBoxContainer = %PlacementSection
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

var _floor_ids: Array[String] = []


func _ready() -> void:
    tool_picker.item_selected.connect(tool_selected.emit)
    floor_picker.item_selected.connect(_on_floor_selected)
    floor_name_input.text_submitted.connect(func(_text: String) -> void: floor_renamed.emit(floor_name_input.text))
    _floor_add.pressed.connect(func() -> void: floor_created.emit(floor_name_input.text))
    _floor_rename.pressed.connect(func() -> void: floor_renamed.emit(floor_name_input.text))
    _floor_up.pressed.connect(floor_moved.emit.bind(1))
    _floor_down.pressed.connect(floor_moved.emit.bind(-1))
    _floor_default.pressed.connect(floor_default_requested.emit)
    _floor_remove.pressed.connect(floor_removed.emit)
    grid_controls.settings_changed.connect(grid_changed.emit)
    lock_checkbox.toggled.connect(scope_toggled.emit)
    _transform_button.pressed.connect(_on_transform_requested)
    brush_color_picker.color_changed.connect(brush_color_changed.emit)
    brush_width_spinner.value_changed.connect(brush_width_changed.emit)
    _palette_picker.item_selected.connect(palette_selected.emit)
    angle_spinner.value_changed.connect(_on_placement_rotation_changed)
    preview_picker.item_selected.connect(preview_changed.emit)
    reference_checkbox.toggled.connect(reference_toggled.emit)
    opacity_slider.value_changed.connect(reference_opacity_changed.emit)
    _navigation_toggle.toggled.connect(automatic_navigation_toggled.emit)


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
    lock_checkbox.disabled = not grid_available
    _ink_section.visible = tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER, AtlasCanvas.Tool.LINE,
        AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.FILL]
    brush_color_picker.disabled = tool == AtlasCanvas.Tool.ERASER
    brush_width_spinner.editable = tool != AtlasCanvas.Tool.FILL
    _terrain_section.visible = tool in [AtlasCanvas.Tool.PAINT, AtlasCanvas.Tool.FILL]
    _placement_section.visible = tool == AtlasCanvas.Tool.BATTLEMAP
    _selection_section.visible = tool == AtlasCanvas.Tool.ART_SELECT


func refresh_selection(selection: AtlasSelection, can_modify: bool) -> void:
    selection_label.text = "Drag a marquee or click ink / a raster asset."
    if not selection.is_empty():
        selection_label.text = "Raster asset selected" if selection.raster_selected else "%d strokes selected" % selection.stroke_indices.size()
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


func _on_floor_selected(index: int) -> void:
    if index >= 0 and index < _floor_ids.size():
        floor_selected.emit(_floor_ids[index])


func _on_transform_requested() -> void:
    selection_transform_requested.emit(Vector2(move_x_spinner.value, move_y_spinner.value),
        scale_spinner.value, deg_to_rad(artwork_rotation_spinner.value))


func _on_placement_rotation_changed(value: float) -> void:
    placement_rotation_changed.emit(deg_to_rad(value))
