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
