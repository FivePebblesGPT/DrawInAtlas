extends SceneTree
## T-257: Escape must roll back a floating host's in-progress move/resize.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T257_NATIVE_FAILED: " + label)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame


func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)


func move(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = false
	root.push_input(event, true)


func capture(name: String) -> void:
	var directory: String = OS.get_environment("T257_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK,
		"capture " + name)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "graphical X11 display required")
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
	check(not host_id.is_empty(), "floating Colors host exists")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var identity: Dictionary = app.dock_layout.snapshot()
	for factor: float in [1.0, 1.5, 2.0]:
		root.content_scale_factor = factor
		await frames(12)
		host.set_host_rect(Rect2(215, 110, 285, 350))
		await frames(6)
		var start: Rect2 = Rect2(host.position, host.size)
		var grip: Button = host._header.get_node("MoveHandle") as Button
		var origin: Vector2 = grip.get_global_rect().get_center()
		mouse(origin, true)
		await frames(2)
		move(origin + Vector2(45, 28))
		await frames(3)
		check(host.position.distance_to(start.position) > 10.0,
			"%.1fx: move preview actually changes host position" % factor)
		escape()
		await frames(4)
		check(Rect2(host.position, host.size) == start,
			"%.1fx: Escape restores exact pre-move rectangle" % factor)
		mouse(origin + Vector2(45, 28), false)
		await frames(5)
		check(Rect2(host.position, host.size) == start and host._gesture.is_empty(),
			"%.1fx: released canceled move cannot reapply preview" % factor)
		for corner: String in ["bottom_right", "top_left"]:
			start = Rect2(host.position, host.size)
			var point: Vector2 = host.get_global_rect().end - Vector2(3, 3) if corner == "bottom_right" else host.get_global_rect().position + Vector2(3, 3)
			var delta: Vector2 = Vector2(42, 27) if corner == "bottom_right" else Vector2(-35, -22)
			mouse(point, true)
			await frames(2)
			move(point + delta)
			await frames(3)
			check(Rect2(host.position, host.size) != start and host._gesture == "resize",
				"%.1fx %s: pointer resizes before cancellation" % [factor, corner])
			escape()
			await frames(4)
			check(Rect2(host.position, host.size) == start,
				"%.1fx %s: Escape restores both size and position" % [factor, corner])
			mouse(point + delta, false)
			await frames(5)
			check(Rect2(host.position, host.size) == start and host._gesture.is_empty(),
				"%.1fx %s: late release leaves original frame" % [factor, corner])
	await capture("floating-escape-restored")
	# A canceled resize must not poison the following legitimate move/resize.
	root.content_scale_factor = 1.0
	await frames(12)
	host.set_host_rect(Rect2(215, 110, 285, 350))
	await frames(6)
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var origin: Vector2 = grip.get_global_rect().get_center()
	var initial: Vector2 = host.position
	mouse(origin, true)
	await frames(2)
	move(origin + Vector2(40, 25))
	await frames(2)
	mouse(origin + Vector2(40, 25), false)
	await frames(6)
	check(host.position.distance_to(initial) > 15.0,
		"normal drag works after repeated cancellations")
	check(app.dock_layout.snapshot() == identity and not app.dock_drag.is_dragging(),
		"cancellation and successful geometry drag never mutate panel ownership")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"canceled moves/resizes do not change Drawing document/history")
	print("T257_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T257_NATIVE_PASSED" if failures == 0 else "T257_NATIVE_FAILED")
	quit(1 if failures else 0)
