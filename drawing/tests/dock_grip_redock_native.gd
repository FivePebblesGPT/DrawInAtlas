extends SceneTree
## T-091: same-frame tab rebuilds and tall-host grip redocking under real X11 input.
const PREFS: String = "user://t091-grip-redock-native.json"
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T091_GRIP_NATIVE_FAILED: " + label)

func frames(n: int = 4) -> void:
	for i: int in range(n):
		await process_frame

func button(point: Vector2, pressed: bool) -> void:
	var input: InputEventMouseButton = InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.position = point
	input.global_position = point
	input.pressed = pressed
	root.push_input(input, true)

func motion(point: Vector2) -> void:
	var input: InputEventMouseMotion = InputEventMouseMotion.new()
	input.position = point
	input.global_position = point
	input.relative = Vector2(8, 8)
	input.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(input, true)

func key_escape() -> void:
	var input: InputEventKey = InputEventKey.new()
	input.keycode = KEY_ESCAPE
	input.pressed = true
	root.push_input(input, true)

func capture_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and image.get_width() >= 1280 and image.get_height() >= 800,
		"native framebuffer readback " + label)
	var screenshots: String = OS.get_environment("T091_SCREENSHOTS")
	if not screenshots.is_empty():
		DirAccess.make_dir_recursive_absolute(screenshots)
		check(image.save_png(screenshots.path_join(label + ".png")) == OK,
			"optional captured screenshot " + label)


func assert_unique_host(host: DrawingFloatingHost, group_id: String, members: Array) -> void:
	var header: HBoxContainer = host._header
	check(header.get_child_count() == 3, "one grip/tab strip/close after rebuild")
	check(host._body.get_child_count() == 1, "one detached active-group frame")
	check(host.tab_strips.size() == 1 and host.group_frames.size() == 1, "one strip and frame indexed")
	check(host.tab_buttons.size() == members.size(), "exactly one button per member")
	var strip: Node = header.get_child(1)
	check(strip.name == "TabStripScroll_" + group_id, "current tab strip immediately replaces old strip")
	var row: Node = strip.get_child(0)
	check(row.get_child_count() == members.size(), "tab strip contains only current tabs")
	var active_id: String = String(host.layout.group_info(group_id)["active"])
	check(host.views[active_id].get_parent() == host.group_frames[group_id], "only active panel attached to visible frame")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires X11 native framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_settings_path = PREFS
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await frames(12)
	var baseline_rev: int = workspace.current_document().revision
	var colors_view: Control = workspace.dock_views["colors"]
	var history_view: Control = workspace.dock_views["history"]
	var host_id: String = workspace.float_group("colors")
	check(not host_id.is_empty(), "created first floating host")
	await frames(8)
	var host: DrawingFloatingHost = workspace.floating_hosts[host_id]
	var group_id: String = String(workspace.dock_layout.container_info(host_id)["groups"][0]["id"])
	assert_unique_host(host, group_id, ["colors"])
	check(workspace.move_group_to_floating("history", host_id), "merge second dock group as a tab")
	await frames(6)
	var members: Array = workspace.dock_layout.group_info(group_id)["panels"]
	check(members == ["colors", "history"], "unique two-tab group membership")
	# Three synchronous refreshes must never show stacked chrome or free a live panel.
	check(workspace.dock_layout.select_panel("colors"), "activate first tab for same-frame swap")
	workspace._render_dock()
	check(workspace.dock_layout.select_panel("history"), "activate second tab within same frame")
	workspace._render_dock()
	host.render()
	assert_unique_host(host, group_id, members)
	await frames(4)
	assert_unique_host(host, group_id, members)
	check(colors_view == workspace.dock_views["colors"] and history_view == workspace.dock_views["history"],
		"stable panel identity across redraws")
	var tab: Button = host.tab_buttons["history"]
	var tab_point: Vector2 = tab.get_global_rect().get_center()
	button(tab_point, true)
	await frames(2)
	button(tab_point, false)
	await frames(5)
	check(String(workspace.dock_layout.group_info(group_id)["active"]) == "history", "native tab click switches active panel")
	assert_unique_host(host, group_id, members)
	await capture_frame("t091-unique-multitab")

	# Normal grip dragging in the canvas keeps move-host behavior.
	host.set_host_rect(Rect2(Vector2(240, 55), Vector2(350, 655)))
	await frames(4)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var start: Vector2 = grip.get_global_rect().get_center()
	button(start, true)
	await frames(2)
	motion(start + Vector2(85, 30))
	await frames(2)
	button(start + Vector2(85, 30), false)
	await frames(5)
	check(host.position.distance_to(Vector2(240, 55)) > 30.0, "normal grip still moves host over canvas")
	check(workspace.dock_layout.owner_of("colors") == host_id and not workspace.dock_drag.is_dragging(),
		"ordinary host move leaves model and drag coordinator clean")

	# The host is taller than the destination dock group. Pointer can reach a
	# dock tab even when this source host overlays the dock on screen.
	host.set_host_rect(Rect2(Vector2(570, 30), Vector2(430, 720)))
	await frames(5)
	var strip: ScrollContainer = workspace.dock_tab_strips.values()[0] as ScrollContainer
	var target: Vector2 = strip.get_global_rect().get_center()
	check(not workspace._dock_target_at(target).is_empty(), "visible dock has a valid target")
	start = grip.get_global_rect().get_center()
	var unchanged: Dictionary = workspace.dock_layout.snapshot()
	button(start, true)
	await frames(2)
	motion(start.lerp(target, 0.55))
	await frames(2)
	motion(target)
	await frames(3)
	check(workspace.dock_drop_hint.visible, "tall host shows dock insertion target without Shift")
	check(workspace.dock_layout.snapshot() == unchanged, "hover redock preview is model-immutable")
	button(target, false)
	await frames(8)
	check(workspace.dock_layout.owner_of("colors") == "right" and workspace.dock_layout.owner_of("history") == "right",
		"grip release docks entire tab group")
	check(workspace.floating_hosts.is_empty() and not workspace.dock_drag.is_dragging(),
		"empty host reaped and transaction cleared")
	check(colors_view == workspace.dock_views["colors"] and history_view == workspace.dock_views["history"],
		"redocking preserves both panel identities")
	await capture_frame("t091-tall-redocked")

	# Escape during a second grip-to-dock hover must not transfer any panel.
	var second: String = workspace.float_group("layers")
	check(not second.is_empty(), "second host floated for cancel case")
	await frames(6)
	var cancel_host: DrawingFloatingHost = workspace.floating_hosts[second]
	cancel_host.set_host_rect(Rect2(Vector2(555, 28), Vector2(430, 730)))
	await frames(4)
	var cancel_grip: Button = cancel_host._header.get_node("MoveHandle") as Button
	start = cancel_grip.get_global_rect().get_center()
	if workspace.dock_tab_strips.is_empty():
		target = workspace.inspector.get_global_rect().get_center()
	else:
		strip = workspace.dock_tab_strips.values()[0] as ScrollContainer
		target = strip.get_global_rect().get_center()
	unchanged = workspace.dock_layout.snapshot()
	button(start, true)
	await frames(2)
	motion(target)
	await frames(3)
	check(workspace.dock_drop_hint.visible, "cancellable redock target visible")
	key_escape()
	await frames(2)
	button(target, false)
	await frames(5)
	check(workspace.dock_layout.snapshot() == unchanged, "Escape cancels redock without mutation")
	check(not workspace.dock_drag.is_dragging() and not workspace.dock_drop_hint.visible,
		"cancellation clears preview state")

	# Leaving a valid target returns to host motion; release over canvas must
	# never commit a previously-previewed redock.
	start = cancel_grip.get_global_rect().get_center()
	unchanged = workspace.dock_layout.snapshot()
	button(start, true)
	await frames(2)
	motion(target)
	await frames(3)
	check(workspace.dock_drop_hint.visible, "re-entry presents a valid target")
	var outside: Vector2 = Vector2(460, 610)
	motion(outside)
	await frames(3)
	check(not workspace.dock_drop_hint.visible and not workspace.dock_drag.is_dragging(),
		"leaving dock clears stale pending target")
	button(outside, false)
	await frames(5)
	check(workspace.dock_layout.snapshot() == unchanged and workspace.dock_layout.owner_of("layers") == second,
		"release outside dock never commits stale preview")
	check(workspace.current_document().revision == baseline_rev, "dock actions never change document revision")

	print("T091_GRIP_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T091_GRIP_NATIVE_PASSED")
	quit(1 if failures else 0)
