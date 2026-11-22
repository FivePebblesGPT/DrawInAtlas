extends SceneTree
## T-226: native X11 pointer, wheel, focus and viewport checks for inline Colors.

var checks: int = 0
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("T226_NATIVE_FAILED: " + label)

func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame

func pointer(point: Vector2, down: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	pointer(point, true)
	await frames(2)
	pointer(point, false)
	await frames(5)

func wheel(point: Vector2, direction: MouseButton) -> void:
	pointer(point, true, direction)
	await frames(5)

func enter() -> void:
	for down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = down
		root.push_input(event, true)
		await frames(2)

func capture(label: String) -> void:
	var folder: String = OS.get_environment("T226_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"native framebuffer screenshot: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(14)
	check(app.dock_layout.move_group("colors", "right", 0), "Colors group can move ahead of Brushes")
	app._render_dock()
	await frames(9)
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var dirty: bool = doc.is_dirty()
	var history: int = doc.history_length()
	check(app.color_advanced is ColorPicker and app.color_advanced.visible and
		app.color_picker_scroll.get_parent() == app.dock_views["colors"],
		"native full ColorPicker is an always-visible inline child")
	check(app.color_top_strip.get_parent() == app.dock_views["colors"] and
		app.color_top_strip.get_child_count() == 2 and app.color_recent_buttons.size() == 6,
		"two balanced header halves contain role blocks and recent bars")
	var roles: Control = app.color_top_strip.get_child(0)
	var recents: Control = app.color_top_strip.get_child(1)
	check(absf(roles.size.x - recents.size.x) < 24.0,
		"role and recent region occupy approximately equal width")
	check(app.color_advanced.get_global_rect().position.y > app.color_top_strip.get_global_rect().end.y,
		"picker follows the compact header inside the same scrollable panel")
	app._set_foreground(Color8(22, 62, 201, 255))
	await frames(4)
	var fg_pixel: Vector2i = Vector2i(app.foreground_button.global_position) + Vector2i(5, 5)
	await RenderingServer.frame_post_draw
	var pixel: Color = root.get_texture().get_image().get_pixelv(fg_pixel)
	check(pixel.b > pixel.r + 0.25 and pixel.b > pixel.g + 0.25,
		"native framebuffer paints foreground blue block")
	check(app.foreground_button.get_theme_stylebox("normal").border_color.b > 0.75,
		"currently edited foreground has a distinct border")
	await click(app.background_button)
	check(app.color_edit_background and app.color_advanced.color == app.color_background and
		app.color_hex.text == "#FFFFFFFF" and app.canvas.color_rgba == app._pack_color(app.active_color),
		"native pointer switches active edit role to BG without changing paint")
	check(app.background_button.get_theme_stylebox("normal").border_color.b > 0.75,
		"BG role has visible selected border")
	app.inspector.ensure_control_visible(app.color_hex)
	await frames(6)
	await click(app.color_hex)
	check(root.gui_get_focus_owner() == app.color_hex, "actual pointer focuses canonical hex field")
	app.color_hex.text = "#A1B2C300"
	await enter()
	check(app.color_background == Color8(161, 178, 195, 0) and
		app.color_advanced.color == app.color_background and app.canvas.color_rgba == app._pack_color(app.active_color),
		"native Enter edits hidden BG RGB and synchronizes inline picker")
	await click(app.foreground_button)
	check(not app.color_edit_background and app.color_hex.text == "#163EC9FF" and
		app.color_advanced.color == app.active_color,
		"native FG click restores picker/hex focus to foreground")
	app.recent_colors.clear()
	app._remember_recent(Color8(22, 62, 201, 255))
	app._remember_recent(Color8(161, 178, 195, 0))
	app._remember_recent(Color8(240, 51, 66, 200))
	app._refresh_color_controls()
	await frames(6)
	check(app.color_recent_buttons[0].visible and not app.color_recent_buttons[1].visible and
		app.color_recent_buttons[0].tooltip_text.contains("#F03342C8"),
		"display filter hides current roles and exposes only other RGBA8 bar")
	await click(app.color_recent_buttons[0])
	check(app.active_color == Color8(240, 51, 66, 200) and
		app.canvas.color_rgba == app._pack_color(app.active_color),
		"native bar click applies filtered color to FG rather than raw history slot")
	check(app.color_recent_buttons[0].tooltip_text.contains("#163EC9FF"),
		"recent role filter refreshes after applying a bar")
	await capture("expanded")
	# The picker must remain reachable, not merely exist offscreen.
	app.inspector.ensure_control_visible(app.color_advanced)
	await frames(8)
	var scroll: ScrollContainer = app.inspector
	check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,
		"full inline picker increases content height and is reachable through panel scroll")
	check(scroll.get_global_rect().intersects(app.color_advanced.get_global_rect()),
		"scroll can bring the native picker into the visible dock viewport")
	# The picker itself must respond to actual mouse input, not only a helper
	# invoked from our model test. Scroll its color square into view first.
	scroll.scroll_vertical = 45
	await frames(8)
	var picker_point: Vector2 = app.color_advanced.get_global_rect().position + Vector2(42, 45)
	check(scroll.get_global_rect().has_point(picker_point) and
		app.color_picker_scroll.get_global_rect().has_point(picker_point),
		"native color square has an actual on-screen click target")
	var before_native_pick: int = app.canvas.color_rgba
	pointer(picker_point, true)
	await frames(3)
	pointer(picker_point, false)
	await frames(7)
	check(app.canvas.color_rgba != before_native_pick and
		app.color_advanced.color == app.active_color and
		app.color_hex.text == "#" + app.active_color.to_html(true).to_upper(),
		"actual pointer in Godot color square changes FG, picker and exact hex")
	var picker_wheel_before: int = scroll.scroll_vertical
	var picked_color: Color = app.active_color
	await wheel(picker_point, MOUSE_BUTTON_WHEEL_UP)
	check(scroll.scroll_vertical < picker_wheel_before and app.active_color == picked_color,
		"plain wheel directly over native ColorPicker scrolls host, not active pigment")
	var before_wheel: int = scroll.scroll_vertical
	await wheel(scroll.get_global_rect().position + Vector2(scroll.size.x - 6, scroll.size.y * 0.5), MOUSE_BUTTON_WHEEL_UP)
	check(scroll.scroll_vertical < before_wheel or before_wheel == 0,
		"wheel over dock scrollbar scrolls vertically even beside native picker")
	root.size = Vector2i(1050, 490)
	app.dock_split.split_offset = roundi(app.dock_split.size.x) - 190
	await frames(14)
	check(app.inspector.size.x <= 235 and app.color_hex.size.x >= 105,
		"narrow and short dock retains a usable exact-hex editor")
	app.inspector.ensure_control_visible(app.color_advanced)
	await frames(8)
	check(app.inspector.get_global_rect().intersects(app.color_advanced.get_global_rect()) and
		app.color_advanced.visible,
		"narrow and short dock scrolls to embedded native picker")
	var picker_horizontal: ScrollContainer = app.color_picker_scroll
	check(picker_horizontal.get_h_scroll_bar().max_value > picker_horizontal.get_h_scroll_bar().page,
		"narrow native picker exposes horizontal scroll for offscreen controls")
	picker_horizontal.scroll_horizontal = 10000
	await frames(5)
	check(picker_horizontal.scroll_horizontal > 0, "right-hand native picker controls are horizontally reachable")
	picker_horizontal.scroll_horizontal = 0
	app.color_advanced.grab_focus()
	await frames(3)
	check(root.gui_get_focus_owner() == app.color_advanced,
		"inline native picker accepts keyboard focus")
	await capture("narrow-short")
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		root.size = Vector2i(1280, 720)
		await frames(14)
		app.inspector.ensure_control_visible(app.color_advanced)
		await frames(8)
		check(app.color_advanced.is_visible_in_tree() and
			app.inspector.get_global_rect().intersects(app.color_picker_scroll.get_global_rect()) and
			app.canvas.size.x > 125,
			"native picker and canvas reachable at %s UI scale" % scale)
		app.inspector.scroll_vertical = 0
		await frames(5)
		check(app.foreground_button.is_visible_in_tree() and
			app.inspector.get_global_rect().intersects(app.foreground_button.get_global_rect()),
			"FG/BG top bar remains reachable at %s UI scale" % scale)
		await capture("scale-%d" % roundi(scale * 100))
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	await frames(10)
	# Flyout uses the identical view and its own ScrollContainer.
	app._toggle_dock()
	await frames(5)
	check(app.dock_layout.container_info("right")["minimized"], "dock minimizes")
	await click(app.dock_rail_buttons["colors"])
	await frames(6)
	var flyout_scroll: ScrollContainer = app.dock_flyout_body.get_parent() as ScrollContainer
	check(app.dock_flyout.visible and app.color_picker_scroll.get_parent() == app.dock_views["colors"] and
		flyout_scroll != null, "picker remains embedded in real flyout panel view")
	flyout_scroll.ensure_control_visible(app.color_advanced)
	await frames(5)
	check(flyout_scroll.get_global_rect().intersects(app.color_advanced.get_global_rect()),
		"flyout scroll can reach native picker")
	flyout_scroll.scroll_vertical = 220
	await frames(6)
	var flyout_before: int = flyout_scroll.scroll_vertical
	await wheel(flyout_scroll.get_global_rect().position + Vector2(flyout_scroll.size.x - 5, flyout_scroll.size.y * 0.5), MOUSE_BUTTON_WHEEL_UP)
	check(flyout_before > 0 and flyout_scroll.scroll_vertical < flyout_before,
		"native wheel scroll works in minimized icon-rail flyout")
	await capture("flyout")
	app._toggle_dock()
	await frames(7)
	var floated: String = app.float_group("colors")
	await frames(7)
	check(not floated.is_empty() and app.floating_hosts.has(floated),
		"Colors can float without copying view")
	var host: DrawingFloatingHost = app.floating_hosts[floated]
	host.set_host_rect(Rect2(Vector2(250, 140), Vector2(260, 325)))
	await frames(12)
	check(app.color_advanced.is_visible_in_tree() and app.color_picker_scroll.get_parent() == app.dock_views["colors"],
		"picker stays inline after floating and resize")
	host._scroll.ensure_control_visible(app.color_advanced)
	await frames(8)
	check(host._scroll.get_global_rect().intersects(app.color_advanced.get_global_rect()),
		"short floating host scroll reaches native picker")
	host._scroll.scroll_vertical = 220
	await frames(6)
	var host_before: int = host._scroll.scroll_vertical
	await wheel(host._scroll.get_global_rect().position + Vector2(host._scroll.size.x - 5, host._scroll.size.y * 0.5), MOUSE_BUTTON_WHEEL_UP)
	check(host_before > 0 and host._scroll.scroll_vertical < host_before,
		"floating-host wheel scroll reaches native picker controls")
	await capture("floating")
	check(doc.revision == revision and doc.is_dirty() == dirty and doc.history_length() == history,
		"all color, scroll and dock interaction is non-dirty and non-undoable")
	app.queue_free()
	await frames(4)
	print("T226_NATIVE: %d checks; %d failed" % [checks, failed])
	print("T226_NATIVE_PASSED" if failed == 0 else "T226_NATIVE_FAILED")
	quit(0 if failed == 0 else 1)
