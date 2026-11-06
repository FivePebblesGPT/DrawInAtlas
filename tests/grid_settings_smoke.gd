extends SceneTree
## T-008: toolbar popup owns grid configuration, edit masks remain separate.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GRID SETTINGS FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame

	var popup: AtlasGridSettingsPopup = editor.grid_settings_popup
	var form: AtlasGridControls = editor.grid_controls
	var map: AtlasMapDocument = editor.canvas.map
	var floor: AtlasFloor = editor.canvas.floor
	_check(popup.get_node("Panel/Margin/Layout/Scroll/GridControls") == form,
		"board configuration is owned by the popup, not inspector")
	_check(not editor.inspector.has_node("Scroll/Margin/Sections/MapSection/GridControls"),
		"inspector has no duplicate always-visible grid form")
	_check(editor.inspector.lock_checkbox.get_parent().get_node("Heading").text == "EDIT MASK",
		"edit mask is labeled separately from grid configuration")
	_check(editor.grid_settings_button.text == "Grid" and editor.grid_settings_button.icon != null,
		"toolbar uses a recognizable icon and short action label")
	_check(editor.grid_settings_button.tooltip_text.contains("shape"),
		"grid toolbar action explains available settings")
	_check(form.get_grid().same_as(map.grid), "popup begins with current board grid")
	_check(not popup.visible, "settings remain hidden until toolbar activation")

	editor.grid_settings_button.pressed.emit()
	await process_frame
	_check(popup.visible, "toolbar action opens the popup")
	_check(form.get_grid().same_as(map.grid), "opening reads current grid")
	var geometry: AtlasGrid = map.grid.copy()
	var stroke: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2(1.125, 2.5), Vector2(45.75, 9.0)]))
	editor._on_stroke(stroke, false)
	var ink: Array[AtlasStroke] = AtlasStroke.clone_all(floor.strokes)
	form.size_spinner.value = geometry.cell_size + 17.0
	_check(is_equal_approx(map.grid.cell_size, geometry.cell_size + 17.0),
		"popup applies cell spacing through history")
	_check(editor.edits.can_undo(), "grid edits join undo history")
	_check(AtlasStroke.same_artwork(floor.strokes, ink), "grid change never rescales ink")
	editor._on_undo()
	_check(map.grid.same_as(geometry), "undo restores the entire original grid")
	_check(is_equal_approx(form.size_spinner.value, geometry.cell_size),
		"undo synchronizes the open popup")
	editor._on_redo()
	_check(is_equal_approx(form.size_spinner.value, geometry.cell_size + 17.0),
		"redo synchronizes the open popup")
	var applied: AtlasGrid = map.grid.copy()
	applied.origin = Vector2(41.5, -20.25)
	applied.rotation = deg_to_rad(21.0)
	applied.distance_per_cell = 3.25
	applied.distance_unit = "km"
	applied.visible = false
	applied.kind = AtlasGrid.Kind.SQUARE
	editor.apply_grid(applied)
	_check(form.get_grid().same_as(applied), "all settings refresh from command changes")
	_check(not form.visibility_checkbox.button_pressed and form.unit_picker.get_item_text(form.unit_picker.selected) == "km",
		"overlay and measurement values are visible in the popup")
	_check(AtlasStroke.same_artwork(floor.strokes, ink), "all geometry/units retain board coordinates")

	popup.hide()
	var changed: AtlasGrid = map.grid.copy()
	changed.kind = AtlasGrid.Kind.GRIDLESS
	editor.apply_grid(changed)
	_check(editor.lock_checkbox.disabled, "edit-mask availability still follows grid geometry")
	editor.grid_settings_button.pressed.emit()
	await process_frame
	_check(form.get_grid().same_as(changed) and form.shape_picker.selected == AtlasGrid.Kind.GRIDLESS,
		"reopening reads even external grid changes")
	_check(not form.size_spinner.editable and form.visibility_checkbox.disabled,
		"gridless option disables irrelevant grid settings")
	popup.done_button.pressed.emit()
	await process_frame
	_check(not popup.visible, "Done dismisses the settings popup")
	_check(editor.inspector.lock_checkbox.get_parent().is_visible_in_tree(),
		"edit-mask control remains available outside the popup")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_GRID_SETTINGS_PASSED (%d checks)" % checks if failures == 0 else
		"ATLAS_GRID_SETTINGS_FAILED (%d/%d checks)" % [failures, checks])
	quit(0 if failures == 0 else 1)
