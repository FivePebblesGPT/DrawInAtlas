extends SceneTree
## T-255: Atlas embeds the same clipped floating-tab input contract.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T255_ATLAS_FAILED: " + label)


func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame


func click(point: Vector2) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)
		await frames(4)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var atlas_host: Control = Control.new()
	root.add_child(atlas_host)
	atlas_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	atlas_host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var color_view: Control = app.dock_views["colors"]
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "Atlas floats Colors")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	host.set_host_rect(Rect2(220, 120, 236, 390))
	for panel: String in ["layers", "brushes", "history"]:
		check(app.move_group_to_floating(panel, host_id), "Atlas merges " + panel)
		await frames(5)
	var future: VBoxContainer = VBoxContainer.new()
	future.name = "future"
	app.dock_stash.add_child(future)
	app.dock_views["future"] = future
	check(app.dock_layout.register_panel("future") and
		app.dock_layout.attach_panel("future", "right", "future"), "Atlas registers unknown panel")
	app._render_dock()
	await frames(5)
	check(app.move_group_to_floating("future", host_id), "five tabs in one Atlas host")
	await frames(5)
	var group_id: String = app.dock_layout.group_of("colors")
	check(app.dock_layout.select_panel("future"), "set distinct active tab")
	app._render_dock()
	await frames(5)
	var strip: ScrollContainer = host.tab_strips[group_id] as ScrollContainer
	strip.scroll_horizontal = int(strip.get_h_scroll_bar().max_value)
	await frames(8)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var point: Vector2 = grip.get_global_rect().position + Vector2(10, 20)
	check((host.tab_buttons["colors"] as Button).get_global_rect().has_point(point) and
		not strip.get_global_rect().has_point(point), "Atlas clipped tab projects over grip")
	await click(point)
	check(app.dock_layout.group_info(group_id)["active"] == "future" and host.visible,
		"Atlas grip click does not switch to invisible tab")
	strip.scroll_horizontal = 0
	await frames(6)
	var close: Button = host._header.get_node("HideHost") as Button
	var overlap: Rect2 = close.get_global_rect().intersection(
		(host.tab_buttons["future"] as Button).get_global_rect())
	var close_point: Vector2 = overlap.position + Vector2(2, 20)
	check(overlap.size.x > 8.0 and host._hit_resize_edges(close_point) == Vector4i.ZERO,
		"Atlas close hit target overlaps invisible tab outside resize edge")
	await click(close_point)
	check(not host.visible, "Atlas close still hides the overflowing host")
	app.show_hidden_floating_hosts()
	await frames(5)
	check(host.visible and app.dock_views["colors"] == color_view,
		"Atlas restores original panel identity on reopen")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"Atlas source and global history unaffected")
	check(app.get_parent() == atlas_host, "no Atlas lifecycle takeover")
	print("T255_ATLAS: %d checks; %d failed" % [checks, failures])
	print("T255_ATLAS_PASSED" if failures == 0 else "T255_ATLAS_FAILED")
	quit(1 if failures else 0)
