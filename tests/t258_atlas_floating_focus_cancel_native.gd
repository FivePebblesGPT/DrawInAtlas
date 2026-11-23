extends SceneTree
## T-258: embedded Atlas-hosted Drawing must cancel floating focus-loss previews.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T258_ATLAS_FAILED: " + label)


func frames(n: int = 5) -> void:
	for _i: int in range(n):
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
	var container: Control = Control.new()
	root.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	container.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var id: String = app.float_group("colors")
	check(not id.is_empty(), "Atlas-hosted floating panel exists")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[id]
	host.set_host_rect(Rect2(220, 110, 280, 345))
	await frames(4)
	var original: Rect2 = Rect2(host.position, host.size)
	var snapshot: Dictionary = app.dock_layout.snapshot()
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var point: Vector2 = grip.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	move(point + Vector2(45, 30))
	await frames(3)
	check(host.position.distance_to(original.position) > 15, "Atlas move preview changed host")
	host.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await frames(3)
	check(Rect2(host.position, host.size) == original and host._gesture.is_empty(),
		"Atlas host cancels move on focus loss")
	mouse(point + Vector2(45, 30), false)
	await frames(3)
	check(Rect2(host.position, host.size) == original, "Atlas late release cannot reapply move")
	var corner: Vector2 = host.get_global_rect().end - Vector2(3, 3)
	mouse(corner, true)
	await frames(2)
	move(corner + Vector2(35, 25))
	await frames(3)
	check(Rect2(host.position, host.size) != original, "Atlas resize preview changed frame")
	host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(3)
	check(Rect2(host.position, host.size) == original and host._gesture.is_empty(),
		"Atlas host cancels resize on application focus loss")
	mouse(corner + Vector2(35, 25), false)
	await frames(3)
	check(Rect2(host.position, host.size) == original, "Atlas late release cannot reapply resize")
	check(app.dock_layout.snapshot() == snapshot and not app.dock_drag.is_dragging(),
		"Atlas focus loss preserves ownership and cross drag state")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"Atlas source and global history remain unchanged")
	print("T258_ATLAS: %d checks; %d failed" % [checks, failures])
	print("T258_ATLAS_PASSED" if failures == 0 else "T258_ATLAS_FAILED")
	quit(1 if failures else 0)
