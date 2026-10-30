class_name AtlasLayerPanel
extends VBoxContainer

signal layer_selected(id: String)
signal layers_changed(layers: Array[AtlasLayer], selected_id: String)
signal import_requested
signal presented_detail_selected(level: int)

@onready var layer_list: ItemList = $LayerList
@onready var visibility_checkbox: CheckBox = $VisibilityCheckbox
@onready var lock_checkbox: CheckBox = $LockCheckbox
@onready var opacity_spinner: SpinBox = $OpacitySpinner
@onready var name_input: LineEdit = $NameInput
@onready var layer_detail_spinner: SpinBox = $LayerDetailSpinner
@onready var view_detail_spinner: SpinBox = $ViewDetailSpinner
@onready var _up: Button = $Order/RaiseButton
@onready var _down: Button = $Order/LowerButton
var _floor: AtlasFloor
var _selected: String = ""
var _ids: Array[String] = []


func _ready() -> void:
	layer_list.item_selected.connect(_on_selected)
	name_input.text_submitted.connect(_rename)
	name_input.focus_exited.connect(func() -> void: _rename(name_input.text))
	visibility_checkbox.toggled.connect(_set_property.bind(&"visible"))
	lock_checkbox.toggled.connect(_set_property.bind(&"locked"))
	opacity_spinner.value_changed.connect(_set_property.bind(&"opacity"))
	layer_detail_spinner.value_changed.connect(func(value: float) -> void:
		_set_property(int(value), &"detail_level"))
	view_detail_spinner.value_changed.connect(func(value: float) -> void:
		presented_detail_selected.emit(int(value)))
	_up.pressed.connect(_move.bind(1))
	_down.pressed.connect(_move.bind(-1))
	$NewInkButton.pressed.connect(_add_ink)
	$NewTerrainButton.pressed.connect(_add_tiles)
	$NewRasterButton.pressed.connect(_add_raster)
	$ImportButton.pressed.connect(import_requested.emit)


func set_floor(floor: AtlasFloor, selected_id: String, view_level: int = 0) -> void:
	_floor = floor
	_selected = selected_id
	view_detail_spinner.set_value_no_signal(view_level)
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
