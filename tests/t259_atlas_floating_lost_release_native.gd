extends SceneTree
## T-259: Atlas embeds the same floating host and must recover lost release.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T259_ATLAS_FAILED: " + label)

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

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 required")
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
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "Atlas floating group created")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	host.set_host_rect(Rect2(230, 140, 280, 340))
	await frames(4)
	var initial: Rect2 = Rect2(host.position, host.size)
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var owners: Dictionary = app.dock_layout.snapshot()
	var grip: Button = host._header.get_node("MoveHandle") as Button
	var point: Vector2 = grip.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	motion(point + Vector2(37, 24), true)
	await frames(3)
	check(host.position.distance_to(initial.position) > 12, "Atlas move preview starts")
	motion(point + Vector2(62, 37), false)
	await frames(3)
	check(Rect2(host.position, host.size) == initial and host._gesture.is_empty(),
		"Atlas unpressed motion rolls back missed-release move")
	mouse(point + Vector2(62, 37), false)
	await frames(3)
	check(Rect2(host.position, host.size) == initial, "Atlas late release preserves original frame")
	var corner: Vector2 = host.get_global_rect().end - Vector2(3, 3)
	mouse(corner, true)
	await frames(2)
	motion(corner + Vector2(31, 23), true)
	await frames(3)
	check(Rect2(host.position, host.size) != initial, "Atlas resize preview starts")
	motion(corner + Vector2(43, 30), false)
	await frames(3)
	check(Rect2(host.position, host.size) == initial and host._gesture.is_empty(),
		"Atlas unpressed motion rolls back missed-release resize")
	mouse(corner + Vector2(43, 30), false)
	await frames(3)
	var tab: Button = host.tab_buttons["colors"] as Button
	point = tab.get_global_rect().get_center()
	mouse(point, true)
	await frames(2)
	motion(point + Vector2(0, 47), true)
	await frames(3)
	check(app.dock_drag.is_dragging(), "Atlas tab cross-drag begins")
	motion(point + Vector2(0, 56), false)
	await frames(3)
	check(not app.dock_drag.is_dragging() and host._candidate_id.is_empty(),
		"Atlas unpressed motion cancels stale tab drag")
	mouse(point + Vector2(0, 56), false)
	await frames(3)
	check(app.dock_layout.snapshot() == owners, "Atlas owners remain unchanged")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"Atlas document and history remain unchanged")
	print("T259_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T259_ATLAS_PASSED" if failures == 0 else "T259_ATLAS_FAILED")
	quit(1 if failures else 0)
