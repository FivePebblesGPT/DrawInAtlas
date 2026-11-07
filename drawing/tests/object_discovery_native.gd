extends SceneTree
## T-093 X11/Xvfb pointer, dock and framebuffer evidence. Not physical latency.
var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T093_NATIVE_FAILED: " + description)


func frames(n: int = 4) -> void:
	for i: int in range(n):
		await process_frame


func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(5)


func capture(label: String) -> void:
	var folder: String = OS.get_environment("T093_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	check(pixels != null and pixels.save_png(folder.path_join(label + ".png")) == OK,
		"saved a real framebuffer screenshot: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 display is required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 900)
	var base: String = ProjectSettings.globalize_path("user://t093-native-" + DrawingDocument.new_id())
	var objects: String = base.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "fixture Objects directory created")
	var document: DrawingDocument = DrawingDocument.new("t093-native-source")
	var added: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	var edited: DrawingResult = document.begin_edit(String(added.value), document.revision)
	check(edited.ok, "start native Object source edit")
	var edit: DrawingEditSession = edited.value as DrawingEditSession
	var bytes: PackedByteArray = PackedByteArray()
	for i: int in range(16 * 16):
		bytes.append_array(PackedByteArray([26, 91, 220, 255]))
	check(edit.apply_region(Rect2i(0, 0, 16, 16), bytes).ok and edit.commit().ok,
		"source contains visible blue pixels")
	var source: String = objects.path_join("native.drawing")
	check(DrawingObjectEditorFile.save(document, source, "Blue Object", Vector2i.ZERO,
		Rect2i(0, 0, 16, 16), 1).ok, "save valid portable Object")
	var digest: String = FileAccess.get_sha256(source)
	var prefs: String = "user://t093-native-root-" + DrawingDocument.new_id() + ".json"
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.recent_objects_root_settings_path = prefs
	root.add_child(app)
	await frames(12)
	check(app.asset_browser == null and app.tabs.size() == 1,
		"clean standalone starts with Drawing only, not a guessed campaign")
	app._show_asset_browser_empty()
	await frames(10)
	var panel: DrawingAssetBrowserPanel = app.asset_browser
	check(panel != null and panel.message.text.contains("No Objects/ folder") and
		panel.root_display.is_visible_in_tree(), "browser shows first-use instructions")
	check(panel.choose_root_button.is_visible_in_tree() and
		panel.open_button.disabled and not panel.place_button.visible,
		"choose root is visible and Atlas placement is not offered in standalone")
	app.inspector.ensure_control_visible(panel.choose_root_button)
	await frames(7)
	check(app.inspector.get_global_rect().intersects(panel.choose_root_button.get_global_rect()),
		"Choose Objects button is reachable through the actual dock scroll")
	await click(panel.choose_root_button)
	check(app.asset_browser_directory_dialog.visible, "pointer Choose triggers filesystem picker")
	check(app.asset_browser_directory_dialog.title.contains("Objects/"),
		"folder picker explains required project subdirectory")
	app.asset_browser_directory_dialog.hide()
	# FileDialog is a separate embedded Window; emulate its confirmed directory
	# callback, not an unverified synthetic click inside that separate viewport.
	app._chosen_objects_root(objects)
	await frames(12)
	check(panel.root_display.text.contains("Objects") and
		panel.root_display.tooltip_text == objects,
		"explicit root shown compactly, with exact path tooltip")
	check(panel.assets.item_count == 1 and panel.recent_root_button.visible,
		"one source is listed and recent-folder control becomes available")
	check(panel.assets.get_item_tooltip(0).contains("t093-native-source"),
		"rendered row exposes immutable source ID")
	app.inspector.ensure_control_visible(panel.assets)
	await frames(12)
	check(panel.assets.get_item_icon(0) != null,
		"visible source loads a real lazy thumbnail")
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	check(screenshot != null and screenshot.get_width() >= 1280 and screenshot.get_height() >= 900,
		"real X11 framebuffer readback covers the workspace")
	await capture("t093-object-sources")
	var row_point: Vector2 = panel.assets.get_global_rect().position + \
		panel.assets.get_item_rect(0).get_center()
	check(panel.assets.get_global_rect().has_point(row_point), "native source row hit target is within browser")
	var row_event: InputEventMouseButton = InputEventMouseButton.new()
	row_event.button_index = MOUSE_BUTTON_LEFT
	row_event.position = row_point
	row_event.global_position = row_point
	row_event.pressed = true
	root.push_input(row_event, true)
	await frames(3)
	row_event.pressed = false
	root.push_input(row_event, true)
	await frames(6)
	check(panel.selected_asset_id() == "t093-native-source" and not panel.open_button.disabled,
		"real pointer selects exact stable source ID")
	app.inspector.ensure_control_visible(panel.open_button)
	await frames(8)
	await click(panel.open_button)
	check(app.tabs.size() == 2 and app.current_object() != null and
		app.current_object().source_id == "t093-native-source",
		"native Open click creates dedicated Object Editor, not a linked map instance")
	check(FileAccess.get_sha256(source) == digest and not app.current_document().is_dirty(),
		"opening does not mutate original Object source")
	var count: int = app.tabs.size()
	check(not app.show_asset_browser(base), "incorrect root produces an actionable failure")
	check(app.tabs.size() == count and panel.index.root_path == objects,
		"failed folder switch does not open a tab or change bound source folder")
	check(app.status.text.contains("Objects/") and app.status.text.contains("Error:"),
		"wrong folder appears as a visible error in status")
	app._open_object_file(base.path_join("missing.drawing"))
	check(app.tabs.size() == count and app.status.text.contains("Error:"),
		"missing direct source open fails without empty success tab")
	root.size = Vector2i(960, 640)
	app.size = Vector2(960, 640)
	await frames(12)
	check(panel.choose_root_button.is_visible_in_tree() and
		panel.root_display.text.contains("Objects"), "narrow viewport retains root and chooser")
	await capture("t093-narrow-object-sources")
	var restarted: Control = load("res://main.tscn").instantiate()
	restarted.layout_persistence_enabled = false
	restarted.recent_objects_root_settings_path = prefs
	root.add_child(restarted)
	await frames(8)
	check(restarted.asset_browser == null, "relaunch does not silently open a remembered Atlas/Objects path")
	restarted._show_asset_browser_empty()
	await frames(5)
	check(restarted.asset_browser.recent_root_button.visible and
		restarted.asset_browser.index.root_path.is_empty(), "recent folder is opt-in on relaunch")
	restarted.inspector.ensure_control_visible(restarted.asset_browser.recent_root_button)
	await frames(6)
	await click(restarted.asset_browser.recent_root_button)
	check(restarted.asset_browser.index.root_path == objects and
		restarted.asset_browser.assets.item_count == 1,
		"native recent-root click reopens saved folder deliberately")
	print("T093_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T093_NATIVE_PASSED")
	quit(1 if failures else 0)
