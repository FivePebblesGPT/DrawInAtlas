extends SceneTree
## T-254: icon-only tabs in the canonical embedded Drawing host used by Atlas.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T254_ATLAS_FAILED: " + label)


func frames(n: int = 7) -> void:
	for _i: int in range(n):
		await process_frame


func click(control: Control) -> void:
	var target: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = target
		event.global_position = target
		root.push_input(event, true)
		await frames(4)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1150, 760)
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(19)
	var layout: DrawingDockLayout = workspace.dock_layout
	var revision: int = workspace.current_document().revision
	var dirty: bool = workspace.current_document().is_dirty()
	var original: Dictionary = workspace.dock_views.duplicate()
	check(layout.merge_groups("layers", "colors", 1), "merge two panels in Atlas Drawing host")
	check(layout.set_group_collapsed("colors", true), "preserve group collapse bit")
	workspace._render_dock()
	await frames()
	await click(workspace.dock_toggle)
	await click(workspace.dock_rail_buttons["colors"])
	check(workspace.dock_flyout.visible, "Atlas host opens transient flyout")
	for panel: String in ["colors", "layers"]:
		var tab: Button = workspace.dock_flyout_tabs.get_node("Tab_" + panel) as Button
		check(tab.text.is_empty() and tab.icon == workspace._dock_icon(panel) and
			tab.icon == (workspace.dock_rail_buttons[panel] as Button).icon,
			panel + " uses same icon in Atlas flyout")
		check(tab.custom_minimum_size == Vector2(42, 42) and tab.focus_mode == Control.FOCUS_ALL,
			panel + " is compact and keyboard accessible")
	await click(workspace.dock_flyout_tabs.get_node("Tab_layers"))
	check(layout.group_info("colors")["active"] == "layers" and
		workspace.dock_views["layers"] == original["layers"],
		"switching Atlas flyout tabs keeps original Drawing panel")
	check(bool(layout.group_info("colors")["collapsed"]),
		"Atlas flyout switch does not change collapsed group")
	await click(workspace.dock_flyout_tabs.get_node("Tab_layers"))
	check(workspace.dock_flyout.visible and
		(workspace.dock_flyout_tabs.get_node("Tab_layers") as Button).button_pressed,
		"active Atlas flyout icon remains pressed")
	await click(workspace.dock_toggle)
	check(not workspace.dock_flyout.visible and not bool(layout.container_info("right")["minimized"]),
		"reexpand hides the flyout without losing tabs")
	check(workspace.current_document().revision == revision and workspace.current_document().is_dirty() == dirty,
		"Atlas Drawing history/persistence unchanged")
	print("T254_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T254_ATLAS_PASSED" if failures == 0 else "T254_ATLAS_FAILED")
	quit(1 if failures else 0)
