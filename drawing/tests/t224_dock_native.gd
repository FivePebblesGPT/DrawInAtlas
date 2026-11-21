extends SceneTree
## T-224: real pointer threshold, icon proximity, distinct hints and rollback.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T224_NATIVE_FAILED: " + description)

func frames(n: int = 6) -> void:
	for _i: int in range(n):
		await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)

func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.relative = Vector2(15, 8)
	root.push_input(event, true)

func drag_from(control: Control, target: Vector2) -> void:
	var start: Vector2 = control.get_global_rect().get_center()
	mouse(start, true)
	await frames(3)
	motion(start.lerp(target, 0.5))
	await frames(3)
	motion(target)
	await frames(5)

func drop(point: Vector2) -> void:
	mouse(point, false)
	await frames(9)

func escape() -> void:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	root.push_input(e, true)
	await frames(3)
	e.pressed = false
	root.push_input(e, true)
	await frames(3)

func screenshot(name: String) -> void:
	var directory: String = OS.get_environment("T224_SCREENSHOTS")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "capture " + name)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	check(layout.set_panel_visible("brushes", false), "hide Brushes for stable icon geometry")
	check(layout.set_group_collapsed("colors", true), "collapse tall inline picker to expose nearby groups")
	app._render_dock()
	await frames()
	var original: Dictionary = layout.snapshot()
	var colors: Button = app.dock_tab_buttons["colors"]
	var layers: Button = app.dock_tab_buttons["layers"]
	var layers_pos: Vector2 = layers.get_global_rect().get_center()
	# Neither a passive hover nor a subthreshold gesture can group icons.
	motion(layers_pos)
	await frames(2)
	check(not app.dock_drag.is_dragging() and layout.snapshot() == original,
		"passive proximity cannot merge")
	var origin: Vector2 = colors.get_global_rect().get_center()
	mouse(origin, true)
	await frames(2)
	motion(origin + Vector2(3, 2))
	await frames(2)
	check(not app.dock_drag.is_dragging(), "7px threshold enforced")
	mouse(origin + Vector2(3, 2), false)
	await frames(8)
	# Active icon clicks may change collapse, so restore the baseline before drag checks.
	if not layout.group_info("colors")["collapsed"]:
		layout.set_group_collapsed("colors", true)
	app._render_dock()
	await frames(7)
	original = layout.snapshot()
	# A real icon drag over another icon previews a group merge without mutation.
	layers_pos = (app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center()
	await drag_from(app.dock_tab_buttons["colors"], layers_pos)
	check(app.dock_drag.is_dragging() and app.dock_drag.source_kind() == DrawingDockDrag.PANEL,
		"only Colors icon is being dragged")
	check(app.dock_drop_hint.visible and app.dock_drop_caption.visible and
		app.dock_drop_caption.text.begins_with("Group panel") and app.dock_merge_outline.visible,
		"green icon-proximity merge preview and outlined target group")
	check(layout.snapshot() == original, "merge hover does not mutate any layout data")
	await screenshot("merge-preview")
	# Merely passing over the body, then releasing, invalidates the prior target.
	var body: Vector2 = (app.dock_group_frames["layers"] as Control).get_global_rect().end - Vector2(16, 18)
	motion(body)
	await frames(5)
	check(not app.dock_drop_hint.visible and not app.dock_merge_outline.visible and
		app.dock_drag.target().is_empty(), "body hover clears the prior merge target")
	await drop(body)
	check(layout.snapshot() == original, "invalid body release is bit-exact rollback")
	# Explicit release on the icon merges the groups, preserving unique ownership.
	layers_pos = (app.dock_tab_buttons["layers"] as Button).get_global_rect().get_center()
	await drag_from(app.dock_tab_buttons["colors"], layers_pos)
	await drop(layers_pos)
	check(layout.group_of("colors") == layout.group_of("layers") and
		layout.group_info("colors").is_empty(), "icon merge removes empty source group")
	check(layout.rail_icons("right").size() == 3 and app.dock_views["colors"] != app.dock_views["layers"],
		"all panel views are unique after merge")
	var group_id: String = layout.group_of("colors")
	var tab: Control = app.dock_tab_buttons["colors"]
	var target: Vector2 = (app.dock_tab_buttons["layers"] as Control).get_global_rect().position + Vector2(3, 18)
	var before_reorder: Dictionary = layout.snapshot()
	await drag_from(tab, target)
	check(app.dock_drop_caption.visible and app.dock_drop_caption.text == "Reorder panel" and
		not app.dock_merge_outline.visible and layout.snapshot() == before_reorder,
		"same-group icon preview is a blue reorder, not a merge")
	await screenshot("reorder-preview")
	await escape()
	mouse(target, false)
	await frames(5)
	check(layout.snapshot() == before_reorder and not app.dock_drop_caption.visible,
		"Escape preserves membership, active tab, collapse and layout exactly")
	# A gap is an amber singleton split, not a merge.
	var groups: Array = layout.container_info("right")["groups"]
	var group_index: int = groups.find_custom(func(g: Dictionary) -> bool: return g["id"] == group_id)
	var frame: Control = app.dock_group_frames[group_id]
	var gap: Vector2 = Vector2(frame.get_global_rect().get_center().x, frame.get_global_rect().position.y + 2)
	await drag_from(app.dock_tab_buttons["colors"], gap)
	check(app.dock_drop_hint.visible and app.dock_drop_caption.text == "Split panel into new group" and
		app.dock_drag.target().get("kind") == DrawingDockDrag.GROUP_SLOT and not app.dock_merge_outline.visible,
		"group gap previews separate singleton insertion")
	await screenshot("split-preview")
	await drop(gap)
	check(layout.group_of("colors") != layout.group_of("layers") and
		layout.group_info(layout.group_of("colors"))["panels"] == ["colors"],
		"gap drop creates exactly one new singleton group")
	check(layout.container_info("right")["groups"].size() == groups.size() + 1,
		"split grows dock group count by one")
	# Keyboard alternative uses the same model transaction, not an alternate layout.
	(app.dock_tab_buttons["colors"] as Button).grab_focus()
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_DOWN
	key.ctrl_pressed = true
	key.alt_pressed = true
	key.pressed = true
	root.push_input(key, true)
	await frames(5)
	key.pressed = false
	root.push_input(key, true)
	await frames(5)
	check(layout.group_of("colors") == layout.group_of("layers"),
		"Ctrl+Alt+Down groups single panel with next group")
	# All panel gestures leave document history untouched.
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"document history and dirty flag unchanged")
	# T-223 marker is the whole-group source: it shows a green group-merge
	# caption, unlike the green single-panel icon merge above.
	var merged_id: String = layout.group_of("colors")
	check(layout.set_group_collapsed(merged_id, true), "collapse tall merged group to expose History")
	app._render_dock()
	await frames(7)
	var marker_target: Vector2 = (app.dock_tab_buttons["history"] as Control).get_global_rect().get_center()
	var before_marker: Dictionary = layout.snapshot()
	await drag_from(app.dock_group_handles[merged_id], marker_target)
	check(app.dock_drag.source_kind() == DrawingDockDrag.GROUP and
		app.dock_drop_caption.text.begins_with("Merge whole group") and app.dock_merge_outline.visible,
		"triangle drag previews whole-group merge, never a single panel")
	check(layout.snapshot() == before_marker, "whole-group hover leaves layout unchanged")
	await escape()
	mouse(marker_target, false)
	await frames(7)
	check(layout.snapshot() == before_marker and not app.dock_merge_outline.visible,
		"whole-group Escape restores all tabs and clears group outline")
	# Save/reopen must persist icon membership and order through the existing
	# versioned layout file, without leaking document state into preferences.
	var preferences_path: String = "user://t224-dock-layout-native.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	app.layout_settings_path = preferences_path
	app.layout_persistence_enabled = true
	var persisted: Dictionary = layout.snapshot()
	check(app._save_workspace_layout(), "save regrouped layout")
	app.queue_free()
	await frames(12)
	app = load("res://main.tscn").instantiate()
	app.layout_settings_path = preferences_path
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	layout = app.dock_layout
	check(app.layout_recovery_status == "loaded" and layout.snapshot() == persisted,
		"restart restores exact icon order, group ownership and active/collapsed bits")
	# Native scale/scroll: hint and real icons fit within view.
	for scale: float in [1.5, 2.0]:
		root.content_scale_factor = scale
		root.size = Vector2i(1200, 760)
		await frames(9)
		check(app.dock_tab_buttons.has("colors") and app.dock_tab_buttons.has("layers"),
			"icons remain addressable at %s UI scale" % scale)
		await screenshot("scale-%d" % roundi(scale * 100.0))
	root.content_scale_factor = 1.0
	root.size = Vector2i(720, 490)
	await frames(8)
	check(app.inspector.size.x >= 190.0 and app.dock_tab_strips.has(layout.group_of("colors")),
		"narrow dock retains scrollable icon strip")
	await screenshot("narrow")
	# Add more panels to force real horizontal overflow and hold an icon drag
	# over the strip's visible right edge; the same transaction must autoscroll.
	for extra: String in ["extra-a", "extra-b", "extra-c", "extra-d", "extra-e", "extra-f"]:
		var view: VBoxContainer = VBoxContainer.new()
		view.name = extra
		view.add_child(Label.new())
		app.dock_stash.add_child(view)
		app.dock_views[extra] = view
		check(layout.register_panel(extra) and layout.attach_panel(extra, "right", extra), "register overflow " + extra)
		check(layout.merge_groups(extra, layout.group_of("colors"), layout.group_info(layout.group_of("colors"))["panels"].size()),
			"group extra icon for horizontal overflow " + extra)
	app._render_dock()
	await frames(9)
	var strip: ScrollContainer = app.dock_tab_strips[layout.group_of("colors")]
	check(strip.get_h_scroll_bar().max_value > strip.get_h_scroll_bar().page, "horizontal tab overflow exists")
	var before_autoscroll: Dictionary = layout.snapshot()
	var strip_end: Vector2 = strip.get_global_rect().end - Vector2(4, 15)
	await drag_from(app.dock_tab_buttons["colors"], strip_end)
	await frames(50)
	check(strip.scroll_horizontal > 0 and app.dock_drag.is_dragging(), "held icon drag auto-scrolls horizontal strip")
	check(layout.snapshot() == before_autoscroll, "horizontal auto-scroll does not mutate membership")
	await escape()
	mouse(strip_end, false)
	await frames(8)
	check(layout.snapshot() == before_autoscroll and not app.dock_drop_hint.visible,
		"overflow Escape restores every group and clears insertion overlays")
	print("T224_DOCK_NATIVE: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
