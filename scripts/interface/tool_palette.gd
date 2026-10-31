class_name AtlasToolPalette
extends VBoxContainer
## The canvas owns the chosen tool; the palette only requests it and mirrors it.

signal tool_selected(index: int)

const CATEGORIES: Array[Dictionary] = [
	{"title": "DRAW & ERASE", "tools": [
		{"id": AtlasCanvas.Tool.PEN, "name": "Brush", "key": "B", "icon": "pen", "hint": "Drag or tap to paint on the active ink or raster layer; width and opacity in the inspector"},
		{"id": AtlasCanvas.Tool.ERASER, "name": "Eraser", "key": "E", "icon": "eraser", "hint": "Cut ink segments or clear raster pixels on the active layer; width in inspector"},
		{"id": AtlasCanvas.Tool.FILL, "name": "Fill", "key": "F", "icon": "fill", "hint": "Preview contiguous/global RGBA fill on raster with tolerance. Release to apply; Esc cancels"},
	]},
	{"title": "SHAPES", "tools": [
		{"id": AtlasCanvas.Tool.TEXT, "name": "Text", "key": "T", "icon": "text", "hint": "Click to place persistent editable text; click existing text to edit; font and style in the editor"},
		{"id": AtlasCanvas.Tool.LINE, "name": "Line", "key": "L", "icon": "line", "hint": "Drag to draw a straight line"},
		{"id": AtlasCanvas.Tool.WALL_PATH, "name": "Wall path", "key": "W", "icon": "wall-path", "hint": "Click vertices, Enter finish open, right-click close; drag nodes, Shift insert, Alt delete; restyle from inspector"},
		{"id": AtlasCanvas.Tool.POLYGON, "name": "Polygon", "key": "P", "icon": "polygon", "hint": "Click to place vertices, Enter/right-click/double-click to close; outline or solid fill in inspector"},
		{"id": AtlasCanvas.Tool.RECTANGLE, "name": "Rectangle", "key": "R", "icon": "rectangle", "hint": "Drag a rectangle outline"},
		{"id": AtlasCanvas.Tool.ELLIPSE, "name": "Ellipse", "key": "O", "icon": "ellipse", "hint": "Drag an ellipse outline"},
	]},
	{"title": "SELECT", "tools": [
		{"id": AtlasCanvas.Tool.ART_SELECT, "name": "Select artwork", "key": "V", "icon": "select", "hint": "Active-layer objects: drag/select, Ctrl+drag add, Alt+drag subtract; Ctrl+D deselect"},
		{"id": AtlasCanvas.Tool.MOVE, "name": "Move artwork", "key": "M", "icon": "move", "hint": "Pick an object or drag the existing active-layer selection; grid snapping optional; Escape cancels"},
		{"id": AtlasCanvas.Tool.SELECT, "name": "Select grid cell", "key": "", "icon": "cell", "hint": "Choose the cell used by the edit-scope mask"},
	]},
]

var _buttons: Dictionary[int, Button] = {}
var _active_tool: int = AtlasCanvas.Tool.PEN
var _current_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	for category: Dictionary in CATEGORIES:
		_add_category(category)
	_current_label = Label.new()
	_current_label.custom_minimum_size = Vector2(1, 0)
	_current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_current_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	add_child(_current_label)
	sync_tool(_active_tool)


func _add_category(category: Dictionary) -> void:
	var title: Label = Label.new()
	title.text = category["title"]
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	add_child(title)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for definition: Dictionary in category["tools"]:
		var id: int = definition["id"]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(42, 42)
		button.toggle_mode = true
		button.theme_type_variation = &"ActivityButton"
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.icon = load("res://img/tools/%s.svg" % definition["icon"]) as Texture2D
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var shortcut: String = " (%s)" % definition["key"] if not String(definition["key"]).is_empty() else ""
		button.tooltip_text = "%s%s\n%s" % [definition["name"], shortcut, definition["hint"]]
		button.accessibility_name = String(definition["name"]) + shortcut
		button.pressed.connect(_on_pressed.bind(id))
		grid.add_child(button)
		_buttons[id] = button


func sync_tool(index: int) -> void:
	if not _buttons.has(index):
		return
	_active_tool = index
	for id: int in _buttons:
		_buttons[id].set_pressed_no_signal(id == index)
	var selected: Button = _buttons[index]
	_current_label.text = "Active: %s\nOptions → right inspector" % selected.tooltip_text.get_slice("\n", 0)


static func description_for(index: int) -> String:
	for category: Dictionary in CATEGORIES:
		for definition: Dictionary in category["tools"]:
			if definition["id"] == index:
				var shortcut: String = " (%s)" % definition["key"] if not String(definition["key"]).is_empty() else ""
				return "%s%s" % [definition["name"], shortcut]
	return "Unknown tool"


func button_for(index: int) -> Button:
	return _buttons.get(index)


func _on_pressed(index: int) -> void:
	sync_tool(index)
	tool_selected.emit(index)
