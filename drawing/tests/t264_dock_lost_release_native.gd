extends SceneTree
## T-264: dropped mouse-up must not turn a dock icon drag into a late transfer.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T264_NATIVE_FAILED: " + description)

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

func drag_and_drop_release(app: Control, source: Control, label: String) -> void:
	var baseline: Dictionary = app.dock_layout.snapshot()
	var start: Vector2 = source.get_global_rect().get_center()
	var target: Vector2 = app.canvas.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(start.lerp(target, 0.5), true)
	await frames(2)
	motion(target, true)
	await frames(3)
	check(app.dock_drag.is_dragging() and app._cross_source == "right" and
		app.dock_layout.snapshot() == baseline, label + ": held drag previews without ownership change")
	# OS reports no buttons, without first delivering a mouse-up or focus loss.
	motion(target + Vector2(8, 7), false)
	await frames(3)
	check(not app.dock_drag.is_dragging() and app._drag_candidate_id.is_empty() and
		app._cross_source.is_empty(), label + ": unpressed motion cancels drag and pointer candidate")
	check(app.dock_layout.snapshot() == baseline and not app._detach_hint.visible and
		not app.dock_drop_hint.visible, label + ": cancellation clears drop preview and preserves layout")
	mouse(target + Vector2(8, 7), false)
	await frames(4)
	var unchanged: bool = app.dock_layout.snapshot() == baseline and app.floating_hosts.is_empty()
	check(unchanged, label + ": late release does not float or reorder any panel")
	# A negative-control run may have detached the source. Restore the fixture
	# before exercising the remaining independent pointer paths.
	if not unchanged:
		app.reset_workspace_layout()
		await frames(10)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 native display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1500, 980)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(22)
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var dirty: bool = doc.is_dirty()
	var history: int = doc.history_length()
	# Expanded dock tab and group marker use distinct drag sources.
	for scale: float in [1.0, 1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(10)
		await drag_and_drop_release(app, app.dock_tab_buttons["colors"], "%.1fx dock icon" % scale)
		await drag_and_drop_release(app, app.dock_group_handles["colors"], "%.1fx dock group" % scale)
	root.content_scale_factor = 1.0
	await frames(9)
	# A new left-button gesture works even if the lost release never arrives.
	var icon: Button = app.dock_tab_buttons["colors"]
	var before: Dictionary = app.dock_layout.snapshot()
	var start: Vector2 = icon.get_global_rect().get_center()
	var target: Vector2 = app.canvas.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(target, true)
	await frames(3)
	check(app.dock_drag.is_dragging(), "held drag starts before a missing release")
	motion(target + Vector2(10, 6), false)
	await frames(4)
	check(app.dock_layout.snapshot() == before and not app.dock_drag.is_dragging(),
		"unpressed motion cancels even without a following mouse-up")
	# Deliberately NO stale mouse-up: the next independent mouse-down must
	# clear the suppression latch, yet still protect a later canceled release.
	icon = app.dock_tab_buttons["colors"]
	start = icon.get_global_rect().get_center()
	mouse(start, true)
	await frames(2)
	motion(target, true)
	await frames(3)
	check(app.dock_drag.is_dragging() and app._cross_source == "right",
		"first fresh press after lost mouse-up starts another dock drag")
	motion(target + Vector2(5, 4), false)
	await frames(3)
	mouse(target + Vector2(5, 4), false)
	await frames(4)
	check(app.dock_layout.snapshot() == before and not app.dock_drag.is_dragging(),
		"late release of fresh canceled drag still cannot mutate ownership")
	# Minimized rail and the flyout icon both route through the dock candidate.
	# Enter minimized mode through the production toggle command; the
	# actual rail and flyout drag cases below use native pointer events.
	app._toggle_dock()
	await frames(8)
	check(bool(app.dock_layout.container_info("right")["minimized"]), "dock minimized for rail recovery")
	await drag_and_drop_release(app, app.dock_rail_buttons["colors"], "minimized rail icon")
	var rail: Button = app.dock_rail_buttons["colors"]
	mouse(rail.get_global_rect().get_center(), true)
	await frames(2)
	mouse(rail.get_global_rect().get_center(), false)
	await frames(8)
	check(app.dock_flyout.visible, "normal fresh click still opens flyout after lost release")
	await drag_and_drop_release(app, app.dock_flyout_tabs.get_node("Tab_colors"), "flyout icon")
	check(app.dock_flyout.visible and app.dock_layout.owner_of("colors") == "right",
		"flyout stays open and panel remains docked after canceled drag")
	check(doc.revision == revision and doc.is_dirty() == dirty and doc.history_length() == history,
		"all pointer recovery leaves raster and history unchanged")
	print("T264_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T264_NATIVE_PASSED" if failures == 0 else "T264_NATIVE_FAILED")
	quit(1 if failures else 0)
