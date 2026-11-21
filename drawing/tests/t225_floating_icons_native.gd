extends SceneTree
## T-225: native floating icon identity, interaction, focus, grip, persistence and scaling.

const PREFS: String = "user://t225-floating-icons.json"
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T225_NATIVE_FAILED: " + label)


func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame


func mouse(point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event, true)


func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(14, 9)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	mouse(point, true)
	await frames(3)
	mouse(point, false)
	await frames(7)


func drag(source: Control, target: Vector2) -> void:
	var start: Vector2 = source.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(start.lerp(target, 0.5))
	await frames(3)
	motion(target)
	await frames(4)


func release(point: Vector2) -> void:
	mouse(point, false)
	await frames(9)


func press(key: Key, ctrl: bool = false, alt: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(5)


func capture(label: String) -> void:
	var directory: String = OS.get_environment("T225_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK,
		"native screenshot " + label)


func icon_check(app: Control, host: DrawingFloatingHost, panel_id: String) -> void:
	var tab: Button = host.tab_buttons.get(panel_id) as Button
	check(tab != null, panel_id + " floating tab exists")
	if tab == null:
		return
	var shared: Texture2D = app._dock_icon(panel_id)
	check(shared != null and tab.icon == shared and tab.icon.get_width() > 0,
		panel_id + " shares dock icon (including fallback)")
	check(tab.text.is_empty() and tab.expand_icon and tab.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		panel_id + " uses centered icon only")
	check(tab.custom_minimum_size == Vector2(42, 42) and tab.focus_mode == Control.FOCUS_ALL,
		panel_id + " has consistent compact keyboard target")
	check(tab.tooltip_text.contains(panel_id.capitalize()), panel_id + " has name tooltip")
	if tab.get_property_list().any(func(p: Dictionary) -> bool: return p["name"] == "accessibility_name"):
		check(String(tab.get("accessibility_name")).contains(panel_id.capitalize()),
			panel_id + " has accessible name")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires a native X11 framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.layout_persistence_enabled = true
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var float_id: String = app.float_group("colors")
	await frames(9)
	check(not float_id.is_empty(), "float Colors group")
	var host: DrawingFloatingHost = app.floating_hosts[float_id]
	host.set_host_rect(Rect2(Vector2(250, 125), Vector2(288, 340)))
	await frames(5)
	icon_check(app, host, "colors")
	check(host.tab_buttons["colors"].button_pressed, "active tab is pressed")
	await capture("single-icon")
	var before: Dictionary = layout.snapshot()
	await click(host.tab_buttons["colors"])
	check(host.visible and app.floating_hosts.has(float_id) and layout.snapshot() == before,
		"active floating icon click never collapses, closes or changes persistence")
	check(host.tab_buttons["colors"].button_pressed, "active icon remains pressed after click")
	for panel_id: String in ["layers", "brushes", "history"]:
		check(app.move_group_to_floating(panel_id, float_id), "merge " + panel_id + " into one float host")
		await frames(7)
		icon_check(app, host, panel_id)
	check(host.group_frames.size() == 1 and host.tab_buttons.size() == 4,
		"one floating group with four compact icons")
	check(host.tab_buttons.size() == 4 and host.tab_strips.size() == 1,
		"one scrollable icon strip for four tabs")
	await capture("four-icons")
	# Use accessible selection directly before keyboard gestures so the selected
	# state remains visible, without relying on OS-specific keyboard focus routing.
	await click(host.tab_buttons["layers"])
	check(layout.group_info(layout.group_of("layers"))["active"] == "layers" and
		host.tab_buttons["layers"].button_pressed and not host.tab_buttons["colors"].button_pressed,
		"pointer switches active icon and matching panel view")
	var stable: Dictionary = layout.snapshot()
	await click(host.tab_buttons["layers"])
	check(layout.snapshot() == stable and host.visible and host.tab_buttons["layers"].button_pressed,
		"repeat active click leaves floating host and state unchanged")
	(host.tab_buttons["colors"] as Button).grab_focus()
	await frames(3)
	await press(KEY_ENTER)
	check(layout.group_info(layout.group_of("colors"))["active"] == "colors" and host.visible,
		"keyboard activation changes tab without closing group")
	check((host.tab_buttons["colors"] as Button).has_focus(),
		"keyboard focus survives floating tab rebuild")
	# Real pointer drag is one panel; Escape restores exact model transaction.
	var target: Vector2 = (host.tab_buttons["layers"] as Control).get_global_rect().position + Vector2(3, 19)
	var snapshot: Dictionary = layout.snapshot()
	await drag(host.tab_buttons["history"], target)
	check(app.dock_drag.is_dragging() and app.dock_drag.source_kind() == DrawingDockDrag.PANEL,
		"floating icon drag selects one panel, never whole group")
	await press(KEY_ESCAPE)
	await release(target)
	check(layout.snapshot() == snapshot and not app.dock_drag.is_dragging(),
		"Escape cancels icon reorder without changing ownership/order")
	# Grip is a separate hit target and moves the host, not a single tab.
	var grip: Button = host.get_node("FloatingColumn/FloatingTitleBar/MoveHandle") as Button
	var initial: Vector2 = host.position
	var grip_target: Vector2 = grip.get_global_rect().get_center() + Vector2(55, 40)
	await drag(grip, grip_target)
	await release(grip_target)
	check(host.position.distance_to(initial) > 20.0 and layout.snapshot() == snapshot,
		"grip moves whole floating frame without rearranging tabs")
	# Hide/reopen and persistence must reuse the same live Controls.
	app.hide_floating_host(float_id)
	await frames(4)
	check(not host.visible and layout.owner_of("colors") == float_id, "hide keeps tab ownership")
	app.show_hidden_floating_hosts()
	await frames(6)
	check(host.visible and host.tab_buttons.has("history") and host.tab_buttons["history"].icon != null,
		"reopen restores identical icon identities")
	check(app._save_workspace_layout(), "persist icon-based floating layout")
	await capture("reopened")
	app.queue_free()
	await frames(9)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_settings_path = PREFS
	reopened.layout_persistence_enabled = true
	reopened.preferences_persistence_enabled = false
	root.add_child(reopened)
	await frames(20)
	check(reopened.layout_recovery_status == "loaded" and reopened.floating_hosts.has(float_id),
		"saved floating host restores after restart")
	var restored: DrawingFloatingHost = reopened.floating_hosts[float_id]
	for panel_id: String in ["colors", "layers", "brushes", "history"]:
		icon_check(reopened, restored, panel_id)
	check(reopened.dock_layout.container_info(float_id)["groups"].size() == 1,
		"restart preserves one-group invariant")
	var future: VBoxContainer = VBoxContainer.new()
	future.name = "FuturePanel"
	reopened.dock_stash.add_child(future)
	reopened.dock_views["future"] = future
	check(reopened.dock_layout.register_panel("future") and reopened.dock_layout.attach_panel("future", "right", "future"),
		"register future panel without icon asset")
	reopened._render_dock()
	await frames(7)
	check(reopened.move_group_to_floating("future", float_id), "future tab joins floating group")
	await frames(7)
	icon_check(reopened, restored, "future")
	check(restored.tab_buttons.size() == 5 and restored.tab_strips.size() == 1,
		"one scrollable icon strip for five tabs")
	await capture("five-icons")
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		reopened._clamp_floating_hosts()
		await frames(7)
		check(restored.get_global_rect().position.x >= 0 and
			restored.get_global_rect().end.x <= reopened.size.x + 1,
			"scaling %.1fx keeps compact icon tabs within window" % scale)
		await capture("scale-%d" % int(scale * 100))
	root.content_scale_factor = 1.0
	check(reopened.current_document().revision == revision and reopened.current_document().is_dirty() == dirty,
		"tab interactions never changed document pixels or history")
	print("T225_NATIVE: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
