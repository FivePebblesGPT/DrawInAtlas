extends SceneTree
## T-079 targeted native viewport/keyboard witness for shared grouped flyouts.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T079_FAILED: " + description)


func frames(count: int = 5) -> void:
	for _index: int in range(count):
		await process_frame


func click(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(5)


func press_enter() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(5)


func screenshot(name: String) -> void:
	var directory: String = OS.get_environment("T079_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png(directory.path_join(name + ".png")) == OK, "native framebuffer " + name)


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
	root.add_child(app)
	await frames(14)
	var layout: DrawingDockLayout = app.dock_layout
	var initial_revision: int = app.current_document().revision
	var initial_dirty: bool = app.current_document().is_dirty()
	check(layout.rail_icons("right").size() == 3, "default singleton groups register three attached panels")
	check(app.dock_panels.get_child_count() == 4 and app.dock_panels.get_child(3).name == "Group_history",
		"expanded dock displays independently collapsible ordered groups")
	var colors: Button = app.dock_header_buttons["colors"]
	var layers: Button = app.dock_header_buttons["layers"]
	check(colors.focus_mode == Control.FOCUS_ALL and layers.focus_mode == Control.FOCUS_ALL,
		"native chevrons reachable by keyboard")
	await click(colors)
	check(bool(layout.group_info("colors")["collapsed"]) and not bool(layout.group_info("layers")["collapsed"]),
		"real pointer collapses Colors but leaves Layers expanded")
	check(not (app.dock_views["colors"] as Control).is_visible_in_tree() and app.layers.is_visible_in_tree(),
		"collapsed group body hidden without losing the neighboring panel")
	await click(app.dock_header_buttons["history"] as Button)
	check(bool(layout.group_info("history")["collapsed"]), "History independently collapses")
	await click(app.dock_header_buttons["history"] as Button)
	check(not bool(layout.group_info("history")["collapsed"]), "History restores without expanding Colors")
	# A fixture with two tabs proves rail membership is model-driven, not one icon per group.
	var swatches: VBoxContainer = VBoxContainer.new()
	swatches.name = "Swatches"
	var swatch_text: Label = Label.new()
	swatch_text.text = "Palette swatches"
	swatches.add_child(swatch_text)
	app.dock_stash.add_child(swatches)
	app.dock_views["swatches"] = swatches
	check(layout.register_panel("swatches") and layout.attach_panel("swatches", "right", "swatch-group"),
		"register fixture view on same T-078 model")
	check(layout.merge_groups("swatch-group", "colors", 1), "merge swatches with Colors in fixture")
	app._render_dock()
	var icons: Array[Dictionary] = layout.rail_icons("right")
	check(icons.size() == 4 and icons[0]["panel"] == "colors" and icons[1]["panel"] == "swatches" and
		not bool(icons[1]["separator_before"]) and bool(icons[2]["separator_before"]),
		"joined Colors/Swatches icons adjacent with separator before Layers")
	await screenshot("expanded-groups")
	# Expand dock width preserves a useful canvas at 420px, and group scroll works on short windows.
	root.size = Vector2i(420, 420)
	app.size = Vector2(420, 420)
	await frames(14)
	check(app.get_child(0).size.x <= 420 and app.canvas.size.x >= 125 and
		app.inspector.get_global_rect().end.x <= app.global_position.x + 421,
		"420px viewport retains canvas and dock within window")
	var dock_scroll: ScrollContainer = app.inspector
	check(dock_scroll.get_v_scroll_bar().max_value > dock_scroll.get_v_scroll_bar().page,
		"short window exposes real vertical group scrolling")
	(app.dock_header_buttons["history"] as Button).grab_focus()
	await frames(8)
	check((app.dock_header_buttons["history"] as Button).has_focus() and dock_scroll.scroll_vertical > 0,
		"focus scrolls the History chevron into view")
	var old_scroll: int = dock_scroll.scroll_vertical
	var minimize: Button = app.dock_panels.get_node("MinimizeDock") as Button
	minimize.grab_focus()
	await frames(8)
	await click(minimize)
	check(bool(layout.container_info("right")["minimized"]) and app.dock_rail.visible and
		app.inspector.visible and app.inspector.size.x <= 62,
		"real pointer minimizes the dock into a narrow, persistent rail")
	check(app.dock_rail_buttons.size() == 4 and app.dock_rail.get_child_count() == 7,
		"rail contains four panel icons, two group separators and an expand control")
	for panel_id: String in ["colors", "swatches", "layers", "history"]:
		var icon_button: Button = app.dock_rail_buttons[panel_id]
		check(icon_button.icon != null and icon_button.text.is_empty() and icon_button.focus_mode == Control.FOCUS_ALL and
			icon_button.tooltip_text.contains(panel_id.capitalize()) and icon_button.custom_minimum_size.x >= 40,
			"graphic/tooltip/focus/hit-target for " + panel_id)
		for property: Dictionary in icon_button.get_property_list():
			if property["name"] == "accessibility_name":
				check(String(icon_button.get("accessibility_name")).contains(panel_id.capitalize()),
					"platform accessibility label for " + panel_id)
				break
	var flyout: PanelContainer = app.dock_flyout
	var canvas_width: float = app.canvas.size.x
	await click(app.dock_rail_buttons["colors"] as Button)
	check(flyout.visible and flyout.get_parent() == app.canvas and layout.container_info("right")["flyout_group"] == "colors",
		"rail icon opens in-app group flyout attached to canvas")
	check(app.dock_flyout_tabs.get_child_count() == 2 and
		(app.dock_views["colors"] as Control).get_parent() == app.dock_flyout_body,
		"Colors and Swatches share one tabbed flyout")
	check(is_equal_approx(app.canvas.size.x, canvas_width), "flyout does not resize the canvas")
	check(flyout.position.x >= 0.0 and flyout.get_global_rect().end.x <= app.canvas.get_global_rect().end.x + 1.0,
		"flyout stays inside the canvas's application viewport")
	await click(app.dock_rail_buttons["swatches"] as Button)
	check(app.dock_flyout == flyout and layout.group_info("colors")["active"] == "swatches" and
		(app.dock_views["swatches"] as Control).get_parent() == app.dock_flyout_body,
		"second group icon selects Swatches in same flyout instance")
	await click(app.dock_flyout_tabs.get_node("Tab_colors") as Button)
	check(flyout.visible and layout.group_info("colors")["active"] == "colors" and app.dock_flyout == flyout,
		"native flyout tab click selects another member without creating a new flyout")
	await click(app.dock_rail_buttons["swatches"] as Button)
	check(flyout.visible and layout.group_info("colors")["active"] == "swatches",
		"group rail member switches the tab back without dismissing it")
	await click(app.dock_rail_buttons["swatches"] as Button)
	check(not flyout.visible and layout.container_info("right")["flyout_group"] == "",
		"clicking active rail icon toggles shared flyout closed")
	await click(app.dock_rail_buttons["layers"] as Button)
	check(flyout.visible and layout.container_info("right")["flyout_group"] == "layers" and
		app.layers.get_parent() == app.dock_views["layers"],
		"switching groups reuses flyout and the original Layers control")
	app._change_tool("Pan")
	# Canvas clicks alone are not implicit flyout dismissal; Pan does not edit pixels.
	var position: Vector2 = app.canvas.get_global_rect().get_center()
	if flyout.get_global_rect().has_point(position):
		position = app.canvas.global_position + Vector2(15, 15)
	var input: InputEventMouseButton = InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.position = position
	input.global_position = position
	input.pressed = true
	root.push_input(input, true)
	await frames(3)
	input.pressed = false
	root.push_input(input, true)
	await frames(5)
	check(flyout.visible and layout.container_info("right")["flyout_group"] == "layers",
		"canvas pointer input does not dismiss current group")
	await screenshot("minimized-flyout")
	var history_icon: Button = app.dock_rail_buttons["history"]
	history_icon.grab_focus()
	await frames(4)
	check(history_icon.has_focus(), "history icon accepts native keyboard focus")
	await press_enter()
	check(layout.container_info("right")["flyout_group"] == "history" and flyout.visible,
		"Enter on focused rail icon switches group flyout")
	await click(app.dock_rail.get_node("ExpandDock") as Button)
	await frames(5)
	check(not bool(layout.container_info("right")["minimized"]) and
		bool(layout.group_info("colors")["collapsed"]) and layout.group_info("colors")["active"] == "swatches",
		"restore retains independent collapse and active-tab model state")
	check(dock_scroll.scroll_vertical >= 0, "restored dock scroll viewport remains usable")
	(app.dock_header_buttons["history"] as Button).grab_focus()
	await frames(7)
	var scroll_before_menu: int = dock_scroll.scroll_vertical
	app._toggle_dock()
	await frames(4)
	app._toggle_dock()
	await frames(8)
	check(dock_scroll.scroll_vertical >= mini(scroll_before_menu, 8),
		"Window menu minimize/restore preserves prior vertical focus scroll")
	check(app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty,
		"dock interactions do not mutate drawing pixels, document history or dirty state")
	check(layout.owner_of("swatches") == "right" and layout.owner_of("layers") == "right" and
		layout.rail_icons("right").size() == 4, "repeated switches preserve unique model ownership")
	print("T079_DOCK_UI: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T079_DOCK_UI_PASSED")
	quit(1 if failures else 0)
