extends SceneTree
## T-265: the shared Drawing workspace keeps Atlas-hosted close clicks exact.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T265_ATLAS_FAILED: " + description)

func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame

func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await frames()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 window required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1024, 800)
	var wrapper: Control = Control.new()
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	wrapper.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(18)
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	while app.tabs.size() < 12:
		app.new_drawing()
	for i: int in range(app.tab_bar.tab_count):
		app.tab_bar.set_tab_title(i, "A long Atlas session tab %d xxxxxxxx" % i)
	await frames(8)
	var bar: TabBar = app.tab_bar
	var last: int = bar.tab_count - 1
	app._activate(last)
	await frames(5)
	var hidden_rect: Rect2 = bar.get_tab_rect(0)
	var point: Vector2 = bar.get_global_transform_with_canvas() * (hidden_rect.position +
		Vector2(hidden_rect.size.x - 18.0, hidden_rect.size.y / 2.0))
	var actual: int = bar.get_tab_idx_at_point(bar.get_global_transform_with_canvas().affine_inverse() * point)
	check(actual > 0 and actual < last, "Atlas tab overflow exposes a different visible index")
	check(app._tab_close_hit(point) == actual, "Atlas hit test rejects hidden-tab alias")
	await click(point)
	check(app.close_dialog.visible and app._closing_index == actual,
		"Atlas real pointer opens the correct inactive document prompt")
	check(app.tabs.size() == 12 and app.active_tab == last,
		"Atlas close prompt does not destroy or switch documents")
	app.close_dialog.hide()
	app._cancel_pending_close()
	check(doc.revision == revision and doc.history_length() == history and doc.is_dirty() == dirty,
		"Atlas native document and history untouched by tab close cancellation")
	print("T265_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T265_ATLAS_PASSED" if failures == 0 else "T265_ATLAS_FAILED")
	quit(1 if failures else 0)
