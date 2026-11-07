extends SceneTree
## T-081 native floating host witness: ownership, pointer, keyboard, bounds and recovery.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T081_NATIVE_FAILED: " + label)

func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame

func mouse(at: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = pressed
	root.push_input(event, true)

func motion(at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = Vector2(18, 10)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	mouse(at, true)
	await frames(3)
	mouse(at, false)
	await frames(6)

func drag_from(control: Control, at: Vector2) -> void:
	var start: Vector2 = control.get_global_rect().get_center()
	mouse(start, true)
	await frames(3)
	motion(start.lerp(at, 0.55))
	await frames(3)
	motion(at)
	await frames(4)

func drag_point(start: Vector2, at: Vector2) -> void:
	mouse(start, true)
	await frames(3)
	motion(start.lerp(at, 0.55))
	await frames(3)
	motion(at)
	await frames(4)

func drag_end(at: Vector2) -> void:
	mouse(at, false)
	await frames(7)

func press(key: Key, ctrl: bool = false, alt: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event, true)
	await frames(3)
	event.pressed = false
	root.push_input(event, true)
	await frames(3)

func fixture(app: Control, name: String) -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = name.capitalize()
	var caption: Label = Label.new()
	caption.text = name.capitalize() + " unique view"
	panel.add_child(caption)
	app.dock_stash.add_child(panel)
	app.dock_views[name] = panel
	check(app.dock_layout.register_panel(name) and app.dock_layout.attach_panel(name, "right", name), "register " + name)

func screenshot(label: String) -> void:
	var directory: String = OS.get_environment("T081_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "native screenshot " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires native display")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	root.add_child(app)
	await frames(14)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	fixture(app, "swatches")
	fixture(app, "gradients")
	check(layout.merge_groups("swatches", "colors", 1), "merge Colors/Swatches")
	check(layout.merge_groups("gradients", "colors", 2), "merge Colors/Swatches/Gradients")
	app._render_dock()
	await frames(6)
	check(layout.rail_icons("right").size() == 5, "initial dock has five panel icons")
	var original_canvas_width: float = app.canvas.size.x
	var original_dock_floor: float = app.inspector.get_combined_minimum_size().x
	check(original_dock_floor >= 190.0, "expanded dock reserves compact panel width")
	var first_id: String = app.float_group("colors")
	await frames(9)
	check(not first_id.is_empty(), "float group programmatically")
	check(layout.container_info(first_id)["kind"] == DrawingDockLayout.FLOATING, "floating model container kind")
	check(layout.owner_of("colors") == first_id and layout.owner_of("swatches") == first_id and layout.owner_of("gradients") == first_id,
		"all source group members transferred atomically")
	check(layout.rail_icons("right").size() == 2 and layout.rail_icons("right")[0]["panel"] == "layers" and layout.rail_icons("right")[1]["panel"] == "history", "floated panel icons absent from dock only")
	check(app.dock_group_frames.size() == 2 and not app.dock_group_frames.has("colors"), "expanded dock no longer renders floated group")
	var host: DrawingFloatingHost = app.floating_hosts[first_id]
	check(host is PanelContainer and host.get_class() != "Window" and host.get_parent() == app,
		"host is one in-app Control, never native OS Window")
	check(host.tab_buttons.size() == 3 and host.group_frames.size() == 1, "three tabs share one floating group")
	check(app.dock_views["colors"].get_parent() == host.group_frames["colors"] and app.dock_views["swatches"].get_parent() == app.dock_stash,
		"only active real view is rendered")
	check(is_equal_approx(original_canvas_width, app.canvas.size.x), "floating overlay leaves split canvas width unchanged")
	check(is_equal_approx(original_dock_floor, app.inspector.get_combined_minimum_size().x),
		"removing Colors cannot shrink expanded dock minimum width")
	await click(host.tab_buttons["swatches"] as Button)
	check(layout.group_info("colors")["active"] == "swatches", "native tab click selects alternative panel")
	check(app.dock_views["swatches"].get_parent() == host.group_frames["colors"] and app.dock_views["colors"].get_parent() == app.dock_stash,
		"same view instance reparents on selection")
	var tab: Button = host.tab_buttons["gradients"]
	var target: Vector2 = (host.tab_buttons["colors"] as Button).get_global_rect().position + Vector2(3, 18)
	var snapshot: Dictionary = layout.snapshot()
	await drag_from(tab, target)
	check(host.get_node("FloatingInsertionHint").visible and layout.snapshot() == snapshot, "valid floating tab preview is nonmutating")
	await screenshot("tab-insertion")
	await drag_end(target)
	check(layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches"], "pointer reordered floating tabs")
	check(host.tab_buttons["gradients"].get_index() == 0, "tab visual order follows model after commit")
	# Esc must restore exact snapshot including selection and ownership.
	snapshot = layout.snapshot()
	tab = host.tab_buttons["swatches"]
	target = (host.tab_buttons["gradients"] as Button).get_global_rect().position + Vector2(4, 18)
	await drag_from(tab, target)
	check(host.get_node("FloatingInsertionHint").visible, "Esc setup has preview")
	await press(KEY_ESCAPE)
	await drag_end(target)
	check(layout.snapshot() == snapshot and not host.get_node("FloatingInsertionHint").visible,
		"Esc cancels floating tab move exactly")
	var initial_position: Vector2 = host.position
	var grip: Button = host.get_node("FloatingColumn/FloatingTitleBar/MoveHandle") as Button
	target = grip.get_global_rect().get_center() + Vector2(128, 70)
	await drag_from(grip, target)
	await drag_end(target)
	check(host.position.distance_to(initial_position) > 70.0, "native pointer moves floating host")
	check(host.get_global_rect().end.x <= app.get_global_rect().end.x and host.position.x >= 0, "moved host stays in client")
	var initial_size: Vector2 = host.size
	var corner_point: Vector2 = host.get_global_rect().end - Vector2(3, 3)
	target = corner_point + Vector2(78, 56)
	await drag_point(corner_point, target)
	await drag_end(target)
	check(host.size.x > initial_size.x and host.size.y > initial_size.y, "native pointer resizes floating host")
	check(host.get_global_rect().end.x <= app.get_global_rect().end.x and host.get_global_rect().end.y <= app.get_global_rect().end.y,
		"resized host remains within viewport")
	var second_id: String = app.float_group("history")
	await frames(8)
	check(not second_id.is_empty() and second_id != first_id, "multiple floating containers have unique IDs")
	var second: DrawingFloatingHost = app.floating_hosts[second_id]
	check(layout.owner_of("history") == second_id and layout.owner_of("layers") == "right",
		"other dock icon remains while second host floats")
	second.set_host_rect(Rect2(host.position + Vector2(host.size.x - 4.0, 35.0), Vector2(250, 210)))
	await frames(6)
	check(second.get_global_rect().intersects(host.get_global_rect()), "two in-app hosts can overlap canvas and each other")
	check(second.get_index() > host.get_index(), "new host starts on top")
	# Raise via a visible title handle that isn't covered by the newer host.
	await click(host.get_node("FloatingColumn/FloatingTitleBar/MoveHandle") as Button)
	check(host.get_index() > second.get_index(), "pointer focuses and raises first floating host")
	await click(second.get_node("FloatingColumn/FloatingTitleBar/MoveHandle") as Button)
	check(second.get_index() > host.get_index(), "pointer focuses and raises other floating host")
	# Explicit merge into an occupied host keeps one group, without nested title bars.
	check(app.move_group_to_floating("layers", first_id), "programmatic group merge into occupied float")
	await frames(6)
	check(host.group_frames.size() == 1 and layout.owner_of("layers") == first_id and layout.rail_icons("right").is_empty(),
		"one group after merge, all source panel icons removed from dock")
	check(layout.group_info("layers").is_empty() and layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches", "layers"],
		"merged tabs preserve stable panel IDs and exact order")
	check(host.get_node_or_null("FloatingColumn/ResizeBar") == null and
		host.get_node_or_null("FloatingColumn/FloatingTitleBar/FloatingTitle") == null,
		"no floating secondary group heading or full-size resize bar")
	# The active tab can be split only by constructing another independent host.
	check(layout.select_panel("swatches"), "select floating tab for separate host")
	app._render_dock()
	await frames(4)
	host._arrange(2, "colors")
	await frames(6)
	var new_host_id: String = layout.owner_of("swatches")
	check(new_host_id != first_id and app.floating_hosts.has(new_host_id),
		"floating tab split creates another host, not another group")
	check(layout.container_info(first_id)["groups"].size() == 1 and
		layout.container_info(new_host_id)["groups"].size() == 1,
		"both floating hosts own one group")
	check(app.dock_drag.begin_panel("swatches") and
		app.dock_drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "colors", "index": 2}) and
		app.dock_drag.commit(), "merge split tab back into original host")
	app._reap_empty_hosts()
	app._render_dock()
	await frames(6)
	check(layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches", "layers"],
		"remerge keeps tab order and source identity")
	# Keyboard uses the same transaction as pointer drag and the arrange menu.
	(host.tab_buttons["swatches"] as Button).grab_focus()
	await frames(4)
	await press(KEY_LEFT, true, true)
	check(layout.group_info("colors")["panels"] == ["gradients", "swatches", "colors", "layers"],
		"focused floating tab Ctrl+Alt+Left reorders")
	(host.tab_buttons["swatches"] as Button).grab_focus()
	await press(KEY_RIGHT, true, true)
	check(layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches", "layers"],
		"focused floating tab Ctrl+Alt+Right restores order")
	# Closing/hiding cannot reattach or destroy any panel, and Window recovers it.
	var before_hide: Dictionary = layout.snapshot()
	await click(host.get_node("FloatingColumn/FloatingTitleBar/HideHost") as Button)
	check(not host.visible and layout.snapshot() == before_hide, "close affordance hides without redocking")
	check(is_equal_approx(original_canvas_width, app.canvas.size.x),
		"hiding the floated overlay cannot resize the canvas")
	check(not (app.dock_views["layers"] as Control).is_visible_in_tree(), "hidden host body not visible")
	app.show_hidden_floating_hosts()
	await frames(6)
	check(host.visible and layout.snapshot() == before_hide and host.tab_buttons.has("swatches"),
		"Window recovery brings back identical panel tabs")
	check(is_equal_approx(original_canvas_width, app.canvas.size.x),
		"showing a hidden floated overlay cannot resize the canvas")
	app.hide_floating_host(first_id)
	app.hide_floating_host(first_id)
	app.show_floating_host(first_id)
	app.show_floating_host(first_id)
	check(host.visible and layout.snapshot() == before_hide, "repeated hide/show idempotent")
	# Strong geometry clamping, even at a short HiDPI viewport.
	root.size = Vector2i(420, 350)
	app.size = Vector2(420, 350)
	await frames(14)
	check(host.get_global_rect().end.x <= app.get_global_rect().end.x + 1.0 and host.get_global_rect().end.y <= app.get_global_rect().end.y + 1.0,
		"existing host clamped when window shrinks")
	host.set_host_rect(Rect2(Vector2(-900, -400), Vector2(4000, 6000)))
	check(host.position.x >= 0.0 and host.position.y >= 0.0 and host.get_global_rect().end.x <= app.get_global_rect().end.x + 1.0,
		"invalid offscreen oversized rectangle clamped")
	check(host.size.x >= 200.0 and host.size.y >= 160.0, "small viewport still has usable host frame")
	host.set_host_rect(Rect2(Vector2(INF, NAN), Vector2(NAN, -INF)))
	check(not is_nan(host.position.x) and not is_nan(host.position.y) and host.size.x > 0 and host.size.y > 0,
		"nonfinite geometry cannot poison layout")
	# Godot's HiDPI canvas stretch changes logical viewport size. Match T-080's
	# 900px native witness so the child workspace has a nonzero client area.
	root.size = Vector2i(900, 630)
	root.content_scale_factor = 1.5
	app.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	app.grow_horizontal = Control.GROW_DIRECTION_END
	app.grow_vertical = Control.GROW_DIRECTION_END
	app.position = Vector2.ZERO
	app.size = Vector2(900, 630)
	await frames(12)
	host.clamp_to_client()
	check(host.position.x >= 0 and host.get_global_rect().end.x <= app.get_global_rect().end.x + 1,
		"1.5x content scale preserves host bounds")
	check((host.get_node("FloatingColumn/FloatingTitleBar/MoveHandle") as Button).focus_mode == Control.FOCUS_ALL and
		(host.get_node("FloatingColumn/FloatingTitleBar/HideHost") as Button).custom_minimum_size.x >= 30.0,
		"HiDPI keyboard focus and grab affordances remain usable")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"dock operations never change Drawing revision or dirty state")
	check(app.dock_views.size() == 5 and layout.snapshot()["panels"].size() == 5,
		"five original Control views and model IDs remain unique")
	print("T081_FLOAT_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T081_FLOAT_NATIVE_PASSED")
	quit(1 if failures else 0)
