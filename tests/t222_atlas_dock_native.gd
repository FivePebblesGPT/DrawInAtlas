extends SceneTree
## T-222: Atlas hosts the same Drawing workspace Control. Dock clicks only
## change that workspace's view/layout; they never create another panel view.

var checks: int = 0
var failed: int = 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("T222_ATLAS_FAILED: " + label)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame


func click(at: Vector2, right: bool = false) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await frames(3)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1050, 720)
	# Mimic the embedded editor: the host owns the window and full-screen
	# surface; Drawing owns only its workspace subtree.
	var host: Control = Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(15)
	check(workspace.dock_toggle != null and workspace.dock_toggle.is_visible_in_tree(),
		"Atlas embedded workspace owns compact overlay")
	check(workspace.dock_views.size() == workspace.dock_layout.rail_icons("right").size(),
		"one view/control per stable dock panel")
	check(workspace.get_parent() == host and not workspace._window_quit_guard_enabled,
		"Drawing does not usurp Atlas window quit policy")
	# Hide tall Brushes view so Colors is visible to the pointer.
	check(workspace.dock_layout.set_panel_visible("brushes", false), "hide brush fixture")
	workspace._render_dock()
	await frames()
	var document_revision: int = workspace.current_document().revision
	var dirty: bool = workspace.current_document().is_dirty()
	await click((workspace.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(workspace.dock_layout.group_info("colors")["collapsed"],
		"embedded active-panel click collapses")
	await click((workspace.dock_tab_buttons["colors"] as Button).get_global_rect().get_center(), true)
	check(workspace.dock_panel_menu.visible and workspace.dock_layout.group_info("colors")["collapsed"],
		"Atlas RMB panel menu does not expand")
	workspace.dock_panel_menu.hide()
	await frames(3)
	await click(workspace.dock_toggle.get_global_rect().get_center())
	check(workspace.dock_layout.container_info("right")["minimized"],
		"embedded dock minimizes without changing Atlas host geometry")
	check(workspace.dock_layout.group_info("colors")["collapsed"],
		"embedded flyout/collapse persistence is separate")
	await click((workspace.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(workspace.dock_flyout.visible, "embedded panel icon opens overlay flyout")
	check(workspace.dock_views["colors"].get_parent() == workspace.dock_flyout_body,
		"original Colors view moved to flyout, not duplicated")
	await click(workspace.dock_toggle.get_global_rect().get_center())
	check(not workspace.dock_layout.container_info("right")["minimized"] and
		not workspace.dock_flyout.visible, "expanded dock closes transient flyout")
	check(workspace.current_document().revision == document_revision and
		workspace.current_document().is_dirty() == dirty,
		"embedded dock interactions preserve document revision/history")
	print("T222_ATLAS: %d checks; %d failed" % [checks, failed])
	print("T222_ATLAS_PASSED" if failed == 0 else "T222_ATLAS_FAILED")
	quit(1 if failed else 0)
