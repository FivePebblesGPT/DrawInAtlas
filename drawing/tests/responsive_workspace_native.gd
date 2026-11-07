extends SceneTree
## T-090: real X11 window, UI-scale, field-wheel and per-tab close witnesses.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T090_NATIVE_FAILED: " + description)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func wheel_at(target: Vector2, direction: int, shift: bool = false) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = target
	event.global_position = target
	event.button_index = MOUSE_BUTTON_WHEEL_UP if direction > 0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event, true)
	await frames(3)


func click_at(target: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = target
		event.global_position = target
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames(3)


func shortcut(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.ctrl_pressed = true
		root.push_input(event, true)
		await process_frame
	await frames(2)


func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await frames(2)


func screenshot(name: String) -> void:
	var path: String = OS.get_environment("T090_SCREENSHOTS")
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path)
	var image: Image = root.get_texture().get_image()
	check(image.save_png(path.path_join(name + ".png")) == OK, "screenshot: " + name)


func check_tool_glyph_centers(app: Control) -> void:
	# Actual SVG pixels are lime-green against a dark button. Inspect the
	# framebuffer at 100/150/200% instead of trusting icon_alignment alone.
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "tool rail framebuffer is available")
	if image == null or image.is_empty():
		return
	var rail: VBoxContainer = app.tool_buttons["Brush"].get_parent()
	check(absf(rail.size.x - 42.0) <= 1.0, "compact rail is 42 logical pixels")
	var scale: float = root.content_scale_factor
	var previous_end: float = -1.0
	for name: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan"]:
		var button: Button = app.tool_buttons[name]
		var rect: Rect2 = button.get_global_rect()
		check(absf(rect.size.x - 34.0) <= 1.0 and absf(rect.size.y - 34.0) <= 1.0 and
			absf(rect.get_center().x - rail.get_global_rect().get_center().x) <= 1.0 and
			(previous_end < 0.0 or rect.position.y >= previous_end - 0.5),
			"%s has a centered nonoverlapping 34px target" % name)
		previous_end = rect.end.y
		var left: int = maxi(0, int(floor(rect.position.x * scale)))
		var right: int = mini(image.get_width(), int(ceil(rect.end.x * scale)))
		var top: int = maxi(0, int(floor(rect.position.y * scale)))
		var bottom: int = mini(image.get_height(), int(ceil(rect.end.y * scale)))
		var x0: int = right
		var x1: int = left
		var y0: int = bottom
		var y1: int = top
		var count: int = 0
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				var color: Color = image.get_pixel(x, y)
				if color.g < 0.75 or color.g < color.r + 0.10 or color.g < color.b + 0.08:
					continue
				count += 1
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
		var center: Vector2 = Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
		var offset: Vector2 = center - rect.get_center() * scale
		check(count >= 12 and absf(offset.x) <= 2.0 * scale and
			absf(offset.y) <= 2.0 * scale,
			"%s SVG pixels centered at %.1fx (count=%d, offset=%s)" %
			[name, scale, count, offset])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display is required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	root.add_child(app)
	await frames(10)
	check_tool_glyph_centers(app)
	await screenshot("t090-tool-rail")
	for name: String in ["Eraser", "Select", "Move", "Text", "Pan", "Brush"]:
		var button: Button = app.tool_buttons[name]
		await click_at(button.get_global_rect().get_center())
		check(app.active_tool == name and button.button_pressed,
			"native centered tool target activates %s" % name)
	check(app.tab_bar.tab_close_display_policy == TabBar.CLOSE_BUTTON_SHOW_ALWAYS,
		"close affordance belongs to each document tab")
	check(app.tabs_line.get_child_count() == 1,
		"detached global new/close buttons are absent")
	var file_menu: PopupMenu = app.top_bar._menus[0].get_popup()
	var window_menu: PopupMenu = app.top_bar._menus[6].get_popup()
	var file_labels: String = ""
	for i: int in range(file_menu.item_count):
		file_labels += file_menu.get_item_text(i) + ";"
	var window_labels: String = ""
	for i: int in range(window_menu.item_count):
		window_labels += window_menu.get_item_text(i) + ";"
	check(file_labels.contains("Close tab") and file_labels.contains("Rename source") and
		file_labels.contains("Save source As") and not window_labels.contains("Object") and
		not window_labels.contains("Close tab"), "file and object commands stay outside Window")
	await shortcut(KEY_N)
	check(app.tabs.size() == 2 and app.active_tab == 1, "native Ctrl+N opens a second document")
	await key(KEY_BRACKETRIGHT)
	check(app.width_spin.value == 4.0, "] increases brush size without document edits")
	await key(KEY_BRACKETLEFT)
	check(app.width_spin.value == 3.0, "[ decreases brush size without document edits")
	for dims: Vector2i in [Vector2i(800, 600), Vector2i(1280, 760), Vector2i(1920, 1080)]:
		root.size = dims
		await frames(12)
		var expected_width: float = root.get_visible_rect().size.x
		check(absf(app.size.x - expected_width) < 3.0 and
			app.canvas.get_global_rect().end.x <= app.size.x + 2.0 and
			app.canvas.size.x >= 125.0 and app.canvas.size.y >= 190.0,
			"viewport fills resized client and keeps usable canvas: %s" % dims)
		check(app.tab_bar.get_global_rect().end.x <= app.size.x + 1.0 and
			app.top_bar.size.y < 55.0, "tab strip and single options row fit: %s" % dims)
		var image: Image = root.get_texture().get_image()
		if image != null and not image.is_empty():
			var left_edge: Color = image.get_pixel(2, int(image.get_height() / 2))
			var right_edge: Color = image.get_pixel(image.get_width() - 3, int(image.get_height() / 2))
			check(left_edge.r > 0.1 and right_edge.r > 0.1,
				"framebuffer left/right edges contain workspace, not black pillars: %s" % dims)
		else:
			check(false, "native framebuffer available for resized window")
		await screenshot("t090-%dx%d" % [dims.x, dims.y])
	root.size = Vector2i(1280, 760)
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(12)
		check(app.tab_bar.get_global_rect().end.x <= app.size.x + 2.0 and
			app.canvas.size.x >= 125.0 and app.top_bar.size.y < 65.0,
			"scaled tabs, canvas and top bar remain within logical client: %.1fx" % scale)
		check_tool_glyph_centers(app)
		await screenshot("t090-scale-%d" % int(scale * 100.0))
	root.content_scale_factor = 1.0
	await frames(8)
	app._change_tool("Brush")
	app.width_spin.value = 5.0
	await frames(3)
	var hover: Vector2 = app.width_spin.get_global_rect().get_center()
	await wheel_at(hover, 1)
	check(app.width_spin.value == 6.0 and app.canvas.brush_width == 6.0,
		"real wheel over Brush px increments model width while hovering")
	await wheel_at(hover, -1)
	check(app.width_spin.value == 5.0, "real wheel over Brush px decrements width")
	var before_scroll: int = app.top_bar.options_scroll.scroll_horizontal
	await wheel_at(hover, -1, true)
	check(app.width_spin.value == 5.0 and
		app.top_bar.options_scroll.scroll_horizontal >= before_scroll,
		"Shift+wheel preserves Brush px while scrolling overflow")
	# Exercise the per-tab mouse close target, not merely the TabBar signal.
	app._activate(1)
	var tab: Rect2 = app.tab_bar.get_tab_rect(0)
	var close_point: Vector2 = app.tab_bar.global_position + tab.position + Vector2(tab.size.x - 18.0, tab.size.y * 0.5)
	await click_at(close_point)
	check(app._closing_index == 0 and app.close_dialog.visible and app.tabs.size() == 2 and
		app.active_tab == 1,
		"close glyph of nonactive first tab targets that dirty document without switching")
	app.close_dialog.hide()
	app._cancel_pending_close()
	check(app.tabs.size() == 2, "cancelled tab close does not lose unsaved document")
	app._activate(0)
	app._save_file(OS.get_user_data_dir().path_join("t090-autosave.drawing"))
	await frames(8)
	tab = app.tab_bar.get_tab_rect(0)
	close_point = app.tab_bar.global_position + tab.position + Vector2(tab.size.x - 18.0,
		tab.size.y * 0.5)
	await click_at(close_point)
	check(app.tabs.size() == 1, "per-tab mouse close removes a saved document")
	DirAccess.remove_absolute(OS.get_user_data_dir().path_join("t090-autosave.drawing"))
	check(app.tool_buttons["Brush"].button_pressed and
		app.tool_buttons["Brush"].icon != null and
		app.tool_buttons["Brush"].focus_mode == Control.FOCUS_ALL,
		"MIT tool icons retain pressed and focus styling")
	print("T090_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T090_NATIVE_PASSED: %d checks" % checks)
	quit(1 if failures > 0 else 0)
