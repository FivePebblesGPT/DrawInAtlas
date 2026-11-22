extends SceneTree
## T-254: real X11 flyout icon, context, drag/rollback, persistence and scaling.

const PREFS: String = "user://t254-flyout-icons.json"
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T254_FLYOUT_FAILED: " + label)


func frames(n: int = 6) -> void:
	for _i: int in range(n):
		await process_frame


func mouse(point: Vector2, pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = which
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)


func click(control: Control, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	mouse(at, true, which)
	await frames(3)
	mouse(at, false, which)
	await frames(8)


func key(value: Key, shift: bool = false, ctrl: bool = false, alt: bool = false) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = value
		event.pressed = down
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		event.alt_pressed = alt
		root.push_input(event, true)
		await frames(4)


func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(14, 8)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func drag(source: Control, target: Vector2) -> void:
	var origin: Vector2 = source.get_global_rect().get_center()
	mouse(origin, true)
	await frames(3)
	motion(origin.lerp(target, 0.5))
	await frames(3)
	motion(target)
	await frames(4)


func tab_for(app: Control, panel_id: String) -> Button:
	return app.dock_flyout_tabs.get_node_or_null("Tab_" + panel_id) as Button


func icon_contract(app: Control, panel_id: String, active: bool) -> void:
	var tab: Button = tab_for(app, panel_id)
	check(tab != null, panel_id + ": flyout tab exists")
	if tab == null:
		return
	var rail: Button = app.dock_rail_buttons.get(panel_id) as Button
	check(rail != null and tab.icon == rail.icon and tab.icon == app._dock_icon(panel_id) and
		tab.icon != null and tab.icon.get_width() > 0,
		panel_id + ": same canonical icon including unknown-panel fallback")
	check(tab.text.is_empty() and tab.expand_icon and tab.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		panel_id + ": icon only; no text button")
	check(tab.custom_minimum_size == Vector2(42, 42) and tab.focus_mode == Control.FOCUS_ALL,
		panel_id + ": compact focusable target")
	check(tab.toggle_mode and tab.button_pressed == active and tab.tooltip_text.contains(panel_id.capitalize()),
		panel_id + ": active state and accessible name tooltip")
	if tab.get_property_list().any(func(prop: Dictionary) -> bool: return prop["name"] == "accessibility_name"):
		check(String(tab.get("accessibility_name")).contains(panel_id.capitalize()),
			panel_id + ": accessibility name exists")


func shot(name: String) -> void:
	var target: String = OS.get_environment("T254_SCREENSHOTS")
	if target.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(target)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(target.path_join(name + ".png")) == OK,
		"framebuffer " + name)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires native X11 window")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1220, 810)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var swatches: VBoxContainer = VBoxContainer.new()
	swatches.name = "Swatches"
	swatches.add_child(Label.new())
	var gradients: VBoxContainer = VBoxContainer.new()
	gradients.name = "Gradients"
	gradients.add_child(Label.new())
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.initial_extra_panels = {"swatches": swatches, "gradients": gradients}
	root.add_child(app)
	await frames(20)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var views: Dictionary = app.dock_views.duplicate()
	check(layout.set_panel_visible("brushes", false), "hide Brushes to expose compact test groups")
	for panel: String in ["layers", "history", "swatches", "gradients"]:
		check(layout.merge_groups(panel, "colors", layout.group_info("colors")["panels"].size()),
			"build scrollable five-panel flyout: " + panel)
	check(layout.set_group_collapsed("colors", true), "persisted collapse flag in setup")
	app._render_dock()
	await frames(8)
	await click(app.dock_toggle)
	check(bool(layout.container_info("right")["minimized"]), "minimized by real pointer")
	await click(app.dock_rail_buttons["colors"])
	check(app.dock_flyout.visible and layout.container_info("right")["flyout_group"] == "colors",
		"rail icon opens one temporary flyout")
	check(bool(layout.group_info("colors")["collapsed"]), "transient flyout preserves persisted collapsed bit")
	for panel: String in ["colors", "layers", "history", "swatches", "gradients"]:
		icon_contract(app, panel, panel == "colors")
	check(app.dock_flyout_tabs.get_child_count() == 5 and app.dock_flyout_tab_scroll != null,
		"all five tabs use one horizontal ScrollContainer")
	await shot("flyout-100")
	# Clicking the current tab is a no-op; it cannot unpress or close itself.
	var before: Dictionary = layout.snapshot()
	await click(tab_for(app, "colors"))
	check(layout.snapshot() == before and app.dock_flyout.visible and tab_for(app, "colors").button_pressed,
		"active flyout icon click is a no-op, remains pressed")
	# The inactive icon uses the model and preserves one shared view.
	await click(tab_for(app, "layers"))
	check(layout.group_info("colors")["active"] == "layers" and app.dock_flyout.visible,
		"LMB selects inactive flyout icon")
	check(app.dock_views["layers"] == views["layers"] and
		(app.dock_views["layers"] as Control).get_parent() == app.dock_flyout_body,
		"original panel Control reparented; no duplicate")
	check(bool(layout.group_info("colors")["collapsed"]), "LMB does not affect group collapsed bit")
	check(tab_for(app, "layers").has_focus(), "focus restored to newly selected flyout icon")
	icon_contract(app, "layers", true)
	# RMB must target the clicked *inactive* tab, without selecting it.
	before = layout.snapshot()
	await click(tab_for(app, "colors"), MOUSE_BUTTON_RIGHT)
	check(app.dock_panel_menu.visible and app._dock_menu_panel_id == "colors",
		"RMB context menu targets inactive flyout icon")
	check(layout.snapshot() == before, "right-click does not switch or collapse")
	app.dock_panel_menu.hide()
	await frames(4)
	(tab_for(app, "colors") as Button).grab_focus()
	await frames(2)
	await key(KEY_F10, true)
	check(app.dock_panel_menu.visible and app._dock_menu_panel_id == "colors",
		"Shift+F10 opens inactive flyout panel's menu")
	check(layout.snapshot() == before, "keyboard menu does not switch or collapse")
	app.dock_panel_menu.hide()
	await frames(5)
	# Subthreshold movement does not begin a drag; Escape during an actual drag
	# rolls back all model groups, tab selection and panel identities.
	var start: Vector2 = tab_for(app, "layers").get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(start + Vector2(3, 2))
	await frames(2)
	check(not app.dock_drag.is_dragging(), "sub-7px movement is not a drag")
	mouse(start + Vector2(3, 2), false)
	await frames(8)
	before = layout.snapshot()
	await drag(tab_for(app, "layers"), tab_for(app, "colors").get_global_rect().get_center())
	check(app.dock_drag.is_dragging() and app.dock_drag.source_kind() == DrawingDockDrag.PANEL,
		"flyout icon drags exactly one panel")
	check(layout.snapshot() == before, "drag preview cannot mutate layout")
	await key(KEY_ESCAPE)
	mouse(start, false)
	await frames(8)
	check(layout.snapshot() == before and not app.dock_drag.is_dragging(),
		"Escape restores tab order, active state, collapsed bit and flyout")
	icon_contract(app, "layers", true)
	icon_contract(app, "colors", false)
	# Context move targets the selected tab, not whole-group grip.
	app._show_dock_panel_menu("colors", tab_for(app, "colors").get_global_rect().get_center())
	app.dock_panel_menu.hide()
	app._dock_panel_menu_action(1)
	await frames(9)
	check(layout.group_info("colors")["panels"][0] == "layers" and
		layout.group_info("colors")["active"] == "layers", "context action reorders only inactive icon")
	for panel: String in ["colors", "layers", "history", "swatches", "gradients"]:
		check(app.dock_views[panel] == views[panel], panel + ": reordering kept same view")
	# Rail opens/closes the flyout without modifying the persistent group bit.
	await click(app.dock_rail_buttons["layers"])
	check(not app.dock_flyout.visible and bool(layout.group_info("colors")["collapsed"]),
		"rail active click closes transient flyout only")
	await click(app.dock_rail_buttons["colors"])
	check(app.dock_flyout.visible, "rail reopens icon flyout")
	await shot("reopened-flyout")
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(13)
		check(app.dock_flyout.visible and app.dock_flyout_tab_scroll.is_visible_in_tree(),
			"flyout reachable at %d%%" % roundi(scale * 100.0))
		for panel: String in ["colors", "layers", "history", "swatches", "gradients"]:
			icon_contract(app, panel, panel == String(layout.group_info("colors")["active"]))
		await shot("flyout-%d" % roundi(scale * 100.0))
	root.content_scale_factor = 1.0
	root.size = Vector2i(600, 470)
	await frames(12)
	check(app.dock_flyout.visible and app.dock_flyout.get_global_rect().end.x <= root.size.x + 2.0,
		"compact flyout stays within small window")
	await shot("flyout-narrow")
	# Save/restore with the flyout open, and verify minimized state + icon parity.
	app.layout_persistence_enabled = true
	check(app._save_workspace_layout(), "save one-group minimized flyout layout")
	var saved: Dictionary = layout.snapshot()
	app.queue_free()
	await frames(15)
	app = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.preferences_persistence_enabled = false
	var swatch2: VBoxContainer = VBoxContainer.new()
	swatch2.add_child(Label.new())
	var gradient2: VBoxContainer = VBoxContainer.new()
	gradient2.add_child(Label.new())
	app.initial_extra_panels = {"swatches": swatch2, "gradients": gradient2}
	root.add_child(app)
	await frames(22)
	layout = app.dock_layout
	check(app.layout_recovery_status == "loaded" and layout.snapshot() == saved,
		"relaunch recovers exact tabs, transient flyout and collapse")
	check(app.dock_flyout.visible and tab_for(app, "colors") != null,
		"recovered flyout rebuilds icons from original panel identities")
	icon_contract(app, "swatches", false)
	# Floating a whole merged group retains one host and icon parity.
	await click(app.dock_toggle)
	check(not bool(layout.container_info("right")["minimized"]), "expand resets transient flyout")
	var float_id: String = app.float_group("colors")
	await frames(10)
	check(not float_id.is_empty() and app.floating_hosts.has(float_id), "float the whole tabbed group")
	if not float_id.is_empty():
		var host: DrawingFloatingHost = app.floating_hosts[float_id]
		check(host.group_frames.size() == 1 and host.tab_buttons.size() == 5,
			"one floating host with five icon tabs")
		for panel: String in ["colors", "layers", "history", "swatches", "gradients"]:
			var tab: Button = host.tab_buttons.get(panel) as Button
			check(tab != null and tab.text.is_empty() and tab.icon == app._dock_icon(panel),
				panel + ": floating and flyout icon parity")
		app.hide_floating_host(float_id)
		check(not host.visible and layout.group_of("colors") == "colors",
			"hiding floating group retains model ownership")
		app.show_floating_host(float_id)
		check(host.visible and host.tab_buttons.size() == 5, "reopen floating icon group")
		# Redock the whole group through the same transactional planner used
		# by native grip input. This cannot leave two owners for any panel.
		check(app.dock_drag.begin_group("colors"), "begin floating whole-group redock")
		check(app.dock_drag.preview({"kind": DrawingDockDrag.GROUP_SLOT,
			"container": "right", "index": 0}), "preflight redock target")
		check(app.dock_drag.commit(), "commit whole-group redock")
		app._reap_empty_hosts()
		app._render_dock()
		await frames(10)
		check(layout.owner_of("colors") == "right" and app.floating_hosts.is_empty() and
			layout.group_info("colors")["panels"].size() == 5,
			"redock removes empty floating host without losing panel IDs")
		for panel: String in ["colors", "layers", "history", "swatches", "gradients"]:
			check(app.dock_views[panel] != null and
				layout.owner_of(panel) == "right", panel + ": redock view has exactly one owner")
		await click(app.dock_toggle)
		await click(app.dock_rail_buttons["layers"])
		check(app.dock_flyout.visible, "redocked group recovers minimized flyout")
		icon_contract(app, "layers", true)
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"panel operations do not change document/history")
	print("T254_FLYOUT_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T254_FLYOUT_NATIVE_PASSED" if failures == 0 else "T254_FLYOUT_NATIVE_FAILED")
	quit(1 if failures else 0)
