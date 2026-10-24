class_name AtlasLayerPanel
extends VBoxContainer

signal layer_selected(id: String)
signal layers_changed(layers: Array[AtlasLayer], selected_id: String)
signal import_requested

var layer_list: ItemList
var visibility_checkbox: CheckBox
var lock_checkbox: CheckBox
var opacity_spinner: SpinBox
var name_input: LineEdit
var _floor: AtlasFloor
var _selected: String = ""
var _ids: Array[String] = []
var _up: Button
var _down: Button


func _ready() -> void:
    add_theme_constant_override("separation", 8)
    layer_list = ItemList.new()
    layer_list.custom_minimum_size = Vector2(0, 120)
    layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layer_list.item_selected.connect(_on_selected)
    add_child(layer_list)
    name_input = LineEdit.new()
    name_input.placeholder_text = "Layer name"
    name_input.text_submitted.connect(_rename)
    name_input.focus_exited.connect(func() -> void: _rename(name_input.text))
    add_child(name_input)
    visibility_checkbox = CheckBox.new()
    visibility_checkbox.text = "Visible"
    visibility_checkbox.toggled.connect(_set_property.bind(&"visible"))
    add_child(visibility_checkbox)
    lock_checkbox = CheckBox.new()
    lock_checkbox.text = "Locked"
    lock_checkbox.toggled.connect(_set_property.bind(&"locked"))
    add_child(lock_checkbox)
    var label: Label = Label.new()
    label.text = "Opacity"
    add_child(label)
    opacity_spinner = SpinBox.new()
    opacity_spinner.min_value = 0.0
    opacity_spinner.max_value = 1.0
    opacity_spinner.step = 0.05
    opacity_spinner.value_changed.connect(_set_property.bind(&"opacity"))
    add_child(opacity_spinner)
    var order: HBoxContainer = HBoxContainer.new()
    add_child(order)
    _up = _button("Raise", _move.bind(1))
    _down = _button("Lower", _move.bind(-1))
    order.add_child(_up)
    order.add_child(_down)
    add_child(_button("New ink layer", _add_ink))
    add_child(_button("New terrain layer", _add_tiles))
    add_child(_button("New raster layer", _add_raster))
    add_child(_button("Import image…", import_requested.emit))


func set_floor(floor: AtlasFloor, selected_id: String) -> void:
    _floor = floor
    _selected = selected_id
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
        layer_list.add_item(layer.display_name + " · " + layer.kind + flags)
        if layer.id == _selected:
            layer_list.select(layer_list.item_count - 1)
    var current: AtlasLayer = floor.layer_by_id(_selected)
    name_input.editable = current != null
    visibility_checkbox.disabled = current == null
    lock_checkbox.disabled = current == null
    opacity_spinner.editable = current != null
    if current != null:
        name_input.text = current.display_name
        visibility_checkbox.set_pressed_no_signal(current.visible)
        lock_checkbox.set_pressed_no_signal(current.locked)
        opacity_spinner.set_value_no_signal(current.opacity)
    else:
        name_input.text = ""
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
    layers.append(layer)
    layers_changed.emit(layers, layer.id)


func _button(text: String, callback: Callable) -> Button:
    var button: Button = Button.new()
    button.text = text
    button.pressed.connect(callback)
    return button
