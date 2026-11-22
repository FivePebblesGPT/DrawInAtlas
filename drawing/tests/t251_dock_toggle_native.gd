extends SceneTree
## T-251: native pointer, keyboard and framebuffer verification of the dock-owned
## toggle in both layout modes. X11 rendering is required; this is not owner UX signoff.

const PREFS: String = "user://t251-dock-toggle-layout.json"
var checks: int = 0
var failures: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T251_DOCK_FAILED: " + message)


func frames(count: int = 8) -> void:
	for _index: int in range(count):
		await process_frame


func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await frames(3)


func key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)
		await frames(4)


func overlaps(a: Rect2, b: Rect2) -> bool:
	var intersection: Rect2 = a.intersection(b)
	return intersection.size.x > 0.5 and intersection.size.y > 0.5


func check_geometry(app: Control, minimized: bool, label: String) -> void:
	var toggle: Button = app.dock_toggle
	var bounds: Rect2 = app.inspector.get_global_rect()
	var area: Rect2 = toggle.get_global_rect()
	check(toggle.visible and toggle.is_visible_in_tree() and toggle.size.x <= 32.0 and toggle.size.y <= 60.0,
		label + ": one visible, bounded vector half-circle")
	check(area.position.x >= bounds.position.x - 0.5 and area.end.x <= bounds.end.x + 0.5 and
		area.position.y >= bounds.position.y - 0.5 and area.end.y <= bounds.end.y + 0.5,
		label + ": whole hit rect is inside PanelDock")
	check(absf(area.position.x - bounds.position.x) <= 1.0 and
		absf(area.position.y - bounds.position.y) <= 1.0,
		label + ": same dock-relative anchor at top left")
	check(not overlaps(area, app.canvas.get_global_rect()),
		label + ": toggle never captures canvas pointer area")
	if minimized:
		check(toggle.get_parent() == app.dock_toggle_slot and not toggle.top_level and
			app.dock_toggle_slot.get_parent() == app.dock_rail and app.dock_rail.get_child(0) == app.dock_toggle_slot,
			label + ": toggle is first real child of VBox rail slot")
		check(app.dock_toggle_slot.visible and app.dock_toggle_slot.size.y >= 56.0 and
			app.dock_rail.visible and not app.dock_panel_gutter.visible,
			label + ": slot contributes its height to minimized layout")
		for item: Button in app.dock_rail_buttons.values():
			check(item.get_global_rect().position.y >= area.end.y - 0.5 and
				not overlaps(area, item.get_global_rect()),
				label + ": rail icon starts after toggle's reserved slot")
	else:
		check(toggle.top_level and toggle.get_parent() == app.inspector and
			not app.dock_toggle_slot.visible and app.dock_panel_gutter.visible,
			label + ": overlay is dock-owned, scroll-independent and slot is hidden")
		check(app.dock_panel_gutter.get_theme_constant("margin_left") >= 34 and
			app.dock_panels.get_parent() == app.dock_panel_gutter,
			label + ": expanded content uses horizontal, not vertical gutter")
		for node: Node in app.dock_panel_gutter.find_children("*", "Button", true, false):
			var button: Button = node as Button
			if button.is_visible_in_tree():
				check(not overlaps(area, button.get_global_rect()),
					label + ": no scrolled button under toggle: " + button.name)


func shot(name: String) -> void:
	var destination: String = OS.get_environment("T251_SCREENSHOTS")
	if destination.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(destination)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(destination.path_join(name + ".png")) == OK,
		"native framebuffer saved: " + name)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 renderer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1180, 750)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(18)
	var source_revision: int = app.current_document().revision
	var source_dirty: bool = app.current_document().is_dirty()
	check(app.dock_layout.set_panel_visible("brushes", false), "use compact panel fixture")
	app._render_dock()
	await frames()
	check_geometry(app, false, "initial expanded")
	await shot("expanded")
	var previous_slot: HBoxContainer = app.dock_toggle_slot
	var previous_toggle: Button = app.dock_toggle
	await click(previous_toggle.get_global_rect().get_center())
	check(bool(app.dock_layout.container_info("right")["minimized"]), "real LMB minimizes dock")
	check_geometry(app, true, "minimized")
	check(app.dock_rail.get_child_count() == app.dock_rail_buttons.size() + 3,
		"toggle slot persisted alongside three icon groups and separators")
	await shot("minimized")
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(app.dock_flyout.visible, "flyout still opens below unobstructed icon")
	check_geometry(app, true, "flyout visible")
	await shot("flyout")
	# A dock model refresh must never delete/recreate the slot or button.
	app._render_dock()
	await frames()
	check(app.dock_toggle_slot == previous_slot and app.dock_toggle == previous_toggle and
		app.dock_rail.get_child(0) == previous_slot,
		"re-render preserves same toggle and fixed slot identity")
	await click(app.dock_toggle.get_global_rect().get_center())
	check(not bool(app.dock_layout.container_info("right")["minimized"]) and not app.dock_flyout.visible,
		"real LMB expands and closes transient flyout")
	check_geometry(app, false, "re-expanded")
	app.dock_toggle.grab_focus()
	await frames(3)
	await key(KEY_ENTER)
	check(bool(app.dock_layout.container_info("right")["minimized"]), "keyboard Enter minimizes the dock")
	check(app.dock_toggle.has_focus(), "focus remains on persistent toggle after reparent")
	await key(KEY_ENTER)
	check(not bool(app.dock_layout.container_info("right")["minimized"]), "keyboard Enter expands the dock")
	# Scroll groups under the fixed overlay: no clickable icon may reach its hit area.
	app.inspector.scroll_vertical = 350
	await frames(10)
	check_geometry(app, false, "scrolled expanded")
	app.inspector.scroll_vertical = 0
	await frames()
	# Floating a group neither steals the toggle nor overlaps its geometry.
	var host_id: String = app.float_group("layers")
	await frames(10)
	check(not host_id.is_empty() and app.floating_hosts.size() == 1,
		"group floating remains available while dock has new overlay hierarchy")
	check_geometry(app, false, "floating group")
	await shot("floating")
	# Keep the floating fixture clear of the dock at extreme simulated DPI.
	# Native controls overlap in a 590-logical-pixel client if the floating
	# window is left straddling the right dock; that is not a dock-toggle hit test.
	var floating: DrawingFloatingHost = app.floating_hosts[host_id] as DrawingFloatingHost
	floating.set_host_rect(Rect2(Vector2(8, 65), Vector2(220, 235)))
	await frames()

	# Responsive/HiDPI geometry and click handling, both dock states.
	root.size = Vector2i(420, 420)
	await frames(15)
	check(app.canvas.size.x >= 125.0, "420px window retains usable editing viewport")
	check_geometry(app, false, "narrow expanded")
	await shot("narrow")
	root.size = Vector2i(1180, 750)
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(16)
		check_geometry(app, false, "expanded %d%%" % roundi(100.0 * scale))
		await click(app.dock_toggle.get_global_rect().get_center())
		check(bool(app.dock_layout.container_info("right")["minimized"]),
			"DPI-scaled native pointer minimizes at %d%%" % roundi(scale * 100.0))
		check_geometry(app, true, "minimized %d%%" % roundi(100.0 * scale))
		await shot("minimized-%d" % roundi(100.0 * scale))
		await click(app.dock_toggle.get_global_rect().get_center())
		check(not bool(app.dock_layout.container_info("right")["minimized"]),
			"DPI-scaled native pointer expands at %d%%" % roundi(scale * 100.0))
	root.content_scale_factor = 1.0
	await frames(14)
	# Restart from minimized settings: recover the slot, not a top-level button.
	await click(app.dock_toggle.get_global_rect().get_center())
	app.layout_settings_path = PREFS
	app.layout_persistence_enabled = true
	check(app._save_workspace_layout(), "save minimized group state")
	app.queue_free()
	await frames(10)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_settings_path = PREFS
	reopened.layout_persistence_enabled = true
	reopened.preferences_persistence_enabled = false
	root.add_child(reopened)
	await frames(18)
	check(reopened.layout_recovery_status == "loaded" and
		bool(reopened.dock_layout.container_info("right")["minimized"]),
		"restart restores minimized group state")
	check_geometry(reopened, true, "restarted minimized")
	await click(reopened.dock_toggle.get_global_rect().get_center())
	check_geometry(reopened, false, "restarted expanded")
	check(reopened.current_document().revision == source_revision and
		reopened.current_document().is_dirty() == source_dirty,
		"dock state/geometry does not mutate document revision or dirty flag")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("T251_DOCK: %d checks; %d failures" % [checks, failures])
	print("T251_DOCK_PASSED" if failures == 0 else "T251_DOCK_FAILED")
	quit(1 if failures else 0)
