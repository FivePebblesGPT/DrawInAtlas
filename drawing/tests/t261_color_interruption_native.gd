extends SceneTree
## T-261: interrupted native ColorPicker drags roll back, then recover on a fresh press.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T261_NATIVE_FAILED: " + label)


func frames(n: int = 3) -> void:
	for _i: int in range(n):
		await process_frame


func pointer(position: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = down
	root.push_input(event, true)


func motion(position: Vector2, down: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	root.push_input(event, true)


func drag(start: Vector2) -> void:
	pointer(start, true)
	await frames(3)
	for step: int in range(9):
		motion(start + Vector2(2.0 * float(step), 4.0 * float(step % 4)), true)
		await frames(2)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1400, 850)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	check(app.dock_layout.move_group("colors", "right", 0), "Colors dock visible")
	app._render_dock()
	await frames(10)
	var initial: Color = Color8(35, 86, 168, 222)
	app._set_foreground(initial)
	app.recent_colors.clear()
	app.recent_colors_settings_path = "user://t261-gesture-prefs-v1.json"
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(app.recent_colors_settings_path + suffix))
	app.preferences_persistence_enabled = true
	app._save_color_history()
	app.inspector.scroll_vertical = 0
	await frames(6)
	var point: Vector2 = app.color_advanced.get_global_rect().position + Vector2(35, 45)
	check(app.inspector.get_global_rect().has_point(point), "real picker canvas is visible")
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	await drag(point)
	check(app._color_edit_pending and app._color_edit_pointer_down and app.active_color != initial and
		app.recent_colors.is_empty(), "held drag previews pigment without recent entry")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await frames(4)
	check(app.active_color == initial and app.canvas.color_rgba == app._pack_color(initial) and
		app.recent_colors.is_empty() and not app._color_edit_pending,
		"window focus loss rolls back held foreground preview")
	app.color_advanced.color_changed.emit(Color8(211, 88, 42, 0))
	await frames(2)
	check(app.active_color == initial and app.recent_colors.is_empty(),
		"stale native change signal after focus loss is ignored")
	pointer(point + Vector2(14, 8), false)
	await frames(5)
	check(app.active_color == initial and app.recent_colors.is_empty(),
		"late mouse-up cannot commit an interrupted pigment")
	var persisted: Dictionary = DrawingColorHistorySettings.read_file(app.recent_colors_settings_path)
	check(persisted.get("foreground") == initial and (persisted.get("recent") as Array).is_empty(),
		"canceled held preview does not overwrite settled pigment preference")
	await drag(point + Vector2(57, 27))
	pointer(point + Vector2(73, 27), false)
	await frames(6)
	check(app.active_color != initial and not app._color_edit_pending and
		app.recent_colors.size() == 1 and app._pack_color(app.recent_colors[0]) == app._pack_color(initial),
		"first clean press after focus loss commits exactly one settled edit")
	var settled: Color = app.active_color
	app.recent_colors.clear()
	await drag(point)
	check(app._color_edit_pending and app.active_color != settled,
		"second held native drag changes live pigment")
	# Simulate a dropped OS mouse-up with the next motion reporting no buttons held.
	motion(point + Vector2(22, 20), false)
	await frames(4)
	check(app.active_color == settled and app.recent_colors.is_empty() and
		not app._color_edit_pending, "unpressed motion cancels lost-release preview")
	app.color_advanced.color_changed.emit(Color8(252, 55, 69, 11))
	await frames(2)
	check(app.active_color == settled and app.recent_colors.is_empty(),
		"lost-release suppresses late native changes")
	persisted = DrawingColorHistorySettings.read_file(app.recent_colors_settings_path)
	check(persisted.get("foreground") == settled and (persisted.get("recent") as Array).size() == 1,
		"missing mouse-up never writes a transient pigment to disk")
	await drag(point + Vector2(70, 24))
	pointer(point + Vector2(76, 28), false)
	await frames(5)
	check(app.recent_colors.size() == 1 and app._pack_color(app.recent_colors[0]) == app._pack_color(settled),
		"fresh press recovers from missing release without losing recents")
	# BG with alpha-zero hidden RGB must restore source bytes; FG paint stays fixed.
	var current_fg: Color = app.active_color
	app._color_swatch_pressed("Background")
	var initial_bg: Color = app.color_background
	app.recent_colors.clear()
	app._begin_color_edit()
	app._color_edit_pointer_down = true
	app.color_advanced.color_changed.emit(Color8(49, 111, 203, 0))
	check(app.color_background == Color8(49, 111, 203, 0),
		"interrupted BG preview preserves RGBA8 including hidden RGB")
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(4)
	check(app.color_background == initial_bg and app.active_color == current_fg and
		app.recent_colors.is_empty() and not app._color_edit_pending,
		"application focus loss cancels BG preview but not FG brush")
	# Keyboard/text edit is not a pointer preview and must settle on focus loss.
	app._end_cancelled_color_pointer()
	app._begin_color_edit()
	app.color_advanced.color_changed.emit(Color8(7, 93, 131, 0))
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await frames(4)
	check(app.color_background == Color8(7, 93, 131, 0) and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(initial_bg),
		"unheld keyboard edit settles once on focus loss without RGB loss")
	check(doc.revision == rev and doc.history_length() == history and doc.is_dirty() == dirty,
		"all interrupted/settled palette edits leave raster and Undo history intact")
	app.queue_free()
	await frames(3)
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://t261-gesture-prefs-v1.json" + suffix))
	print("T261_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T261_NATIVE_PASSED" if failures == 0 else "T261_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
