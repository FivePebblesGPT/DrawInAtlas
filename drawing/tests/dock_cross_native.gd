extends SceneTree
## T-082 native pointer witness: real cross-container drops and exact rollback.
var checks: int = 0
var failures: int = 0

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T082_NATIVE_FAILED: " + detail)

func frames(n: int = 6) -> void:
	for _i: int in range(n):
		await process_frame

func mouse(point: Vector2, down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = point
	e.global_position = point
	e.pressed = down
	root.push_input(e, true)

func motion(point: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = point
	e.global_position = point
	e.relative = Vector2(20, 12)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)

func drag_from(control: Control, point: Vector2) -> void:
	var start: Vector2 = control.get_global_rect().get_center()
	mouse(start, true)
	await frames(3)
	motion(start.lerp(point, 0.5))
	await frames(4)
	motion(point)
	await frames(5)

func drop(point: Vector2) -> void:
	mouse(point, false)
	await frames(9)

func press_escape() -> void:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e, true)
	await frames(3)
	e.pressed = false
	root.push_input(e, true)
	await frames(3)

func fixture(app: Control, panel_id: String) -> void:
	var pane: VBoxContainer = VBoxContainer.new()
	pane.name = "Fixture_" + panel_id
	pane.add_child(Label.new())
	app.dock_stash.add_child(pane)
	app.dock_views[panel_id] = pane
	check(app.dock_layout.register_panel(panel_id) and app.dock_layout.attach_panel(panel_id, "right", panel_id), "fixture " + panel_id)

func screenshot(label: String) -> void:
	var folder: String = OS.get_environment("T082_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"native capture " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("T082 native test needs X11")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1240, 800)
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(18)
	var layout: DrawingDockLayout = app.dock_layout
	var initial_rev: int = app.current_document().revision
	var initial_dirty: bool = app.current_document().is_dirty()
	fixture(app, "swatches")
	fixture(app, "gradients")
	fixture(app, "effects")
	check(layout.merge_groups("layers", "colors", 1), "group Colors and Layers")
	app._render_dock()
	await frames()
	var origin: Dictionary = layout.snapshot()
	# Detach by dragging the whole group handle onto the bare canvas.
	var detach_point: Vector2 = app.canvas.get_global_rect().get_center()
	await drag_from(app.dock_group_handles["colors"], detach_point)
	check(app._detach_hint.visible and layout.snapshot() == origin, "canvas detach preview does not mutate state")
	await drop(detach_point)
	check(app.floating_hosts.size() == 1, "whole-group canvas drop creates floating host")
	var host_id: String = "float-1"
	var host: DrawingFloatingHost = app.floating_hosts.get(host_id)
	check(host != null and layout.owner_of("colors") == host_id and layout.owner_of("layers") == host_id, "both panels floated with unique ownership")
	check(layout.rail_icons("right").size() == 4 and layout.rail_icons("right")[0]["panel"] == "history", "source rail drops both icons")
	check(host.group_frames.has("colors"), "one original group visible in new host")
	# Reorder floating tabs, keep the reordered group intact on redock.
	var reorder_target: Vector2 = (host.tab_buttons["colors"] as Control).get_global_rect().position + Vector2(4, 20)
	await drag_from(host.tab_buttons["layers"], reorder_target)
	check(host._hint.visible, "floating tab insertion preview")
	await drop(reorder_target)
	check(layout.group_info("colors")["panels"] == ["layers", "colors"], "floating tabs reordered Layers / Colors")
	# Reattach between two existing singleton groups using minimized rail separator.
	app._toggle_dock()
	await frames(12)
	var a: Rect2 = (app.dock_rail_buttons["history"] as Control).get_global_rect()
	var b: Rect2 = (app.dock_rail_buttons["swatches"] as Control).get_global_rect()
	var insert_point: Vector2 = Vector2(a.get_center().x, (a.end.y + b.position.y) / 2.0)
	await drag_from(host.group_handles["colors"], insert_point)
	check(layout.snapshot()["containers"].size() == 2, "redock preview leaves both containers unchanged")
	check(app.dock_drop_hint.visible and app.dock_drag.target().get("kind") == DrawingDockDrag.GROUP_SLOT,
		"rail gap offers whole-group insertion instead of merging")
	await screenshot("group-redock-preview")
	await drop(insert_point)
	var rail: Array[Dictionary] = layout.rail_icons("right")
	check(rail.map(func(item: Dictionary) -> String: return item["panel"]) == ["history", "layers", "colors", "swatches", "gradients", "effects"], "exact redock rail icon sequence")
	check(not rail[2]["separator_before"] and rail[1]["separator_before"] and rail[3]["separator_before"], "group icon separators match membership")
	check(layout.container_info(host_id).is_empty() and not app.floating_hosts.has(host_id), "empty original floating host removed")
	check(layout.group_info("colors")["panels"] == ["layers", "colors"], "whole-group redock preserves floating tab order")
	check(layout.owner_of("layers") == "right" and layout.owner_of("colors") == "right", "redock panel ownership restored")
	check(not app.dock_drop_hint.visible and not app._detach_hint.visible, "previews cleared on drop")
	# Single-panel move into another host: preserve other members in the dock.
	var second_id: String = app.float_group("effects")
	await frames(8)
	var second: DrawingFloatingHost = app.floating_hosts[second_id]
	var source_tab: Button = app.dock_rail_buttons["colors"]
	var target_point: Vector2 = (second.tab_buttons["effects"] as Control).get_global_rect().get_center()
	await drag_from(source_tab, target_point)
	check(second._hint.visible and layout.owner_of("colors") == "right", "dock-to-host panel preview and unchanged ownership")
	await drop(target_point)
	check(layout.owner_of("colors") == second_id and layout.owner_of("layers") == "right", "only chosen panel transferred")
	check(layout.group_info("effects")["panels"].has("colors"), "single panel merged into floating tabs")
	# Esc and invalid drop leave exact source/destination state.
	var before_cancel: Dictionary = layout.snapshot()
	var source: Control = second.tab_buttons["colors"]
	var invalid_point: Vector2 = Vector2(8, 10)
	await drag_from(source, invalid_point)
	check(not second._hint.visible and not app.dock_drop_hint.visible and not app._detach_hint.visible, "invalid target hides all hints")
	await drop(invalid_point)
	check(layout.snapshot() == before_cancel, "invalid destination exact rollback")
	source = second.tab_buttons["colors"]
	await drag_from(source, (app.dock_rail_buttons["history"] as Control).get_global_rect().get_center())
	await press_escape()
	await drop(invalid_point)
	check(layout.snapshot() == before_cancel, "Esc cancels transfer without mutating either container")
	check(not app.dock_drag.is_dragging() and app._cross_source.is_empty(), "Esc clears coordinator")
	# Two floating hosts: group drop into another host, with actual separator target.
	var third_id: String = app.float_group("history")
	await frames(10)
	var third: DrawingFloatingHost = app.floating_hosts[third_id]
	second.set_host_rect(Rect2(Vector2(45, 85), Vector2(290, 350)))
	third.set_host_rect(Rect2(Vector2(380, 105), Vector2(300, 380)))
	await frames(8)
	check(layout.owner_of("history") == third_id and layout.owner_of("effects") == second_id,
		"two distinct float hosts have exclusive owners")
	var last_frame: Rect2 = (third.group_frames["history"] as Control).get_global_rect()
	var group_drop: Vector2 = Vector2(last_frame.get_center().x, last_frame.end.y - 3)
	await drag_from(second.group_handles["effects"], group_drop)
	check(third._hint.visible and app.dock_drag.target().get("kind") == DrawingDockDrag.GROUP_SLOT,
		"floating-to-floating whole-group target is a separate group slot")
	await drop(group_drop)
	check(not app.floating_hosts.has(second_id) and layout.container_info(second_id).is_empty(),
		"source float removed after entire group leaves")
	check(layout.container_info(third_id)["groups"].map(func(g: Dictionary) -> String: return g["id"]) == ["history", "effects"],
		"target floating group order matches release point")
	check(layout.group_info("effects")["panels"] == ["effects", "colors"],
		"whole-group cross-host drop preserves tab sequence")
	check(layout.rail_icons(third_id)[2]["separator_before"] == false,
		"cross-host joined group has no separator between member icons")
	# Real pointer merge from float into expanded dock, not an extra group.
	app._toggle_dock()
	await frames(9)
	check(not layout.container_info("right")["minimized"], "expanded dock restored for cross-container merge")
	var swatch: Control = app.dock_tab_buttons["swatches"]
	var merge_point: Vector2 = swatch.get_global_rect().get_center()
	await drag_from(third.tab_buttons["colors"], merge_point)
	check(app.dock_drop_hint.visible and app.dock_drag.target().get("kind") == DrawingDockDrag.TAB_SLOT,
		"floating panel offers expanded dock tab insertion marker")
	await drop(merge_point)
	check(layout.owner_of("colors") == "right" and layout.group_of("colors") == "swatches",
		"only floating tab merged into existing dock group")
	check(layout.group_info("effects")["panels"] == ["effects"], "source group retains other tab")
	check(layout.rail_icons("right").any(func(item: Dictionary) -> bool: return item["panel"] == "colors"),
		"rail reflects recovered single tab")
	# Target changed during preview: stale transaction must not replay over new state.
	var before_stale: Dictionary = layout.snapshot()
	var stale_target: Vector2 = (app.dock_tab_buttons["swatches"] as Control).get_global_rect().get_center()
	await drag_from(third.tab_buttons["effects"], stale_target)
	check(app.dock_drop_hint.visible and layout.snapshot() == before_stale, "stale-drag setup preview is nonmutating")
	check(layout.set_group_collapsed("history", true), "intervening model change invalidates captured baseline")
	var after_mutation: Dictionary = layout.snapshot()
	await drop(stale_target)
	check(layout.snapshot() == after_mutation, "stale drop cannot overwrite concurrent model update")
	check(not app.dock_drag.is_dragging(), "stale drag clears transaction")
	# An OS focus loss should cancel a drag and suppress the subsequent release
	# without changing the active panel or keyboard focus.
	var focus_source: Button = third.tab_buttons["effects"]
	focus_source.grab_focus()
	await frames(3)
	var before_focus_loss: Dictionary = layout.snapshot()
	var dock_pointer: Vector2 = (app.dock_tab_buttons["swatches"] as Control).get_global_rect().get_center()
	await drag_from(focus_source, dock_pointer)
	check(app.dock_drop_hint.visible, "focus-loss drag was previewing a valid target")
	app._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await drop(dock_pointer)
	check(layout.snapshot() == before_focus_loss and not app.dock_drag.is_dragging(),
		"focus loss cancels both containers and suppresses release")
	check(root.gui_get_focus_owner() == focus_source, "cancelled focus-loss drag keeps source focus")
	# A destination may disappear before release; stale transaction cannot
	# recreate it or overwrite the legitimate concurrent change.
	await drag_from(third.tab_buttons["effects"], dock_pointer)
	check(app.dock_drop_hint.visible, "target-destruction setup has visible dock hint")
	check(layout.move_group("swatches", third_id, 2), "destination group externally transferred during hover")
	app._render_dock()
	await frames(4)
	var after_destroy: Dictionary = layout.snapshot()
	await drop(dock_pointer)
	check(layout.snapshot() == after_destroy and layout.owner_of("effects") == third_id,
		"destroyed target rejects stale drop and preserves external mutation")
	check(not app.dock_drag.is_dragging() and app._cross_source.is_empty(), "destroyed target clears coordinator")
	# Menu and keyboard alternatives use the same model transaction.
	third._arrange(7, "effects")
	await frames(6)
	check(layout.owner_of("effects") == "right" and layout.owner_of("history") == third_id,
		"floating Arrange redocks only its active tab")
	app._dock_arrange_action(9, "colors")
	await frames(6)
	check(layout.owner_of("layers") == third_id and layout.owner_of("effects") == "right",
		"dock Arrange moves active tab into a visible floating host")
	# Close/hidden host cannot swallow a dock drop. Cursor over an existing
	# hidden host's rectangle is still a canvas detach, not a hidden target.
	app.hide_floating_host(third_id)
	var covered: Vector2 = third.get_global_rect().get_center()
	check(app._topmost_host(covered) == null, "hidden float excluded from hit testing")
	app.show_floating_host(third_id)
	await frames(5)
	# Narrow dock and explicit 1.5x logical viewport are distinct conditions.
	app._toggle_dock()
	root.size = Vector2i(540, 460)
	app.size = Vector2(540, 460)
	await frames(14)
	check(app.inspector.get_global_rect().end.x <= app.get_global_rect().end.x + 2,
		"narrow dock remains in viewport")
	check(third.get_global_rect().end.x <= app.get_global_rect().end.x + 2 and third.get_global_rect().end.y <= app.get_global_rect().end.y + 2,
		"narrow floating host reclamps to client")
	root.size = Vector2i(900, 630)
	root.content_scale_factor = 1.5
	app.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	app.grow_horizontal = Control.GROW_DIRECTION_END
	app.grow_vertical = Control.GROW_DIRECTION_END
	app.position = Vector2.ZERO
	app.size = Vector2(900, 630)
	await frames(14)
	third.clamp_to_client()
	check(third.get_global_rect().end.x <= app.get_global_rect().end.x + 2,
		"1.5x content scale retains bounded floating panel")
	check(app.inspector.get_global_rect().end.x <= app.get_global_rect().end.x + 2,
		"1.5x content scale retains dock within workspace")
	check(app.current_document().revision == initial_rev and app.current_document().is_dirty() == initial_dirty, "no drag modifies document revision/dirty flag")
	print("T082_CROSS_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T082_CROSS_NATIVE_PASSED")
	quit(1 if failures else 0)
