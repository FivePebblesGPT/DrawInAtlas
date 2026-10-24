class_name AtlasBoardDialog
extends ConfirmationDialog

signal board_requested(board_name: String, grid: AtlasGrid)

@onready var name_input: LineEdit = $Scroll/Margin/Form/NameInput
@onready var grid_controls: AtlasGridControls = $Scroll/Margin/Form/GridControls


func _ready() -> void:
    name_input.text_changed.connect(_validate_name)
    register_text_enter(name_input)
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
