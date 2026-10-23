class_name AtlasGridControls
extends VBoxContainer
## Shared grid/measurement form for existing boards and board creation.

signal settings_changed(grid: AtlasGrid)

const SHAPES: Array[String] = ["No grid", "Square", "Pointy hex", "Flat hex"]
const UNITS: Array[String] = ["mi", "km", "ft", "m", "tiles"]

var shape_picker: OptionButton
var size_spinner: SpinBox
var rotation_spinner: SpinBox
var origin_x_spinner: SpinBox
var origin_y_spinner: SpinBox
var distance_spinner: SpinBox
var unit_picker: OptionButton
var visibility_checkbox: CheckBox
var _size_label: Label
var _grid: AtlasGrid = AtlasGrid.new()


func _ready() -> void:
    add_theme_constant_override("separation", 8)
    add_child(_label("Grid shape"))
    shape_picker = OptionButton.new()
    for caption: String in SHAPES:
        shape_picker.add_item(caption)
    shape_picker.item_selected.connect(_on_shape_changed)
    add_child(shape_picker)
    visibility_checkbox = CheckBox.new()
    visibility_checkbox.text = "Show grid overlay"
    visibility_checkbox.tooltip_text = "Very dense grids hide while zoomed out; zoom in to see their lines."
    visibility_checkbox.toggled.connect(_on_visibility_changed)
    add_child(visibility_checkbox)
    _size_label = _label("Cell size (board units)")
    add_child(_size_label)
    size_spinner = _number(0.001, 4096.0, 0.001)
    size_spinner.value_changed.connect(_on_size_changed)
    add_child(size_spinner)
    add_child(_label("Origin (board units)"))
    var origin_row: HBoxContainer = HBoxContainer.new()
    add_child(origin_row)
    origin_x_spinner = _number(-1000000.0, 1000000.0, 0.001)
    origin_y_spinner = _number(-1000000.0, 1000000.0, 0.001)
    origin_x_spinner.allow_lesser = true
    origin_y_spinner.allow_lesser = true
    origin_x_spinner.tooltip_text = "Origin X"
    origin_y_spinner.tooltip_text = "Origin Y"
    origin_x_spinner.value_changed.connect(_on_origin_changed.bind(0))
    origin_y_spinner.value_changed.connect(_on_origin_changed.bind(1))
    origin_row.add_child(origin_x_spinner)
    origin_row.add_child(origin_y_spinner)
    add_child(_label("Rotation (degrees)"))
    rotation_spinner = _number(-3600.0, 3600.0, 0.1)
    rotation_spinner.allow_lesser = true
    rotation_spinner.value_changed.connect(_on_rotation_changed)
    add_child(rotation_spinner)
    add_child(_label("Native distance per cell / unit"))
    var native_row: HBoxContainer = HBoxContainer.new()
    add_child(native_row)
    distance_spinner = _number(0.001, 1000000.0, 0.001)
    distance_spinner.value_changed.connect(_on_distance_changed)
    native_row.add_child(distance_spinner)
    unit_picker = OptionButton.new()
    unit_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    unit_picker.item_selected.connect(_on_unit_changed)
    native_row.add_child(unit_picker)
    var hint: Label = _label("Overlay settings never resize artwork or convert another board’s units.")
    hint.theme_type_variation = &"MutedLabel"
    add_child(hint)
    _sync_controls()


func set_grid(grid: AtlasGrid) -> void:
    _grid = grid.copy()
    if is_node_ready():
        _sync_controls()


func get_grid() -> AtlasGrid:
    return _grid.copy()


func _sync_controls() -> void:
    shape_picker.select(_grid.kind)
    visibility_checkbox.set_pressed_no_signal(_grid.visible)
    size_spinner.set_value_no_signal(_grid.cell_size)
    rotation_spinner.set_value_no_signal(rad_to_deg(_grid.rotation))
    origin_x_spinner.set_value_no_signal(_grid.origin.x)
    origin_y_spinner.set_value_no_signal(_grid.origin.y)
    distance_spinner.set_value_no_signal(_grid.distance_per_cell)
    unit_picker.clear()
    for unit: String in UNITS:
        unit_picker.add_item(unit)
    var index: int = UNITS.find(_grid.distance_unit)
    if index < 0:
        index = unit_picker.item_count
        unit_picker.add_item(_grid.distance_unit)
    unit_picker.select(index)
    var gridded: bool = _grid.kind != AtlasGrid.Kind.GRIDLESS
    for spinner: SpinBox in [size_spinner, rotation_spinner, origin_x_spinner, origin_y_spinner, distance_spinner]:
        spinner.editable = gridded
    visibility_checkbox.disabled = not gridded
    _size_label.text = "Cell size (board units)"
    if _grid.kind in [AtlasGrid.Kind.HEX_POINTY, AtlasGrid.Kind.HEX_FLAT]:
        _size_label.text = "Hex radius (board units)"


func _publish(candidate: AtlasGrid) -> void:
    if not candidate.is_valid() or candidate.same_as(_grid):
        _sync_controls()
        return
    _grid = candidate.copy()
    _sync_controls()
    settings_changed.emit(_grid.copy())


func _on_shape_changed(index: int) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.kind = index as AtlasGrid.Kind
    _publish(candidate)


func _on_visibility_changed(visible: bool) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.visible = visible
    _publish(candidate)


func _on_size_changed(value: float) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.cell_size = value
    _publish(candidate)


func _on_origin_changed(value: float, axis: int) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.origin[axis] = value
    _publish(candidate)


func _on_rotation_changed(value: float) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.rotation = deg_to_rad(value)
    _publish(candidate)


func _on_distance_changed(value: float) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.distance_per_cell = value
    _publish(candidate)


func _on_unit_changed(index: int) -> void:
    var candidate: AtlasGrid = _grid.copy()
    candidate.distance_unit = unit_picker.get_item_text(index)
    _publish(candidate)


func _number(minimum: float, maximum: float, step: float) -> SpinBox:
    var spinner: SpinBox = SpinBox.new()
    spinner.min_value = minimum
    spinner.max_value = maximum
    spinner.step = step
    spinner.allow_greater = true
    spinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return spinner


func _label(text: String) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label
