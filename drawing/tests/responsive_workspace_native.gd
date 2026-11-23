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


func pointer_at(target: Vector2, pressed: bool) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = target
	motion.global_position = target
	root.push_input(motion, true)
	await process_frame
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = target
	event.global_position = target
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await frames(2)


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
	var capture_status: int = image.save_png(path.path_join(name + ".png"))
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: drawing/tests/responsive_workspace_native.gd: " + str(capture_status))


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
	await screenshot("t090-tool-rail")
	for name: String in ["Eraser", "Select", "Move", "Text", "Pan", "Brush"]:
		var button: Button = app.tool_buttons[name]
		await click_at(button.get_global_rect().get_center())
		check(app.active_tool == name and button.button_pressed,
			"native centered tool target activates %s" % name)
	check(app.tab_bar.tab_close_display_policy == TabBar.CLOSE_BUTTON_SHOW_ALWAYS,
		"close affordance belongs to each document tab")
	check(app.tabs_line.get_child_count() == 1 and
		app.tabs_line.get_parent() == app.canvas.get_parent(),
		"document tabs share the canvas column, not the tool rail or panel dock")
	var file_menu: PopupMenu = app.top_bar._menus[0].get_popup()
	var window_menu: PopupMenu = app.top_bar._menus[7].get_popup()
	var file_labels: String = ""
	for i: int in range(file_menu.item_count):
		file_labels += file_menu.get_item_text(i) + ";"
	var window_labels: String = ""
	for i: int in range(window_menu.item_count):
		window_labels += window_menu.get_item_text(i) + ";"
	check(file_labels.contains("Close Tab") and not file_labels.contains("Source") and
		app.top_bar._menus[1].get_popup().get_item_text(2).contains("Rename Source") and
		not window_labels.contains("Object") and not window_labels.contains("Close tab"),
		"File and Object stay distinct and outside Window")
	await shortcut(KEY_N)
	check(app.tabs.size() == 2 and app.active_tab == 1, "native Ctrl+N opens a second document")
	# Width is a workspace preference; the harness must not depend on a prior run.
	app.width_spin.value = 3.0
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
		check(app.tab_bar.get_global_rect().end.x <= app.size.x + 1.0,
			"document tab hit region remains in the resized client: %s" % dims)
		await screenshot("t090-%dx%d" % [dims.x, dims.y])
	root.size = Vector2i(1280, 760)
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(12)
		check(app.tab_bar.get_global_rect().end.x <= app.size.x + 2.0 and
			app.canvas.size.x >= 125.0,
			"scaled tabs, canvas and top bar remain within logical client: %.1fx" % scale)
		await screenshot("t090-scale-%d" % int(scale * 100.0))
	root.content_scale_factor = 1.0
	await frames(8)
	# Native pointer opens the actual collapsed More popup. Checkboxes must
	# remain visible there, not just in their now-hidden source menus.
	root.size = Vector2i(800, 600)
	app.size = Vector2(560, 600)
	await frames(10)
	var top: Control = app.top_bar
	top._refresh_layout()
	var more_popup: PopupMenu = top.more_menu.get_popup()
	var grid_more_id: int = -1
	var tabs_more_id: int = -1
	for item: int in range(more_popup.item_count):
		match more_popup.get_item_text(item):
			"View › Show grid": grid_more_id = item
			"Window › Show document tabs": tabs_more_id = item
	check(top.more_menu.visible and tabs_more_id >= 0 and
		(grid_more_id >= 0 or top._menus[3].visible),
		"narrow native viewport moves Window and later menus into More")
	if tabs_more_id >= 0:
		check(more_popup.is_item_checkable(tabs_more_id) and
			more_popup.is_item_checked(tabs_more_id) == app.show_document_tabs,
			"native More popup mirrors the current document-tabs checkmark")
		# The 560px test-only app width is below the standalone 800px minimum.
		# The tall native popup can cover its own trigger on mouse release;
		# verify the pointer-down opening and release after dispatch instead.
		var more_target: Vector2 = top.more_menu.get_global_rect().get_center()
		await pointer_at(more_target, true)
		check(more_popup.visible, "real pointer opens the native More menu")
		await screenshot("t090-more-checkmarks")
		more_popup.id_pressed.emit(tabs_more_id)
		check(not app.show_document_tabs and not more_popup.is_item_checked(tabs_more_id),
			"native More action updates tabs and its checked state")
		app._toggle_document_tabs()
		more_popup.hide()
		await pointer_at(more_target, false)
	if grid_more_id >= 0:
		check(more_popup.is_item_checkable(grid_more_id) and
			more_popup.is_item_checked(grid_more_id) == app.canvas.show_grid,
			"collapsed native View grid command retains checkable state")
		app._toggle_grid()
		check(more_popup.is_item_checked(grid_more_id) == app.canvas.show_grid,
			"native View grid checkmark updates without rebuilding popup")
		app._toggle_grid()
	root.size = Vector2i(1280, 760)
	app.size = Vector2(1280, 760)
	await frames(10)
	# The current dock toggle uses a real rail slot when minimized and a
	# dock-owned overlay when expanded. Resizing or collapsing it must not
	# reintroduce T-090's black gutters or steal the top toolbar viewport.
	for minimized: bool in [true, false]:
		app._toggle_dock()
		await frames(10)
		check(bool(app.dock_layout.container_info("right")["minimized"]) == minimized,
			"T-090 resize verifies intended dock state: %s" % minimized)
		check(app.top_bar.get_global_rect().end.x <= app.size.x + 2.0 and
			app.canvas.get_global_rect().end.x <= app.size.x + 2.0 and
			app.canvas.size.x >= 125.0 and app.dock_toggle.is_visible_in_tree(),
			"dock toggle preserves full-width chrome and usable canvas: %s" % minimized)
	root.size = Vector2i(1280, 760)
	app.size = Vector2(1280, 760)
	await frames(10)
	check(not top.more_menu.visible and top._menus[7].get_popup().is_item_checked(2),
		"wide viewport restores original Window menu and its checked state")
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
		app.tool_buttons["Brush"].focus_mode == Control.FOCUS_ALL,
		"active Brush command remains pressed and keyboard-focusable")
	print("T090_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T090_NATIVE_PASSED: %d checks" % checks)
	quit(1 if failures > 0 else 0)
