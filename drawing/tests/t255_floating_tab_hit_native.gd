extends SceneTree
## T-255: clipped floating tabs must not intercept grip/close or offscreen drag.

const PREFS: String = "user://t255-floating-hit.json"
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T255_NATIVE_FAILED: " + label)


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


func move(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(14, 10)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func click(point: Vector2) -> void:
	mouse(point, true)
	await frames(3)
	mouse(point, false)
	await frames(5)


func capture(label: String) -> void:
	var directory: String = OS.get_environment("T255_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK,
		"saved screenshot " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "float Colors")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	host.set_host_rect(Rect2(220, 120, 236, 380))
	for panel: String in ["layers", "brushes", "history"]:
		check(app.move_group_to_floating(panel, host_id), "merge " + panel)
		await frames(5)
	var future: VBoxContainer = VBoxContainer.new()
	future.name = "FuturePanel"
	app.dock_stash.add_child(future)
	app.dock_views["future"] = future
	check(app.dock_layout.register_panel("future") and
		app.dock_layout.attach_panel("future", "right", "future"), "register fallback panel")
	app._render_dock()
	await frames(5)
	check(app.move_group_to_floating("future", host_id), "five tabs in one host")
	await frames(6)
	var group_id: String = app.dock_layout.group_of("colors")
	check(host.tab_buttons.size() == 5 and host.tab_strips.size() == 1,
		"overflowing icon strip owns five tabs")
	check(app.dock_layout.select_panel("future"), "select rightmost fallback panel")
	app._render_dock()
	await frames(5)
	var strip: ScrollContainer = host.tab_strips[group_id] as ScrollContainer
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var close: Button = host._header.get_node("HideHost") as Button
	check(strip.get_h_scroll_bar().max_value - strip.get_h_scroll_bar().page > 40,
		"genuinely overflowed strip")
	strip.scroll_horizontal = int(strip.get_h_scroll_bar().max_value)
	await frames(8)
	var grip_point: Vector2 = grip.get_global_rect().position + Vector2(10, 20)
	var offscreen: Button = host.tab_buttons["colors"] as Button
	check(offscreen.get_global_rect().has_point(grip_point) and
		not strip.get_global_rect().has_point(grip_point), "hidden Colors hit rectangle overlaps move grip")
	var snapshot: Dictionary = app.dock_layout.snapshot()
	await click(grip_point)
	check(app.dock_layout.snapshot() == snapshot and host.visible,
		"clicking move grip does not activate clipped-away Colors tab")
	await capture("grip-scroll-right")

	var start_position: Vector2 = host.position
	mouse(grip_point, true)
	await frames(2)
	move(grip_point + Vector2(45, 30))
	await frames(3)
	mouse(grip_point + Vector2(45, 30), false)
	await frames(6)
	check(host.position.distance_to(start_position) > 20.0,
		"dragging grip moves host despite clipped-away tab overlap")
	check(app.dock_layout.snapshot() == snapshot and not app.dock_drag.is_dragging(),
		"grip move leaves panel group ownership intact")

	# A partially visible tab must still work in its genuinely visible segment.
	strip = host.tab_strips[group_id] as ScrollContainer
	var partial: Button = host.tab_buttons["layers"] as Button
	var visible_rect: Rect2 = partial.get_global_rect().intersection(strip.get_global_rect())
	check(visible_rect.size.x >= 8.0 and visible_rect.size.x < partial.size.x,
		"Layers has a partially visible, clipped icon")
	await click(visible_rect.get_center())
	check(app.dock_layout.group_info(group_id)["active"] == "layers",
		"visible section of partly clipped tab remains clickable")
	await capture("partially-visible-tab")

	# Scroll back: the hidden rightmost tab projects over the close button.
	strip = host.tab_strips[group_id] as ScrollContainer
	strip.scroll_horizontal = 0
	await frames(8)
	close = host._header.get_node("HideHost") as Button
	var future_tab: Button = host.tab_buttons["future"] as Button
	var overlap: Rect2 = close.get_global_rect().intersection(future_tab.get_global_rect())
	check(overlap.size.x >= 8.0 and not strip.get_global_rect().has_point(overlap.get_center()),
		"hidden Future tab projects across visible close button")
	var close_point: Vector2 = overlap.position + Vector2(2, 20)
	check(host._hit_resize_edges(close_point) == Vector4i.ZERO,
		"close test uses button interior outside documented 8px resize border")
	await click(close_point)
	check(not host.visible and app.dock_layout.owner_of("colors") == host_id,
		"close button works even when hidden tab lies underneath")
	app.show_hidden_floating_hosts()
	await frames(7)
	check(host.visible and app.dock_layout.group_info(group_id)["active"] == "layers",
		"reopened host retains selected visible tab")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"clipping, grip and close never change source/history")
	print("T255_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T255_NATIVE_PASSED" if failures == 0 else "T255_NATIVE_FAILED")
	quit(1 if failures else 0)
