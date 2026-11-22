extends SceneTree
## T-222: actual X11 mouse, keyboard, layout and framebuffer checks for the
## compact dock edge and stable panel-icon activation semantics.

var checks: int = 0
var failed: int = 0


func check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("T222_NATIVE_FAILED: " + title)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame


func mouse(point: Vector2, down: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = index
	event.pressed = down
	root.push_input(event, true)


func click(point: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	mouse(point, true, index)
	await frames(2)
	mouse(point, false, index)
	await frames(7)


func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(9, 0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func menu_key() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F10
	event.shift_pressed = true
	event.pressed = true
	root.push_input(event, true)
	await frames(4)
	event.pressed = false
	root.push_input(event, true)
	await frames(4)


func screenshot(label: String) -> void:
	var target: String = OS.get_environment("T222_SCREENSHOTS")
	if target.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(target)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(target.path_join(label + ".png")) == OK,
		"saved native screenshot " + label)


func layout_group_collapsed(snapshot: Dictionary, group_id: String) -> bool:
	for container: Dictionary in snapshot["containers"]:
		for group: Dictionary in container["groups"]:
			if group["id"] == group_id:
				return group["collapsed"]
	return false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1180, 750)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(15)
	var layout: DrawingDockLayout = app.dock_layout
	var baseline_revision: int = app.current_document().revision
	var baseline_dirty: bool = app.current_document().is_dirty()
	check(layout.set_panel_visible("brushes", false), "hide large brush fixture to reveal panel icons")
	app._render_dock()
	await frames(5)
	check(app.dock_toggle != null and app.dock_toggle.visible and app.dock_toggle.top_level and
		app.dock_toggle.get_parent() == app.inspector,
		"expanded toggle is a non-scrolling overlay owned by PanelDock")
	check(app.dock_panels.get_node_or_null("MinimizeDock") == null and
		app.dock_rail.get_node_or_null("ExpandDock") == null,
		"no giant minimize or expand rows")
	check(app.dock_toggle.get_global_rect().position.x >= app.inspector.get_global_rect().position.x and
		app.dock_toggle.get_global_rect().end.x <= app.inspector.get_global_rect().position.x + 34 and
		app.dock_panels.get_parent() == app.dock_panel_gutter,
		"dock-local overlay fits inside the panel gutter, not the canvas")
	check(app.dock_toggle.size.x <= 32 and app.dock_toggle.size.y <= 60,
		"compact logical toggle footprint")
	await screenshot("expanded")
	# Expanded singleton: active icon closes exactly its body; second click reopens.
	await click((app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(layout.group_info("colors")["collapsed"], "active expanded icon collapses singleton")
	await click((app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(not layout.group_info("colors")["collapsed"], "active collapsed icon re-expands")
	var icon_before_drag: Button = app.dock_tab_buttons["colors"]
	var small_drag_start: Vector2 = icon_before_drag.get_global_rect().get_center()
	mouse(small_drag_start, true)
	await frames(2)
	motion(small_drag_start + Vector2(4, 0))
	await frames(2)
	check(not app.dock_drag.is_dragging(), "motion below seven pixels remains a click")
	mouse(small_drag_start + Vector2(4, 0), false)
	await frames(7)
	check(layout.group_info("colors")["collapsed"], "subthreshold movement still activates icon")
	await click((app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(not layout.group_info("colors")["collapsed"], "subthreshold click is reversible")
	# Group two stable icons; inactive click changes active and expands if needed.
	check(layout.merge_groups("layers", "colors", 1), "group colors and layers")
	app._render_dock()
	await frames()
	await click((app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center())
	check(layout.group_info("colors")["active"] == "layers" and
		not layout.group_info("colors")["collapsed"], "inactive icon selects without collapsing")
	await click((app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center())
	check(layout.group_info("colors")["collapsed"], "active grouped icon collapses shared group")
	await click((app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(layout.group_info("colors")["active"] == "colors" and
		not layout.group_info("colors")["collapsed"], "inactive icon selects and expands collapsed group")
	var before_menu: Dictionary = layout.snapshot()
	await click((app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(app.dock_panel_menu.visible and app._dock_menu_panel_id == "layers", "RMB opens clicked-panel menu")
	check(layout.snapshot() == before_menu, "RMB never selects or collapses group")
	check(app.dock_panel_menu.get_item_text(app.dock_panel_menu.get_item_index(3)) == "Float this panel",
		"menu contains individual-panel action")
	app.dock_panel_menu.hide()
	await frames(3)
	(app.dock_tab_buttons["layers"] as Button).grab_focus()
	await menu_key()
	check(app.dock_panel_menu.visible and app._dock_menu_panel_id == "layers",
		"Shift+F10 works without changing active panel")
	check(layout.snapshot() == before_menu, "keyboard menu open is not an activation")
	app.dock_panel_menu.hide()
	await frames(3)
	# The per-panel menu moves an *inactive* icon without switching it.
	app._show_dock_panel_menu("layers", (app.dock_tab_buttons["layers"] as Button).global_position)
	app.dock_panel_menu.hide()
	app._dock_panel_menu_action(0)
	await frames(5)
	check(layout.group_info("colors")["panels"] == ["layers", "colors"] and
		layout.group_info("colors")["active"] == "colors", "RMB left action targets inactive tab")
	app._show_dock_panel_menu("layers", (app.dock_tab_buttons["layers"] as Button).global_position)
	app.dock_panel_menu.hide()
	app._dock_panel_menu_action(1)
	await frames(5)
	check(layout.group_info("colors")["panels"] == ["colors", "layers"],
		"RMB right action reverses inactive tab move")
	# Previewing a drag inside the source icon must never trigger collapse.
	var button: Button = app.dock_tab_buttons["colors"]
	var drag_start: Vector2 = button.get_global_rect().get_center()
	mouse(drag_start, true)
	await frames(2)
	motion(drag_start + Vector2(10, 0))
	await frames(2)
	check(app.dock_drag.is_dragging(), "7px explicit drag threshold wins")
	mouse(drag_start + Vector2(10, 0), false)
	await frames(8)
	check(not layout.group_info("colors")["collapsed"], "releasing drag on source icon never collapses")
	# Right clicking context menu action uses panel target, not active tab.
	app._show_dock_panel_menu("layers", (app.dock_tab_buttons["layers"] as Button).global_position)
	app.dock_panel_menu.hide()
	app._dock_panel_menu_action(2)
	await frames(5)
	check(layout.group_of("layers") != "colors" and layout.group_info("colors")["active"] == "colors",
		"menu splits *clicked* inactive panel transactionally")
	# Whole-dock minimize is separate from the existing group collapse bit.
	check(layout.set_group_collapsed("colors", true), "prepare collapsed group")
	app._render_dock()
	await frames(4)
	var selected_before: String = layout.group_info("colors")["active"]
	await click(app.dock_toggle.get_global_rect().get_center())
	check(layout.container_info("right")["minimized"] and app.dock_toggle.visible and
		app.dock_toggle.minimized and not app.dock_toggle.top_level and
		app.dock_toggle.get_parent() == app.dock_toggle_slot,
		"half-circle moves into a genuine rail slot on minimize")
	check(app.inspector.size.x <= 55 and app.dock_rail.visible and not app.dock_panels.visible,
		"minimized rail is narrow without an expand button row")
	check(layout.group_info("colors")["collapsed"], "minimizing does not reset collapse bit")
	await screenshot("minimized")
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(layout.container_info("right")["flyout_group"] == "colors" and app.dock_flyout.visible,
		"rail icon opens transient flyout even for collapsed group")
	check(layout.group_info("colors")["collapsed"], "flyout does not expand persisted group")
	await screenshot("flyout")
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(layout.container_info("right")["flyout_group"] == "" and not app.dock_flyout.visible,
		"active rail icon hides flyout")
	before_menu = layout.snapshot()
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(app.dock_panel_menu.visible and layout.snapshot() == before_menu,
		"rail right-click menu leaves flyout and collapse state intact")
	app.dock_panel_menu.hide()
	await frames(3)
	await click(app.dock_toggle.get_global_rect().get_center())
	check(not layout.container_info("right")["minimized"] and
		layout.group_info("colors")["collapsed"] and layout.group_info("colors")["active"] == selected_before,
		"expanding restores previous group collapse and tab selection")
	check(app.current_document().revision == baseline_revision and
		app.current_document().is_dirty() == baseline_dirty, "dock interaction never edits document or history")
	# A 420px window must preserve a canvas and a discoverable overlaid toggle.
	root.size = Vector2i(420, 420)
	await frames(12)
	check(app.canvas.size.x >= 125 and app.inspector.get_global_rect().end.x <= 421,
		"narrow dock does not consume the canvas")
	check(app.dock_toggle.visible and app.dock_toggle.get_global_rect().position.x >=
		app.inspector.get_global_rect().position.x and app.dock_toggle.get_global_rect().end.x <=
		app.inspector.get_global_rect().position.x + 34, "dock-local overlay tracks narrow split")
	await screenshot("narrow")
	# Simulate scaled desktop content. The vector semicircle must remain a
	# small seam overlay without clipping the editor in either DPI setting.
	root.size = Vector2i(1180, 750)
	for ui_scale: float in [1.5, 2.0]:
		root.content_scale_factor = ui_scale
		await frames(14)
		var seam: Rect2 = app.dock_toggle.get_global_rect()
		var dock: Rect2 = app.inspector.get_global_rect()
		check(app.dock_toggle.is_visible_in_tree() and seam.size.x <= 32 and
			absf(seam.position.x - dock.position.x) <= 3.0 and seam.end.x <= dock.position.x + 34.0,
			"vector toggle remains inside panel dock at %.0f%%" % (ui_scale * 100.0))
		check(app.canvas.size.x >= 125 and app.dock_toggle.get_global_rect().position.x >= 0,
			"scaled dock leaves visible canvas and reachable toggle at %.0f%%" % (ui_scale * 100.0))
		await screenshot("scale-%d" % roundi(ui_scale * 100.0))
	root.content_scale_factor = 1.0
	await frames(10)
	# Persist collapsed, active, group order and dock minimized independently.
	var settings: String = "user://t222-native-layout.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	app.layout_settings_path = settings
	app.layout_persistence_enabled = true
	check(app._save_workspace_layout(), "dock preference file saved")
	var persisted: Dictionary = DrawingDockPersistence.read_file(settings)
	check(not persisted.is_empty(), "persisted layout decodes")
	var snapshot: Dictionary = layout.snapshot()
	app.queue_free()
	await frames(8)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_settings_path = settings
	reopened.layout_persistence_enabled = true
	reopened.preferences_persistence_enabled = false
	root.add_child(reopened)
	await frames(15)
	check(reopened.layout_recovery_status == "loaded", "dock recovers saved layout on restart")
	check(reopened.dock_layout.group_info("colors")["collapsed"] == layout_group_collapsed(snapshot, "colors") and
		reopened.dock_layout.group_info("colors")["active"] == selected_before,
		"persisted collapse and active selection restored")
	check(reopened.dock_toggle.visible and not reopened.dock_toggle.minimized,
		"overlay survives restart in expanded state")
	# Float is an actual transaction from the context menu, not a second copy.
	reopened._show_dock_panel_menu("layers", (reopened.dock_tab_buttons["layers"] as Button).global_position)
	reopened.dock_panel_menu.hide()
	reopened._dock_panel_menu_action(3)
	await frames(7)
	check(reopened.dock_layout.owner_of("layers") != "right" and reopened.floating_hosts.size() == 1,
		"RMB float action moves clicked panel into single floating host")
	check(reopened.dock_views["layers"].get_parent() != reopened.dock_stash and
		reopened.dock_layout.rail_icons("right").size() == 2,
		"float does not duplicate or orphan original panel view")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	print("T222_NATIVE: %d checks; %d failed" % [checks, failed])
	print("T222_NATIVE_PASSED" if failed == 0 else "T222_NATIVE_FAILED")
	quit(1 if failed else 0)
