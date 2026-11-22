extends SceneTree
## T-264: embedded Drawing dock pointer ownership is also bounded.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T264_ATLAS_FAILED: " + description)

func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame

func mouse(point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event, true)

func motion(point: Vector2, held: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func cancelled_drag(app: Control, source: Control, label: String) -> void:
	var baseline: Dictionary = app.dock_layout.snapshot()
	var start: Vector2 = source.get_global_rect().get_center()
	var target: Vector2 = app.canvas.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(target, true)
	await frames(3)
	check(app.dock_drag.is_dragging() and app._cross_source == "right",
		label + ": Atlas dock drag begins")
	motion(target + Vector2(12, 8), false)
	await frames(3)
	check(not app.dock_drag.is_dragging() and app._drag_candidate_id.is_empty(),
		label + ": unpressed motion cancels source")
	check(app.dock_layout.snapshot() == baseline and not app._detach_hint.visible,
		label + ": cancellation preserves owners and clears hints")
	mouse(target + Vector2(12, 8), false)
	await frames(4)
	check(app.dock_layout.snapshot() == baseline and app.floating_hosts.is_empty(),
		label + ": delayed release cannot detach")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1450, 900)
	var scene: Control = Control.new()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	scene.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	var dirty: bool = doc.is_dirty()
	var history: int = doc.history_length()
	await cancelled_drag(app, app.dock_tab_buttons["colors"], "expanded tab")
	await cancelled_drag(app, app.dock_group_handles["colors"], "expanded group")
	app._toggle_dock()
	await frames(9)
	check(bool(app.dock_layout.container_info("right")["minimized"]),
		"Atlas dock enters minimized state")
	await cancelled_drag(app, app.dock_rail_buttons["colors"], "rail")
	var rail: Button = app.dock_rail_buttons["colors"]
	mouse(rail.get_global_rect().get_center(), true)
	await frames(2)
	mouse(rail.get_global_rect().get_center(), false)
	await frames(8)
	check(app.dock_flyout.visible, "Atlas flyout opens on a fresh click")
	await cancelled_drag(app, app.dock_flyout_tabs.get_node("Tab_colors"), "flyout tab")
	check(doc.revision == rev and doc.is_dirty() == dirty and doc.history_length() == history,
		"Atlas native drawing remains byte/history untouched")
	print("T264_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T264_ATLAS_PASSED" if failures == 0 else "T264_ATLAS_FAILED")
	quit(1 if failures else 0)
