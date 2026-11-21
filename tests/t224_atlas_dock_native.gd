extends SceneTree
## T-224: shared embedded Atlas workspace transfers a panel, never its document.
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T224_ATLAS_FAILED: " + message)

func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = point
	e.global_position = point
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	root.push_input(e, true)

func motion(point: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = point
	e.global_position = point
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.relative = Vector2(20, 12)
	root.push_input(e, true)

func drag(source: Control, target: Vector2) -> void:
	var start: Vector2 = source.get_global_rect().get_center()
	mouse(start, true)
	await frames(3)
	motion(start.lerp(target, 0.5))
	await frames(3)
	motion(target)
	await frames(5)

func release(point: Vector2) -> void:
	mouse(point, false)
	await frames(10)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1100, 740)
	var atlas: Control = Control.new()
	root.add_child(atlas)
	atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	atlas.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	check(layout.set_panel_visible("brushes", false) and layout.set_group_collapsed("colors", true),
		"compact icon geometry for embedded workspace")
	app._render_dock()
	await frames(7)
	var initial: Dictionary = layout.snapshot()
	var destination: Vector2 = (app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center()
	await drag(app.dock_tab_buttons["colors"], destination)
	check(app.dock_drop_caption.text == "Group panel with Layers" and app.dock_merge_outline.visible,
		"Atlas uses same green proximity preview")
	check(layout.snapshot() == initial, "Atlas preview keeps model unchanged")
	await release(destination)
	check(layout.group_of("colors") == "layers" and layout.group_info("colors").is_empty(),
		"only dragged Colors panel joins Layers")
	var host_id: String = app.float_group("history")
	await frames(8)
	check(not host_id.is_empty() and app.floating_hosts.has(host_id), "Atlas floating host created")
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	var target: Vector2 = (host.tab_buttons["history"] as Control).get_global_rect().get_center()
	var before: Dictionary = layout.snapshot()
	await drag(app.dock_tab_buttons["colors"], target)
	check(host._hint.visible and app.dock_merge_outline.visible and
		app.dock_drop_caption.text.begins_with("Group panel"), "dock-to-floating merge preview")
	check(layout.snapshot() == before, "floating preview non-mutating")
	await release(target)
	check(layout.owner_of("colors") == host_id and layout.owner_of("layers") == "right",
		"floating transfer moves one icon and leaves its old group")
	check(layout.container_info(host_id)["groups"].size() == 1 and
		host.tab_buttons.has("history") and host.tab_buttons.has("colors"),
		"floating host remains one group with both tabs")
	check(app.dock_views["colors"].get_parent() == app.dock_stash or
		app.dock_views["colors"].get_parent() == host.group_frames[layout.group_of("colors")],
		"shared Colors view is reused, never duplicated")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"external Atlas document history remains unchanged")
	check(not app._window_quit_guard_enabled and app.get_parent() == atlas,
		"Atlas retains host window and lifecycle authority")
	print("T224_ATLAS_NATIVE: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
