extends SceneTree
## T-259: reconcile a missed mouse-up from an unpressed pointer motion.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T259_NATIVE_FAILED: " + label)

func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)

func motion(point: Vector2, held: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 graphical test required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "Colors floating host created")
	await frames(7)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	for factor: float in [1.0, 1.5, 2.0]:
		root.content_scale_factor = factor
		await frames(10)
		host.set_host_rect(Rect2(230, 130, 300, 350))
		await frames(5)
		var initial: Rect2 = Rect2(host.position, host.size)
		var grip: Button = host._header.get_node("MoveHandle") as Button
		var anchor: Vector2 = grip.get_global_rect().get_center()
		mouse(anchor, true)
		await frames(2)
		motion(anchor + Vector2(40, 24), true)
		await frames(3)
		check(host.position.distance_to(initial.position) > 12 and host._gesture == "move",
			"%.1fx move preview starts while left held" % factor)
		# Simulate the OS losing mouse-up but reporting that no button is held.
		motion(anchor + Vector2(82, 46), false)
		await frames(3)
		check(Rect2(host.position, host.size) == initial and host._gesture.is_empty(),
			"%.1fx unpressed motion rolls back missed-release move" % factor)
		mouse(anchor + Vector2(82, 46), false)
		await frames(3)
		check(Rect2(host.position, host.size) == initial,
			"%.1fx delayed release cannot reapply canceled move" % factor)
		# No focus-loss notification: the pointer's button mask alone must recover.
		var corner: Vector2 = host.get_global_rect().end - Vector2(3, 3)
		mouse(corner, true)
		await frames(2)
		motion(corner + Vector2(30, 22), true)
		await frames(3)
		check(Rect2(host.position, host.size) != initial and host._gesture == "resize",
			"%.1fx resize preview starts while held" % factor)
		motion(corner + Vector2(60, 40), false)
		await frames(3)
		check(Rect2(host.position, host.size) == initial and host._gesture.is_empty(),
			"%.1fx unpressed motion rolls back missed-release resize" % factor)
		mouse(corner + Vector2(60, 40), false)
		await frames(2)
		check(Rect2(host.position, host.size) == initial,
			"%.1fx delayed release cannot reapply canceled resize" % factor)
	root.content_scale_factor = 1.0
	await frames(9)
	host.set_host_rect(Rect2(230, 130, 300, 350))
	await frames(5)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var point: Vector2 = grip.get_global_rect().get_center()
	var before: Rect2 = Rect2(host.position, host.size)
	mouse(point, true)
	await frames(2)
	motion(point + Vector2(48, 20), true)
	await frames(3)
	motion(point + Vector2(50, 24), false)
	await frames(3)
	# The next fresh press is valid even when no stale release follows.
	point = grip.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	motion(point + Vector2(52, 25), true)
	await frames(3)
	mouse(point + Vector2(52, 25), false)
	await frames(3)
	check(host.position.distance_to(before.position) > 15 and host._gesture.is_empty(),
		"fresh press after missed release still moves the host")
	# Scrolled/cross-container tabs share the same pointer-lifetime requirement.
	var tab: Button = host.tab_buttons["colors"] as Button
	var tab_point: Vector2 = tab.get_global_rect().get_center()
	var owner_before: Dictionary = app.dock_layout.snapshot()
	mouse(tab_point, true)
	await frames(2)
	motion(tab_point + Vector2(0, 48), true)
	await frames(3)
	check(app.dock_drag.is_dragging(), "tab cross-drag begins while held")
	motion(tab_point + Vector2(0, 58), false)
	await frames(3)
	check(not app.dock_drag.is_dragging() and host._candidate_id.is_empty(),
		"unpressed motion cancels tab cross-drag")
	mouse(tab_point + Vector2(0, 58), false)
	await frames(3)
	check(app.dock_layout.snapshot() == owner_before,
		"late tab release does not transfer panel ownership")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"pointer recovery never touches document or history")
	# An idle host must not cancel this host's legitimate held-button preview.
	var other_id: String = app.float_group("brushes")
	check(not other_id.is_empty(), "second floating host available")
	await frames(7)
	var other: DrawingFloatingHost = app.floating_hosts[other_id]
	other.set_host_rect(Rect2(750, 130, 280, 320))
	host.set_host_rect(Rect2(230, 130, 300, 350))
	await frames(4)
	before = Rect2(host.position, host.size)
	point = grip.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	motion(point + Vector2(42, 26), true)
	await frames(3)
	check(host._gesture == "move", "first host has active valid move")
	other._input(_unpressed_motion(other.get_global_rect().get_center()))
	await frames(2)
	check(host._gesture == "move", "idle sibling ignores unpressed motion")
	mouse(point + Vector2(42, 26), false)
	await frames(3)
	check(host.position.distance_to(before.position) > 12,
		"valid pressed movement commits without false cancel")
	print("T259_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T259_NATIVE_PASSED" if failures == 0 else "T259_NATIVE_FAILED")
	quit(1 if failures else 0)

func _unpressed_motion(point: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.global_position = point
	event.position = point
	event.button_mask = 0
	return event
