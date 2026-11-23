extends SceneTree
## T-223: marker-only group chrome, pointer/menu/drag persistence and scaling.

const PREFS: String = "user://t223-dock-layout.json"
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T223_NATIVE_FAILED: " + message)

func frames(count: int = 6) -> void:
	for _i: int in range(count):
		await process_frame

func mouse(point: Vector2, down: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)

func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	mouse(point, true, button)
	await frames(2)
	mouse(point, false, button)
	await frames(8)

func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(11, 4)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func press_key(key: Key, shift: bool = false, ctrl: bool = false, alt: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(4)

func shot(label: String) -> void:
	var directory: String = OS.get_environment("T223_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var capture_status: int = root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: drawing/tests/t223_dock_native.gd: " + str(capture_status))

func add_fixture(app: Control, panel_id: String) -> void:
	var view: VBoxContainer = VBoxContainer.new()
	view.name = panel_id.capitalize()
	view.add_child(Label.new())
	app.dock_stash.add_child(view)
	app.dock_views[panel_id] = view
	check(app.dock_layout.register_panel(panel_id) and app.dock_layout.attach_panel(panel_id, "right", panel_id),
		"register extra panel " + panel_id)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1180, 750)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(16)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	check(layout.set_panel_visible("brushes", false), "hide Brushes for compact fixture")
	check(layout.merge_groups("layers", "colors", 1), "prepare multi-panel Colors group")
	app._render_dock()
	await frames(8)
	var marker: Button = app.dock_group_handles["colors"]
	check(marker.tooltip_text.contains("Colors") and marker.focus_mode == Control.FOCUS_ALL,
		"marker has discoverable accessible group identity")
	await shot("expanded")
	# Marker and active icon share the same collapse bit.
	await click(marker.get_global_rect().get_center())
	check(layout.group_info("colors")["collapsed"], "marker LMB collapses its group")
	await click((app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(not layout.group_info("colors")["collapsed"], "active icon reopens marker-collapsed group")
	marker = app.dock_group_handles["colors"]
	await click(marker.get_global_rect().get_center())
	check(layout.group_info("colors")["collapsed"], "marker triangle reflects collapsed bit")
	await shot("collapsed")
	# Right click and keyboard menu are group-scoped, without panel activation.
	var before_menu: Dictionary = layout.snapshot()
	await click((app.dock_group_handles["colors"] as Button).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(app.dock_group_menu.visible and app._dock_menu_group_id == "colors", "RMB opens group menu")
	var color_position: int = app._dock_group_position("colors")
	var last_position: int = layout.container_info("right")["groups"].size() - 1
	check(app.dock_group_menu.is_item_disabled(0) == (color_position == 0) and
		app.dock_group_menu.is_item_disabled(1) == (color_position == last_position) and
		not app.dock_group_menu.is_item_disabled(4), "group menu enables only applicable reorder/split actions")
	check(layout.snapshot() == before_menu, "RMB does not alter collapse or active panel")
	app.dock_group_menu.hide()
	await frames(3)
	(app.dock_group_handles["colors"] as Button).grab_focus()
	await press_key(KEY_F10, true)
	check(app.dock_group_menu.visible, "Shift+F10 opens menu from focused group marker")
	app.dock_group_menu.hide()
	await frames(4)
	# A drag threshold beats click, and Escape cancels without changing layout.
	marker = app.dock_group_handles["colors"]
	var start: Vector2 = marker.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(start + Vector2(3, 0))
	await frames(2)
	check(not app.dock_drag.is_dragging(), "subthreshold marker motion is a click")
	mouse(start + Vector2(3, 0), false)
	await frames(8)
	check(not layout.group_info("colors")["collapsed"], "subthreshold marker click expands")
	marker = app.dock_group_handles["colors"]
	start = marker.get_global_rect().get_center()
	before_menu = layout.snapshot()
	mouse(start, true)
	await frames(2)
	motion(start + Vector2(11, 8))
	await frames(4)
	check(app.dock_drag.is_dragging() and app.dock_drag.source_kind() == DrawingDockDrag.GROUP,
		"marker motion begins whole-group transaction")
	await press_key(KEY_ESCAPE)
	mouse(start + Vector2(11, 8), false)
	await frames(8)
	check(layout.snapshot() == before_menu and not app.dock_drag.is_dragging(),
		"Escape restores all membership and collapse bits")
	# Group RMB menu reorder and split (not individual-panel gesture).
	(app.dock_group_handles["colors"] as Button).grab_focus()
	app._show_dock_group_menu("colors", (app.dock_group_handles["colors"] as Button).global_position)
	app.dock_group_menu.hide()
	app._dock_group_menu_action(1) # Move group down.
	await frames(6)
	check(app.get_viewport().gui_get_focus_owner() == app.dock_group_handles["colors"],
		"group reorder restores focus to the new marker")
	check(layout.container_info("right")["groups"].find_custom(func(group: Dictionary) -> bool: return group["id"] == "colors") > 0 and
		layout.group_info("colors")["panels"] == ["colors", "layers"],
		"group menu reorder keeps tab membership/order")
	app._show_dock_group_menu("colors", (app.dock_group_handles["colors"] as Button).global_position)
	app.dock_group_menu.hide()
	app._dock_group_menu_action(4) # Split active panel.
	await frames(6)
	check(layout.group_of("colors") != layout.group_of("layers"), "group menu split affects active panel")
	# Bring the colors group back for persisted collapse and host transfer checks.
	check(layout.merge_groups(layout.group_of("colors"), layout.group_of("layers"), 0),
		"restore original group identity after split")
	check(layout.select_panel("colors"), "restore Colors as active tab")
	app._render_dock()
	await frames(5)
	app.layout_settings_path = PREFS
	app.layout_persistence_enabled = true
	check(app._save_workspace_layout(), "write persisted group layout")
	app.queue_free()
	await frames(10)
	app = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(18)
	layout = app.dock_layout
	check(app.layout_recovery_status == "loaded" and layout.group_info("colors")["active"] == "colors",
		"group active panel restores after restart")
	check(layout.group_info("colors")["panels"] == ["colors", "layers"] and
		layout.group_info("colors")["collapsed"] == false,
		"group ordering and collapse bit restore on restart")
	check(app.dock_group_handles.has("colors"), "new marker recreated on restart")
	# Context float action removes entire group with one floating host.
	app._show_dock_group_menu("colors", (app.dock_group_handles["colors"] as Button).global_position)
	app.dock_group_menu.hide()
	app._dock_group_menu_action(5)
	await frames(9)
	check(layout.owner_of("colors") == layout.owner_of("layers") and layout.owner_of("colors") != "right" and
		app.floating_hosts.size() == 1, "context Float creates one host for entire group")
	var host: DrawingFloatingHost = app.floating_hosts.values()[0]
	check(host.group_handles.size() == 1 and host.tab_buttons.has("colors") and host.tab_buttons.has("layers"),
		"floating host retains a single group and both panel views")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"dock changes do not touch document history")
	await shot("floating")
	# UI scaling and compact windows: tab strip/marker remain focusable.
	var colors_group: String = layout.group_of("colors")
	check(app.dock_layout.move_group(colors_group, "right", 0), "re-dock the floated group")
	app._reap_empty_hosts()
	app._render_dock()
	await frames(7)
	await click(app.dock_toggle.get_global_rect().get_center())
	check(layout.container_info("right")["minimized"], "toggle minimizes for flyout check")
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(app.dock_flyout.visible and app.dock_flyout.find_child("FlyoutTitle", true, false) == null,
		"minimized flyout has tabs and no visible group name")
	check(app.dock_views["colors"].get_parent() == app.dock_flyout_body,
		"flyout reuses original Colors panel view")
	await shot("flyout")
	await click(app.dock_toggle.get_global_rect().get_center())
	check(not layout.container_info("right")["minimized"], "expand returns to group marker")
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		root.size = Vector2i(1180, 750)
		await frames(12)
		marker = app.dock_group_handles["colors"]
		check(marker.is_visible_in_tree() and marker.focus_mode == Control.FOCUS_ALL and marker.get_global_rect().intersects(app.inspector.get_global_rect()),
			"marker remains focusable and reachable at %.0f%%" % (scale * 100.0))
		await shot("scale-%d" % roundi(scale * 100.0))
	root.content_scale_factor = 1.0
	root.size = Vector2i(420, 430)
	await frames(14)
	check(app.canvas.size.x >= 125 and (app.dock_group_handles["colors"] as Button).is_visible_in_tree(),
		"marker and canvas remain reachable at 420px width")
	await shot("narrow")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"resizing and re-dock do not touch document history")
	# Group menu merge is whole-group, not an active-tab transfer.
	var groups_before_merge: Array = layout.container_info("right")["groups"]
	var neighbor_id: String = String(groups_before_merge[1]["id"])
	var original_members: Array = layout.group_info("colors")["panels"].duplicate()
	app._show_dock_group_menu("colors", (app.dock_group_handles["colors"] as Button).global_position)
	app.dock_group_menu.hide()
	app._dock_group_menu_action(3) # Merge into next group.
	await frames(6)
	var neighbor_members: Array = layout.group_info(neighbor_id)["panels"]
	check(layout.group_info("colors").is_empty() and neighbor_members.size() >= original_members.size() and
		original_members.all(func(panel: String) -> bool: return neighbor_members.has(panel)),
		"group menu merge transfers every panel without orphaning its view")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("T223_NATIVE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
