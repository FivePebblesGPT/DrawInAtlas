extends SceneTree
## T-080 native pointer/keyboard witness for transactional dock reorganization.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T080_NATIVE_FAILED: " + label)

func frames(count: int = 4) -> void:
	for _i: int in range(count):
		await process_frame

func mouse(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func motion(position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.relative = Vector2(10, 10)
	root.push_input(event, true)

func press_key(key: Key, ctrl: bool = false, alt: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(3)

func drag_begin(source: Control, destination: Vector2) -> void:
	var start: Vector2 = source.get_global_rect().get_center()
	mouse(start, true)
	await frames(3)
	motion(start.lerp(destination, 0.6))
	await frames(3)
	motion(destination)
	await frames(5)

func drag_end(destination: Vector2) -> void:
	mouse(destination, false)
	await frames(7)

func icons(layout: DrawingDockLayout) -> Array[String]:
	var ids: Array[String] = []
	for item: Dictionary in layout.rail_icons("right"):
		ids.append(item["panel"])
	return ids

func screenshot(label: String) -> void:
	var target_dir: String = OS.get_environment("T080_SCREENSHOTS")
	if target_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(target_dir)
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	check(pixels.save_png(target_dir.path_join(label + ".png")) == OK, "native screenshot " + label)


func fixture(app: Control, layout: DrawingDockLayout, panel: String) -> void:
	var view: VBoxContainer = VBoxContainer.new()
	view.name = panel.capitalize()
	var label: Label = Label.new()
	label.text = panel.capitalize() + " fixture"
	view.add_child(label)
	app.dock_stash.add_child(view)
	app.dock_views[panel] = view
	check(layout.register_panel(panel) and layout.attach_panel(panel, "right", panel), "register " + panel)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native window required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(12)
	var layout: DrawingDockLayout = app.dock_layout
	var baseline_revision: int = app.current_document().revision
	var baseline_dirty: bool = app.current_document().is_dirty()
	for panel_id: String in ["swatches", "gradients", "patterns"]:
		fixture(app, layout, panel_id)
	check(layout.merge_groups("swatches", "colors", 1), "group Colors/Swatches")
	check(layout.merge_groups("gradients", "colors", 2), "group Colors/Swatches/Gradients")
	check(layout.merge_groups("patterns", "colors", 3), "group Colors/Swatches/Gradients/Patterns")
	app._render_dock()
	await frames()
	check(icons(layout) == ["colors", "swatches", "gradients", "patterns", "layers", "history"], "initial panel rail order")
	check(layout.rail_icons("right")[4]["separator_before"] and not layout.rail_icons("right")[3]["separator_before"], "group separators distinguish shared tabbed group")
	check(app.dock_tab_strips["colors"] != null and app.dock_group_handles["colors"] != null, "drag controls available")
	var initial: Dictionary = layout.snapshot()
	var tab: Button = app.dock_tab_buttons["gradients"]
	var target: Vector2 = (app.dock_tab_buttons["colors"] as Button).get_global_rect().position + Vector2(4, 21)
	await drag_begin(tab, target)
	check(app.dock_drop_hint.visible and layout.snapshot() == initial, "native preview hint without mutation")
	await screenshot("tab-reorder-preview")
	await drag_end(target)
	check(layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches", "patterns"], "pointer reorders tab to front")
	check(icons(layout).slice(0, 4) == ["gradients", "colors", "swatches", "patterns"], "rail order mirrors moved tab")
	# Esc cancellation after a displayed, valid insertion hint must restore exact state.
	var before_cancel: Dictionary = layout.snapshot()
	tab = app.dock_tab_buttons["swatches"]
	target = (app.dock_tab_buttons["gradients"] as Button).get_global_rect().position + Vector2(3, 20)
	await drag_begin(tab, target)
	check(app.dock_drop_hint.visible, "Esc setup shows alignment hint")
	await press_key(KEY_ESCAPE)
	await drag_end(target)
	check(not app.dock_drop_hint.visible and layout.snapshot() == before_cancel, "Esc rolls back exact group/order/selection")
	# Invalid canvas drop does not activate an accidental canvas brush gesture.
	var document_before: Dictionary = layout.snapshot()
	tab = app.dock_tab_buttons["patterns"]
	target = app.canvas.get_global_rect().get_center()
	await drag_begin(tab, target)
	check(not app.dock_drop_hint.visible, "invalid canvas drop has no fake alignment target")
	await drag_end(target)
	check(layout.snapshot() == document_before, "invalid drop is exact no-op")
	# Split a tab at the top of its source group and merge it back at a precise slot.
	tab = app.dock_tab_buttons["swatches"]
	(app.dock_header_buttons["colors"] as Button).grab_focus()
	await frames(6)
	var color_frame: Control = app.dock_group_frames["colors"]
	target = color_frame.global_position + Vector2(35, 3)
	await drag_begin(tab, target)
	check(app.dock_drop_hint.visible, "before-group insertion hint")
	await drag_end(target)
	var detached_group: String = layout.group_of("swatches")
	check(detached_group != "colors" and layout.container_info("right")["groups"][0]["id"] == detached_group, "top boundary splits panel to new group")
	check(layout.rail_icons("right")[1]["separator_before"], "split creates rail group separator")
	tab = app.dock_tab_buttons["swatches"]
	target = (app.dock_tab_buttons["gradients"] as Button).get_global_rect().end - Vector2(4, 18)
	await drag_begin(tab, target)
	await drag_end(target)
	check(layout.group_of("swatches") == "colors" and layout.group_info(detached_group).is_empty(), "merge returns split panel without orphaned group")
	check(layout.group_info("colors")["panels"].find("swatches") == 1, "merge inserts at indicated target slot")
	# Whole-group movement preserves identity, active tab, collapse and member order.
	var original_color_members: Array = layout.group_info("colors")["panels"].duplicate()
	check(layout.set_group_collapsed("colors", true), "collapse group before move")
	app._render_dock()
	await frames()
	var group_handle: Button = app.dock_group_handles["colors"]
	group_handle.grab_focus()
	await frames(6)
	var history_frame: Control = app.dock_group_frames["history"]
	target = Vector2(history_frame.get_global_rect().end.x - 24.0,
		minf(history_frame.get_global_rect().end.y - 2.0, app.inspector.get_global_rect().end.y - 6.0))
	await drag_begin(group_handle, target)
	await frames(36) # native auto-scroll toward the last group
	var bottom_group_rect: Rect2 = (app.dock_group_frames["history"] as Control).get_global_rect()
	var end_point: Vector2 = Vector2(target.x, minf(bottom_group_rect.end.y - 3.0, app.inspector.get_global_rect().end.y - 4.0))
	motion(end_point)
	await frames(5)
	target = end_point
	check(app.dock_drop_hint.visible, "whole-group insertion hint")
	await drag_end(target)
	var groups: Array = layout.container_info("right")["groups"]
	check(groups[-1]["id"] == "colors" and layout.group_info("colors")["panels"] == original_color_members, "pointer moves group to bottom with order intact")
	check(layout.group_info("colors")["collapsed"], "moved group's collapsed state retained")
	# Group drag into another group is a merge rather than a split.
	check(layout.set_group_collapsed("history", true), "shorten intermediate group for visible merge target")
	app._render_dock()
	app.inspector.scroll_vertical = 0
	await frames(6)
	group_handle = app.dock_group_handles["layers"]
	group_handle.grab_focus()
	await frames(8)
	var color_header: Control = app.dock_group_frames["colors"].get_node("GroupHeader")
	target = color_header.get_global_rect().get_center()
	await drag_begin(group_handle, target)
	check(app.dock_drop_hint.visible, "merge target has visible hint")
	await drag_end(target)
	check(layout.group_of("layers") == "colors" and layout.group_info("layers").is_empty(), "group merge transfers original tabs")
	# Window deactivation aborts a valid hover without a spurious tab click.
	var before_focus_loss: Dictionary = layout.snapshot()
	var source_focus: Button = app.dock_tab_buttons["gradients"]
	var focus_target: Vector2 = (app.dock_tab_buttons["colors"] as Button).get_global_rect().position + Vector2(4, 22)
	await drag_begin(source_focus, focus_target)
	check(app.dock_drop_hint.visible, "window-focus cancellation setup shows valid target")
	app._notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await drag_end(focus_target)
	check(layout.snapshot() == before_focus_loss and not app.dock_drop_hint.visible,
		"window focus loss cancels transaction and release without changing selection")
	# Keyboard: panel left/right, split, group reorder through focused handles.
	var keyboard_tab: Button = app.dock_tab_buttons["patterns"]
	keyboard_tab.grab_focus()
	await frames()
	var prior_index: int = layout.group_info("colors")["panels"].find("patterns")
	await press_key(KEY_LEFT, true, true)
	check(layout.group_info("colors")["panels"].find("patterns") == prior_index - 1, "Ctrl+Alt+Left keyboard tab move")
	keyboard_tab = app.dock_tab_buttons["patterns"]
	keyboard_tab.grab_focus()
	await press_key(KEY_S, true, true)
	check(layout.group_of("patterns") != "colors", "Ctrl+Alt+S keyboard split")
	var new_group_id: String = layout.group_of("patterns")
	group_handle = app.dock_group_handles[new_group_id]
	group_handle.grab_focus()
	await press_key(KEY_DOWN, true, true, true)
	check(layout.container_info("right")["groups"][-1]["id"] == new_group_id, "Ctrl+Alt+Shift+Down keyboard group reorder")
	# Narrow/high-density viewport with horizontal overflow; tab and group focus remain reachable.
	for panel_id: String in ["extra-a", "extra-b", "extra-c", "extra-d", "extra-e"]:
		fixture(app, layout, panel_id)
		check(layout.merge_groups(panel_id, "colors", layout.group_info("colors")["panels"].size()), "add overflow fixture " + panel_id)
	app._render_dock()
	app.grow_horizontal = Control.GROW_DIRECTION_END
	app.grow_vertical = Control.GROW_DIRECTION_END
	app.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.size = Vector2i(420, 420)
	app.position = Vector2.ZERO
	app.size = Vector2(420, 420)
	await frames(16)
	check(app.canvas.size.x >= 125 and app.inspector.get_global_rect().end.x <= 421, "420px dock does not steal canvas")
	var tab_strip: ScrollContainer = app.dock_tab_strips["colors"]
	check(tab_strip.get_h_scroll_bar().max_value > tab_strip.get_h_scroll_bar().page, "narrow tab strip scrolls horizontally")
	tab_strip.scroll_horizontal = 500
	await frames(6)
	check(tab_strip.scroll_horizontal > 0, "overflow scroll reaches later tabs")
	# A real drag from the scrolled-right end of the strip must still target its
	# visible tab slots, rather than incorrectly using unclipped button positions.
	var overflow_group: Array = layout.group_info("colors")["panels"]
	var previous_last: int = overflow_group.find("extra-e")
	var extra_source: Button = app.dock_tab_buttons["extra-e"]
	var extra_target: Button = app.dock_tab_buttons["extra-c"]
	var extra_pos: Vector2 = extra_target.get_global_rect().position + Vector2(3, 20)
	if extra_source.is_visible_in_tree() and tab_strip.get_global_rect().has_point(extra_source.get_global_rect().get_center()) and tab_strip.get_global_rect().has_point(extra_pos):
		await drag_begin(extra_source, extra_pos)
		check(app.dock_drop_hint.visible, "scrolled tab strip shows accessible drop hint")
		await drag_end(extra_pos)
		check(layout.group_info("colors")["panels"].find("extra-e") < previous_last,
			"native drag reorders tab in horizontally scrolled strip")
	else:
		check(false, "overflow fixture tabs are both reachable in the strip viewport")
	root.size = Vector2i(900, 630)
	root.content_scale_factor = 1.5
	app.position = Vector2.ZERO
	app.size = Vector2(900, 630)
	await frames(12)
	check(app.canvas.size.x >= 125 and app.inspector.visible, "1.5x content-scale dock remains functional")
	check((app.dock_tab_buttons["history"] as Button).focus_mode == Control.FOCUS_ALL, "history tab remains focusable")
	# Minimized rail participates in the same transaction path, and the flyout
	# still derives its member tabs from the reordered model.
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	app.position = Vector2.ZERO
	app.size = Vector2(1280, 800)
	await frames(12)
	app._toggle_dock()
	await frames(8)
	check(app.dock_rail.visible and app.dock_rail_buttons.size() == layout.rail_icons("right").size(),
		"minimized rail has one icon per live attached panel after reorganization")
	var rail_order_before: Array = layout.group_info("colors")["panels"].duplicate()
	var rail_source: Button = app.dock_rail_buttons["extra-d"]
	var rail_target: Button = app.dock_rail_buttons["gradients"]
	var rail_position: Vector2 = rail_target.get_global_rect().position + Vector2(21, 3)
	await drag_begin(rail_source, rail_position)
	check(app.dock_drop_hint.visible, "native minimized rail drag indicates exact member slot")
	await drag_end(rail_position)
	check(layout.group_info("colors")["panels"].find("extra-d") < rail_order_before.find("extra-d"),
		"rail drag commits panel order into shared group state")
	var rail_members: Array[Dictionary] = layout.rail_icons("right")
	check(rail_members.size() == app.dock_rail_buttons.size() and
		rail_members[0]["panel"] == layout.container_info("right")["groups"][0]["panels"][0],
		"rail buttons and group entries stay synchronized after native drag")
	var flyout_button: Button = app.dock_rail_buttons["colors"]
	var flyout_point: Vector2 = flyout_button.get_global_rect().get_center()
	mouse(flyout_point, true)
	await frames(3)
	mouse(flyout_point, false)
	await frames(6)
	check(app.dock_flyout.visible and app.dock_flyout_tabs.get_child_count() == layout.group_info("colors")["panels"].size(),
		"flyout displays entire reordered group, no cloned tab list")
	# Re-render and menu actions cannot duplicate or orphan any panel Control.
	var unique: Dictionary = {}
	for entry: Dictionary in layout.rail_icons("right"):
		var panel: String = entry["panel"]
		unique[panel] = true
		check(app.dock_views[panel].get_parent() != null, "source panel Control survives: " + panel)
	check(unique.size() == app.dock_views.size(), "all panels remain uniquely owned")
	check(app.current_document().revision == baseline_revision and app.current_document().is_dirty() == baseline_dirty, "dock reorganization never edits drawing history or dirty state")
	print("T080_DOCK_REORDER_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T080_DOCK_REORDER_NATIVE_PASSED")
	quit(1 if failures else 0)
