extends SceneTree
## T-092 real X11/Xvfb pointer/framebuffer smoke. Never infer physical input latency.
const PREFS: String = "user://t092-native-preferences.json"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T092_NATIVE_FAILED: " + label)

func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = point
	e.global_position = point
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	control.get_viewport().push_input(e, true)
	await frames(2)
	e.pressed = false
	control.get_viewport().push_input(e, true)
	await frames(4)

func capture(label: String) -> void:
	var folder: String = OS.get_environment("T092_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png(folder.path_join(label + ".png")) == OK,
		"framebuffer screenshot saved " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_settings_path = PREFS
	root.add_child(app)
	await frames(14)
	check(app.color_advanced != null and not app.color_advanced.visible,
		"advanced picker hidden at launch")
	check(not app.record_selection_history and app.history_list.item_count == 1,
		"history starts empty and preference off")
	check(app.color_hex.get_parent().name == "Colors" and
		app.history_list.get_parent().name == "History",
		"compact controls belong to their independent dock panels")
	var initial_revision: int = app.current_document().revision
	var initial_dirty: bool = app.current_document().is_dirty()
	app._set_foreground(Color8(25, 66, 208, 255))
	await frames(3)
	check(app.color_hex.text == "#1942D0FF", "hex mirrors live brush pigment")
	await RenderingServer.frame_post_draw
	var sample: Vector2i = Vector2i(app.foreground_button.global_position) + Vector2i(4, 4)
	var rendered: Color = root.get_texture().get_image().get_pixelv(sample)
	check(rendered.b > rendered.r + 0.25 and rendered.b > rendered.g + 0.25,
		"native framebuffer shows foreground blue swatch")
	await click(app.color_swatch_buttons[4])
	check(app.active_color == Color(0.12, 0.20, 0.35),
		"native recent swatch click restores previous brush pigment")
	var active_before_bg: Color = app.active_color
	var paint_before_bg: int = app.canvas.color_rgba
	await click(app.background_button)
	check(app.color_edit_background and app.active_color == active_before_bg and
		app.color_hex.text == "#FFFFFFFF" and app.canvas.color_rgba == paint_before_bg,
		"native BG chip selects independent editor without swapping brush color")
	check(app.color_role_label.text == "Editing BG", "secondary edit target is visibly labelled")
	app.color_hex.text = "#3C6496C8"
	app._commit_hex()
	check(app.color_background == Color8(60, 100, 150, 200) and
		app.active_color == active_before_bg and app.canvas.color_rgba == paint_before_bg,
		"editing background hex does not touch brush or artwork")
	app.color_rgb[3].value = 0
	check(app.color_background == Color8(60, 100, 150, 0) and
		app.color_hex.text == "#3C649600" and app.canvas.color_rgba == paint_before_bg,
		"alpha control retains hidden background RGB at zero alpha")
	await click(app.previous_background_button)
	check(app.color_background == Color8(60, 100, 150, 200) and
		app.active_color == active_before_bg,
		"native previous BG chip restores only the secondary pigment")
	await click(app.foreground_button)
	check(not app.color_edit_background and app.color_hex.text == "#" + active_before_bg.to_html(true).to_upper(),
		"native FG chip restores brush controls")
	check(app.color_role_label.text == "Editing FG", "foreground editing target is visibly labelled")
	await click(app.previous_foreground_button)
	check(app.active_color != active_before_bg and not app.color_edit_background,
		"native previous FG restores only foreground pigment")
	await click(app.background_button)
	await click(app.color_advanced_toggle)
	check(app.color_advanced.visible and app.color_advanced.color == app.color_background,
		"native click reveals picker seeded with selected background")
	app._set_selected_color(Color8(14, 28, 42, 128))
	check(app.color_background == Color8(14, 28, 42, 128) and app.canvas.color_rgba == app._pack_color(app.active_color),
		"advanced picker background updates without altering brush")
	await click(app.color_advanced_toggle)
	check(not app.color_advanced.visible, "native click restores narrow compact palette")
	check(app.current_document().revision == initial_revision and
		app.current_document().is_dirty() == initial_dirty,
		"color controls do not dirty document")
	var edit_menu: PopupMenu = app.top_bar._menus[1].get_popup()
	check(edit_menu.get_item_text(2).contains("Preferences") and not edit_menu.is_item_checkable(2),
		"Edit menu exposes Preferences, not in-panel setting")
	app._show_preferences()
	await frames(5)
	check(app.preferences_dialog.visible and app.selection_history_toggle.is_visible_in_tree(),
		"Preferences dialog is keyboard and pointer accessible")
	# Godot hosts AcceptDialog in a separate embedded Window: SceneTree.root
	# pointer injection cannot target its subviewport. Exercise the real toggle
	# signal here; physical pointer evidence is limited to dock controls below.
	app.selection_history_toggle.button_pressed = true
	await frames(3)
	check(app.record_selection_history and app.current_document().record_selection_history,
		"native preference toggles current document and all future tabs")
	check(DrawingWorkspacePreferences.read_file(PREFS).get("record_selection_history") == true,
		"preference persists without a document save")
	app.preferences_dialog.hide()
	var doc: DrawingDocument = app.current_document()
	var new_layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER,
		"Blue note", "root", "t092-blue", -1, true)
	check(new_layer.ok, "create an undoable layer event")
	var revision: int = doc.revision
	app._after_edit()
	await frames(4)
	check(doc.history_position() == 1 and app.history_list.item_count == 2,
		"history lists Initial state and one meaningful action")
	check(app.history_list.get_item_text(1).contains("Add · Blue note") and
		app.history_label.text == "1 / 1", "event label and applied cursor are visible")
	check(app.history_redo.disabled and not app.history_undo.disabled,
		"history actions reflect available undo step")
	app.inspector.ensure_control_visible(app.history_undo)
	await frames(6)
	await click(app.history_undo)
	check(doc.history_position() == 0 and doc.revision > revision and not doc.has_node("t092-blue"),
		"native Undo moves cursor backward, revision forward, and restores tree")
	check(app.status.text.contains("history 0/1") and not app.status.text.contains("revision"),
		"status avoids misleading revision-as-undo-position")
	app.inspector.ensure_control_visible(app.history_redo)
	await frames(4)
	await click(app.history_redo)
	check(doc.history_position() == 1 and doc.has_node("t092-blue"),
		"native Redo restores the structural gesture")
	var before_selection_revision: int = doc.revision
	var before: DrawingHistoryContext = app._capture_context()
	var after: DrawingHistoryContext = before.detached_copy()
	after.selection_mask = DrawingSelection.new(Rect2i(-1, -1, 4, 4), true)
	check(doc.record_selection_change(before, after), "selection event is optional and recorded")
	app._update_status()
	check(doc.history_length() == 2 and doc.revision == before_selection_revision and
		app.history_list.get_item_text(2).contains("Selection"),
		"selection-only event appears without content revision")
	app.inspector.ensure_control_visible(app.history_undo)
	await frames(6)
	await click(app.history_undo)
	check(doc.history_position() == 1 and doc.revision == before_selection_revision,
		"selection-only Undo does not change internal revision")
	app.new_drawing()
	check(app.current_document().record_selection_history and app.tabs.size() == 2,
		"new document inherits preference across tabs")
	# Narrow standard dock and floating Color panel: controls must remain reachable.
	app.dock_split.split_offset = roundi(app.dock_split.size.x) - 190
	await frames(8)
	check(app.inspector.size.x < 240 and app.color_hex.size.x > 120 and
		app.color_hex.get_global_rect().end.x <= app.inspector.get_global_rect().end.x + 5,
		"narrow dock keeps hex field inside its viewport")
	check(app.color_role_label.size.x <= app.inspector.size.x + 2,
		"narrow dock keeps active color-role caption within available width")
	check(app.color_rgb.size() == 4 and app.color_rgb[3].size.x >= 69 and
		app.color_rgb[3].get_global_rect().end.x <= app.inspector.get_global_rect().end.x + 5,
		"RGBA alpha is reachable at narrow dock width")
	app.inspector.scroll_vertical = 0
	await frames(8)
	check(app.foreground_button.is_visible_in_tree() and
		app.inspector.get_global_rect().intersects(app.foreground_button.get_global_rect()),
		"scrolled-to-top narrow dock exposes the active Colors controls")
	await capture("t092-compact-narrow")
	root.size = Vector2i(1280, 720)
	app.size = Vector2(1280, 720)
	root.content_scale_factor = 1.5
	await frames(12)
	check(app.color_hex.is_visible_in_tree() and app.canvas.size.x > 380 and
		app.inspector.size.x > 140 and app.color_role_label.is_visible_in_tree(),
		"150% scale preserves a usable canvas and selected-color indicator")
	await capture("t092-scaled-narrow")
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	app.size = Vector2(1280, 800)
	await frames(8)
	var floated: String = app.float_group("colors")
	await frames(6)
	check(not floated.is_empty() and app.floating_hosts.has(floated), "Colors group detaches to one floating host")
	var host: DrawingFloatingHost = app.floating_hosts[floated]
	host.set_host_rect(Rect2(Vector2(260, 145), Vector2(300, 440)))
	await frames(10)
	check(host.visible and app.color_hex.is_visible_in_tree() and app.foreground_button.is_visible_in_tree(),
		"compact Colors controls are visible in floating group")
	await capture("t092-colors-floating")
	app._toggle_advanced_picker()
	await frames(7)
	check(app.color_advanced.visible and app.color_advanced.get_parent().name == "Colors",
		"advanced picker remains accessible after floating/resize")
	await capture("t092-advanced-floating")
	app._toggle_advanced_picker()
	app.queue_free()
	await frames(8)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_persistence_enabled = false
	reopened.preferences_settings_path = PREFS
	root.add_child(reopened)
	await frames(8)
	check(reopened.record_selection_history and reopened.selection_history_toggle.button_pressed,
		"relaunch loads same app preference")
	check(reopened.current_document().record_selection_history and
		reopened.current_document().revision == initial_revision,
		"preference survives restart independently of artwork")
	reopened.queue_free()
	await frames(5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("T092_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T092_NATIVE_PASSED")
	quit(0 if failures == 0 else 1)
