extends SceneTree
## T-063 native viewport: compact menu/options, shortcuts, focus, dock and save safety.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T063_FAILED: " + description)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame


func shortcut(code: Key, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = shift
	root.push_input(event, true)
	await frames()
	event.pressed = false
	root.push_input(event, true)
	await frames()


func snapshot(name: String) -> void:
	var folder: String = OS.get_environment("T063_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png(folder.path_join(name + ".png")) == OK,
		"native workspace screenshot is captured for review: " + name)


func pointer(canvas: Control, pixel: Vector2i, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(Vector2(pixel) + Vector2(0.5, 0.5))
	event.global_position = event.position
	root.push_input(event, true)
	await frames()


func motion(canvas: Control, pixel: Vector2i) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + canvas.pixel_to_position(Vector2(pixel) + Vector2(0.5, 0.5))
	event.global_position = event.position
	root.push_input(event, true)
	await frames()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires native display")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(12)
	var top: HBoxContainer = app.top_bar
	var menus: HBoxContainer = top.menu_region
	var names: Array[String] = []
	for menu: Control in top._menus:
		names.append((menu as MenuButton).text)
	check(names == ["File", "Edit", "View", "Image", "Layers", "Select", "Window", "Help"],
		"exact eight fixed menu names in intended order")
	check(top.divider.name == "BarDivider" and top.options_scroll.name == "ToolOptionsRegion",
		"dedicated boundary and flexible options container")
	check(not top.more_menu.visible and top._menus[7].visible,
		"full desktop displays all eight application menus")
	await snapshot("drawing-1280")
	check(top.options_region.get_child_count() == 2 and top.active_options == "Brush",
		"brush options show width and generic snap")
	check(not app.record_selection_history and app.selection_history_toggle.get_parent().name == "History",
		"selection-history preference OFF in History dock, not tool options")
	check(app.dock_split != null and app.inspector.get_parent() == app.dock_split,
		"right dock is a resizable split sibling")
	check(app.status.text.contains("cursor") and app.status.text.contains("zoom"),
		"status reports pixel coordinates and zoom")
	var file_popup: PopupMenu = top._menus[0].get_popup()
	check(file_popup.get_item_text(3).contains("Ctrl+Shift+S"),
		"Save As accelerator discoverable in File menu")
	var edit_popup: PopupMenu = top._menus[1].get_popup()
	check(edit_popup.get_item_text(1).contains("Ctrl+Y"),
		"one primary redo shortcut visible")
	await shortcut(KEY_S, true)
	check(app.save_dialog.visible and app.tabs[app.active_tab]["path"] == "",
		"Ctrl+Shift+S opens Save As without overwriting source")
	app.save_dialog.hide()
	app._cancel_pending_close()
	app._toggle_selection_history()
	check(app.record_selection_history and app.selection_history_toggle.button_pressed,
		"Edit menu and History dock share preference")
	check(edit_popup.is_item_checked(2), "Edit menu reflects checked history preference")
	app._selection_history_preference_changed(false)
	check(not app.record_selection_history and not edit_popup.is_item_checked(2),
		"history preference returns to OFF in dock and Edit menu")
	app._toggle_dock()
	check(not app.inspector.visible, "dock can hide independently of drawing canvas")
	app._toggle_dock()
	check(app.inspector.visible, "dock can reopen")
	app._change_tool("Pan")
	await frames()
	check(top.options_region.get_child_count() == 0 and top.active_options == "Pan",
		"Pan has no inert contextual controls")
	app._change_tool("Brush")
	root.size = Vector2i(560, 600)
	app.size = Vector2(560, 600)
	await frames(15)
	check(top.more_menu.visible and top._menus[0].visible and top._menus[1].visible,
		"narrow window retains File/Edit and exposes More")
	check(app.get_child(0).size.x <= 560.0 and app.canvas.size.x > 140,
		"narrow root and drawing canvas fit actual window rather than clipping")
	var about_index: int = -1
	for index: int in range(top.more_menu.get_popup().item_count):
		if top.more_menu.get_popup().get_item_text(index).contains("About Drawing"):
			about_index = index
			break
	check(about_index >= 0, "hidden Help command remains discoverable in More")
	if about_index >= 0:
		top._more_selected(about_index)
		check(app.get_node("WorkspaceAbout").visible, "More invokes the original Help action")
		app.get_node("WorkspaceAbout").hide()
	check(not top._menus[7].visible and top._more_actions.size() > 0,
		"hidden menus remain represented by live More commands")
	check(menus.get_child(menus.get_child_count() - 1) == top.more_menu,
		"More trigger follows the visible File/Edit/View menu group")
	check(app.get_child(0).size.x <= 570 and top.size.y < 52 and top.options_region.get_child_count() == 2,
		"narrow options stay on one row with their real controls")
	var wheel_value: float = app.width_spin.value
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	top.consume_option_wheel(wheel, app.width_spin)
	check(app.width_spin.value == wheel_value, "scrolling over brush width does not change it")
	var wheel_position: Vector2 = app.width_spin.global_position + Vector2(20, 12)
	wheel.position = wheel_position
	wheel.global_position = wheel_position
	root.push_input(wheel, true)
	await frames(4)
	check(app.width_spin.value == wheel_value,
		"native unmodified wheel over brush width cannot alter the setting")
	await frames(4)
	check(top.left_cue.visible and top.right_cue.visible,
		"long brush options have edge cues, rather than wrapping")
	var before_scroll: int = top.options_scroll.scroll_horizontal
	var shifted: InputEventMouseButton = InputEventMouseButton.new()
	shifted.pressed = true
	shifted.shift_pressed = true
	shifted.button_index = MOUSE_BUTTON_WHEEL_DOWN
	top.consume_option_wheel(shifted, app.width_spin)
	await frames(4)
	check(top.options_scroll.scroll_horizontal > before_scroll and
		app.width_spin.value == wheel_value, "Shift+wheel scrolls options without changing brush width")
	top.scroll_options(250)
	await frames()
	check(top.options_scroll.scroll_horizontal > 0 and not top.left_cue.disabled,
		"chevron input scrolls the tool settings horizontally")
	var native_wheel: InputEventMouseButton = InputEventMouseButton.new()
	native_wheel.position = app.width_spin.get_global_rect().get_center()
	native_wheel.global_position = native_wheel.position
	native_wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	native_wheel.pressed = true
	native_wheel.shift_pressed = true
	var native_before: int = top.options_scroll.scroll_horizontal
	root.push_input(native_wheel, true)
	await frames()
	check(app.width_spin.value == wheel_value and
		top.options_scroll.scroll_horizontal >= native_before,
		"native wheel over numeric brush control cannot mutate its value")
	app.snap_toggle.grab_focus()
	await frames(5)
	var viewport_bounds: Rect2 = Rect2(top.options_scroll.global_position, top.options_scroll.size)
	var focused_bounds: Rect2 = Rect2(app.snap_toggle.global_position, app.snap_toggle.size)
	check(app.snap_toggle.has_focus() and viewport_bounds.intersects(focused_bounds),
		"keyboard focus scrolls the focused option into the visible region")
	app._change_tool("Text")
	check(top.options_scroll.scroll_horizontal == 0 and
		app.width_spin.get_parent() == top._unused_options and
		not app.width_spin.is_visible_in_tree(),
		"tool switch resets scroll and hides unsupported brush controls")
	root.size = Vector2i(420, 600)
	app.size = Vector2(420, 600)
	await frames(12)
	check(app.get_child(0).size.x <= 420 and top.size.y < 52,
		"420px window keeps one-row workspace within viewport")
	check(top._menus[0].visible and top._menus[1].visible and top.more_menu.visible,
		"File/Edit and overflow remain accessible at 420px")
	app._change_tool("Brush")
	await frames(4)
	await snapshot("drawing-420")
	root.content_scale_factor = 1.5
	await frames(12)
	check(top.size.y < 70 and top.more_menu.visible and app.get_child(0).size.x <= 420,
		"scaled compact workspace retains More without root overflow")
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	app.size = Vector2(1280, 800)
	await frames(12)
	app._change_tool("Brush")
	check(not top.more_menu.visible, "resizing restores all native menus")
	var source_path: String = OS.get_user_data_dir().path_join("t063-original.drawing")
	var target_path: String = OS.get_user_data_dir().path_join("t063-save-as.drawing")
	app._save_file(source_path)
	check(FileAccess.file_exists(source_path) and not app.current_document().is_dirty(),
		"saving a new workspace tab clears the content dirty state")
	var saved_before: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	var current: DrawingDocument = app.current_document()
	var layer: String = app.current_layer()
	var pixel: Vector2i = Vector2i(5, 6)
	await motion(app.canvas, pixel)
	check(app.status.text.contains("cursor 5,6") and not current.is_dirty(),
		"native pointer motion updates cursor status without dirtying the document")
	await pointer(app.canvas, pixel, true)
	await pointer(app.canvas, pixel, false)
	var original_pixel: DrawingResult = current.read_pixel(layer, pixel.x, pixel.y)
	check(original_pixel.ok and int(original_pixel.value) != 0 and current.is_dirty(),
		"native pointer paints shared Drawing document and sets dirty state")
	check(app.tab_bar.get_tab_title(app.active_tab).ends_with(" *"),
		"modified document tab displays an unsaved asterisk")
	app.new_drawing()
	check(app.tabs.size() == 2 and app.active_tab == 1,
		"new ordinary tab retains the edited tab in the workspace")
	app._activate(0)
	check(app.current_document() == current and current.read_pixel(layer, pixel.x, pixel.y).value == original_pixel.value,
		"switching document tabs preserves unsaved exact pixels")
	app._request_close_current()
	check(app.close_dialog.visible and app.tabs.size() == 2,
		"closing modified tab requires an unsaved-change decision")
	app.close_dialog.hide()
	app._cancel_pending_close()
	check(app.tabs.size() == 2 and current.is_dirty(),
		"cancelling close preserves both tabs and dirty state")
	await shortcut(KEY_Z)
	check(int(current.read_pixel(layer, pixel.x, pixel.y).value) == 0,
		"global shortcut undo removes native pointer paint")
	await shortcut(KEY_Y)
	check(current.read_pixel(layer, pixel.x, pixel.y).value == original_pixel.value,
		"primary Ctrl+Y restores the same RGBA8 pixel")
	await shortcut(KEY_S, true)
	check(app.save_dialog.visible and String(app.tabs[app.active_tab]["path"]) == source_path,
		"Save As prompts on an existing file without rewriting its path")
	app.save_dialog.hide()
	app._cancel_pending_close()
	check(FileAccess.get_file_as_bytes(source_path) == saved_before,
		"dismissing Save As preserves original saved bytes")
	app._save_file(target_path)
	check(FileAccess.file_exists(target_path) and String(app.tabs[0]["path"]) == target_path
		and not current.is_dirty(), "Save As creates second portable file and updates active tab")
	check(FileAccess.get_file_as_bytes(source_path) == saved_before and
		FileAccess.get_file_as_bytes(target_path) != saved_before,
		"Save As retains original file and stores distinct modified content")
	DirAccess.remove_absolute(source_path)
	DirAccess.remove_absolute(target_path)
	var hidden_edit: DrawingResult = current.begin_edit(layer, current.revision)
	check(hidden_edit.ok, "compact workspace still provides canonical Drawing edit sessions")
	if hidden_edit.ok:
		var edit: DrawingEditSession = hidden_edit.value as DrawingEditSession
		var applied: DrawingResult = edit.apply_region(Rect2i(-12, 7, 1, 1),
			PackedByteArray([14, 27, 39, 0]))
		check(applied.ok and edit.commit().ok,
			"transparent hidden-RGB edits commit using the shared Drawing core")
		app._after_edit()
		var hidden_pixel: DrawingResult = current.read_pixel(layer, -12, 7)
		check(hidden_pixel.ok and int(hidden_pixel.value) == (14 | (27 << 8) | (39 << 16)),
			"compact workspace preserves hidden RGB at alpha zero")
	print("T063_WORKSPACE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T063_WORKSPACE_PASSED")
	quit(1 if failures else 0)
