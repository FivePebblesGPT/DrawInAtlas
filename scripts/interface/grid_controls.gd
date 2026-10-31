class_name AtlasGridControls
extends VBoxContainer
## Shared grid/measurement form for existing boards and board creation.

signal settings_changed(grid: AtlasGrid)

const SHAPES: Array[String] = ["No grid", "Square", "Pointy hex", "Flat hex"]
const UNITS: Array[String] = ["mi", "km", "ft", "m", "tiles"]

@onready var shape_picker: OptionButton = $ShapePicker
@onready var size_spinner: SpinBox = $CellSizeSpinner
@onready var rotation_spinner: SpinBox = $RotationSpinner
@onready var origin_x_spinner: SpinBox = $OriginRow/OriginXSpinner
@onready var origin_y_spinner: SpinBox = $OriginRow/OriginYSpinner
@onready var distance_spinner: SpinBox = $DistanceRow/DistanceSpinner
@onready var unit_picker: OptionButton = $DistanceRow/UnitPicker
@onready var visibility_checkbox: CheckBox = $VisibilityCheckbox
@onready var _size_label: Label = $CellSizeLabel
var _grid: AtlasGrid = AtlasGrid.new()


func _ready() -> void:
	for caption: String in SHAPES:
		shape_picker.add_item(caption)

	shape_picker.item_selected.connect(_on_shape_changed)
	visibility_checkbox.toggled.connect(_on_visibility_changed)
	size_spinner.value_changed.connect(_on_size_changed)
	origin_x_spinner.value_changed.connect(_on_origin_changed.bind(0))
	origin_y_spinner.value_changed.connect(_on_origin_changed.bind(1))
	rotation_spinner.value_changed.connect(_on_rotation_changed)
	distance_spinner.value_changed.connect(_on_distance_changed)
	unit_picker.item_selected.connect(_on_unit_changed)
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
