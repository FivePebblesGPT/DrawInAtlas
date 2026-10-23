class_name AtlasBoardDialog
extends ConfirmationDialog

signal board_requested(board_name: String, grid: AtlasGrid)

var name_input: LineEdit
var grid_controls: AtlasGridControls


func _ready() -> void:
    title = "New board"
    ok_button_text = "Create"
    dialog_hide_on_ok = false
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(400, 420)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    add_child(scroll)
    var margin: MarginContainer = MarginContainer.new()
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for edge: String in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 12)
    scroll.add_child(margin)
    var form: VBoxContainer = VBoxContainer.new()
    form.add_theme_constant_override("separation", 10)
    margin.add_child(form)
    var name_label: Label = Label.new()
    name_label.text = "Board name"
    form.add_child(name_label)
    name_input = LineEdit.new()
    name_input.placeholder_text = "Untitled board"
    name_input.text_changed.connect(_validate_name)
    form.add_child(name_input)
    register_text_enter(name_input)
    grid_controls = AtlasGridControls.new()
    form.add_child(grid_controls)
    confirmed.connect(_request_board)


func open() -> void:
    name_input.text = "Untitled board"
    var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
    grid.distance_per_cell = 1.0
    grid.distance_unit = "tiles"
    grid_controls.set_grid(grid)
    _validate_name(name_input.text)
    popup_centered_clamped(Vector2i(440, 560), 0.95)
    name_input.grab_focus()
    name_input.select_all()


func _validate_name(value: String) -> void:
    get_ok_button().disabled = value.strip_edges().is_empty()


func _request_board() -> void:
    var board_name: String = name_input.text.strip_edges()
    if board_name.is_empty():
        return
    board_requested.emit(board_name, grid_controls.get_grid())
