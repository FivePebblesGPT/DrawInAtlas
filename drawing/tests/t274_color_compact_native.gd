extends SceneTree
## T-274: inspect real framebuffer separately from functional checks. This suite
## exercises the full-width native picker and optional exact RGBA8 editor in a
## live Drawing window; it does not assert cosmetic rectangles or owner signoff.

var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T274_NATIVE_FAILED: " + message)


func frames(count: int = 5) -> void:
	for _index: int in range(count):
		await process_frame


func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await frames(3)


func press_enter() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)


func shot(name: String) -> void:
	var folder: String = OS.get_environment("T274_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var status: int = root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
	if status != OK:
		print("OPTIONAL_T274_CAPTURE_FAILED: " + str(status))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "actual X11 renderer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(18)
	check(app.dock_layout.move_group("colors", "right", 0), "Colors group can lead the dock")
	app._render_dock()
	await frames(8)
	var document: DrawingDocument = app.current_document()
	var revision: int = document.revision
	var dirty: bool = document.is_dirty()
	var history: int = document.history_length()
	var foreground: Color = app.active_color
	var background: Color = app.color_background
	check(app.color_advanced.is_visible_in_tree() and app.color_advanced.hex_visible and
		app.color_advanced.sliders_visible and app.color_advanced.color_modes_visible,
		"native picker includes HSV/RGB channels and hex editing")
	check(app.color_exact_toggle.is_visible_in_tree() and not app.color_exact_details.visible,
		"duplicate canonical 8-bit editors start behind disclosure")
	check(app.color_recent_buttons.size() == 6 and
		app.color_recent_buttons[0].get_parent().name == "RecentSlot_0",
		"recent colors keep stable slots when history is short")
	check(app.color_picker_scroll.get_h_scroll_bar().max_value <=
		app.color_picker_scroll.get_h_scroll_bar().page + 1.0,
		"default dock displays native picker with no horizontal scrolling")
	await shot("expanded")
	# Use an actual pointer press on the right-side native hue bar, rather than
	# assuming the built-in ColorPicker has a particular child tree.
	var hue_point: Vector2 = app.color_advanced.global_position + Vector2(app.color_advanced.size.x - 18, 130)
	check(app.color_picker_scroll.get_global_rect().has_point(hue_point),
		"hue selector is reachable through the visible native picker viewport")
	await click(hue_point)
	check(app.active_color != foreground and app.color_background == background,
		"native hue bar affects only the active FG pigment")
	check(document.revision == revision and document.history_length() == history and
		document.is_dirty() == dirty, "picker input leaves artwork and history intact")
	await shot("recent-colors")
	# The optional strict RGBA8 editor is accessed by real pointer/keyboard,
	# and retains hidden RGB channels at alpha zero.
	app.inspector.ensure_control_visible(app.color_exact_toggle)
	await frames(8)
	await click(app.color_exact_toggle.get_global_rect().get_center())
	check(app.color_exact_details.visible and app.color_exact_toggle.button_pressed,
		"real disclosure click reveals the optional strict channels")
	app.inspector.ensure_control_visible(app.color_hex)
	await frames(8)
	await click(app.color_hex.get_global_rect().get_center())
	check(root.gui_get_focus_owner() == app.color_hex, "strict hex entry accepts pointer focus")
	app.color_hex.text = "#12345600"
	await press_enter()
	check(app.active_color == Color8(18, 52, 86, 0) and
		app.color_advanced.color == Color8(18, 52, 86, 0),
		"strict hex entry preserves hidden RGB at zero alpha and syncs native picker")
	app.inspector.ensure_control_visible(app.color_exact_toggle)
	await frames(5)
	await click(app.color_exact_toggle.get_global_rect().get_center())
	check(not app.color_exact_details.visible, "pointer collapses duplicate exact editors")
	# Real edge input remains above scrolling native controls and does not
	# select a clipped ColorPicker descendant.
	var edge: Vector2 = app.inspector.get_global_rect().position + Vector2(app.inspector.size.x - 10, 28)
	var before_edge: Color = app.active_color
	await click(edge)
	check(bool(app.dock_layout.container_info("right")["minimized"]) and
		app.active_color == before_edge, "edge hit minimizes without modifying the active color")
	await shot("minimized")
	await click((app.dock_rail_buttons["colors"] as Button).get_global_rect().get_center())
	check(app.dock_flyout.visible, "Colors flyout remains accessible from minimized rail")
	await shot("flyout")
	await click(edge)
	check(not bool(app.dock_layout.container_info("right")["minimized"]) and
		not app.dock_flyout.visible, "edge hit restores dock and closes flyout")
	await frames(8)
	# Exercise scaled logical viewports before floating hosts change z-order.
	root.size = Vector2i(1920, 1200)
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		app.size = Vector2(1920, 1200) / scale
		await frames(14)
		check(app.color_advanced.is_visible_in_tree() and app.dock_toggle.is_visible_in_tree(),
			"picker and collapse control remain present at %.0f%% scale" % (scale * 100.0))
		await shot("scale-%d" % roundi(scale * 100.0))
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	app.size = Vector2(1280, 800)
	await frames(12)
	var host_id: String = app.float_group("colors")
	await frames(10)
	check(not host_id.is_empty() and app.floating_hosts.has(host_id) and
		app.color_advanced.is_visible_in_tree(), "native picker survives float/reparent")
	if app.floating_hosts.has(host_id):
		var host: DrawingFloatingHost = app.floating_hosts[host_id]
		host.set_host_rect(Rect2(Vector2(250, 145), Vector2(350, 580)))
		await frames(8)
		await shot("floating")
	app._dock_apply(DrawingDockDrag.GROUP, "colors", {"kind": DrawingDockDrag.GROUP_SLOT,
		"container": "right", "index": 0}, "drag-group:colors")
	await frames(8)
	check(app.color_advanced.get_parent() == app.color_picker_scroll and
		app._edited_color() == app.active_color,
		"same picker and selected role survive redocking")
	app.dock_split.split_offset = -226
	await frames(8)
	check(app.color_picker_scroll.get_h_scroll_bar().max_value >
		app.color_picker_scroll.get_h_scroll_bar().page,
		"narrow dock permits native horizontal scrolling without truncating its fields")
	await shot("narrow")
	# Focus-follow ensures keyboard users can reach a clipped native child.
	var inputs: Array[Node] = app.color_advanced.find_children("*", "LineEdit", true, false)
	check(not inputs.is_empty(), "native picker retains keyboard-editable fields in narrow dock")
	var editable: LineEdit = null
	for node: Node in inputs:
		var field: LineEdit = node as LineEdit
		if field.is_visible_in_tree() and field.focus_mode != Control.FOCUS_NONE and field.editable:
			editable = field
			break
	check(editable != null, "narrow picker exposes a focusable native edit")
	if editable != null:
		editable.grab_focus()
		await frames(8)
		check(root.gui_get_focus_owner() == editable,
			"narrow picker preserves native keyboard focus")
	app.dock_split.split_offset = -390
	await frames(8)
	check(document.revision == revision and document.history_length() == history and
		document.is_dirty() == dirty, "all UI gestures preserve document history")
	app.queue_free()
	await frames(5)
	print("T274_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T274_NATIVE_PASSED" if failures == 0 else "T274_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
