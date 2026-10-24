class_name AtlasOverviewPanel
extends VBoxContainer
## Metadata discovery and a read-only preview; opening/focusing are explicit actions.

signal query_changed
signal entry_activated(entry: AtlasOverviewEntry)
signal source_focus_requested(entry: AtlasOverviewEntry)

var mode_picker: OptionButton
var recursive_checkbox: CheckBox
var result_list: ItemList
var summary: Label
var preview: AtlasPreviewPanel
var entries: Array[AtlasOverviewEntry] = []
var _campaign: AtlasCampaign
var _open: Button
var _focus: Button


func _ready() -> void:
    add_theme_constant_override("separation", 8)
    mode_picker = OptionButton.new()
    for label: String in ["Campaign", "Current floor links", "Visible area links", "Selected cell links"]:
        mode_picker.add_item(label)
    mode_picker.item_selected.connect(func(_index: int) -> void: query_changed.emit())
    add_child(mode_picker)
    recursive_checkbox = CheckBox.new()
    recursive_checkbox.text = "Include descendants"
    recursive_checkbox.button_pressed = true
    recursive_checkbox.toggled.connect(func(_enabled: bool) -> void: query_changed.emit())
    add_child(recursive_checkbox)
    summary = Label.new()
    summary.theme_type_variation = &"MutedLabel"
    summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(summary)
    result_list = ItemList.new()
    result_list.custom_minimum_size = Vector2(0, 100)
    result_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    result_list.item_selected.connect(_select)
    result_list.item_activated.connect(_activate)
    add_child(result_list)
    _open = Button.new()
    _open.text = "Open map / floor"
    _open.pressed.connect(func() -> void: _activate(_selected_index()))
    add_child(_open)
    _focus = Button.new()
    _focus.text = "Focus source anchor"
    _focus.pressed.connect(_focus_source)
    add_child(_focus)
    preview = AtlasPreviewPanel.new()
    add_child(preview)
    _update_actions(null)


func set_results(campaign: AtlasCampaign, result: AtlasOverviewResult) -> void:
    var previous: AtlasOverviewEntry = selected_entry()
    _campaign = campaign
    entries = result.entries
    recursive_checkbox.disabled = mode_picker.selected == AtlasOverview.Filter.CAMPAIGN
    result_list.clear()
    var selected: int = -1
    for index: int in range(entries.size()):
        var entry: AtlasOverviewEntry = entries[index]
        result_list.add_item(entry.caption)
        result_list.set_item_tooltip(index, entry.breadcrumb + "\n" + entry.broken_reason)
        if _same_entry(previous, entry):
            selected = index
    summary.text = "%d results" % entries.size()
    if result.truncated:
        summary.text += " (limited)"
    if not result.message.is_empty():
        summary.text += "\n" + result.message
    if selected < 0 and not entries.is_empty():
        selected = 0
    if selected >= 0:
        result_list.select(selected)
        _select(selected)
    else:
        _update_actions(null)
        preview.clear_preview()


func selected_entry() -> AtlasOverviewEntry:
    var index: int = _selected_index()
    return entries[index] if index >= 0 and index < entries.size() else null


func refresh_preview() -> void:
    _select(_selected_index())


func _selected_index() -> int:
    var selected: PackedInt32Array = result_list.get_selected_items()
    return selected[0] if not selected.is_empty() else -1


func _select(index: int) -> void:
    var entry: AtlasOverviewEntry = entries[index] if index >= 0 and index < entries.size() else null
    _update_actions(entry)
    if entry == null or not entry.broken_reason.is_empty():
        preview.clear_preview()
    elif is_visible_in_tree():
        preview.request_preview(_campaign, entry.map_id, entry.floor_id)


func _activate(index: int) -> void:
    if index >= 0 and index < entries.size() and entries[index].broken_reason.is_empty():
        entry_activated.emit(entries[index])


func _focus_source() -> void:
    var entry: AtlasOverviewEntry = selected_entry()
    if entry != null and entry.can_focus:
        source_focus_requested.emit(entry)


func _update_actions(entry: AtlasOverviewEntry) -> void:
    _open.disabled = entry == null or not entry.broken_reason.is_empty()
    _focus.disabled = entry == null or not entry.can_focus


func _same_entry(first: AtlasOverviewEntry, second: AtlasOverviewEntry) -> bool:
    return (first != null and first.map_id == second.map_id and first.floor_id == second.floor_id
        and first.source_map_id == second.source_map_id and first.source_floor_id == second.source_floor_id
        and first.link_id == second.link_id)
