extends SceneTree
## T-256: floating tabs need the same pointer/keyboard context affordances as the dock.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T256_NATIVE_FAILED: " + label)


func frames(count: int = 5) -> void:
	for _step: int in range(count):
		await process_frame


func mouse(at: Vector2, down: bool, which: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = which
	event.position = at
	event.global_position = at
	event.pressed = down
	root.push_input(event, true)


func click(at: Vector2, which: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	mouse(at, true, which)
	await frames(3)
	mouse(at, false, which)
	await frames(6)


func key(value: Key, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = value
		event.pressed = down
		event.shift_pressed = shift
		root.push_input(event, true)
		await frames(4)


func shot(name: String) -> void:
	var directory: String = OS.get_environment("T256_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var capture_status: int = root.get_texture().get_image().save_png(directory.path_join(name + ".png"))
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: drawing/tests/t256_floating_tab_menu_native.gd: " + str(capture_status))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "can float Colors")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	host.set_host_rect(Rect2(230, 120, 288, 385))
	for panel: String in ["layers", "brushes", "history"]:
		check(app.move_group_to_floating(panel, host_id), "merge " + panel)
		await frames(5)
	var group_id: String = app.dock_layout.group_of("colors")
	check(app.dock_layout.select_panel("history"), "select History to test inactive context")
	app._render_dock()
	await frames(8)
	var panel_menu: PopupMenu = host.get_node_or_null("FloatingPanelContextMenu") as PopupMenu
	var group_menu: PopupMenu = host.get_node_or_null("FloatingGroupContextMenu") as PopupMenu
	check(panel_menu != null, "panel context menu exists as a real PopupMenu")
	check(group_menu != null, "grip context menu exists as a real PopupMenu")
	if panel_menu == null or group_menu == null:
		print("T256_NATIVE: %d checks; %d failed" % [checks, failures])
		quit(1)
		return
	var before: Dictionary = app.dock_layout.snapshot()
	var brushes: Button = host.tab_buttons["brushes"] as Button
	await click(brushes.get_global_rect().get_center())
	check(panel_menu.visible and host._menu_panel_id == "brushes",
		"RMB targets an inactive floating icon, not selected History")
	check(app.dock_layout.snapshot() == before,
		"RMB does not select/collapse/float the panel or write a transaction")
	check(not panel_menu.is_item_disabled(panel_menu.get_item_index(0)) and
		not panel_menu.is_item_disabled(panel_menu.get_item_index(1)),
		"menu enables valid reordering in both directions")
	await shot("inactive-icon-menu")
	panel_menu.hide()
	await frames(4)
	# The action uses the tab under the prior RMB, even though History is active.
	host._floating_panel_menu_action(0)
	await frames(6)
	check(app.dock_layout.group_info(group_id)["panels"] == ["colors", "brushes", "layers", "history"],
		"Move left changes only context-target Brushes, not the active History tab")
	check(app.dock_layout.group_info(group_id)["active"] == "history",
		"moving an inactive tab keeps active panel and its view")
	# Shift+F10 focuses an icon and opens its menu without changing active state.
	(host.tab_buttons["layers"] as Button).grab_focus()
	await frames(3)
	await key(KEY_F10, true)
	check(panel_menu.visible and host._menu_panel_id == "layers",
		"Shift+F10 opens context of the focused inactive floating icon")
	check(app.dock_layout.group_info(group_id)["active"] == "history",
		"keyboard menu cannot select its focused inactive tab")
	panel_menu.hide()
	await frames(4)
	# A clipped tab can overlap the grip in Godot's reported global geometry.
	host.set_host_rect(Rect2(220, 120, 236, 390))
	var future: VBoxContainer = VBoxContainer.new()
	future.name = "FuturePanel"
	app.dock_stash.add_child(future)
	app.dock_views["future"] = future
	check(app.dock_layout.register_panel("future") and
		app.dock_layout.attach_panel("future", "right", "future"),
		"register future panel")
	app._render_dock()
	await frames(5)
	check(app.move_group_to_floating("future", host_id), "overflow host with a fifth icon")
	await frames(6)
	var strip: ScrollContainer = host.tab_strips[group_id]
	strip.scroll_horizontal = int(strip.get_h_scroll_bar().max_value)
	await frames(8)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var grip_point: Vector2 = grip.get_global_rect().position + Vector2(10, 19)
	check((host.tab_buttons["colors"] as Button).get_global_rect().has_point(grip_point) and
		not strip.get_global_rect().has_point(grip_point),
		"hidden Colors rectangle projects over grip")
	panel_menu.hide()
	group_menu.hide()
	before = app.dock_layout.snapshot()
	await click(grip_point)
	check(group_menu.visible and host._menu_group_id == group_id and not panel_menu.visible,
		"RMB on grip opens group menu, not clipped Colors tab")
	check(app.dock_layout.snapshot() == before, "grip menu leaves tab identity/order intact")
	await shot("grip-menu-clipped")
	group_menu.hide()
	await frames(4)
	# Keyboard context on the grip resolves the *group*, not whichever tab is active.
	grip.grab_focus()
	await frames(3)
	await key(KEY_MENU)
	check(group_menu.visible and host._menu_group_id == group_id,
		"Menu key opens group menu when the grip is focused")
	group_menu.hide()
	await frames(4)
	# The same visible-region rule applies at HiDPI scaling, not only 100%.
	for factor: float in [1.5, 2.0]:
		root.content_scale_factor = factor
		await frames(12)
		host.set_host_rect(Rect2(220, 120, 236, 390))
		strip = host.tab_strips[group_id]
		strip.scroll_horizontal = int(strip.get_h_scroll_bar().max_value)
		await frames(9)
		grip = host._header.get_node("MoveHandle") as Button
		grip_point = grip.get_global_rect().position + Vector2(10, 19) * factor
		panel_menu.hide()
		group_menu.hide()
		await click(grip_point)
		check(group_menu.visible and not panel_menu.visible,
			"HiDPI %d%% clipped tab cannot take grip context" % roundi(factor * 100.0))
		group_menu.hide()
		await frames(4)
	root.content_scale_factor = 1.0
	await frames(12)
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"context menus do not touch document or history")
	# Docking via the context menu moves this *whole group* exactly once.
	host._floating_group_menu_action(0)
	await frames(9)
	check(app.dock_layout.owner_of("colors") == "right" and
		app.dock_layout.owner_of("future") == "right",
		"group action docks all tabs with one transaction")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"group move preserves document revision and dirty status")
	# A panel's Split menu creates a new host, without a second group in the
	# original floating host. Test after the grip case to avoid overlapping hosts.
	var refloat: String = app.float_group(app.dock_layout.group_of("colors"))
	check(not refloat.is_empty(), "refloat docked group to test context split")
	await frames(8)
	var new_host: DrawingFloatingHost = app.floating_hosts[refloat]
	new_host._show_floating_panel_menu("layers", (new_host.tab_buttons["layers"] as Button).get_global_rect().get_center())
	new_host._panel_menu.hide()
	new_host._floating_panel_menu_action(2)
	await frames(7)
	var split_host_id: String = app.dock_layout.owner_of("layers")
	check(split_host_id != refloat and split_host_id != "right" and
		app.floating_hosts.has(split_host_id) and app.dock_layout.owner_of("colors") == refloat,
		"Split context creates a new one-group host for only the targeted tab")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"context split remains a layout-only transaction")
	print("T256_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T256_NATIVE_PASSED" if failures == 0 else "T256_NATIVE_FAILED")
	quit(1 if failures else 0)
