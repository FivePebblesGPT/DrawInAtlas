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

var map_list: ItemList
var map_list_ids: Array[String] = []
var tool_picker: OptionButton
var preview_picker: OptionButton
var angle_spinner: SpinBox
var lock_checkbox: CheckBox
var reference_checkbox: CheckBox
var opacity_slider: HSlider
var status_label: Label
var title_label: Label


func _ready() -> void:
    _build_ui()
    campaign = AtlasCampaignStore.load_campaign()
    if campaign == null:
        campaign = AtlasCampaign.sample()
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Paint terrain, select a cell, or drag a battle grid. Middle-drag to pan.")


func _build_ui() -> void:
    var shell := VBoxContainer.new()
    shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(shell)

    var toolbar := HBoxContainer.new()
    shell.add_child(toolbar)
    toolbar.add_child(_make_button("Sample", _on_sample))
    toolbar.add_child(_make_button("Save", _on_save))
    toolbar.add_child(_make_button("Load", _on_load))
    toolbar.add_child(_make_button("← Back", _on_back))
    title_label = Label.new()
    title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    toolbar.add_child(title_label)

    var content := HBoxContainer.new()
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    shell.add_child(content)

    var left := VBoxContainer.new()
    left.custom_minimum_size = Vector2(190, 0)
    content.add_child(left)
    left.add_child(_label("Campaign maps (double-click)"))
    map_list = ItemList.new()
    map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_list.item_activated.connect(_on_map_activated)
    left.add_child(map_list)
    left.add_child(_label("Find linked maps here; double-click a marker in the canvas."))

    canvas = AtlasCanvas.new()
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    canvas.custom_minimum_size = Vector2(380, 300)
    canvas.paint_requested.connect(_on_paint)
    canvas.selection_requested.connect(_on_select)
    canvas.battlemap_requested.connect(_on_create_battlemap)
    canvas.wheel_step.connect(_on_wheel_step)
    canvas.enter_requested.connect(_enter_link)
    content.add_child(canvas)

    var right := VBoxContainer.new()
    right.custom_minimum_size = Vector2(225, 0)
    content.add_child(right)
    right.add_child(_label("Tool"))
    tool_picker = OptionButton.new()
    for caption in ["Paint cells", "Select cell", "Drag battlemap"]:
        tool_picker.add_item(caption)
    tool_picker.item_selected.connect(_on_tool_changed)
    right.add_child(tool_picker)

    right.add_child(_label("Terrain palette"))
    var palette_picker := OptionButton.new()
    for caption in ["Erase", "Grass", "Forest", "Road", "Water", "Stone"]:
        palette_picker.add_item(caption)
    palette_picker.select(2)
    palette_picker.item_selected.connect(func(index: int) -> void: palette_id = index)
    right.add_child(palette_picker)

    lock_checkbox = CheckBox.new()
    lock_checkbox.text = "Restrict edits to selected cell"
    lock_checkbox.toggled.connect(func(on: bool) -> void:
        locked_to_cell = on
        _message("Cell lock %s" % ("ON" if on else "OFF"))
    )
    right.add_child(lock_checkbox)

    right.add_child(_label("Battlemap rotation (degrees)"))
    angle_spinner = SpinBox.new()
    angle_spinner.min_value = -180.0
    angle_spinner.max_value = 180.0
    angle_spinner.step = 5.0
    angle_spinner.value_changed.connect(func(value: float) -> void:
        canvas.battle_rotation = deg_to_rad(value)
    )
    right.add_child(angle_spinner)

    right.add_child(_label("Child map previews"))
    preview_picker = OptionButton.new()
    for caption in ["Off", "Markers", "Thumbnails"]:
        preview_picker.add_item(caption)
    preview_picker.select(2)
    preview_picker.item_selected.connect(func(index: int) -> void:
        canvas.preview = index as AtlasCanvas.Preview
        canvas.queue_redraw()
    )
    right.add_child(preview_picker)

    reference_checkbox = CheckBox.new()
    reference_checkbox.text = "Read-only parent reference"
    reference_checkbox.button_pressed = true
    reference_checkbox.toggled.connect(func(on: bool) -> void:
        canvas.show_reference = on
        canvas.queue_redraw()
    )
    right.add_child(reference_checkbox)
    right.add_child(_label("Parent reference opacity"))
    opacity_slider = HSlider.new()
    opacity_slider.min_value = 0.0
    opacity_slider.max_value = 1.0
    opacity_slider.step = 0.05
    opacity_slider.value = 0.35
    opacity_slider.value_changed.connect(func(value: float) -> void:
        canvas.reference_opacity = value
        canvas.queue_redraw()
    )
    right.add_child(opacity_slider)
    right.add_child(_label("Scroll: zoom. At limit, 3 extra steps enter/exit."))

    status_label = Label.new()
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    shell.add_child(status_label)


func _make_button(caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.pressed.connect(callback)
    return button


func _label(caption: String) -> Label:
    var result := Label.new()
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
    canvas.camera_center = focus
    canvas.camera_zoom = clampf(zoom_value, MIN_ZOOM, MAX_ZOOM)
    zoom_gate.reset()
    locked_to_cell = false
    lock_checkbox.button_pressed = false
    title_label.text = "%s — %s (%s)" % [campaign.display_name, map.display_name, map.kind]
    _refresh_map_list()
    canvas.queue_redraw()


func _refresh_map_list() -> void:
    map_list.clear()
    map_list_ids.clear()
    var ids := campaign.maps.keys()
    ids.sort()
    for map_id: String in ids:
        var map := campaign.get_map(map_id)
        map_list_ids.append(map_id)
        map_list.add_item("%s — %s" % [map.display_name, map.kind])


func _on_sample() -> void:
    history.clear()
    campaign = AtlasCampaign.sample()
    _show_map(campaign.get_map(campaign.root_map_id))
    _message("Sample campaign reset (not saved).")


func _on_save() -> void:
    var result := AtlasCampaignStore.save_campaign(campaign)
    _message("Saved to user://drawinatlas_campaign.json" if result == OK else "Save failed: %s" % result)


func _on_load() -> void:
    var loaded := AtlasCampaignStore.load_campaign()
    if loaded == null:
        _message("No compatible saved campaign found.")
        return
    campaign = loaded
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
    canvas.tool = index as AtlasCanvas.Tool


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
    canvas.floor.paint(cell, palette_id)
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


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_Q or event.keycode == KEY_E:
        var sign := -1.0 if event.keycode == KEY_Q else 1.0
        angle_spinner.value = wrapf(angle_spinner.value + 15.0 * sign, -180.0, 180.0)
        get_viewport().set_input_as_handled()
