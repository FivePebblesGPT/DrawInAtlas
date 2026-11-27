extends SceneTree
## T-223 Atlas embedding: marker actions own only the shared workspace layout.

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T223_ATLAS_FAILED: " + message)

func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame

func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)
		await frames(3)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1050, 720)
	var atlas_host: Control = Control.new()
	root.add_child(atlas_host)
	atlas_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	atlas_host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(17)
	var layout: DrawingDockLayout = workspace.dock_layout
	var revision: int = workspace.current_document().revision
	var dirty: bool = workspace.current_document().is_dirty()
	check(layout.set_panel_visible("brushes", false), "hide Brushes for compact marker fixture")
	check(layout.merge_groups("layers", "colors", 1), "prepare two-panel group")
	workspace._render_dock()
	await frames(6)
	var marker: Button = workspace.dock_group_handles["colors"]
	check(workspace.dock_header_buttons["colors"] == marker and marker.focus_mode == Control.FOCUS_ALL,
		"Atlas exposes one focusable group control")
	check(workspace.dock_views.size() == layout.rail_icons("right").size() + 2 and workspace.dock_views.has("text_options"),
		"hidden Brushes remains the only extra view")
	check(workspace.get_parent() == atlas_host and not workspace._window_quit_guard_enabled,
		"Atlas owns application window")
	await click(marker.get_global_rect().get_center())
	check(layout.group_info("colors")["collapsed"], "embedded marker collapses group")
	await click((workspace.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
	check(not layout.group_info("colors")["collapsed"], "embedded active icon shares collapse bit")
	var snapshot: Dictionary = layout.snapshot()
	await click((workspace.dock_group_handles["colors"] as Button).get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(workspace.dock_group_menu.visible and layout.snapshot() == snapshot,
		"embedded RMB menu is non-mutating")
	workspace.dock_group_menu.hide()
	await frames(4)
	workspace._show_dock_group_menu("colors", (workspace.dock_group_handles["colors"] as Button).global_position)
	workspace.dock_group_menu.hide()
	workspace._dock_group_menu_action(5)
	await frames(10)
	check(workspace.floating_hosts.size() == 1 and layout.owner_of("layers") == layout.owner_of("colors") and
		layout.owner_of("colors") != "right", "embedded group float transfers all tabs to one host")
	var floating: DrawingFloatingHost = workspace.floating_hosts.values()[0]
	check(floating.tab_buttons.size() == 2 and floating.group_handles.size() == 1 and
		workspace.dock_views["colors"].get_parent() == floating.group_frames["colors"],
		"floating Atlas panel reuses original view and one-group invariant")
	check(layout.move_group("colors", "right", 0), "redock whole Atlas group")
	workspace._reap_empty_hosts()
	workspace._render_dock()
	await frames(7)
	check(workspace.floating_hosts.is_empty() and workspace.dock_tab_buttons.has("layers") and
		workspace.dock_tab_buttons.has("colors"), "redock restores icons without duplicate views")
	check(workspace.current_document().revision == revision and workspace.current_document().is_dirty() == dirty,
		"Atlas history and document dirty bit unchanged")
	print("T223_ATLAS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
