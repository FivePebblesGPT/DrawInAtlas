extends SceneTree
## T-251: the Atlas host embeds one canonical Drawing workspace and must not
## inherit a canvas-side dock toggle or lose panel identity after reparenting.

var checks: int = 0
var failures: int = 0


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T251_ATLAS_FAILED: " + label)


func frames(count: int = 7) -> void:
	for _i: int in range(count):
		await process_frame


func click(point: Vector2) -> void:
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await frames(3)


func check_bounds(workspace: Control, minimized: bool) -> void:
	var toggle: Button = workspace.dock_toggle
	var dock: Rect2 = workspace.inspector.get_global_rect()
	var area: Rect2 = toggle.get_global_rect()
	check(area.position.x >= dock.position.x - 0.5 and area.end.x <= dock.end.x + 0.5 and
		area.position.y >= dock.position.y - 0.5 and area.end.y <= dock.end.y + 0.5,
		"embedded toggle hit rect is inside host dock")
	check(area.intersection(workspace.canvas.get_global_rect()).size == Vector2.ZERO,
		"embedded toggle never sits on Atlas editing canvas")
	check(toggle.get_parent() == (workspace.dock_toggle_slot if minimized else workspace.inspector),
		"embedded toggle has correct flow/overlay parent")
	if minimized:
		check(workspace.dock_rail.get_child(0) == workspace.dock_toggle_slot and
			workspace.dock_toggle_slot.size.y >= 56.0,
			"embedded rail reserves real slot above icons")
	else:
		check(toggle.top_level and workspace.dock_panel_gutter.visible,
			"embedded expanded toggle overlays a dock-local gutter")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1120, 760)
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(18)
	check(workspace.get_parent() == host and not workspace._window_quit_guard_enabled,
		"Drawing stays embedded in Atlas-owned host window")
	var before_revision: int = workspace.current_document().revision
	var before_dirty: bool = workspace.current_document().is_dirty()
	var count: int = workspace.dock_views.size()
	check_bounds(workspace, false)
	await click(workspace.dock_toggle.get_global_rect().get_center())
	check(bool(workspace.dock_layout.container_info("right")["minimized"]),
		"Atlas host can minimize the shared Drawing dock")
	check_bounds(workspace, true)
	await click((workspace.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(workspace.dock_flyout.visible and workspace.dock_views["colors"].get_parent() == workspace.dock_flyout_body,
		"transient flyout still uses original panel view")
	await click(workspace.dock_toggle.get_global_rect().get_center())
	check_bounds(workspace, false)
	check(not workspace.dock_flyout.visible and workspace.dock_views.size() == count,
		"Atlas expansion clears temporary flyout with no duplicated panels")
	check(workspace.current_document().revision == before_revision and
		workspace.current_document().is_dirty() == before_dirty,
		"dock state does not modify Atlas drawing history or save state")
	print("T251_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T251_ATLAS_PASSED" if failures == 0 else "T251_ATLAS_FAILED")
	quit(1 if failures else 0)
