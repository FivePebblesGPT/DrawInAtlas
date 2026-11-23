extends SceneTree
## T-225: embedded Drawing uses shared floating icon tabs without hijacking Atlas.
var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T225_ATLAS_FAILED: " + message)


func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires X11")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1100, 740)
	var atlas: Control = Control.new()
	root.add_child(atlas)
	atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	atlas.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var layout: DrawingDockLayout = app.dock_layout
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var color_view: Control = app.dock_views["colors"]
	var host_id: String = app.float_group("colors")
	await frames(8)
	check(not host_id.is_empty(), "Atlas floats Colors panel")
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	check(host.tab_buttons.has("colors") and (host.tab_buttons["colors"] as Button).focus_mode == Control.FOCUS_ALL,
		"embedded Colors tab is keyboard-focusable")
	check(app.move_group_to_floating("layers", host_id), "merge Layers tab in embedded host")
	await frames(8)
	check(host.tab_buttons.has("layers") and (host.tab_buttons["layers"] as Button).focus_mode == Control.FOCUS_ALL,
		"embedded Layers tab is keyboard-focusable")
	check(host.group_frames.size() == 1 and layout.container_info(host_id)["groups"].size() == 1,
		"Atlas floating host retains one group")
	(host.tab_buttons["colors"] as Button).emit_signal("pressed")
	await frames(6)
	check(layout.group_info(layout.group_of("colors"))["active"] == "colors" and host.visible,
		"embedded active icon cannot collapse or hide host")
	check(color_view.get_parent() == host.group_frames[layout.group_of("colors")],
		"original Colors panel view moved, not cloned")
	app.hide_floating_host(host_id)
	await frames(4)
	app.show_hidden_floating_hosts()
	await frames(6)
	check(host.visible and layout.owner_of("colors") == host_id and host.tab_buttons.has("colors"),
		"Atlas hide/reopen preserves Colors tab identity and ownership")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"Atlas document history unchanged")
	check(app.get_parent() == atlas and not app._window_quit_guard_enabled,
		"no external window or Atlas lifecycle takeover")
	print("T225_ATLAS: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
