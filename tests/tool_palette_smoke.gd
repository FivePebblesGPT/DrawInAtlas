extends SceneTree
## T-006: categorized palette, one active tool, shortcuts and inspector state.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TOOL PALETTE FAILED: " + label)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var palette: AtlasToolPalette = editor.tool_palette
	_check(palette != null and editor.sidebar.get_view_content(&"Tools").is_ancestor_of(palette),
		"tool palette uses the existing sidebar content pane")
	_check(editor.inspector.find_child("ToolPicker", true, false) == null,
		"large inspector selector has been removed")
	_check(palette.get_child_count() == AtlasToolPalette.CATEGORIES.size() * 2 + 1, "categorized tool groups and active settings hint exist")
	var all_tools: Array[int] = []
	for category: Dictionary in AtlasToolPalette.CATEGORIES:
		_check(not String(category["title"]).is_empty(), "category has a readable heading")
		for definition: Dictionary in category["tools"]:
			var id: int = definition["id"]
			all_tools.append(id)
			var button: Button = palette.button_for(id)
			_check(button != null and button.icon != null and button.tooltip_text.contains(definition["name"]),
				"%s has an icon and descriptive tooltip" % definition["name"])
			_check(button.custom_minimum_size == Vector2(42, 42) and button.toggle_mode,
				"%s uses a compact keyboard-focusable control" % definition["name"])
	_check(all_tools.size() == AtlasCanvas.Tool.size(), "all existing tools can be chosen")
	_check(editor.canvas.tool == AtlasCanvas.Tool.PEN and palette.button_for(AtlasCanvas.Tool.PEN).button_pressed,
		"pen selection is synchronized at startup")
	editor.sidebar.select_view(&"Tools")
	_check(editor.sidebar.active_view == &"Tools" and palette.is_visible_in_tree(),
		"Tools is its own sidebar tab")
	for id: int in all_tools:
		palette.button_for(id).pressed.emit()
		_check(editor.canvas.tool == id and palette.button_for(id).button_pressed,
			"tool click updates canvas and active icon for tool %d" % id)
		var pressed_count: int = 0
		for candidate: int in all_tools:
			if palette.button_for(candidate).button_pressed:
				pressed_count += 1
		_check(pressed_count == 1, "exactly one icon remains active")
	# Keyboard and programmatic tool changes must share one state update path.
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.keycode = KEY_B
	shortcut.pressed = true
	editor._unhandled_key_input(shortcut)
	_check(editor.canvas.tool == AtlasCanvas.Tool.PEN and palette.button_for(AtlasCanvas.Tool.PEN).button_pressed,
		"B shortcut updates palette and canvas")
	editor._choose_tool(AtlasCanvas.Tool.ART_SELECT)
	_check(editor.canvas.tool == AtlasCanvas.Tool.ART_SELECT and palette.button_for(AtlasCanvas.Tool.ART_SELECT).button_pressed
		and editor.inspector.get_node("%ActiveToolLabel").text.contains("Select artwork (V)"),
		"programmatic changes update active icon and inspector")
	_check(editor.sidebar.active_view == &"Tools", "choosing a tool does not switch the sidebar tab")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_TOOL_PALETTE_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
