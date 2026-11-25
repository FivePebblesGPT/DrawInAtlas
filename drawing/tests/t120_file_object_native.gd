extends SceneTree
## T-120 native X11 menu pointer, responsive overflow and Open/Save witness.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T120_NATIVE_FAILED: " + description)


func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame


func click(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	for down: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = position
		event.global_position = position
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await frames(4)


func shortcut(code: Key, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.ctrl_pressed = true
		event.shift_pressed = shift
		root.push_input(event, true)
		await process_frame
	await frames(3)


func screenshot(name: String) -> void:
	var directory: String = OS.get_environment("T120_SCREENSHOTS")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	var bitmap: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(directory)
	check(bitmap != null and bitmap.save_png(directory.path_join(name + ".png")) == OK,
		"native renderer captured framebuffer " + name)


func more_index(popup: PopupMenu, label: String) -> int:
	for i: int in range(popup.item_count):
		if popup.get_item_text(i) == label:
			return i
	return -1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 renderer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(12)
	var top: Control = app.top_bar
	top._refresh_layout()
	check(top._menus.size() == 9 and top._menus[0].visible and top._menus[1].visible,
		"normal desktop shows File and Object as independent menu buttons")
	check(top._menus[0].get_popup().item_count == 6 and top._menus[1].get_popup().item_count == 5,
		"File has six and Object has five distinct commands")
	await click(top._menus[1])
	check(top._menus[1].get_popup().visible, "real pointer opens top-level Object popup")
	await screenshot("object-menu-wide")
	top._menus[1].get_popup().hide()
	await click(top._menus[0])
	check(top._menus[0].get_popup().visible, "real pointer opens File popup")
	await screenshot("file-menu-wide")
	top._menus[0].get_popup().id_pressed.emit(1)
	top._menus[0].get_popup().hide()
	await frames(4)
	check(app.open_dialog.visible and app.open_dialog.title.contains("raster image") and
		str(app.open_dialog.filters).contains("*.webp"),
		"single Open command invokes raster-and-drawing filesystem chooser")
	app.open_dialog.hide()
	await shortcut(KEY_O)
	check(app.open_dialog.visible, "Ctrl+O opens the same unified chooser")
	app.open_dialog.hide()

	var base: String = ProjectSettings.globalize_path("user://t120-native-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "native fixtures directory created")
	var image: Image = Image.create(10, 7, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(5, 3, Color8(44, 91, 232, 255))
	var source: String = base.path_join("native-input.png")
	check(image.save_png(source) == OK, "native PNG fixture written")
	var digest: String = FileAccess.get_sha256(source)
	var count: int = app.tabs.size()
	app.open_dialog.file_selected.emit(source)
	await frames(12)
	check(app.tabs.size() == count + 1 and app.current_object() == null and
		String(app.tabs[app.active_tab]["path"]).is_empty() and
		app.canvas.image_bounds == Rect2i(0, 0, 10, 7),
		"dialog selection opens editable unsaved raster tab with visible frame")
	var loaded: DrawingResult = DrawingRenderer.render(app.current_document(),
		Rect2i(0, 0, 10, 7), 0, 0, 256)
	check(loaded.ok and (loaded.value as Image).get_pixel(5, 3).b8 == 232,
		"native canvas receives exact imported pixel content")
	await screenshot("imported-image-frame")
	await shortcut(KEY_W)
	check(app.close_dialog.visible and app.current_object() == null,
		"Ctrl+W on imported unsaved image preserves dirty-close confirmation")
	app.close_dialog.hide()
	app._cancel_pending_close()
	await shortcut(KEY_S)
	check(app.save_dialog.visible and String(app.tabs[app.active_tab]["path"]).is_empty(),
		"native first Save requires new .drawing destination")
	app.save_dialog.hide()
	var target: String = base.path_join("native-result.drawing")
	app._save_file(target)
	await shortcut(KEY_S, true)
	check(app.save_dialog.visible and String(app.tabs[app.active_tab]["path"]) == target,
		"Ctrl+Shift+S exposes independent Save As without mutating current target")
	app.save_dialog.hide()
	app._cancel_pending_close()
	check(FileAccess.file_exists(target) and FileAccess.get_sha256(source) == digest,
		"native Save creates .drawing without altering original raster")
	app.open_dialog.file_selected.emit(target)
	await frames(8)
	check(app.canvas.image_bounds == Rect2i(0, 0, 10, 7) and app.current_object() == null,
		"native Open reopens saved Drawing with frame and no Object publication")

	root.min_size = Vector2i(300, 400)
	root.size = Vector2i(300, 600)
	app.size = Vector2(300, 600)
	await frames(12)
	top._refresh_layout()
	var more: PopupMenu = top.more_menu.get_popup()
	var source_id: int = more_index(more, "Object › Browse Sources…")
	check(top._menus[0].visible and not top._menus[1].visible and top.more_menu.visible and
		source_id >= 0, "narrow desktop moves Object to More and keeps File present")
	var more_target: Vector2 = top.more_menu.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = more_target
	motion.global_position = more_target
	root.push_input(motion, true)
	await process_frame
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = more_target
	down.global_position = more_target
	root.push_input(down, true)
	await frames(3)
	check(not more.visible, "held trigger cannot open tall overflow over its own release")
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = more_target
	up.global_position = more_target
	up.pressed = false
	root.push_input(up, true)
	await frames(3)
	check(more.visible, "native pointer release opens More overflow")
	await screenshot("object-in-more")
	if source_id >= 0:
		more.id_pressed.emit(source_id)
		await frames(7)
		check(app.asset_browser != null and app.asset_browser.index.root_path.is_empty(),
			"overflow Object Browse dispatches same Asset Browser without implicit binding")
	more.hide()
	root.size = Vector2i(1280, 800)
	app.size = Vector2(1280, 800)
	await frames(12)
	top._refresh_layout()
	check(top._menus[1].visible and not top.more_menu.visible and app.current_object() == null,
		"normal desktop restores Object menu, without creating a stray source")
	var before_new: int = app.tabs.size()
	await shortcut(KEY_N)
	check(app.tabs.size() == before_new + 1 and app.current_object() == null,
		"Ctrl+N still creates an ordinary blank Drawing tab")

	print("T120_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T120_NATIVE_PASSED")
	quit(1 if failures else 0)
