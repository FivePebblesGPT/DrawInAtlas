extends SceneTree
## T-257: the same floating host rollback under the Atlas Drawing consumer.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T257_ATLAS_FAILED: " + label)


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


func escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var atlas_host: Control = Control.new()
	root.add_child(atlas_host)
	atlas_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	atlas_host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var id: String = app.float_group("colors")
	check(not id.is_empty(), "Atlas owns floating Colors host")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[id]
	host.set_host_rect(Rect2(240, 110, 290, 345))
	await frames(5)
	var before: Rect2 = Rect2(host.position, host.size)
	var snapshot: Dictionary = app.dock_layout.snapshot()
	var rev: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var point: Vector2 = grip.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	move(point + Vector2(50, 24))
	await frames(4)
	check(host.position.distance_to(before.position) > 20, "Atlas move preview changes position")
	escape()
	await frames(4)
	check(Rect2(host.position, host.size) == before, "Atlas Escape restores move geometry")
	mouse(point + Vector2(50, 24), false)
	await frames(5)
	check(Rect2(host.position, host.size) == before, "Atlas stale release stays canceled")
	var corner: Vector2 = host.get_global_rect().end - Vector2(3, 3)
	mouse(corner, true)
	await frames(2)
	move(corner + Vector2(38, 31))
	await frames(4)
	check(Rect2(host.position, host.size) != before, "Atlas corner resize preview changes frame")
	escape()
	await frames(4)
	check(Rect2(host.position, host.size) == before, "Atlas Escape restores resize frame")
	mouse(corner + Vector2(38, 31), false)
	await frames(5)
	check(Rect2(host.position, host.size) == before and app.dock_layout.snapshot() == snapshot,
		"Atlas canceled frames never modify native layout")
	check(app.current_document().revision == rev and app.current_document().is_dirty() == dirty,
		"Atlas drawing source and history stay untouched")
	print("T257_ATLAS: %d checks; %d failed" % [checks, failures])
	print("T257_ATLAS_PASSED" if failures == 0 else "T257_ATLAS_FAILED")
	quit(1 if failures else 0)
