extends SceneTree
## T-258: focus loss must roll back floating previews and release pointer ownership.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T258_NATIVE_FAILED: " + label)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
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
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native graphical display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var id: String = app.float_group("colors")
	check(not id.is_empty(), "floating group created")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[id]
	var initial_layout: Dictionary = app.dock_layout.snapshot()
	var initial_revision: int = app.current_document().revision
	var initial_dirty: bool = app.current_document().is_dirty()
	for factor: float in [1.0, 1.5, 2.0]:
		root.content_scale_factor = factor
		await frames(10)
		host.set_host_rect(Rect2(215, 110, 290, 360))
		await frames(5)
		var original: Rect2 = Rect2(host.position, host.size)
		var grip: Button = host._header.get_node("MoveHandle") as Button
		var origin: Vector2 = grip.get_global_rect().get_center()
		mouse(origin, true)
		await frames(2)
		move(origin + Vector2(55, 35))
		await frames(3)
		check(host.position.distance_to(original.position) > 15,
			"%.1fx moving preview changes frame before focus loss" % factor)
		host.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		await frames(3)
		check(Rect2(host.position, host.size) == original and host._gesture.is_empty(),
			"%.1fx window focus loss restores move frame and gesture" % factor)
		mouse(origin + Vector2(55, 35), false)
		await frames(3)
		check(Rect2(host.position, host.size) == original,
			"%.1fx stale release does not commit canceled move" % factor)
		var corner: Vector2 = host.get_global_rect().end - Vector2(3, 3)
		mouse(corner, true)
		await frames(2)
		move(corner + Vector2(38, 26))
		await frames(3)
		check(Rect2(host.position, host.size) != original,
			"%.1fx resize preview changes frame before focus loss" % factor)
		host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await frames(3)
		check(Rect2(host.position, host.size) == original and host._gesture.is_empty(),
			"%.1fx application focus loss restores resize frame and gesture" % factor)
		mouse(corner + Vector2(38, 26), false)
		await frames(3)
		check(Rect2(host.position, host.size) == original,
			"%.1fx stale release does not commit canceled resize" % factor)
	# A lost OS release must not suppress the first legitimate post-focus click.
	root.content_scale_factor = 1.0
	await frames(10)
	host.set_host_rect(Rect2(215, 110, 290, 360))
	await frames(3)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var origin: Vector2 = grip.get_global_rect().get_center()
	mouse(origin, true)
	await frames(2)
	move(origin + Vector2(44, 29))
	await frames(2)
	host.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await frames(2)
	var restored: Rect2 = Rect2(host.position, host.size)
	# No stale release: the window lost it. The next press must start a fresh gesture.
	mouse(grip.get_global_rect().get_center(), true)
	await frames(2)
	var next_origin: Vector2 = grip.get_global_rect().get_center()
	move(next_origin + Vector2(41, 22))
	await frames(3)
	mouse(next_origin + Vector2(41, 22), false)
	await frames(4)
	check(host.position.distance_to(restored.position) > 15,
		"first new press/release after focus return commits normally")
	# Focus loss must also cancel a pending tab gesture/cross-container preview.
	var tab: Button = host.tab_buttons["colors"] as Button
	var tab_center: Vector2 = tab.get_global_rect().get_center()
	var owner_before: Dictionary = app.dock_layout.snapshot()
	mouse(tab_center, true)
	await frames(2)
	move(tab_center + Vector2(0, 50))
	await frames(3)
	check(app.dock_drag.is_dragging(), "tab drag begins before focus loss")
	host.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await frames(3)
	check(not app.dock_drag.is_dragging() and host._candidate_id.is_empty(),
		"focus loss cancels pending tab drag")
	mouse(tab_center + Vector2(0, 50), false)
	await frames(3)
	check(app.dock_layout.snapshot() == owner_before,
		"focus loss and stale release preserve panel ownership")
	check(app.dock_layout.snapshot() == initial_layout,
		"geometry-only tests do not change layout model")
	check(app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty,
		"focus cancellation leaves document and history unchanged")
	# An idle sibling also receives the OS notification; it must not cancel
	# this host's active preview or the shared DrawingDockDrag transaction.
	var other_id: String = app.float_group("brushes")
	check(not other_id.is_empty(), "second floating group exists")
	await frames(8)
	var other: DrawingFloatingHost = app.floating_hosts[other_id]
	other.set_host_rect(Rect2(720, 110, 275, 320))
	host.set_host_rect(Rect2(215, 110, 290, 360))
	await frames(5)
	var own_before: Rect2 = Rect2(host.position, host.size)
	var own_grip: Button = host._header.get_node("MoveHandle") as Button
	var own_point: Vector2 = own_grip.get_global_rect().get_center()
	mouse(own_point, true)
	await frames(2)
	move(own_point + Vector2(47, 24))
	await frames(3)
	check(host._gesture == "move" and host.position.distance_to(own_before.position) > 15,
		"active host owns move preview before sibling loses focus")
	other.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(3)
	check(host._gesture == "move" and host.position.distance_to(own_before.position) > 15,
		"idle sibling focus loss cannot cancel another host's move")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(3)
	check(Rect2(host.position, host.size) == own_before and host._gesture.is_empty(),
		"own focus loss still restores pending move")
	mouse(own_point + Vector2(47, 24), false)
	await frames(3)
	check(Rect2(host.position, host.size) == own_before,
		"sibling sequence cannot publish a late release")
	print("T258_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T258_NATIVE_PASSED" if failures == 0 else "T258_NATIVE_FAILED")
	quit(1 if failures else 0)
