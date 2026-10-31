extends SceneTree
## T-007: icon affordances must retain discoverable names and working actions.

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("COMPACT CONTROLS FAILED: " + message)


func _run() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	var panel: AtlasLayerPanel = editor.layer_panel
	var actions: HBoxContainer = panel.get_node("Order")
	var floor_actions: HBoxContainer = editor.inspector.get_node("Scroll/Margin/Sections/FloorSection/FloorActions")
	_check(actions.get_child_count() == 5, "five layer commands share one toolbar")
	_check(floor_actions.get_child_count() == 4, "four floor commands share one toolbar")
	for group: HBoxContainer in [actions, floor_actions]:
		for child: Node in group.get_children():
			var button: Button = child as Button
			_check(button != null and button.text.is_empty() and button.icon != null,
				"%s uses a rendered icon instead of a text-only action" % child.name)
			_check(button != null and not button.accessibility_name.is_empty()
				and not button.tooltip_text.is_empty() and button.focus_mode == Control.FOCUS_ALL,
				"%s supports keyboard and accessibility discovery" % child.name)
	_check(editor.inspector.get_node("Scroll/Margin/Sections/FloorSection/FloorRemove").text == "Delete floor"
		and editor.inspector.get_node("Scroll/Margin/Sections/FloorSection/FloorDefault").text == "Make default",
		"destructive and ambiguous commands retain clear text")
	_check(panel.get_node("ShowEditingDetail").text == "Show editing layer detail",
		"hidden edit-target recovery retains explicit text")
	var floor: AtlasFloor = editor.canvas.floor
	var original_layers: int = floor.layers.size()
	panel.get_node("Order/NewInkButton").pressed.emit()
	_check(floor.layers.size() == original_layers + 1 and floor.layer_by_id(editor.canvas.active_layer_id) is AtlasInkLayer,
		"new ink icon creates and selects an ink layer")
	panel.get_node("Order/NewRasterButton").pressed.emit()
	_check(floor.layers.size() == original_layers + 2 and floor.layer_by_id(editor.canvas.active_layer_id) is AtlasRasterLayer,
		"new raster icon retains its original command")
	var selected: String = editor.canvas.active_layer_id
	_check(panel.get_node("Order/RaiseButton").disabled and not panel.get_node("Order/LowerButton").disabled, "layer toolbar reflects topmost selection bounds")
	panel.get_node("Order/LowerButton").pressed.emit()
	_check(floor.layer_by_id(selected) != null and floor.layers[-1].id != selected,
		"lower icon reorders the selected layer")
	panel.get_node("Order/RaiseButton").pressed.emit()
	_check(floor.layers[-1].id == selected, "raise icon restores the selected layer")
	var floor_section: VBoxContainer = editor.inspector.get_node("Scroll/Margin/Sections/FloorSection")
	var before: int = editor.canvas.map.floors.size()
	var name_input: LineEdit = floor_section.get_node("FloorNameInput")
	name_input.text = "New floor via icon"
	floor_actions.get_node("FloorAdd").pressed.emit()
	_check(editor.canvas.map.floors.size() == before + 1, "add-floor icon preserves creation")
	_check(not floor_actions.get_node("FloorDown").disabled, "down-floor icon enabled for last floor")
	_check(floor_actions.get_node("FloorUp").disabled, "up-floor icon disabled for last floor")
	name_input.text = "Renamed via icon"
	floor_actions.get_node("FloorRename").pressed.emit()
	_check(editor.canvas.floor.display_name == "Renamed via icon", "rename icon preserves rename")
	floor_actions.get_node("FloorDown").pressed.emit()
	_check(editor.canvas.map.floors[0].id == editor.canvas.floor.id, "lower-floor icon preserves ordering")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_COMPACT_CONTROLS_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
