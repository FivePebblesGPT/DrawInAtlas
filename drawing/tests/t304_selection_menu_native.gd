extends SceneTree
## Shared workspace menu contract with actual native popup input.
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T304_NATIVE_FAILED: " + description)

func frames(count: int = 5) -> void:
	for i: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

func click(window: Window, position: Vector2) -> void:
	window.warp_mouse(position)
	await frames(3)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		window.push_input(event, true)
		await frames(2)

func key(window: Window, code: Key, ctrl: bool = false, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		event.shift_pressed = shift
		window.push_input(event, true)
		await frames(2)

func popup_key(code: String) -> void:
	var helper: String = ProjectSettings.globalize_path("res://tests/x11_test_key.py")
	if not FileAccess.file_exists(helper):
		helper = ProjectSettings.globalize_path("res://../tests/x11_test_key.py")
	var result: int = OS.execute("python3", PackedStringArray([helper, code]))
	check(result == 0, "OS key injection succeeds")
	await frames(8)

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("T304_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	var image: Image = DisplayServer.screen_get_image(0)
	if image != null:
		var result: Error = image.save_png(folder.path_join(name + ".png"))
		if result != OK:
			printerr("OPTIONAL_VISUAL_CAPTURE_FAILED: " + str(result))

func find_item(popup: PopupMenu, label: String) -> int:
	for i: int in range(popup.item_count):
		if popup.get_item_text(i) == label:
			return i
	return -1

func check_mode(app: Control, direct: PopupMenu, overflow: PopupMenu, index: int) -> void:
	check(app.canvas.selection_mode == app.SELECTION_MODES[index] and app.selection_mode_control.selected == index,
		"canvas and contextual mode agree: " + app.SELECTION_MODES[index])
	for popup: PopupMenu in [direct, overflow]:
		var selected_count: int = 0
		for i: int in range(popup.item_count):
			if popup.is_item_checked(i):
				selected_count += 1
		check(selected_count == 1 and popup.is_item_checked(index) and popup.is_item_radio_checkable(index),
			"exactly one radio mode in each menu copy")

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		check(false, "native display and tiles required")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(40, 40)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(10)
	var top: Control = app.top_bar
	var selection: PopupMenu = top._menus[6].get_popup()
	check(top._menus[6].text == "Selection", "Selection menu named explicitly")
	check(selection.item_count == 4 and selection.get_item_text(0) == "Selection mode", "dedicated mode submenu replaces duplicate tools and flat modes")
	var file: PopupMenu = top._menus[0].get_popup()
	var edit: PopupMenu = top._menus[2].get_popup()
	check(file.get_item_accelerator(0) == (KEY_MASK_CTRL | KEY_N) and file.get_item_text(0) == "New", "native accelerator distinct from command text")
	check(file.get_item_accelerator(3) == (KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S) and edit.get_item_accelerator(6) == KEY_DELETE,
		"Save As and Delete captions use actual key metadata")
	check(file.is_item_shortcut_disabled(0) and edit.is_item_shortcut_disabled(6), "menu captions cannot bypass focus-aware shortcuts")
	check(top.options_region.get_child_count() == 2, "Brush has no exposed snap control")
	var direct: PopupMenu = selection.get_item_submenu_node(0) as PopupMenu
	if direct == null:
		check(false, "native submenu missing")
		quit(1)
		return
	var overflow: PopupMenu = top._radio_submenus[Vector2i(6, 0)][1]
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var history: int = doc.history_length()
	check_mode(app, direct, overflow, 0)
	await click(root, top._menus[0].get_global_rect().get_center())
	check(file.visible, "pointer opens File menu")
	await screenshot("file-shortcuts")
	file.hide()
	await click(root, top._menus[2].get_global_rect().get_center())
	check(edit.visible, "pointer opens Edit menu")
	await screenshot("edit-shortcuts")
	edit.hide()
	await click(root, app.tool_buttons["Select"].get_global_rect().get_center())
	check(app.active_tool == "Select" and top.options_region.get_child_count() == 1, "Select rail stays active with only combine mode")
	await click(root, top._menus[6].get_global_rect().get_center())
	check(selection.visible, "pointer opens Selection")
	selection.set_focused_item(0)
	await popup_key("Right")
	check(direct.visible, "keyboard opens native Selection mode submenu")
	await screenshot("selection-mode")
	if direct.visible:
		direct.set_focused_item(1)
		await popup_key("Return")
	check_mode(app, direct, overflow, 1)
	selection.hide()
	direct.hide()
	# Mode affects real subsequent marquee, not content revision or history.
	var canvas: Control = app.canvas
	canvas.set_selection_mask(DrawingSelection.new(Rect2i(0, 0, 2, 2), true))
	canvas.start_gesture(canvas.pixel_to_position(Vector2(3.5, 0.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(4.5, 1.5)))
	check(canvas.selection_mask.allows(Vector2i(0, 0)) and canvas.selection_mask.allows(Vector2i(3, 0)), "Add menu mode unions real rectangle")
	check(doc.revision == revision and doc.history_length() == history, "mode and selection do not mutate document")
	app.selection_mode_control.select(2)
	app.selection_mode_control.item_selected.emit(2)
	check_mode(app, direct, overflow, 2)
	root.size = Vector2i(800, 600)
	await frames(12)
	await click(root, top._menus[6].get_global_rect().get_center())
	check(selection.visible, "800px window still exposes Selection directly")
	selection.set_focused_item(0)
	await popup_key("Right")
	await screenshot("selection-800")
	direct.hide()
	selection.hide()
	root.content_scale_factor = 1.5
	await frames(12)
	var more: PopupMenu = top.more_menu.get_popup()
	var more_index: int = find_item(more, "Selection › Selection mode")
	check(not top._menus[6].visible and more_index >= 0, "narrow layout preserves native submenu in More")
	if more_index >= 0:
		check(more.get_item_submenu_node(more_index) == overflow, "overflow uses stable submenu copy")
		var deselect_index: int = find_item(more, "Selection › Deselect")
		check(deselect_index >= 0 and more.get_item_accelerator(deselect_index) == (KEY_MASK_CTRL | KEY_D), "overflow shortcut caption preserved")
		await click(root, top.more_menu.get_global_rect().get_center())
		check(more.visible, "pointer opens narrow More")
		more.set_focused_item(more_index)
		await popup_key("Right")
		check(overflow.visible, "keyboard opens nested overflow mode menu")
		await screenshot("selection-narrow")
		if overflow.visible:
			overflow.set_focused_item(3)
			await popup_key("Return")
		check_mode(app, direct, overflow, 3)
	more.hide()
	overflow.hide()
	# Verify mode changes cannot publish a pending floating Move or alter a held rectangle.
	var seed: DrawingEditSession = doc.begin_edit(app.current_layer(), doc.revision).value
	check(seed.fill_rect(Rect2i(0, 0, 2, 2), 0xff998877).ok and seed.commit().ok, "seed floating move")
	canvas.set_selection_mask(DrawingSelection.new(Rect2i(0, 0, 2, 2), true))
	app._change_tool("Move")
	var move_revision: int = doc.revision
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(3.5, 0.5)))
	check(canvas.has_floating_move(), "move preview remains detached")
	app._set_selection_mode("Replace")
	check_mode(app, direct, overflow, 0)
	check(canvas.has_floating_move() and doc.revision == move_revision, "mode change does not drop pending Move")
	app._cancel_floating_move()
	app._change_tool("Select")
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(3.5, 3.5)))
	app._set_selection_mode("Subtract")
	check_mode(app, direct, overflow, 0)
	check(canvas.selecting and doc.revision == move_revision, "held rectangle keeps captured mode without publication")
	canvas.cancel_gesture()
	root.size = Vector2i(1280, 800)
	root.content_scale_factor = 1.5
	await frames(12)
	await click(root, top._menus[0].get_global_rect().get_center())
	await screenshot("file-hidpi")
	file.hide()
	root.content_scale_factor = 1.0
	await frames(8)
	await key(root, KEY_D, true)
	check(not canvas.selection_mask.enabled, "Ctrl+D remains routed to canvas selection")
	for tool: String in ["Brush", "Eraser", "Select", "Move", "Text", "Pan", "Bucket", "Shapes"]:
		app._change_tool(tool)
		check(not canvas.snap_to_grid, "normal tool does not enable hidden snapping: " + tool)
	canvas.snap_to_grid = true
	app.new_drawing()
	check(not canvas.snap_to_grid, "new tab cannot inherit a stale snap flag")
	app._activate(0)
	check(not canvas.snap_to_grid, "returning tab cannot restore a hidden snap flag")
	# Delete in a focused text field must never delete selected artwork.
	var active_doc: DrawingDocument = app.current_document()
	canvas.set_selection_mask(DrawingSelection.new(Rect2i(0, 0, 2, 2), true))
	var text: LineEdit = LineEdit.new()
	text.text = "abc"
	app.add_child(text)
	text.grab_focus()
	text.caret_column = 0
	var text_revision: int = active_doc.revision
	await key(root, KEY_DELETE)
	check(text.text == "bc" and active_doc.revision == text_revision, "Delete stays in focused text field")
	text.queue_free()
	await frames()
	canvas.grab_focus()
	var count: int = app.tabs.size()
	await key(root, KEY_N, true)
	check(app.tabs.size() == count + 1, "Ctrl+N executes once, not via duplicate accelerator routing")
	print("T304_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T304_NATIVE_PASSED")
	quit(1 if failures else 0)
