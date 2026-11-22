extends SceneTree
## T-252: actual GUI mouse gestures on Godot's embedded ColorPicker.
## The test samples held-frame pigment changes and the final recent bar.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T252_NATIVE_FAILED: " + label)


func frames(n: int = 3) -> void:
	for _i: int in range(n):
		await process_frame


func pointer(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)


func click(control: Control) -> void:
	pointer(control.get_global_rect().get_center(), true)
	await frames(2)
	pointer(control.get_global_rect().get_center(), false)
	await frames(3)


func screenshot(label: String) -> void:
	var folder: String = OS.get_environment("T252_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"native framebuffer: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 is required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	check(app.dock_layout.move_group("colors", "right", 0), "Colors group can lead dock")
	app._render_dock()
	await frames(10)
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	var hist: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	var colors: Control = app.dock_views["colors"]
	var roles: Control = app.color_top_strip.get_child(0)
	var recent: Control = app.color_top_strip.get_child(1)
	check(roles.get_child_count() == 3 and recent.get_child_count() == 6 and
		absf(roles.size.x - recent.size.x) < 24,
		"concept-like balanced FG/Swap/BG and vertical recents without restore row")
	check(not colors.has_node("PigmentUtilities") and not colors.has_node("PreviousBG") and
		not colors.has_node("Recent"), "no restore-previous chrome or Recent label")
	var first: Color = Color8(35, 76, 140, 222)
	app._set_foreground(first)
	app.recent_colors.clear()
	app._refresh_color_controls()
	app.inspector.scroll_vertical = 0
	await frames(8)
	var origin: Vector2 = app.color_advanced.get_global_rect().position + Vector2(32, 44)
	check(app.inspector.get_global_rect().has_point(origin) and
		app.color_picker_scroll.get_global_rect().has_point(origin), "real picker square is visible")
	var changed: Dictionary = {}
	pointer(origin, true)
	await frames(3)
	for step: int in range(22):
		var position: Vector2 = origin + Vector2(float(step) * 3.5, float(step % 5) * 5.0)
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = position
		motion.global_position = position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.relative = Vector2(3.5, 5.0)
		root.push_input(motion, true)
		await frames(2)
		changed[app._pack_color(app.active_color)] = true
		check(app.recent_colors.is_empty(), "held-frame %d does not enter recents" % step)
	check(changed.size() > 9 and app.canvas.color_rgba == app._pack_color(app.active_color),
		"real pointer updates many distinct live brush preview colors")
	var ending: Color = app.active_color
	pointer(origin + Vector2(73.5, 5.0), false)
	await frames(7)
	check(not app._color_edit_pending and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(first),
		"real mouse release commits one original pigment, not a drag gradient")
	check(ending != first and app._visible_recent_colors().size() == 1,
		"settled drag retains current pigment and previous becomes visible bar")
	await screenshot("committed-foreground")
	var stable: Color = app.active_color
	var original_recent: Color = app.recent_colors[0]
	pointer(origin, true)
	await frames(2)
	for step: int in range(9):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = origin + Vector2(float(step) * 7.0, 12.0)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await frames(2)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await frames(2)
	pointer(origin + Vector2(56, 12), false)
	await frames(6)
	check(app.active_color == stable and app.recent_colors.size() == 1 and
		app.recent_colors[0] == original_recent and not app._color_edit_ignore_until_release,
		"Escape cancels a real native picker drag without leaving recents or paint changed")
	await click(app.background_button)
	check(app.color_edit_background and app.canvas.color_rgba == app._pack_color(stable),
		"real pointer changes selected BG role, not foreground paint")
	app.inspector.scroll_vertical = 0
	await frames(6)
	var bg_origin: Vector2 = app.color_advanced.get_global_rect().position + Vector2(45, 55)
	pointer(bg_origin, true)
	await frames(2)
	for step: int in range(13):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = bg_origin + Vector2(float(step) * 4, 11)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await frames(1)
	pointer(bg_origin + Vector2(48, 11), false)
	await frames(6)
	check(app.active_color == stable and app.color_background != Color.WHITE and
		app.recent_colors.size() == 2 and app._pack_color(app.recent_colors[0]) == app._pack_color(Color.WHITE),
		"real BG drag commits once and leaves FG/brush unchanged")
	await screenshot("committed-background")
	var snapshot: Array[Color] = app.recent_colors.duplicate()
	var host_id: String = app.float_group("colors")
	await frames(8)
	check(not host_id.is_empty() and app.color_top_strip.get_parent() == colors and
		app.recent_colors == snapshot,
		"floating/reparenting the same panel preserves settled recent colors")
	app._dock_apply(DrawingDockDrag.GROUP, "colors", {"kind": DrawingDockDrag.GROUP_SLOT,
		"container": "right", "index": 0}, "drag-group:colors")
	await frames(6)
	check(app.recent_colors == snapshot and app.color_hex.text == "#" + app.color_background.to_html(true).to_upper(),
		"redocking preserves selected role, hex and recents")
	check(doc.revision == rev and doc.history_length() == hist and doc.is_dirty() == dirty,
		"all native ColorPicker operations preserve drawing history and dirty state")
	app.queue_free()
	await frames()
	print("T252_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T252_NATIVE_PASSED" if failures == 0 else "T252_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
