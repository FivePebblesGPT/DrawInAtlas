class_name AtlasEditor
extends Control

## Vertical-slice editor shell. Entire domain and UI are pure GDScript.
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 3.0
const ZOOM_FACTOR: float = 1.2

var campaign: AtlasCampaign
var canvas: AtlasCanvas
var zoom_gate := AtlasZoomGate.new()
var history: Array[Dictionary] = []
var locked_to_cell: bool = false
var palette_id: int = 2
var automatic_navigation: bool = false
var edits: AtlasEditHistory = AtlasEditHistory.new()
var view_session: AtlasViewSession = AtlasViewSession.new()
var store_io: AtlasStoreIO

@export var sidebar: Sidebar
@export var load_saved_on_startup: bool = true
@export var save_path: String = AtlasCampaignStore.DEFAULT_PATH
@export var title_label: Label

var map_list: ItemList
var map_list_ids: Array[String] = []
var tool_picker: OptionButton
var preview_picker: OptionButton
var angle_spinner: SpinBox
var lock_checkbox: CheckBox
var reference_checkbox: CheckBox
var opacity_slider: HSlider
var status_label: Label
var search_list: ItemList
var search_map_ids: Array[String] = []
var distance_spinner: SpinBox
var unit_picker: OptionButton
var grid_controls: AtlasGridControls
var board_dialog: AtlasBoardDialog
var layer_panel: AtlasLayerPanel
var raster_importer: AtlasRasterImporter
var use_system_clipboard: bool = true
var clipboard_text: String = ""
var _paste_count: int = 0
var brush_color_picker: ColorPickerButton
var brush_width_spinner: SpinBox
var _ink_section: VBoxContainer
var _terrain_section: VBoxContainer
var _placement_section: VBoxContainer
var _selection_section: VBoxContainer
var selection_label: Label
var move_x_spinner: SpinBox
var move_y_spinner: SpinBox
var scale_spinner: SpinBox
var artwork_rotation_spinner: SpinBox
var _transform_button: Button
var floor_picker: OptionButton
var floor_name_input: LineEdit
var _floor_ids: Array[String] = []
var _floor_up: Button
var _floor_down: Button
var _floor_remove: Button
var _floor_default: Button
var map_name_input: LineEdit
var map_tags_input: LineEdit
var map_preview: AtlasPreviewPanel
var overview_panel: AtlasOverviewPanel
var _search_entries: Array[AtlasOverviewEntry] = []

const NATIVE_UNITS: Array[String] = ["mi", "km", "ft", "m", "tiles"]


func _ready() -> void:
    _build_ui()
    var restored: AtlasStoreResult
    if load_saved_on_startup:
        restored = AtlasCampaignStore.load_result(save_path, store_io)
        campaign = restored.campaign
    var loaded: bool = campaign != null
    if campaign == null:
        campaign = AtlasCampaign.sample()
    edits.changed.connect(_refresh_edit_state)
    edits.changed.connect(_on_documents_changed)
    edits.reset(campaign, loaded and (restored == null or not restored.recovered))
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("B pen · E eraser · V select · F fill · L/R/O outlines · Ctrl+Z undo · Middle-drag pan")
    if restored != null and restored.recovered:
        _message(restored.message + " Save to establish a fresh checkpoint.")
    elif restored != null and restored.error != OK and restored.error != ERR_FILE_NOT_FOUND:
        _message(restored.message + " A temporary sample is open; the save was not replaced.")


func _build_ui() -> void:
    var shell: VBoxContainer = VBoxContainer.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(shell)

    var content: HBoxContainer = HBoxContainer.new()
    content.name = "CanvasAndInspector"
    content.add_theme_constant_override("separation", 1)
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    shell.add_child(content)

    _build_sidebar_views()
    _build_canvas(content)
    _build_inspector(content)
    _build_status_label(shell)
    board_dialog = AtlasBoardDialog.new()
    board_dialog.theme = sidebar.theme
    board_dialog.board_requested.connect(_on_board_requested)
    add_child(board_dialog)
    raster_importer = AtlasRasterImporter.new()
    raster_importer.image_ready.connect(import_raster)
    raster_importer.failed.connect(_message)
    add_child(raster_importer)
    _on_tool_changed(tool_picker.selected)


func _build_sidebar_views() -> void:
    var maps_view: Control = sidebar.get_view_content(&"Maps")
    maps_view.get_node("Heading").text = "Campaign maps"
    maps_view.get_node("Description").text = "Double-click a map to open it."
    map_list = ItemList.new()
    map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_list.item_activated.connect(_on_map_activated)
    map_list.item_selected.connect(_preview_map_index)
    maps_view.add_child(map_list)
    map_name_input = LineEdit.new()
    map_name_input.placeholder_text = "Current board name"
    map_name_input.text_submitted.connect(func(_text: String) -> void: _apply_map_metadata())
    maps_view.add_child(map_name_input)
    map_tags_input = LineEdit.new()
    map_tags_input.placeholder_text = "Tags, comma separated"
    map_tags_input.text_submitted.connect(func(_text: String) -> void: _apply_map_metadata())
    maps_view.add_child(map_tags_input)
    maps_view.add_child(_action_button("Apply name / tags", _apply_map_metadata))
    map_preview = AtlasPreviewPanel.new()
    maps_view.add_child(map_preview)

    var search_view: Control = sidebar.get_view_content(&"Search")
    search_view.get_node("Description").text = "Name, floor, kind or #tag. Double-click to open."
    overview_panel = AtlasOverviewPanel.new()
    overview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    overview_panel.query_changed.connect(func() -> void: _refresh_search_list(sidebar.get_search_query()))
    overview_panel.entry_activated.connect(_open_overview_entry)
    overview_panel.source_focus_requested.connect(_focus_overview_source)
    search_view.add_child(overview_panel)
    search_list = overview_panel.result_list
    sidebar.search_changed.connect(_refresh_search_list)
    sidebar.view_selected.connect(_on_sidebar_view_selected)

    var layers_view: Control = sidebar.get_view_content(&"Layers")
    layers_view.get_node("Heading").hide()
    layers_view.get_node("Description").hide()
    layer_panel = AtlasLayerPanel.new()
    layer_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layer_panel.layer_selected.connect(select_layer)
    layer_panel.layers_changed.connect(apply_layers)
    layer_panel.import_requested.connect(func() -> void: raster_importer.request_import())
    layers_view.add_child(layer_panel)


func _build_canvas(parent: HBoxContainer) -> void:
    canvas = AtlasCanvas.new()
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.custom_minimum_size = Vector2(160, 160)
    canvas.paint_requested.connect(_on_paint)
    canvas.selection_requested.connect(_on_select)
    canvas.battlemap_requested.connect(_on_create_battlemap)
    canvas.wheel_step.connect(_on_wheel_step)
    canvas.enter_requested.connect(_enter_link)
    canvas.pointer_moved.connect(_on_pointer_moved)
    canvas.interaction_started.connect(zoom_gate.reset)
    canvas.mouse_exited.connect(zoom_gate.reset)
    canvas.stroke_requested.connect(_on_stroke)
    canvas.selection_changed.connect(_on_selection_changed)
    canvas.transform_requested.connect(transform_selection)
    canvas.fill_requested.connect(fill_at)
    canvas.interaction_started.connect(_refresh_scope)
    parent.add_child(canvas)


func _build_inspector(parent: HBoxContainer) -> void:
    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size = Vector2(252, 0)
    parent.add_child(panel)
    var inspector: ScrollContainer = ScrollContainer.new()
    inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    inspector.follow_focus = true
    panel.add_child(inspector)
    var margin: MarginContainer = MarginContainer.new()
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for edge: String in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 14)
    inspector.add_child(margin)
    var sections: VBoxContainer = VBoxContainer.new()
    sections.custom_minimum_size = Vector2(204, 0)
    sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sections.add_theme_constant_override("separation", 20)
    margin.add_child(sections)

    _build_floor_controls(sections)
    _build_tool_controls(sections)
    _build_ink_controls(sections)
    _build_selection_controls(sections)
    _build_terrain_controls(sections)
    _build_map_controls(sections)
    _build_placement_controls(sections)
    _build_reference_controls(sections)


func _build_tool_controls(parent: VBoxContainer) -> void:
    var tools: VBoxContainer = _create_section(parent, "TOOLS")
    tool_picker = OptionButton.new()
    for caption: String in ["Pen", "Eraser", "Paint cells", "Select scope cell", "Drag battlemap",
            "Line", "Rectangle outline", "Ellipse outline", "Select artwork", "Fill raster / terrain"]:
        tool_picker.add_item(caption)
    tool_picker.item_selected.connect(_on_tool_changed)
    tools.add_child(tool_picker)


func _build_floor_controls(parent: VBoxContainer) -> void:
    var section: VBoxContainer = _create_section(parent, "FLOORS")
    floor_picker = OptionButton.new()
    floor_picker.clip_text = true
    floor_picker.item_selected.connect(_on_floor_selected)
    section.add_child(floor_picker)
    floor_name_input = LineEdit.new()
    floor_name_input.placeholder_text = "Floor name"
    floor_name_input.text_submitted.connect(func(_text: String) -> void: rename_floor(floor_name_input.text))
    section.add_child(floor_name_input)
    var names: HBoxContainer = HBoxContainer.new()
    names.add_child(_action_button("Add", func() -> void: create_floor(floor_name_input.text)))
    names.add_child(_action_button("Rename", func() -> void: rename_floor(floor_name_input.text)))
    section.add_child(names)
    var order: HBoxContainer = HBoxContainer.new()
    _floor_up = _action_button("Raise", move_floor.bind(1))
    _floor_down = _action_button("Lower", move_floor.bind(-1))
    order.add_child(_floor_up)
    order.add_child(_floor_down)
    section.add_child(order)
    _floor_default = _action_button("Make default", make_floor_default)
    _floor_remove = _action_button("Delete floor", remove_floor)
    section.add_child(_floor_default)
    section.add_child(_floor_remove)


func _action_button(text: String, callback: Callable) -> Button:
    var button: Button = Button.new()
    button.text = text
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.pressed.connect(callback)
    return button


func _refresh_floor_controls() -> void:
    floor_picker.clear()
    _floor_ids.clear()
    var selected: int = -1
    for index: int in range(canvas.map.floors.size()):
        var floor: AtlasFloor = canvas.map.floors[index]
        _floor_ids.append(floor.id)
        var caption: String = "%d · %s" % [index + 1, floor.display_name]
        if floor.id == canvas.map.default_floor_id:
            caption += " (default)"
        floor_picker.add_item(caption)
        floor_picker.get_popup().set_item_tooltip(index, floor.display_name)
        if floor.id == canvas.floor.id:
            selected = index
    floor_picker.select(selected)
    floor_name_input.text = canvas.floor.display_name
    _floor_up.disabled = selected == canvas.map.floors.size() - 1
    _floor_down.disabled = selected <= 0
    _floor_remove.disabled = canvas.map.floors.size() <= 1
    _floor_default.disabled = canvas.floor.id == canvas.map.default_floor_id


func _on_floor_selected(index: int) -> void:
    if index >= 0 and index < _floor_ids.size():
        switch_floor(_floor_ids[index])


func _capture_view() -> AtlasViewState:
    if canvas.map == null or canvas.floor == null:
        return null
    return AtlasViewState.new(canvas.map.id, canvas.floor.id, canvas.camera_center, canvas.camera_zoom, canvas.active_layer_id)


func _remember_view() -> void:
    var state: AtlasViewState = _capture_view()
    if state != null:
        view_session.remember(state)


func switch_floor(id: String) -> bool:
    if canvas.map.floor_by_id(id) == null:
        _message("Floor not found; the current view was kept.")
        return false
    _remember_view()
    var state: AtlasViewState = view_session.resolve(campaign, canvas.map.id, id, canvas.camera_center, canvas.camera_zoom)
    if state == null:
        return false
    return _show_map(canvas.map, state.focus, state.zoom, state.floor_id, state.layer_id)


func open_map(id: String, floor_id: String = "") -> bool:
    _remember_view()
    var state: AtlasViewState = view_session.resolve(campaign, id, floor_id)
    if state == null:
        _message("Map or floor unavailable; the current view and history were kept.")
        return false
    if canvas.map.id != state.map_id or canvas.floor.id != state.floor_id:
        _push_history()
    return _show_map(campaign.get_map(id), state.focus, state.zoom, state.floor_id, state.layer_id)


func _clone_floors() -> Array[AtlasFloor]:
    var result: Array[AtlasFloor] = []
    for floor: AtlasFloor in canvas.map.floors:
        var copy: AtlasFloor = AtlasFloor.new()
        copy.id = floor.id
        copy.display_name = floor.display_name
        copy.layers = AtlasLayerCodec.clone_all(floor.layers)
        result.append(copy)
    return result


func _apply_floors(after: Array[AtlasFloor], default_id: String) -> bool:
    canvas.cancel_edit()
    var command: AtlasFloorEdit = AtlasFloorEdit.new(canvas.map.id, canvas.map.floors, after,
        canvas.map.default_floor_id, default_id)
    if not edits.execute(command):
        _message("Floor edit rejected: invalid/stale data or protected/referenced floor.")
        return false
    _refresh_after_history()
    return true


func create_floor(name: String) -> bool:
    if name.strip_edges().is_empty():
        _message("Choose a floor name.")
        return false
    var floor: AtlasFloor = AtlasFloor.new()
    floor.id = "floor-" + Crypto.new().generate_random_bytes(16).hex_encode()
    floor.display_name = name.strip_edges()
    floor.terrain_layer().grid = canvas.map.grid.copy()
    var after: Array[AtlasFloor] = _clone_floors()
    after.append(floor)
    if not _apply_floors(after, canvas.map.default_floor_id):
        return false
    return switch_floor(floor.id)


func rename_floor(name: String) -> bool:
    if name.strip_edges().is_empty():
        _message("Choose a floor name.")
        return false
    var after: Array[AtlasFloor] = _clone_floors()
    after[canvas.map.floors.find(canvas.floor)].display_name = name.strip_edges()
    return _apply_floors(after, canvas.map.default_floor_id)


func move_floor(direction: int) -> bool:
    var index: int = canvas.map.floors.find(canvas.floor)
    var target: int = index + direction
    if target < 0 or target >= canvas.map.floors.size():
        return false
    var after: Array[AtlasFloor] = _clone_floors()
    var floor: AtlasFloor = after[index]
    after.remove_at(index)
    after.insert(target, floor)
    return _apply_floors(after, canvas.map.default_floor_id)


func make_floor_default() -> bool:
    return _apply_floors(_clone_floors(), canvas.floor.id)


func remove_floor() -> bool:
    if canvas.map.floors.size() <= 1:
        return false
    var after: Array[AtlasFloor] = _clone_floors()
    after.remove_at(canvas.map.floors.find(canvas.floor))
    var default_id: String = canvas.map.default_floor_id
    if default_id == canvas.floor.id:
        default_id = after[0].id
    return _apply_floors(after, default_id)


func _build_ink_controls(parent: VBoxContainer) -> void:
    _ink_section = _create_section(parent, "INK")
    _ink_section.add_child(_create_label("Color"))
    brush_color_picker = ColorPickerButton.new()
    brush_color_picker.custom_minimum_size = Vector2(0, 32)
    brush_color_picker.color = canvas.brush_color
    brush_color_picker.edit_alpha = false
    brush_color_picker.color_changed.connect(func(color: Color) -> void: canvas.brush_color = color)
    _ink_section.add_child(brush_color_picker)
    _ink_section.add_child(_create_label("Width (board units)"))
    brush_width_spinner = SpinBox.new()
    brush_width_spinner.min_value = 0.5
    brush_width_spinner.max_value = 256.0
    brush_width_spinner.step = 0.5
    brush_width_spinner.value = canvas.brush_width
    brush_width_spinner.value_changed.connect(func(value: float) -> void: canvas.brush_width = value)
    _ink_section.add_child(brush_width_spinner)


func _build_terrain_controls(parent: VBoxContainer) -> void:
    _terrain_section = _create_section(parent, "TERRAIN")
    _terrain_section.add_child(_create_label("Palette"))
    var palette_picker: OptionButton = OptionButton.new()
    for caption: String in ["Erase", "Grass", "Forest", "Road", "Water", "Stone"]:
        palette_picker.add_item(caption)
    palette_picker.select(2)
    palette_picker.item_selected.connect(func(index: int) -> void: palette_id = index)
    _terrain_section.add_child(palette_picker)



func _build_selection_controls(parent: VBoxContainer) -> void:
    _selection_section = _create_section(parent, "SELECTION")
    selection_label = _create_label("Select artwork with V; drag the corner to scale uniformly.")
    _selection_section.add_child(selection_label)
    _selection_section.add_child(_create_label("Move X / Y (board units)"))
    var row: HBoxContainer = HBoxContainer.new()
    _selection_section.add_child(row)
    move_x_spinner = _transform_number(-1000000.0, 1000000.0, 0.5, 0.0)
    move_y_spinner = _transform_number(-1000000.0, 1000000.0, 0.5, 0.0)
    row.add_child(move_x_spinner)
    row.add_child(move_y_spinner)
    _selection_section.add_child(_create_label("Scale / rotate about center"))
    scale_spinner = _transform_number(0.01, 100.0, 0.01, 1.0)
    artwork_rotation_spinner = _transform_number(-180.0, 180.0, 1.0, 0.0)
    _selection_section.add_child(scale_spinner)
    _selection_section.add_child(artwork_rotation_spinner)
    _transform_button = Button.new()
    _transform_button.text = "Apply transform"
    _transform_button.pressed.connect(_apply_numeric_transform)
    _selection_section.add_child(_transform_button)


func _transform_number(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
    var field: SpinBox = SpinBox.new()
    field.min_value = minimum
    field.max_value = maximum
    field.step = step
    field.value = value
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return field


func _build_map_controls(parent: VBoxContainer) -> void:
    var map_section: VBoxContainer = _create_section(parent, "MAP")
    lock_checkbox = CheckBox.new()
    lock_checkbox.text = "Lock to selected cell"
    lock_checkbox.tooltip_text = "Use Select scope cell first. A locked scope with no cell blocks artwork edits."
    lock_checkbox.disabled = true
    lock_checkbox.toggled.connect(_on_scope_toggled)
    map_section.add_child(lock_checkbox)
    grid_controls = AtlasGridControls.new()
    grid_controls.settings_changed.connect(apply_grid)
    map_section.add_child(grid_controls)
    distance_spinner = grid_controls.distance_spinner
    unit_picker = grid_controls.unit_picker


func _build_placement_controls(parent: VBoxContainer) -> void:
    _placement_section = _create_section(parent, "PLACEMENT")
    _placement_section.add_child(_create_label("Rotation (degrees)"))
    angle_spinner = SpinBox.new()
    angle_spinner.min_value = -180.0
    angle_spinner.max_value = 180.0
    angle_spinner.step = 5.0
    angle_spinner.value_changed.connect(func(value: float) -> void:
        canvas.battle_rotation = deg_to_rad(value)
    )
    _placement_section.add_child(angle_spinner)


func _build_reference_controls(parent: VBoxContainer) -> void:
    var reference_section: VBoxContainer = _create_section(parent, "LINKS & REFERENCES")
    reference_section.add_child(_create_label("Child map previews"))
    preview_picker = OptionButton.new()
    for caption: String in ["Off", "Markers", "Thumbnails"]:
        preview_picker.add_item(caption)
    preview_picker.select(2)
    preview_picker.item_selected.connect(func(index: int) -> void:
        canvas.preview = index as AtlasCanvas.Preview
        canvas.queue_redraw()
    )
    reference_section.add_child(preview_picker)

    reference_checkbox = CheckBox.new()
    reference_checkbox.text = "Read-only parent reference"
    reference_checkbox.button_pressed = true
    reference_checkbox.toggled.connect(func(on: bool) -> void:
        canvas.show_reference = on
        canvas.queue_redraw()
    )
    reference_section.add_child(reference_checkbox)
    reference_section.add_child(_create_label("Parent reference opacity"))
    opacity_slider = HSlider.new()
    opacity_slider.min_value = 0.0
    opacity_slider.max_value = 1.0
    opacity_slider.step = 0.05
    opacity_slider.value = 0.35
    opacity_slider.value_changed.connect(func(value: float) -> void:
        canvas.reference_opacity = value
        canvas.queue_redraw()
    )
    reference_section.add_child(opacity_slider)
    var navigation_toggle: CheckBox = CheckBox.new()
    navigation_toggle.text = "Automatic linked-map zoom"
    navigation_toggle.button_pressed = false
    navigation_toggle.toggled.connect(func(enabled: bool) -> void:
        automatic_navigation = enabled
        zoom_gate.reset()
    )
    reference_section.add_child(navigation_toggle)


func _build_status_label(parent: VBoxContainer) -> void:
    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.theme_type_variation = &"MutedLabel"
    status_label.add_theme_font_size_override("font_size", 12)
    parent.add_child(status_label)


func _on_distance_changed(value: float) -> void:
    if canvas.map != null and is_finite(value) and value > 0.0:
        var candidate: AtlasGrid = canvas.map.grid.copy()
        candidate.distance_per_cell = value
        apply_grid(candidate)


func _on_unit_changed(index: int) -> void:
    if canvas.map != null and index >= 0 and index < NATIVE_UNITS.size():
        var candidate: AtlasGrid = canvas.map.grid.copy()
        candidate.distance_unit = NATIVE_UNITS[index]
        apply_grid(candidate)


func _scope() -> AtlasEditScope:
    var boundary: PackedVector2Array = PackedVector2Array()
    if locked_to_cell and canvas.map != null and canvas.has_selected_cell:
        boundary = canvas.map.grid.cell_polygon(canvas.selected_cell)
    return AtlasEditScope.new(boundary, locked_to_cell)


func _refresh_scope() -> void:
    canvas.edit_scope = _scope()


func _on_scope_toggled(enabled: bool) -> void:
    canvas.cancel_edit()
    locked_to_cell = enabled
    _refresh_scope()
    _message("Selected-cell scope %s." % ("enabled" if enabled else "disabled"))


func _on_selection_changed() -> void:
    if selection_label == null:
        return
    var selection: AtlasSelection = canvas.selection
    selection_label.text = "Drag a marquee or click ink / a raster asset."
    if not selection.is_empty():
        selection_label.text = "Raster asset selected" if selection.raster_selected else "%d strokes selected" % selection.stroke_indices.size()
    move_x_spinner.set_value_no_signal(0.0)
    move_y_spinner.set_value_no_signal(0.0)
    scale_spinner.set_value_no_signal(1.0)
    artwork_rotation_spinner.set_value_no_signal(0.0)
    _transform_button.disabled = not can_modify_selection()


func select_all_artwork() -> void:
    tool_picker.select(AtlasCanvas.Tool.ART_SELECT)
    _on_tool_changed(AtlasCanvas.Tool.ART_SELECT)
    canvas.select_all_artwork()


func _apply_numeric_transform() -> void:
    var delta: Transform2D = AtlasSelectionGeometry.about(canvas.selection.bounds.get_center(),
        Vector2(move_x_spinner.value, move_y_spinner.value), scale_spinner.value, deg_to_rad(artwork_rotation_spinner.value))
    transform_selection(canvas.selection, delta)


func transform_selection(selection: AtlasSelection, delta: Transform2D) -> bool:
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    var transformed: AtlasLayer = AtlasSelectionGeometry.transformed(layer, selection, delta, _scope())
    if transformed == null:
        _message("Transform rejected: stale/locked selection or footprint outside the selected cell.")
        return false
    if transformed.to_dict() == layer.to_dict():
        return false
    var indices: Array[int] = selection.stroke_indices.duplicate()
    var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
    layers[canvas.floor.layers.find(layer)] = transformed
    if not apply_layers(layers, layer.id):
        return false
    canvas.selection = AtlasSelectionGeometry.select_indices(canvas.floor.layer_by_id(layer.id), indices)
    canvas.selection_changed.emit()
    canvas.queue_redraw()
    _message("Transformed artwork without changing its grid or source pixels.")
    return true


func fill_at(point: Vector2) -> bool:
    canvas.cancel_edit()
    canvas.clear_selection()
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if layer == null or not layer.is_editable():
        _message("Fill needs visible, unlocked raster or terrain content.")
        return false
    var result: AtlasFillResult
    if layer is AtlasRasterLayer:
        result = AtlasFill.raster(layer, point, canvas.brush_color, _scope())
        if result.ok:
            var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
            layers[canvas.floor.layers.find(layer)] = result.layer
            return apply_layers(layers, layer.id)
    elif layer is AtlasTileLayer:
        var basis: AtlasGrid = layer.grid if layer.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
        result = AtlasFill.tiles(basis, layer.terrain, basis.document_to_cell(point), palette_id, _scope())
        if result.ok:
            var command: AtlasTileEdit = AtlasTileEdit.new(canvas.map.id, canvas.floor.id, layer.id, layer.terrain, result.terrain)
            if edits.execute(command):
                canvas.queue_redraw()
                _message("Filled connected cells in one undoable action.")
                return true
    if result != null:
        _message(result.message)
    else:
        _message("Bucket fill targets raster pixels or terrain cells; outlines remain vector ink.")
    return false


func can_copy_selection() -> bool:
    if canvas.floor == null:
        return false
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if layer == null or not layer.visible:
        return false
    if layer is AtlasTileLayer:
        var basis: AtlasGrid = layer.grid if layer.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
        var key: String = "%d,%d" % [canvas.selected_cell.x, canvas.selected_cell.y]
        return canvas.has_selected_cell and basis.same_geometry(canvas.map.grid) and layer.terrain.has(key)
    return not canvas.selection.is_empty() and canvas.selection.matches(layer)


func can_modify_selection() -> bool:
    if not can_copy_selection():
        return false
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if not layer.is_editable():
        return false
    if layer is AtlasTileLayer:
        var basis: AtlasGrid = layer.grid if layer.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
        return _scope().allows_polygon(basis.cell_polygon(canvas.selected_cell))
    return _scope().contains_rect(canvas.selection.bounds)


func _system_clipboard_enabled() -> bool:
    return use_system_clipboard and not OS.has_feature("web") and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)


func copy_selection() -> bool:
    if not can_copy_selection():
        _message("Select visible artwork first.")
        return false
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    var encoded: String = ""
    if layer is AtlasInkLayer:
        encoded = AtlasClipboard.encode_ink(layer.strokes, canvas.selection.stroke_indices, canvas.selection.bounds.position)
    elif layer is AtlasRasterLayer:
        encoded = AtlasClipboard.encode_raster(layer, canvas.selection.bounds.position)
    elif layer is AtlasTileLayer:
        var basis: AtlasGrid = layer.grid if layer.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
        var cells: Dictionary = {}
        cells["%d,%d" % [canvas.selected_cell.x, canvas.selected_cell.y]] = layer.terrain["%d,%d" % [canvas.selected_cell.x, canvas.selected_cell.y]]
        encoded = AtlasClipboard.encode_tiles(basis, cells, canvas.selected_cell)
    if encoded.is_empty():
        _message("Selection is invalid or too large for the artwork clipboard.")
        return false
    clipboard_text = encoded
    _paste_count = 0
    if _system_clipboard_enabled():
        DisplayServer.clipboard_set(encoded)
    _message("Copied typed artwork in board units; no physical unit conversion.")
    return true


func delete_selection() -> bool:
    if not can_modify_selection():
        _message("Delete rejected: locked/hidden selection or footprint outside edit scope.")
        return false
    var layer: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if layer is AtlasTileLayer:
        var after: Dictionary = layer.terrain.duplicate()
        after.erase("%d,%d" % [canvas.selected_cell.x, canvas.selected_cell.y])
        var command: AtlasTileEdit = AtlasTileEdit.new(canvas.map.id, canvas.floor.id, layer.id, layer.terrain, after)
        if edits.execute(command):
            canvas.queue_redraw()
            return true
        return false
    var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
    var index: int = canvas.floor.layers.find(layer)
    if layer is AtlasInkLayer:
        var indices: Array[int] = canvas.selection.stroke_indices.duplicate()
        indices.sort()
        indices.reverse()
        var ink: AtlasInkLayer = layers[index] as AtlasInkLayer
        for stroke_index: int in indices:
            ink.strokes.remove_at(stroke_index)
    else:
        layers.remove_at(index)
    return apply_layers(layers, layer.id)


func cut_selection() -> bool:
    if not can_modify_selection():
        return false
    if not copy_selection():
        return false
    return delete_selection()


func paste_selection() -> bool:
    var text: String = DisplayServer.clipboard_get() if _system_clipboard_enabled() else clipboard_text
    var payload: AtlasClipboardData = AtlasClipboard.decode(text)
    if payload == null:
        if _system_clipboard_enabled() and DisplayServer.clipboard_has_image():
            var image: Image = DisplayServer.clipboard_get_image()
            if image != null:
                return import_raster(image)
        _message("Clipboard has no supported artwork.")
        return false
    var anchor: Vector2 = canvas.camera_center + Vector2.ONE * float(20 * _paste_count)
    if paste_payload(payload, anchor):
        _paste_count += 1
        return true
    return false


func paste_payload(payload: AtlasClipboardData, anchor: Vector2) -> bool:
    if payload == null or not anchor.is_finite():
        return false
    var target: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if payload.kind == "INK" and target is AtlasInkLayer and target.is_editable():
        var pasted: Array[AtlasStroke] = AtlasStroke.clone_all(payload.strokes)
        for stroke: AtlasStroke in pasted:
            for point: int in range(stroke.points.size()):
                stroke.points[point] += anchor
        pasted = _scope().clip_strokes(pasted)
        if pasted.is_empty():
            return false
        var after: Array[AtlasStroke] = AtlasStroke.clone_all(target.strokes)
        var first: int = after.size()
        after.append_array(pasted)
        var command: AtlasStrokeEdit = AtlasStrokeEdit.new(canvas.map.id, canvas.floor.id, target.strokes, after, target.id)
        if not edits.execute(command):
            return false
        tool_picker.select(AtlasCanvas.Tool.ART_SELECT)
        _on_tool_changed(AtlasCanvas.Tool.ART_SELECT)
        var indices: Array[int] = []
        for index: int in range(first, after.size()):
            indices.append(index)
        canvas.selection = AtlasSelectionGeometry.select_indices(canvas.floor.layer_by_id(target.id), indices)
        canvas.selection_changed.emit()
        canvas.queue_redraw()
        return true
    if payload.kind == "RASTER" and payload.raster != null:
        var raster: AtlasRasterLayer = AtlasLayerCodec.clone(payload.raster) as AtlasRasterLayer
        raster.id = "raster-" + Crypto.new().generate_random_bytes(16).hex_encode()
        raster.transform = Transform2D(0.0, anchor) * raster.transform
        if not _scope().contains_rect(AtlasSelectionGeometry.select_all(raster).bounds):
            return false
        var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
        layers.append(raster)
        if apply_layers(layers, raster.id):
            select_all_artwork()
            _message("Pasted raster asset. Drag it or use the corner handle to place it.")
            return true
        return false
    if payload.kind == "TILES" and target is AtlasTileLayer and target.is_editable():
        var basis: AtlasGrid = target.grid if target.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
        if basis.kind != payload.grid.kind or basis.cell_size != payload.grid.cell_size or basis.rotation != payload.grid.rotation:
            _message("Tile paste needs matching grid shape, spacing and rotation; no implicit conversion.")
            return false
        var origin: Vector2i = basis.document_to_cell(anchor)
        var cells: Dictionary = target.terrain.duplicate()
        for key: String in payload.tiles:
            var xy: PackedStringArray = key.split(",")
            var x: int = origin.x + int(xy[0])
            var y: int = origin.y + int(xy[1])
            if abs(x) > 2147483647 or abs(y) > 2147483647:
                return false
            var cell: Vector2i = Vector2i(x, y)
            if not _scope().allows_polygon(basis.cell_polygon(cell)):
                return false
            cells["%d,%d" % [cell.x, cell.y]] = payload.tiles[key]
        var command: AtlasTileEdit = AtlasTileEdit.new(canvas.map.id, canvas.floor.id, target.id, target.terrain, cells)
        if edits.execute(command):
            canvas.queue_redraw()
            return true
    _message("Select a compatible, visible and unlocked destination layer.")
    return false


func apply_grid(candidate: AtlasGrid) -> void:
    canvas.cancel_edit()
    var command: AtlasGridEdit = AtlasGridEdit.new(canvas.map.id, canvas.map.grid, candidate)
    if edits.execute(command):
        zoom_gate.reset()
        _message("Grid settings changed. Artwork coordinates are unchanged.")
    _refresh_grid_controls()
    canvas.queue_redraw()


func set_grid_visible(visible: bool) -> void:
    var candidate: AtlasGrid = canvas.map.grid.copy()
    candidate.visible = visible
    apply_grid(candidate)


func open_board_dialog() -> void:
    canvas.cancel_edit()
    board_dialog.open()


func _on_board_requested(board_name: String, grid: AtlasGrid) -> void:
    if create_board(board_name, grid):
        board_dialog.hide()
        canvas.grab_focus()


func create_board(board_name: String, grid: AtlasGrid) -> bool:
    var name: String = board_name.strip_edges()
    if name.is_empty() or not grid.is_valid():
        _message("Choose a board name and valid grid settings.")
        return false
    var id: String = "board-" + Crypto.new().generate_random_bytes(16).hex_encode()
    var document: AtlasMapDocument = AtlasMapDocument.new(id, name)
    document.kind = "BOARD"
    document.grid = grid.copy()
    document.terrain_grid = grid.copy()
    var command: AtlasCreateMap = AtlasCreateMap.new(canvas.map.id, document)
    if not edits.execute(command):
        _message("Board creation failed; the campaign was not replaced.")
        return false
    _push_history()
    _show_map(campaign.get_map(id))
    tool_picker.select(AtlasCanvas.Tool.PEN)
    _on_tool_changed(AtlasCanvas.Tool.PEN)
    _message("Created an independent blank board. No artwork or links were copied.")
    return true


func _create_section(parent: VBoxContainer, caption: String) -> VBoxContainer:
    var section: VBoxContainer = VBoxContainer.new()
    section.add_theme_constant_override("separation", 8)
    parent.add_child(section)
    var heading: Label = _create_label(caption)
    heading.theme_type_variation = &"MutedLabel"
    heading.add_theme_font_size_override("font_size", 11)
    section.add_child(heading)
    return section


func _create_label(caption: String) -> Label:
    var result: Label = Label.new()
    result.text = caption
    result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return result


func _message(value: String) -> void:
    if status_label != null:
        status_label.text = value


func _show_map(map: AtlasMapDocument, focus: Vector2 = Vector2.ZERO, zoom_value: float = 1.0,
        floor_id: String = "", layer_id: String = "") -> bool:
    if map == null or not canvas.set_document(map, campaign, floor_id):
        _message("Map not found.")
        return false
    edits.active_map_id = map.id
    if not layer_id.is_empty():
        canvas.active_layer_id = layer_id
    _refresh_layers()
    canvas.camera_center = focus
    canvas.camera_zoom = clampf(zoom_value, MIN_ZOOM, MAX_ZOOM)
    _refresh_grid_controls()
    zoom_gate.reset()
    locked_to_cell = false
    lock_checkbox.button_pressed = false
    _refresh_floor_controls()
    _refresh_map_metadata()
    _refresh_edit_state()
    _refresh_map_list()
    canvas.queue_redraw()
    return true


func _refresh_grid_controls() -> void:
    if not grid_controls.get_grid().same_geometry(canvas.map.grid):
        canvas.has_selected_cell = false
        locked_to_cell = false
        lock_checkbox.set_pressed_no_signal(false)
        canvas.clear_selection()
    grid_controls.set_grid(canvas.map.grid)
    lock_checkbox.disabled = canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS
    _refresh_scope()


func _refresh_edit_state() -> void:
    if canvas.map != null and campaign != null:
        title_label.text = "%s%s — %s (%s)" % [
            "* " if edits.is_dirty() else "", campaign.display_name,
            canvas.map.display_name + " / " + canvas.floor.display_name, canvas.map.kind
        ]


func _on_stroke(stroke: AtlasStroke, erasing: bool) -> void:
    if not stroke.is_valid():
        return
    canvas.clear_selection()
    var target: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
    if target is AtlasRasterLayer:
        var result: AtlasFillResult = AtlasRasterBrush.paint(target, stroke.points, stroke.color, stroke.width, erasing, _scope())
        if not result.ok:
            _message(result.message)
            return
        var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
        layers[canvas.floor.layers.find(target)] = result.layer
        apply_layers(layers, target.id)
        return
    var layer: AtlasInkLayer = target as AtlasInkLayer
    if layer == null or not layer.is_editable():
        _message("Select visible, unlocked ink or raster content to draw.")
        return
    var before: Array[AtlasStroke] = layer.strokes
    var after: Array[AtlasStroke]
    if erasing:
        after = _scope().erase(before, stroke.points, stroke.width)
    else:
        after = AtlasStroke.clone_all(before)
        after.append_array(_scope().clip_strokes([stroke]))
    var command: AtlasStrokeEdit = AtlasStrokeEdit.new(canvas.map.id, canvas.floor.id, before, after, layer.id)
    if edits.execute(command):
        canvas.queue_redraw()
        _message("Erased ink. One gesture = one undo." if erasing else "Stroke added in board coordinates.")


func _on_undo() -> void:
    canvas.cancel_edit()
    canvas.clear_selection()
    if edits.undo():
        if campaign.get_map(canvas.map.id) == null:
            _on_back()
            if campaign.get_map(canvas.map.id) == null:
                _show_map(campaign.get_map(campaign.root_map_id))
        _refresh_after_history()
        _message("Undo applied to its original board.")
    elif edits.can_undo():
        _message("Undo blocked: the target changed outside this history.")


func _on_redo() -> void:
    canvas.cancel_edit()
    canvas.clear_selection()
    var command: AtlasEditCommand = edits.get_redo_command()
    if edits.redo():
        if command is AtlasCreateMap:
            _push_history()
            _show_map(campaign.get_map(command.new_map_id))
        _refresh_after_history()
        _message("Redo applied.")
    elif edits.can_redo():
        _message("Redo blocked: the target changed outside this history.")


func _refresh_after_history() -> void:
    view_session.prune(campaign)
    var current: AtlasFloor = canvas.map.floor_by_id(canvas.floor.id)
    if current == null:
        var fallback: AtlasViewState = view_session.resolve(campaign, canvas.map.id, "", canvas.camera_center, canvas.camera_zoom)
        if fallback != null:
            _show_map(canvas.map, fallback.focus, fallback.zoom, fallback.floor_id, fallback.layer_id)
    elif current != canvas.floor:
        canvas.set_document(canvas.map, campaign, current.id)
    _refresh_layers()
    _refresh_floor_controls()
    _refresh_map_metadata()
    _refresh_grid_controls()
    _refresh_map_list()
    _refresh_edit_state()
    canvas.queue_redraw()


func _refresh_layers(preferred_id: String = "") -> void:
    if not preferred_id.is_empty():
        canvas.active_layer_id = preferred_id
    if canvas.floor.layer_by_id(canvas.active_layer_id) == null:
        var ink: AtlasInkLayer = canvas.floor.ink_layer()
        canvas.active_layer_id = ink.id if ink != null else ""
        if ink == null and not canvas.floor.layers.is_empty():
            canvas.active_layer_id = canvas.floor.layers[-1].id
    layer_panel.set_floor(canvas.floor, canvas.active_layer_id)


func select_layer(id: String) -> void:
    if canvas.floor.layer_by_id(id) == null:
        return
    canvas.cancel_edit()
    canvas.clear_selection()
    canvas.active_layer_id = id
    _refresh_layers()
    _message("Selected layer: %s" % canvas.floor.layer_by_id(id).display_name)


func apply_layers(layers: Array[AtlasLayer], selected_id: String) -> bool:
    canvas.cancel_edit()
    canvas.clear_selection()
    for layer: AtlasLayer in layers:
        if layer is AtlasTileLayer and layer.grid == null:
            if canvas.floor.layer_by_id(layer.id) != null:
                layer.grid = canvas.map.get_terrain_grid(canvas.floor.id).copy()
            elif canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
                _message("Choose a square or hex grid before creating a terrain layer.")
                _refresh_layers()
                return false
            else:
                layer.grid = canvas.map.grid.copy()
    var new_layer: bool = canvas.floor.layer_by_id(selected_id) == null
    var command: AtlasLayerEdit = AtlasLayerEdit.new(canvas.map.id, canvas.floor.id, canvas.floor.layers, layers)
    if edits.execute(command):
        _refresh_layers(selected_id)
        var selected: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
        if new_layer and ((selected is AtlasInkLayer and selected.strokes.is_empty())
                or (selected is AtlasRasterLayer and selected.chunks.is_empty())):
            tool_picker.select(AtlasCanvas.Tool.PEN)
            _on_tool_changed(AtlasCanvas.Tool.PEN)
        canvas.queue_redraw()
        _message("Layer changed. Hidden or locked layers are not editable.")
        return true
    else:
        _refresh_layers()
    return false


func import_raster(image: Image) -> bool:
    var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
    if layer == null:
        _message("Could not create a raster layer from that image.")
        return false
    layer.id = "raster-" + Crypto.new().generate_random_bytes(16).hex_encode()
    layer.display_name = "Imported image"
    layer.transform.origin = canvas.camera_center - AtlasSelectionGeometry.raster_local_bounds(layer).size * 0.5
    if not _scope().contains_rect(AtlasSelectionGeometry.select_all(layer).bounds):
        _message("Imported image does not fit the selected-cell scope.")
        return false
    var layers: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
    layers.append(layer)
    if apply_layers(layers, layer.id):
        select_all_artwork()
        _message("Imported raster asset. Drag it or use the corner handle to place it.")
        return true
    return false


func _refresh_map_list() -> void:
    map_list.clear()
    map_list_ids.clear()
    var ids := campaign.maps.keys()
    ids.sort()
    for map_id: String in ids:
        var map := campaign.get_map(map_id)
        map_list_ids.append(map_id)
        map_list.add_item("%s — %s · %d floors" % [map.display_name, map.kind, map.floors.size()])
        if canvas.map != null and canvas.map.id == map_id:
            map_list.select(map_list.item_count - 1)
    _refresh_search_list(sidebar.get_search_query())
    var selected: PackedInt32Array = map_list.get_selected_items()
    if not selected.is_empty() and sidebar.get_view_content(&"Maps").is_visible_in_tree():
        _preview_map_index(selected[0])


func _refresh_search_list(query: String) -> void:
    search_map_ids.clear()
    if campaign == null or canvas.map == null or canvas.floor == null:
        return
    var mode: AtlasOverview.Filter = overview_panel.mode_picker.selected as AtlasOverview.Filter
    var region: PackedVector2Array = PackedVector2Array()
    if mode == AtlasOverview.Filter.VISIBLE:
        for corner: Vector2 in [Vector2.ZERO, Vector2(canvas.size.x, 0), canvas.size, Vector2(0, canvas.size.y)]:
            region.append(canvas.local_to_document(corner))
    elif mode == AtlasOverview.Filter.CELL and canvas.has_selected_cell:
        region = canvas.map.grid.cell_polygon(canvas.selected_cell)
    var result: AtlasOverviewResult = AtlasOverview.query(campaign, canvas.map.id, canvas.floor.id,
        mode, query, region, overview_panel.recursive_checkbox.button_pressed)
    _search_entries = result.entries
    for entry: AtlasOverviewEntry in result.entries:
        search_map_ids.append(entry.map_id)
    overview_panel.set_results(campaign, result)


func _on_search_activated(index: int) -> void:
    if index >= 0 and index < _search_entries.size():
        _open_overview_entry(_search_entries[index])


func _open_overview_entry(entry: AtlasOverviewEntry) -> void:
    if entry.broken_reason.is_empty():
        open_map(entry.map_id, entry.floor_id)


func _focus_overview_source(entry: AtlasOverviewEntry) -> void:
    if entry.can_focus and open_map(entry.source_map_id, entry.source_floor_id):
        canvas.camera_center = entry.source_focus
        canvas.queue_redraw()
        _remember_view()


func _preview_map_index(index: int) -> void:
    if index < 0 or index >= map_list_ids.size():
        return
    var state: AtlasViewState = view_session.resolve(campaign, map_list_ids[index])
    if state != null:
        map_preview.request_preview(campaign, state.map_id, state.floor_id)


func _on_sidebar_view_selected(id: StringName) -> void:
    if campaign == null or canvas.map == null:
        return
    if id == &"Search":
        _refresh_search_list(sidebar.get_search_query())
        overview_panel.refresh_preview()
    elif id == &"Maps":
        var selected: PackedInt32Array = map_list.get_selected_items()
        if not selected.is_empty():
            _preview_map_index(selected[0])


func _on_documents_changed() -> void:
    if campaign == null or canvas.map == null or canvas.floor == null:
        return
    if campaign.get_map(canvas.map.id) != canvas.map or canvas.map.floor_by_id(canvas.floor.id) == null:
        return
    _refresh_map_list()


func _refresh_map_metadata() -> void:
    map_name_input.text = canvas.map.display_name
    map_tags_input.text = ", ".join(canvas.map.tags)


func _apply_map_metadata() -> void:
    var tags: Array[String] = []
    var seen: Dictionary[String, bool] = {}
    for part: String in map_tags_input.text.split(",", false):
        var tag: String = part.strip_edges().trim_prefix("#")
        if not tag.is_empty() and not seen.has(tag.to_lower()):
            seen[tag.to_lower()] = true
            tags.append(tag)
    update_map_metadata(map_name_input.text, tags)


func update_map_metadata(name: String, tags: Array[String]) -> bool:
    var command: AtlasMapMetadataEdit = AtlasMapMetadataEdit.new(canvas.map.id, canvas.map.display_name,
        canvas.map.tags, name.strip_edges(), tags)
    if not edits.execute(command):
        _message("Board metadata was unchanged or invalid.")
        return false
    _refresh_map_metadata()
    _refresh_map_list()
    return true


func _on_sample() -> void:
    history.clear()
    _reset_view_helpers()
    campaign = AtlasCampaign.sample()
    edits.reset(campaign, false)
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Sample campaign reset (not saved).")


func _on_save() -> void:
    canvas.commit_edit()
    var result: Error = AtlasCampaignStore.save_campaign(campaign, save_path, store_io)
    if result == OK:
        edits.mark_saved()
    _message("Saved to %s" % save_path if result == OK else "Save failed: %s" % result)


func _on_load() -> void:
    var result: AtlasStoreResult = AtlasCampaignStore.load_result(save_path, store_io)
    if result.campaign == null:
        _message(result.message)
        return
    campaign = result.campaign
    _reset_view_helpers()
    edits.reset(campaign, not result.recovered)
    history.clear()
    _show_map(campaign.get_map(campaign.root_map_id))
    _message(result.message + " Save to repair the current checkpoint." if result.recovered else "Campaign loaded.")


func _on_map_activated(index: int) -> void:
    if index < 0 or index >= map_list_ids.size():
        return
    open_map(map_list_ids[index])


func _reset_view_helpers() -> void:
    view_session.reset()
    map_preview.clear_preview()
    map_preview.cache.invalidate()
    overview_panel.preview.clear_preview()
    overview_panel.preview.cache.invalidate()


func _on_tool_changed(index: int) -> void:
    canvas.choose_tool(index as AtlasCanvas.Tool)
    lock_checkbox.disabled = canvas.map == null or canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS
    if lock_checkbox.disabled:
        locked_to_cell = false
        lock_checkbox.set_pressed_no_signal(false)
    _ink_section.visible = canvas.tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER, AtlasCanvas.Tool.LINE,
        AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE, AtlasCanvas.Tool.FILL]
    brush_color_picker.disabled = canvas.tool == AtlasCanvas.Tool.ERASER
    brush_width_spinner.editable = canvas.tool != AtlasCanvas.Tool.FILL
    _terrain_section.visible = canvas.tool in [AtlasCanvas.Tool.PAINT, AtlasCanvas.Tool.FILL]
    _placement_section.visible = canvas.tool == AtlasCanvas.Tool.BATTLEMAP
    _selection_section.visible = canvas.tool == AtlasCanvas.Tool.ART_SELECT
    if canvas.tool != AtlasCanvas.Tool.ART_SELECT:
        canvas.clear_selection()
    if canvas.floor != null:
        var current: AtlasLayer = canvas.floor.layer_by_id(canvas.active_layer_id)
        if canvas.tool == AtlasCanvas.Tool.PAINT and not current is AtlasTileLayer:
            var tiles: AtlasTileLayer = canvas.floor.terrain_layer()
            if tiles != null:
                select_layer(tiles.id)
        elif canvas.tool in [AtlasCanvas.Tool.LINE, AtlasCanvas.Tool.RECTANGLE, AtlasCanvas.Tool.ELLIPSE] and not current is AtlasInkLayer:
            var ink: AtlasInkLayer = canvas.floor.ink_layer()
            if ink != null:
                select_layer(ink.id)
        elif canvas.tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER] and not (current is AtlasInkLayer or current is AtlasRasterLayer):
            var ink: AtlasInkLayer = canvas.floor.ink_layer()
            if ink != null:
                select_layer(ink.id)
    zoom_gate.reset()
    _refresh_scope()
    _on_selection_changed()


func _on_select(cell: Vector2i) -> void:
    if canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
        _message("This board has no grid cells to select.")
        return
    canvas.selected_cell = cell
    canvas.has_selected_cell = true
    _refresh_scope()
    canvas.selection_changed.emit()
    canvas.queue_redraw()
    _refresh_search_list(sidebar.get_search_query())
    _message("Selected cell %s. Lock restricts mutations, not camera movement." % cell)


func _on_paint(cell: Vector2i) -> void:
    var layer: AtlasTileLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTileLayer
    if layer == null or not layer.is_editable():
        _message("Select a visible, unlocked terrain layer to paint.")
        return
    var basis: AtlasGrid = layer.grid if layer.grid != null else canvas.map.get_terrain_grid(canvas.floor.id)
    if basis.kind == AtlasGrid.Kind.GRIDLESS:
        _message("This terrain layer has no content grid.")
        return
    if not _scope().allows_polygon(basis.cell_polygon(cell)):
        _message("Edit blocked by selected-cell lock.")
        return
    var key: String = "%d,%d" % [cell.x, cell.y]
    if int(layer.terrain.get(key, 0)) == palette_id:
        return
    var after: Dictionary = layer.terrain.duplicate()
    if palette_id == 0:
        after.erase(key)
    else:
        after[key] = palette_id
    var command: AtlasTileEdit = AtlasTileEdit.new(canvas.map.id, canvas.floor.id, layer.id, layer.terrain, after)
    if not edits.execute(command):
        return
    canvas.queue_redraw()


func _on_create_battlemap(start: Vector2, finish: Vector2, radians: float) -> void:
    var delta := (finish - start).rotated(-radians)
    if delta.length() < 30.0:
        _message("Drag a larger rectangle to create a battlemap.")
        return
    const PITCH: float = 24.0
    var local_min := Vector2(minf(0.0, delta.x), minf(0.0, delta.y))
    var placement := AtlasPlacement.new()
    placement.id = "placement-%d-%d" % [Time.get_ticks_msec(), randi()]
    placement.parent_map_id = canvas.map.id
    placement.origin = start + local_min.rotated(radians)
    placement.rotation = radians
    placement.columns = maxi(2, roundi(absf(delta.x) / PITCH))
    placement.rows = maxi(2, roundi(absf(delta.y) / PITCH))
    placement.parent_units_per_cell = PITCH
    placement.child_units_per_cell = 64.0
    placement.symbolic = canvas.map.kind == "WORLD"

    var child_id := "encounter-%d-%d" % [Time.get_ticks_msec(), randi()]
    placement.child_map_id = child_id
    var encounter := AtlasMapDocument.new(child_id, "Encounter %d" % campaign.maps.size())
    encounter.kind = "BATTLEMAP"
    encounter.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, placement.child_units_per_cell)
    encounter.grid.distance_per_cell = 5.0
    encounter.grid.distance_unit = "ft"
    campaign.add_map(encounter)
    campaign.placements.append(placement)

    var link := AtlasMapLink.new()
    link.id = "link-" + placement.id
    link.source_map_id = canvas.map.id
    link.source_floor_id = canvas.floor.id
    link.target_map_id = child_id
    link.placement_id = placement.id
    link.anchor = placement.origin
    link.target_focus = Vector2(placement.columns, placement.rows) * placement.child_units_per_cell * 0.5
    campaign.links.append(link)
    edits.mark_external_change()
    _enter_link(link)


func _push_history() -> void:
    if canvas.map == null:
        return
    _remember_view()
    history.append({
        "map_id": canvas.map.id,
        "floor_id": canvas.floor.id,
        "layer_id": canvas.active_layer_id,
        "focus": canvas.camera_center,
        "zoom": canvas.camera_zoom
    })


func _enter_link(link: AtlasMapLink) -> void:
    if link.source_map_id != canvas.map.id or link.source_floor_id != canvas.floor.id:
        return
    var destination := campaign.get_map(link.target_map_id)
    if destination == null or destination.floor_by_id(link.target_floor_id) == null:
        _message("Broken map link: %s" % link.target_map_id)
        return
    _push_history()
    var arrival: AtlasViewState = view_session.resolve(campaign, destination.id, link.target_floor_id, link.target_focus, link.target_zoom)
    _show_map(destination, link.target_focus, link.target_zoom, link.target_floor_id, arrival.layer_id)
    _message("Entered %s. Use Back or 3 extra outward wheel steps." % destination.display_name)


func _on_back() -> void:
    while not history.is_empty():
        var snapshot: Dictionary = history.pop_back()
        var map: AtlasMapDocument = campaign.get_map(str(snapshot["map_id"]))
        var floor_id: String = str(snapshot.get("floor_id", map.default_floor_id if map != null else ""))
        if map != null and map.floor_by_id(floor_id) != null:
            _remember_view()
            _show_map(map, snapshot["focus"], float(snapshot["zoom"]), floor_id, str(snapshot.get("layer_id", "")))
            _message("Returned to %s." % map.display_name)
            return
    _message("No previous map.")


func _on_wheel_step(direction: int, local_position: Vector2) -> void:
    var old_zoom := canvas.camera_zoom
    var new_zoom := clampf(
        old_zoom * (ZOOM_FACTOR if direction > 0 else 1.0 / ZOOM_FACTOR),
        MIN_ZOOM, MAX_ZOOM
    )
    if not is_equal_approx(old_zoom, new_zoom):
        var point_before := canvas.local_to_document(local_position)
        canvas.camera_zoom = new_zoom
        canvas.camera_center = point_before - (local_position - canvas.size * 0.5) / new_zoom
        zoom_gate.reset()
        canvas.queue_redraw()
        return

    if not automatic_navigation:
        zoom_gate.reset()
        _message("Zoom limit. Use Maps or double-click a marker to open another board.")
        return

    var candidate: String = ""
    var target_link: AtlasMapLink
    if direction > 0:
        var possible := campaign.find_links_at(canvas.map.id, canvas.local_to_document(local_position), canvas.floor.id)
        if possible.size() == 1:
            target_link = possible[0]
            candidate = target_link.id
        elif possible.size() > 1:
            zoom_gate.reset()
            _message("Multiple linked maps overlap. Double-click or use the map list.")
            return
    elif not history.is_empty():
        candidate = "return:" + str(history[-1]["map_id"])

    if candidate.is_empty():
        zoom_gate.reset()
        _message("Zoom limit reached; no map available in that direction.")
        return

    if zoom_gate.accept_blocked_step(direction, candidate, Time.get_ticks_msec()):
        if direction > 0:
            _enter_link(target_link)
        else:
            _on_back()
    else:
        _message("Semantic zoom buffer %d/3 — %s" % [
            zoom_gate.count, "enter" if direction > 0 else "return"
        ])


func _on_pointer_moved(local_position: Vector2) -> void:
    if zoom_gate.count == 0 or zoom_gate.direction < 0:
        return
    var links: Array[AtlasMapLink] = campaign.find_links_at(
        canvas.map.id, canvas.local_to_document(local_position), canvas.floor.id
    )
    if links.size() != 1 or links[0].id != zoom_gate.candidate_id:
        zoom_gate.reset()


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.is_command_or_control_pressed():
        match event.keycode:
            KEY_Z:
                if event.shift_pressed:
                    _on_redo()
                else:
                    _on_undo()
            KEY_Y:
                _on_redo()
            KEY_S:
                _on_save()
            KEY_N:
                open_board_dialog()
            KEY_A:
                select_all_artwork()
            KEY_C:
                copy_selection()
            KEY_X:
                cut_selection()
            KEY_V:
                paste_selection()
            KEY_F:
                sidebar.select_view(&"Search")
            _:
                return
        get_viewport().set_input_as_handled()
        return
    if event.keycode == KEY_ESCAPE:
        if canvas.is_editing():
            canvas.cancel_edit()
        else:
            canvas.clear_selection()
        get_viewport().set_input_as_handled()
    elif (event.keycode == KEY_Q or event.keycode == KEY_E) and canvas.tool == AtlasCanvas.Tool.BATTLEMAP:
        var sign := -1.0 if event.keycode == KEY_Q else 1.0
        angle_spinner.value = wrapf(angle_spinner.value + 15.0 * sign, -180.0, 180.0)
        get_viewport().set_input_as_handled()
    elif event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
        delete_selection()
        get_viewport().set_input_as_handled()
    elif event.keycode in [KEY_B, KEY_E, KEY_V, KEY_F, KEY_L, KEY_R, KEY_O]:
        var tools: Dictionary[int, int] = {KEY_B: AtlasCanvas.Tool.PEN, KEY_E: AtlasCanvas.Tool.ERASER,
            KEY_V: AtlasCanvas.Tool.ART_SELECT, KEY_F: AtlasCanvas.Tool.FILL, KEY_L: AtlasCanvas.Tool.LINE,
            KEY_R: AtlasCanvas.Tool.RECTANGLE, KEY_O: AtlasCanvas.Tool.ELLIPSE}
        var selected: int = tools[event.keycode]
        tool_picker.select(selected)
        _on_tool_changed(selected)
        get_viewport().set_input_as_handled()
