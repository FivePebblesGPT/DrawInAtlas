extends SceneTree
## T-091: real input and framebuffer witness (requires X11/Xvfb, not headless).
const PREFS: String = "user://t091-native-layout.json"
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T091_NATIVE_FAILED: " + label)

func frames(n: int = 5) -> void:
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
	e.relative = Vector2(12, 12)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)

func drag(start: Vector2, finish: Vector2) -> void:
	mouse(start, true)
	await frames(2)
	motion(start.lerp(finish, 0.5))
	await frames(2)
	motion(finish)
	await frames(3)
	mouse(finish, false)
	await frames(5)

func capture(label: String) -> void:
	var path: String = OS.get_environment("T091_SCREENSHOTS")
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path.path_join(label + ".png")) == OK,
		"saved native screenshot " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires native framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.layout_persistence_enabled = true
	root.add_child(app)
	await frames(15)
	var doc_revision: int = app.current_document().revision
	var float_id: String = app.float_group("colors")
	await frames(8)
	check(not float_id.is_empty(), "group floated")
	var host: DrawingFloatingHost = app.floating_hosts[float_id]
	host.set_host_rect(Rect2(Vector2(290, 175), Vector2(325, 270)))
	await frames(6)
	check(app.dock_layout.container_info(float_id)["groups"].size() == 1, "one group in model")
	check(host.group_frames.size() == 1 and host.tab_buttons.size() == 1,
		"exactly one tab strip and active group")
	var header: HBoxContainer = host.get_node("FloatingColumn/FloatingTitleBar") as HBoxContainer
	check(header.get_child_count() == 3 and header.get_child(0).name == "MoveHandle" and
		header.get_child(2).name == "HideHost", "compact grip-tabs-close header")
	check(host.get_node_or_null("FloatingColumn/ResizeBar") == null and
		host.get_node_or_null("FloatingColumn/FloatingTitleBar/FloatingTitle") == null,
		"no redundant title or resize bar")
	check(host._scroll != null and host._scroll.size.y > 40.0, "single active panel visible")
	await capture("t091-compact-header")
	var base: Rect2 = Rect2(Vector2(290, 175), Vector2(325, 270))
	# Resizing from four edges and four corners must move the intended edge only.
	var edge_cases: Array[Dictionary] = [
		{"name": "left", "offset": Vector2(3, 135), "delta": Vector2(-45, 0)},
		{"name": "right", "offset": Vector2(322, 135), "delta": Vector2(45, 0)},
		{"name": "top", "offset": Vector2(162, 3), "delta": Vector2(0, -38)},
		{"name": "bottom", "offset": Vector2(162, 267), "delta": Vector2(0, 38)},
		{"name": "top-left", "offset": Vector2(3, 3), "delta": Vector2(-35, -35)},
		{"name": "top-right", "offset": Vector2(322, 3), "delta": Vector2(35, -35)},
		{"name": "bottom-left", "offset": Vector2(3, 267), "delta": Vector2(-35, 35)},
		{"name": "bottom-right", "offset": Vector2(322, 267), "delta": Vector2(35, 35)}]
	for edge: Dictionary in edge_cases:
		host.set_host_rect(base)
		await frames(3)
		var from: Vector2 = host.get_global_rect().position + edge["offset"]
		await drag(from, from + edge["delta"])
		var final_rect: Rect2 = Rect2(host.position, host.size)
		var shifted: Vector2 = edge["delta"]
		check(final_rect.size.x >= base.size.x + absf(shifted.x) - 3.0 and
			final_rect.size.y >= base.size.y + absf(shifted.y) - 3.0,
			"pointer edge/corner resize: " + edge["name"])
		check(host.position.x >= 0 and host.position.y >= 0 and
			host.get_global_rect().end.x <= app.get_global_rect().end.x + 1 and
			host.get_global_rect().end.y <= app.get_global_rect().end.y + 1,
			"resize stays in client: " + edge["name"])
	# Real pointer drags into the client margin must stop the grabbed edge,
	# not translate the opposite edge to accommodate an oversized frame.
	var bounds_cases: Array[Dictionary] = [
		{"name": "left", "frame": Rect2(48, 175, 325, 270),
			"offset": Vector2(3, 135), "delta": Vector2(-49, 0), "fixed": 373.0, "limit": 5.0},
		{"name": "right", "frame": Rect2(800, 175, 325, 270),
			"offset": Vector2(322, 135), "delta": Vector2(155, 0), "fixed": 800.0, "limit": 1275.0},
		{"name": "top", "frame": Rect2(290, 48, 325, 270),
			"offset": Vector2(162, 3), "delta": Vector2(0, -49), "fixed": 318.0, "limit": 5.0},
		{"name": "bottom", "frame": Rect2(290, 460, 325, 270),
			"offset": Vector2(162, 267), "delta": Vector2(0, 70), "fixed": 460.0, "limit": 795.0}]
	for boundary: Dictionary in bounds_cases:
		host.set_host_rect(boundary["frame"])
		await frames(3)
		var down: Vector2 = host.get_global_rect().position + boundary["offset"]
		await drag(down, down + boundary["delta"])
		var actual: Rect2 = Rect2(host.position, host.size)
		var left_or_top: bool = boundary["name"] == "left" or boundary["name"] == "top"
		var horizontal: bool = boundary["name"] == "left" or boundary["name"] == "right"
		var fixed_edge: float = (actual.end.x if left_or_top else actual.position.x) if horizontal else (actual.end.y if left_or_top else actual.position.y)
		var dragged_edge: float = (actual.position.x if left_or_top else actual.end.x) if horizontal else (actual.position.y if left_or_top else actual.end.y)
		check(absf(fixed_edge - boundary["fixed"]) < 1.0,
			"native edge overdrag preserves opposite anchor: " + boundary["name"])
		check(absf(dragged_edge - boundary["limit"]) < 1.0,
			"native edge overdrag stops at client margin: " + boundary["name"])
	# Move using the only grip. Escape/cancel does not affect model ownership.
	host.set_host_rect(base)
	await frames(4)
	var grip: Button = header.get_node("MoveHandle") as Button
	var start: Vector2 = grip.get_global_rect().get_center()
	await drag(start, start + Vector2(55, 36))
	check(host.position.distance_to(base.position) > 30, "header grip moves host")
	var before: Dictionary = app.dock_layout.snapshot()
	host.hide_requested.emit(float_id)
	check(not host.visible and app.dock_layout.snapshot() == before, "hide retains ownership")
	app.show_hidden_floating_hosts()
	await frames(5)
	check(host.visible and host.tab_buttons.has("colors"), "Window recovery restores same tab")
	# Capture the width on a synthetic splitter drag signal at settled geometry.
	app.dock_split.split_offset = roundi(app.dock_split.size.x) - 345
	await frames(6)
	var actual_width: int = roundi(app.inspector.size.x)
	app.dock_split.dragged.emit(app.dock_split.split_offset)
	await frames(8)
	var prefs: Dictionary = DrawingDockPersistence.read_file(PREFS)
	check(not prefs.is_empty(), "splitter changes autosave on drag")
	check(abs(int(prefs.get("dock_width", 0)) - actual_width) <= 2,
		"settled splitter width saved without shutdown")
	var host_position: Vector2 = host.position
	var host_size: Vector2 = host.size
	app.queue_free()
	await frames(10)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_settings_path = PREFS
	reopened.layout_persistence_enabled = true
	root.add_child(reopened)
	await frames(15)
	check(reopened.layout_recovery_status == "loaded" and reopened.floating_hosts.size() == 1,
		"reload restores floating group")
	check(abs(roundi(reopened.inspector.size.x) - actual_width) <= 3,
		"dragged dock width restored after layout")
	var restored_host: DrawingFloatingHost = reopened.floating_hosts[float_id]
	check(restored_host.position.distance_to(host_position) <= 3.0 and
		restored_host.size.distance_to(host_size) <= 3.0, "host geometry restored")
	check(reopened.current_document().revision == doc_revision, "workspace changes don't edit drawing")
	# Clamp on a narrower workspace, then on a 1.5x canvas scale.
	root.size = Vector2i(540, 460)
	reopened.size = Vector2(540, 460)
	await frames(12)
	check(restored_host.get_global_rect().end.x <= reopened.get_global_rect().end.x + 2 and
		restored_host.get_global_rect().end.y <= reopened.get_global_rect().end.y + 2,
		"narrow window keeps host accessible")
	check(reopened._save_workspace_layout(), "save while viewport width is clamped")
	var narrow_prefs: Dictionary = DrawingDockPersistence.read_file(PREFS)
	check(abs(int(narrow_prefs["dock_width"]) - actual_width) <= 2,
		"temporary viewport clamp never overwrites chosen width")
	root.size = Vector2i(1000, 700)
	root.content_scale_factor = 1.5
	reopened.size = Vector2(1000, 700)
	await frames(12)
	check(restored_host.get_global_rect().end.x <= reopened.get_global_rect().end.x + 2,
		"HiDPI host in client")
	check(abs(reopened._expanded_dock_width - actual_width) <= 2,
		"preferred width survives narrow and HiDPI viewport changes")
	await capture("t091-narrow-restored")
	print("T091_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T091_NATIVE_PASSED")
	quit(1 if failures else 0)
