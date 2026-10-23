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
var grid_label: Label
var distance_spinner: SpinBox
var unit_picker: OptionButton
var brush_color_picker: ColorPickerButton
var brush_width_spinner: SpinBox
var _ink_section: VBoxContainer
var _terrain_section: VBoxContainer
var _placement_section: VBoxContainer

const NATIVE_UNITS: Array[String] = ["mi", "km", "ft", "m", "tiles"]


func _ready() -> void:
    _build_ui()
    if load_saved_on_startup:
        campaign = AtlasCampaignStore.load_campaign(save_path)
    var loaded: bool = campaign != null
    if campaign == null:
        campaign = AtlasCampaign.sample()
    edits.changed.connect(_refresh_edit_state)
    edits.reset(campaign, loaded)
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Draw freely across cells. B: pen · E: eraser · Ctrl+Z: undo · Middle-drag: pan.")


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
    _on_tool_changed(tool_picker.selected)


func _build_sidebar_views() -> void:
    var maps_view: Control = sidebar.get_view_content(&"Maps")
    maps_view.get_node("Heading").text = "Campaign maps"
    maps_view.get_node("Description").text = "Double-click a map to open it."
    map_list = ItemList.new()
    map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_list.item_activated.connect(_on_map_activated)
    maps_view.add_child(map_list)

    var search_view: Control = sidebar.get_view_content(&"Search")
    search_view.get_node("Description").text = "Find maps by name or type. Double-click to open."
    search_list = ItemList.new()
    search_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    search_list.item_activated.connect(_on_search_activated)
    search_view.add_child(search_list)
    sidebar.search_changed.connect(_refresh_search_list)

    var layers_view: Control = sidebar.get_view_content(&"Layers")
    layers_view.get_node("Heading").text = "Ink + terrain (prototype)"
    layers_view.get_node("Description").text = "Freehand ink uses board coordinates. Layer visibility, locking and ordering are pending."


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
    parent.add_child(canvas)


func _build_inspector(parent: HBoxContainer) -> void:
    var panel: PanelContainer = PanelContainer.new()
    panel.custom_minimum_size = Vector2(252, 0)
    parent.add_child(panel)
    var inspector: ScrollContainer = ScrollContainer.new()
    inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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

    _build_tool_controls(sections)
    _build_ink_controls(sections)
    _build_terrain_controls(sections)
    _build_map_controls(sections)
    _build_placement_controls(sections)
    _build_reference_controls(sections)


func _build_tool_controls(parent: VBoxContainer) -> void:
    var tools: VBoxContainer = _create_section(parent, "TOOLS")
    tool_picker = OptionButton.new()
    for caption: String in ["Pen", "Eraser", "Paint cells (prototype)", "Select cell", "Drag battlemap"]:
        tool_picker.add_item(caption)
    tool_picker.item_selected.connect(_on_tool_changed)
    tools.add_child(tool_picker)


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

    lock_checkbox = CheckBox.new()
    lock_checkbox.text = "Cell lock (terrain only)"
    lock_checkbox.disabled = true
    lock_checkbox.toggled.connect(func(on: bool) -> void:
        locked_to_cell = on
        _message("Cell lock %s" % ("ON" if on else "OFF"))
    )
    _terrain_section.add_child(lock_checkbox)


func _build_map_controls(parent: VBoxContainer) -> void:
    var map_section: VBoxContainer = _create_section(parent, "MAP")
    grid_label = _create_label("")
    map_section.add_child(grid_label)
    map_section.add_child(_create_label("Native distance per cell"))
    distance_spinner = SpinBox.new()
    distance_spinner.min_value = 0.001
    distance_spinner.max_value = 1000000.0
    distance_spinner.step = 0.001
    distance_spinner.value_changed.connect(_on_distance_changed)
    map_section.add_child(distance_spinner)
    unit_picker = OptionButton.new()
    for unit: String in NATIVE_UNITS:
        unit_picker.add_item(unit)
    unit_picker.item_selected.connect(_on_unit_changed)
    map_section.add_child(unit_picker)
    var unit_hint: Label = _create_label("Measurement labels only; artwork and linked maps are not rescaled.")
    unit_hint.theme_type_variation = &"MutedLabel"
    map_section.add_child(unit_hint)


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
        if canvas.map.grid.distance_per_cell != value:
            canvas.map.grid.distance_per_cell = value
            edits.mark_external_change()


func _on_unit_changed(index: int) -> void:
    if canvas.map != null and index >= 0 and index < NATIVE_UNITS.size():
        if canvas.map.grid.distance_unit != NATIVE_UNITS[index]:
            canvas.map.grid.distance_unit = NATIVE_UNITS[index]
            edits.mark_external_change()


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


func _show_map(map: AtlasMapDocument, focus: Vector2 = Vector2.ZERO, zoom_value: float = 1.0) -> void:
    if map == null:
        _message("Map not found.")
        return
    canvas.set_document(map, campaign)
    edits.active_map_id = map.id
    canvas.camera_center = focus
    canvas.camera_zoom = clampf(zoom_value, MIN_ZOOM, MAX_ZOOM)
    distance_spinner.set_value_no_signal(map.grid.distance_per_cell)
    var unit_index: int = NATIVE_UNITS.find(map.grid.distance_unit)
    unit_picker.clear()
    for unit: String in NATIVE_UNITS:
        unit_picker.add_item(unit)
    if unit_index < 0:
        unit_index = unit_picker.item_count
        unit_picker.add_item(map.grid.distance_unit)
    unit_picker.select(unit_index)
    distance_spinner.editable = map.grid.kind != AtlasGrid.Kind.GRIDLESS
    unit_picker.disabled = map.grid.kind == AtlasGrid.Kind.GRIDLESS
    const GRID_LABELS: Array[String] = ["None", "Square", "Pointy hex", "Flat hex"]
    grid_label.text = "Grid: %s" % GRID_LABELS[map.grid.kind]
    zoom_gate.reset()
    locked_to_cell = false
    lock_checkbox.button_pressed = false
    _refresh_edit_state()
    _refresh_map_list()
    canvas.queue_redraw()


func _refresh_edit_state() -> void:
    if canvas.map != null and campaign != null:
        title_label.text = "%s%s — %s (%s)" % [
            "* " if edits.is_dirty() else "", campaign.display_name, canvas.map.display_name, canvas.map.kind
        ]


func _on_stroke(stroke: AtlasStroke, erasing: bool) -> void:
    if not stroke.is_valid():
        return
    var before: Array[AtlasStroke] = canvas.floor.strokes
    var after: Array[AtlasStroke]
    if erasing:
        after = AtlasStrokeEraser.erase(before, stroke.points, stroke.width)
    else:
        after = AtlasStroke.clone_all(before)
        after.append(stroke.copy())
    var command: AtlasStrokeEdit = AtlasStrokeEdit.new(canvas.map.id, canvas.floor.id, before, after)
    if edits.execute(command):
        canvas.queue_redraw()
        _message("Erased ink. One gesture = one undo." if erasing else "Stroke added in board coordinates.")


func _on_undo() -> void:
    canvas.cancel_edit()
    if edits.undo():
        canvas.queue_redraw()
        _message("Undid drawing. History retains the original map/floor target.")


func _on_redo() -> void:
    canvas.cancel_edit()
    if edits.redo():
        canvas.queue_redraw()
        _message("Redid drawing.")


func _refresh_map_list() -> void:
    map_list.clear()
    map_list_ids.clear()
    var ids := campaign.maps.keys()
    ids.sort()
    for map_id: String in ids:
        var map := campaign.get_map(map_id)
        map_list_ids.append(map_id)
        map_list.add_item("%s — %s" % [map.display_name, map.kind])
        if canvas.map != null and canvas.map.id == map_id:
            map_list.select(map_list.item_count - 1)
    _refresh_search_list(sidebar.get_search_query())


func _refresh_search_list(query: String) -> void:
    search_list.clear()
    search_map_ids.clear()
    if campaign == null:
        return
    var ids: Array = campaign.maps.keys()
    ids.sort()
    for map_id: String in ids:
        var document: AtlasMapDocument = campaign.get_map(map_id)
        var caption: String = "%s — %s" % [document.display_name, document.kind]
        if query.is_empty() or caption.to_lower().contains(query.to_lower()):
            search_map_ids.append(map_id)
            search_list.add_item(caption)


func _on_search_activated(index: int) -> void:
    if index < 0 or index >= search_map_ids.size():
        return
    var document: AtlasMapDocument = campaign.get_map(search_map_ids[index])
    if document != null and document != canvas.map:
        _push_history()
        _show_map(document)


func _on_sample() -> void:
    history.clear()
    campaign = AtlasCampaign.sample()
    edits.reset(campaign, false)
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Sample campaign reset (not saved).")


func _on_save() -> void:
    canvas.commit_edit()
    var result: Error = AtlasCampaignStore.save_campaign(campaign, save_path)
    if result == OK:
        edits.mark_saved()
    _message("Saved to %s" % save_path if result == OK else "Save failed: %s" % result)


func _on_load() -> void:
    var loaded: AtlasCampaign = AtlasCampaignStore.load_campaign(save_path)
    if loaded == null:
        _message("No compatible saved campaign found.")
        return
    campaign = loaded
    edits.reset(campaign, true)
    history.clear()
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Campaign loaded.")


func _on_map_activated(index: int) -> void:
    if index < 0 or index >= map_list_ids.size():
        return
    var map := campaign.get_map(map_list_ids[index])
    if map != null and map != canvas.map:
        _push_history()
        _show_map(map)
        _message("Opened %s from map index." % map.display_name)


func _on_tool_changed(index: int) -> void:
    canvas.choose_tool(index as AtlasCanvas.Tool)
    lock_checkbox.disabled = canvas.tool != AtlasCanvas.Tool.PAINT
    if lock_checkbox.disabled:
        locked_to_cell = false
        lock_checkbox.set_pressed_no_signal(false)
    _ink_section.visible = canvas.tool in [AtlasCanvas.Tool.PEN, AtlasCanvas.Tool.ERASER]
    brush_color_picker.disabled = canvas.tool == AtlasCanvas.Tool.ERASER
    _terrain_section.visible = canvas.tool == AtlasCanvas.Tool.PAINT
    _placement_section.visible = canvas.tool == AtlasCanvas.Tool.BATTLEMAP
    zoom_gate.reset()


func _on_select(cell: Vector2i) -> void:
    canvas.selected_cell = cell
    canvas.has_selected_cell = true
    canvas.queue_redraw()
    _message("Selected cell %s. Lock restricts mutations, not camera movement." % cell)


func _on_paint(cell: Vector2i) -> void:
    if canvas.map.grid.kind == AtlasGrid.Kind.GRIDLESS:
        _message("Cell paint requires a square or hex grid.")
        return
    if locked_to_cell and (not canvas.has_selected_cell or canvas.selected_cell != cell):
        _message("Edit blocked by selected-cell lock.")
        return
    if canvas.floor.get_terrain(cell) == palette_id:
        return
    canvas.floor.paint(cell, palette_id)
    edits.mark_external_change()
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
    history.append({
        "map_id": canvas.map.id,
        "floor_id": canvas.map.default_floor_id,
        "focus": canvas.camera_center,
        "zoom": canvas.camera_zoom
    })


func _enter_link(link: AtlasMapLink) -> void:
    if link.source_map_id != canvas.map.id:
        return
    var destination := campaign.get_map(link.target_map_id)
    if destination == null:
        _message("Broken map link: %s" % link.target_map_id)
        return
    _push_history()
    _show_map(destination, link.target_focus, link.target_zoom)
    _message("Entered %s. Use Back or 3 extra outward wheel steps." % destination.display_name)


func _on_back() -> void:
    if history.is_empty():
        _message("No previous map.")
        return
    var snapshot: Dictionary = history.pop_back()
    var map := campaign.get_map(str(snapshot["map_id"]))
    _show_map(map, snapshot["focus"], float(snapshot["zoom"]))
    _message("Returned to %s." % map.display_name)


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
        var possible := campaign.find_links_at(canvas.map.id, canvas.local_to_document(local_position))
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
        canvas.map.id, canvas.local_to_document(local_position)
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
            _:
                return
        get_viewport().set_input_as_handled()
        return
    if event.keycode == KEY_ESCAPE:
        canvas.cancel_edit()
        get_viewport().set_input_as_handled()
    elif (event.keycode == KEY_Q or event.keycode == KEY_E) and canvas.tool == AtlasCanvas.Tool.BATTLEMAP:
        var sign := -1.0 if event.keycode == KEY_Q else 1.0
        angle_spinner.value = wrapf(angle_spinner.value + 15.0 * sign, -180.0, 180.0)
        get_viewport().set_input_as_handled()
    elif event.keycode == KEY_B or event.keycode == KEY_E:
        var selected: int = AtlasCanvas.Tool.PEN if event.keycode == KEY_B else AtlasCanvas.Tool.ERASER
        tool_picker.select(selected)
        _on_tool_changed(selected)
        get_viewport().set_input_as_handled()
