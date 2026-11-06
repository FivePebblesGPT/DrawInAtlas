extends SceneTree
## T-083: native save/relaunch, compact screen, focus and layout recovery.
const PREFS: String = "user://t083-native-workspace.json"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T083_NATIVE_FAILED: " + label)

func frames(count: int = 6) -> void:
	for _i: int in range(count):
		await process_frame

func open_app() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	var swatches: VBoxContainer = VBoxContainer.new()
	swatches.name = "Swatches"
	swatches.add_child(Label.new())
	var gradients: VBoxContainer = VBoxContainer.new()
	gradients.name = "Gradients"
	gradients.add_child(Label.new())
	app.initial_extra_panels = {"swatches": swatches, "gradients": gradients}
	root.add_child(app)
	return app

func stop_app(app: Control) -> void:
	root.remove_child(app)
	app.queue_free()
	await frames(7)

func screenshot(label: String) -> void:
	var folder: String = OS.get_environment("T083_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"screenshot " + label)

func bounds_ok(host: DrawingFloatingHost, client: Vector2) -> bool:
	return host.position.x >= 0.0 and host.position.y >= 0.0 and host.position.x + host.size.x <= client.x + 1.0 and host.position.y + host.size.y <= client.y + 1.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("T083 native witness requires X11 display")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1240, 800)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = open_app()
	await frames(18)
	var initial_revision: int = app.current_document().revision
	var initial_dirty: bool = app.current_document().is_dirty()
	check(app.layout_recovery_status == "defaults", "missing settings migrate T-063 defaults")
	check(app.dock_layout.rail_icons("right").map(func(e: Dictionary) -> String: return e["panel"]) ==
		["colors", "layers", "history", "swatches", "gradients"], "default 3 built-in panels and two dynamically registered peers")
	check(app.dock_views.size() == 5, "one unique view per registered panel")
	check(app.dock_layout.merge_groups("layers", "colors", 1), "group colors/layers")
	check(app.dock_layout.merge_groups("gradients", "swatches", 1), "group swatches/gradients")
	check(app.dock_layout.select_panel("layers"), "select nested panel")
	check(app.dock_layout.set_group_collapsed("history", true), "collapse only history group")
	app._render_dock()
	await frames()
	var host_id: String = app.float_group("colors")
	check(host_id == "float-1", "float one multi-tab group")
	await frames(6)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	check(host.get_class() != "Window" and host is PanelContainer, "only in-app Control, no OS window")
	host.set_host_rect(Rect2(Vector2(143, 95), Vector2(352, 310)))
	check(app.dock_layout.move_panel("layers", "colors", 0), "reorder floating tabs before save")
	check(app.dock_layout.group_info("colors")["panels"] == ["layers", "colors"], "reordered group retains both tabs")
	check(app.dock_layout.group_info("colors")["active"] == "layers", "active floating tab preserved")
	app._render_dock()
	app._toggle_dock()
	await frames(10)
	check(app.dock_layout.container_info("right")["minimized"], "dock minimized before save")
	check(app.dock_layout.rail_icons("right").map(func(e: Dictionary) -> String: return e["panel"]) == ["history", "swatches", "gradients"], "only dock-owned icons remain")
	check(app.dock_layout.rail_icons("right")[1]["separator_before"] and not app.dock_layout.rail_icons("right")[2]["separator_before"], "group boundaries persist as separators")
	check(app.dock_layout.activate_from_rail("right", "gradients"), "open common Swatches flyout from rail")
	app._render_dock()
	await frames(7)
	check(app.dock_flyout.visible and app.dock_layout.container_info("right")["flyout_group"] == "swatches", "rail flyout is shared, not native")
	check(app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty, "panel actions never change drawing revision or dirty state")
	var before: Dictionary = app.dock_layout.snapshot()
	var host_pos: Vector2 = host.position
	var host_size: Vector2 = host.size
	check(app._save_workspace_layout(), "save complete mixed workspace to disk")
	check(FileAccess.file_exists(PREFS), "settings file exists")
	await screenshot("t083-before-relaunch")
	await stop_app(app)
	app = open_app()
	await frames(25)
	check(app.layout_recovery_status == "loaded", "settings reloaded without repair")
	check(app.dock_layout.snapshot() == before, "all panel/group ownership, group order, active, collapsed, minimized and flyout states exact")
	check(app.floating_hosts.size() == 1, "one floating host reconstructed from disk")
	host = app.floating_hosts[host_id]
	check(host.visible and host.get_class() != "Window", "visible floating Control restored")
	check(host.position.distance_to(host_pos) <= 2.0 and host.size.distance_to(host_size) <= 2.0, "host frame roundtrip within native pixels")
	check(host.group_frames.has("colors") and host.tab_buttons.has("layers") and host.tab_buttons.has("colors"), "original two tab controls restored in one host")
	check(app.dock_flyout.visible and app.dock_flyout_tabs.get_child_count() == 2, "shared flyout reopens with two member tabs")
	check(app.dock_layout.group_info("history")["collapsed"], "independent collapsed group restored")
	check(app.current_document() != null and app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty, "fresh document unaffected by workspace preference")
	await screenshot("t083-after-relaunch")
	# Hide/reopen survives disk. No group ownership changes on hide.
	app.hide_floating_host(host_id)
	check(not host.visible and app.dock_layout.owner_of("layers") == host_id, "hide preserves floating ownership")
	# No explicit save: clean shutdown must commit the hidden state.
	await stop_app(app)
	app = open_app()
	await frames(18)
	host = app.floating_hosts[host_id]
	check(not host.visible and app.dock_layout.owner_of("layers") == host_id, "hidden host restored with unstranded tabs")
	app.show_hidden_floating_hosts()
	check(host.visible, "Window menu recovery reveals hidden host")
	await frames(5)
	var autosaved: Dictionary = DrawingDockPersistence.read_file(PREFS)
	check(not autosaved.is_empty() and autosaved["hosts"][0]["visible"], "host visibility auto-flushes on change")
	# Two independent overlapping Control hosts preserve visual child/z-order.
	var second_id: String = app.float_group("history")
	await frames(9)
	check(second_id == "float-2" and app.floating_hosts.size() == 2, "second host uses collision-safe restored serial")
	var second: DrawingFloatingHost = app.floating_hosts[second_id]
	second.set_host_rect(Rect2(Vector2(220, 120), Vector2(290, 280)))
	host.raise_host()
	check(host.get_index() > second.get_index(), "raise first host above second")
	check(app._save_workspace_layout(), "save two overlapping hosts with z-order")
	await stop_app(app)
	app = open_app()
	await frames(18)
	host = app.floating_hosts[host_id]
	second = app.floating_hosts[second_id]
	check(host.get_index() > second.get_index(), "frontmost host ordering survives relaunch")
	check(second.position.distance_to(Vector2(220, 120)) <= 2.0, "second host geometry survives relaunch")
	check(app.dock_layout.move_group("history", "right", 0), "redock second host without changing first")
	app._reap_empty_hosts()
	app._render_dock()
	await frames()
	check(app.floating_hosts.size() == 1 and app.floating_hosts.has(host_id), "only empty second host is cleaned up")
	# Native viewport change and non-finite/offscreen protection.
	root.size = Vector2i(420, 610)
	await frames(12)
	host.clamp_to_client()
	check(bounds_ok(host, app.size), "420px viewport never strands host")
	check(app.dock_rail_buttons.size() == 3 and app.dock_rail_buttons.has("gradients"), "narrow rail still has all dock-owned icons")
	check(app.dock_flyout.get_class() != "Window", "narrow flyout still in-app")
	root.size = Vector2i(1240, 800)
	root.content_scale_factor = 1.5
	await frames(14)
	host.clamp_to_client()
	check(bounds_ok(host, app.size), "1.5x scaling keeps floating controls on screen")
	root.content_scale_factor = 1.0
	await frames(8)
	# Redock at exact chosen group position with preserved member order.
	check(app.dock_layout.move_group("colors", "right", 1), "redock floating group at between-group insertion index")
	app._reap_empty_hosts()
	app._render_dock()
	await frames()
	check(app.floating_hosts.is_empty(), "empty floating host retired")
	var icons: Array[Dictionary] = app.dock_layout.rail_icons("right")
	check(icons.map(func(e: Dictionary) -> String: return e["panel"]) ==
		["history", "layers", "colors", "swatches", "gradients"], "exact insertion order survives redock")
	check(icons[1]["separator_before"] and not icons[2]["separator_before"] and icons[3]["separator_before"], "redocked separators reflect groups")
	check(app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty, "layout/recovery leaves document unchanged")
	# Reset returns deterministic T-063 order without losing the open Drawing tab.
	app.reset_workspace_layout()
	await frames(7)
	check(not app.dock_layout.container_info("right")["minimized"] and app.floating_hosts.is_empty(), "reset expands dock and removes float hosts")
	check(app.dock_layout.rail_icons("right").map(func(e: Dictionary) -> String: return e["panel"]) ==
		["colors", "layers", "history", "swatches", "gradients"], "reset restores default registered panel order")
	check(app.current_document() != null and app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty, "reset preserves drawing document state")
	# Rely on _exit_tree rather than explicit save for reset durability.
	await stop_app(app)
	app = open_app()
	await frames(18)
	check(app.layout_recovery_status == "loaded" and app.floating_hosts.is_empty(), "reset survives relaunch")
	check(app.dock_layout.group_of("layers") == "layers", "default singleton T-063 grouping restored")
	# Malformed settings cannot prevent entering the editor.
	app.layout_persistence_enabled = false
	await stop_app(app)
	var invalid: FileAccess = FileAccess.open(PREFS, FileAccess.WRITE)
	invalid.store_string("{\"broken\":")
	invalid.close()
	app = open_app()
	await frames(16)
	if app.layout_recovery_status != "invalid":
		print("T083 invalid diagnostics status=", app.layout_recovery_status, " file=", DrawingDockPersistence.read_file(PREFS))
	check(app.layout_recovery_status == "invalid", "malformed layout detected without crash")
	check(app.dock_layout.owner_of("colors") == "right" and app.floating_hosts.is_empty(), "corrupt snapshot falls back to safe defaults")
	check(app.current_document() != null and app.current_document().revision == initial_revision and app.current_document().is_dirty() == initial_dirty, "corrupt preference does not modify Drawing")
	# Display-change recovery from an extreme saved frame.
	var extreme: Dictionary = DrawingDockPersistence.capture(app.dock_layout, {}, 300, 0, Vector2(1920, 1080))
	check(app.dock_layout.create_container("float-23", DrawingDockLayout.FLOATING), "create fixture floating container")
	check(app.dock_layout.move_group("layers", "float-23", 0), "float a known group fixture")
	extreme["layout"] = app.dock_layout.snapshot()
	extreme["hosts"] = [{"id": "float-23", "visible": true,
		"rect": [1890.0, 950.0, 480.0, 500.0], "client": [1920.0, 1080.0]}]
	check(DrawingDockPersistence.save_file(PREFS, extreme), "save offscreen high-resolution fixture")
	app.layout_persistence_enabled = false
	await stop_app(app)
	root.size = Vector2i(420, 610)
	app = open_app()
	await frames(18)
	check(app.layout_recovery_status == "loaded" and app.floating_hosts.size() == 1, "offscreen fixture reconstructed")
	host = app.floating_hosts["float-23"]
	check(bounds_ok(host, app.size), "offscreen saved frame clamped to new viewport")
	check(app.dock_layout.owner_of("layers") == "float-23", "viewport repair does not rehome a valid panel")
	app.layout_persistence_enabled = false
	await stop_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("T083_NATIVE: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("T083_NATIVE_PASSED")
	quit(0 if failures == 0 else 1)
