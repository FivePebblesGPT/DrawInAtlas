extends SceneTree
## Exercise the composition boundary, including forms and two isolated workspaces.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EDITOR MODULES FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var second_scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	var second: AtlasEditor = second_scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	second.load_saved_on_startup = false
	editor.use_system_clipboard = false
	second.use_system_clipboard = false
	var payload: String = AtlasClipboard.encode_ink(
		[AtlasStroke.new(PackedVector2Array([Vector2.ZERO, Vector2(10, 5)]))], [0], Vector2.ZERO)
	editor.clipboard_text = payload
	editor.locked_to_cell = true
	_check(editor.clipboard_text == payload and editor.locked_to_cell,
		"compatibility state can be populated before the workspace enters the tree")
	root.add_child(scene)
	root.add_child(second_scene)
	for frame: int in range(6):
		await process_frame
	editor.edits.mark_saved()
	second.edits.mark_saved()
	_check(editor.clipboard_text == payload and not editor.locked_to_cell,
		"composition retains a supplied clipboard while initial navigation resets scope")
	_check(editor.paste_selection(), "pre-startup clipboard payload remains usable after composition")
	editor._on_undo()
	await _check_sidebar_expansion(editor)

	_check(editor.inspector.scene_file_path == "res://prefab/inspector.tscn",
		"fixed inspector is independently scene-authored")
	_check(editor.tool_palette.get_parent() == editor.sidebar.get_view_content(&"Tools") and editor.floor_picker.owner == editor.inspector,
		"palette is mounted in sidebar and floor controls remain inspector-owned")
	_check(editor.browser.scene_file_path == "res://prefab/campaign_browser.tscn"
		and editor.map_name_input.owner == editor.browser, "map form is independently scene-authored")
	_check(editor.navigator.views == editor.view_session and editor.navigator.history == editor.history,
		"navigation facade exposes its single state owner")
	_check(editor.navigator.views != second.navigator.views and editor.artwork != second.artwork,
		"workspaces have independent navigation and artwork sessions")

	var canvas: AtlasCanvas = editor.canvas
	var original_name: String = canvas.map.display_name
	var original_tags: Array[String] = canvas.map.tags.duplicate()
	editor.map_name_input.text = "Tower plan"
	editor.map_tags_input.text = "#Tower, TOWER, roof, #roof"
	editor.map_tags_input.text_submitted.emit(editor.map_tags_input.text)
	_check(canvas.map.display_name == "Tower plan" and canvas.map.tags == ["Tower", "roof"],
		"map form emits one typed metadata edit with normalized unique tags")
	editor._on_undo()
	_check(canvas.map.display_name == original_name and canvas.map.tags == original_tags,
		"one undo restores metadata submitted from the browser")
	_check(second.canvas.map.display_name == original_name and not second.edits.is_dirty(),
		"metadata editing cannot reach another workspace")

	editor.inspector.floor_created.emit("Loft")
	var loft: String = canvas.floor.id
	_check(canvas.floor.display_name == "Loft" and editor.floor_name_input.text == "Loft",
		"floor intent changes the document and refreshes the scene-owned form")
	editor.floor_picker.item_selected.emit(0)
	_check(canvas.floor.id == "ground", "floor picker maps a display index to its stable identity")
	editor.switch_floor(loft)
	var before_navigation: Dictionary = editor.campaign.to_dict()
	var before_command: AtlasEditCommand = editor.edits.get_undo_command()
	editor.browser.activate_map(editor.map_list_ids.find("greyhaven"))
	_check(canvas.map.id == "greyhaven" and editor.history.size() == 1,
		"browser Open is routed through the navigator")
	editor._on_back()
	_check(canvas.map.id == "world" and canvas.floor.id == loft,
		"Back from browser navigation restores the exact source floor")
	_check(editor.campaign.to_dict() == before_navigation and editor.edits.get_undo_command() == before_command,
		"browsing keeps canonical data and edit history unchanged")
	_check(second.canvas.floor.id == "ground" and second.history.is_empty(),
		"floor/view memory and Back history are not shared")

	var blank: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64.0)
	_check(editor.create_board("Module sketch", blank), "create a blank editing target")
	editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO, Vector2(20, 10)])), false)
	editor.select_all_artwork()
	var original: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
	editor.move_x_spinner.value = 30.0
	editor.move_y_spinner.value = -10.0
	(editor.inspector.get_node("%TransformButton") as Button).pressed.emit()
	_check(canvas.floor.strokes[0].points[0] == Vector2(30, -10),
		"numeric transform intent reaches scoped artwork editing")
	editor._on_undo()
	_check(AtlasStroke.same_artwork(original, canvas.floor.strokes), "numeric transform remains one reversible edit")
	editor.select_all_artwork()
	_check(editor.copy_selection() and editor.artwork.clipboard_text == editor.clipboard_text,
		"clipboard facade reads the artwork session's payload")
	_check(second.clipboard_text.is_empty(), "internal artwork clipboard is workspace-local")

	var canonical: Dictionary = editor.campaign.to_dict()
	var command: AtlasEditCommand = editor.edits.get_undo_command()
	editor.preview_picker.select(0)
	editor.preview_picker.item_selected.emit(0)
	editor.reference_checkbox.button_pressed = false
	editor.opacity_slider.value = 0.6
	editor.brush_width_spinner.value = 12.0
	editor.brush_color_picker.color_changed.emit(Color.BLUE)
	_check(canvas.preview == AtlasCanvas.Preview.OFF and not canvas.show_reference
		and is_equal_approx(canvas.reference_opacity, 0.6), "reference/preview controls update only the active canvas")
	_check(canvas.brush_width == 12.0 and canvas.brush_color == Color.BLUE,
		"brush controls keep their signal wiring without placement UI")
	_check(editor.campaign.to_dict() == canonical and editor.edits.get_undo_command() == command,
		"presentation and brush preferences never create document edits")

	editor.open_map("world", "ground")
	editor.lock_checkbox.button_pressed = true
	_check(editor.artwork.locked_to_cell and editor.locked_to_cell and not second.artwork.locked_to_cell,
		"scope control updates only its artwork session")
	var first_campaign: AtlasCampaign = editor.campaign
	editor._on_sample()
	_check(editor.campaign != first_campaign and editor.navigator.campaign == editor.campaign
		and editor.edits.active_map_id == editor.canvas.map.id, "campaign replacement rebinds navigation and edit target together")
	_check(editor.history.is_empty() and editor.map_list_ids.size() == 2,
		"campaign reset clears navigation and refreshes browsing")
	_check(second.campaign != editor.campaign and second.canvas.map.id == "world",
		"reset leaves a second workspace intact")
	_check(editor.create_floor("Reset floor") and first_campaign.get_map("world").floors.size() == 2,
		"post-reset commands edit the new campaign rather than the retained previous instance")

	root.remove_child(scene)
	scene.free()
	root.remove_child(second_scene)
	second_scene.free()
	print("ATLAS_EDITOR_MODULES_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)


func _check_sidebar_expansion(editor: AtlasEditor) -> void:
	var previous_size: Vector2i = root.size
	var previous_scale: Vector2i = root.content_scale_size
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1280, 800)
	root.size = root.content_scale_size
	editor.sidebar.select_view(&"Search")
	for frame: int in range(6):
		await process_frame
	var search_height: float = editor.search_list.size.y
	root.content_scale_size.y += 200
	root.size = root.content_scale_size
	for frame: int in range(6):
		await process_frame
	_check(editor.search_list.size.y > search_height + 100,
		"Search results expand into additional sidebar height")
	editor.sidebar.select_view(&"Layers")
	for frame: int in range(6):
		await process_frame
	var layers_height: float = editor.layer_panel.hierarchy.size.y
	root.content_scale_size.y += 200
	root.size = root.content_scale_size
	for frame: int in range(6):
		await process_frame
	_check(editor.layer_panel.hierarchy.size.y > layers_height + 100,
		"Layer hierarchy expands into additional sidebar height")
	root.content_scale_size = previous_scale
	root.size = previous_size
	editor.sidebar.select_view(&"Maps")
	for frame: int in range(6):
		await process_frame
