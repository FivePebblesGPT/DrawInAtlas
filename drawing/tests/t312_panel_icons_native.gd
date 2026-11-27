extends "t304_selection_menu_native.gd"
## Actual panel renders and functional interaction across shared dock states.

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T312_FAILED: " + description)

func effective_filter(item: CanvasItem) -> int:
	var current: Node = item
	while current is CanvasItem:
		var canvas_item: CanvasItem = current as CanvasItem
		if canvas_item.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return canvas_item.texture_filter
		current = current.get_parent()
	return item.get_viewport().canvas_item_default_texture_filter + 1

func capture(name: String, button: Button, window: Window) -> void:
	print("T312_FILTER %s: %d" % [name, effective_filter(button)])
	var folder: String = OS.get_environment("T312_SCREENSHOTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		await RenderingServer.frame_post_draw
		var result: Error = window.get_texture().get_image().save_png(folder.path_join(name + ".png"))
		if result != OK:
			printerr("OPTIONAL_VISUAL_CAPTURE_FAILED: " + str(result))

func exercise(app: Control, window: Window, prefix: String) -> void:
	var layout: DrawingDockLayout = app.dock_layout
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	var layers_view: Control = app.dock_views["layers"]
	var art_filter: int = effective_filter(app.canvas)
	var picker_filter: int = effective_filter(app.dock_views["colors"])
	layout.set_panel_visible("brushes", false)
	check(layout.merge_groups("layers", "colors", 1), "group Colors and Layers")
	var extra: Label = Label.new()
	extra.text = "Fallback icon fixture"
	check(app.register_workspace_panel("sample_panel", extra), "register fallback panel")
	check(layout.merge_groups("sample_panel", "colors", 2), "group fallback icon")
	app._render_dock()
	await frames(10)
	for scale: float in [1.0, 1.5]:
		window.content_scale_factor = scale
		await frames(12)
		var suffix: String = "%s-%d" % [prefix, roundi(scale * 100.0)]
		var edge: Button = app.dock_tab_buttons["colors"]
		await capture("expanded-" + suffix, edge, window)
		await click(window, edge.get_global_rect().get_center())
		check(bool(layout.group_info("colors")["collapsed"]), "expanded icon collapses group")
		await click(window, (app.dock_tab_buttons["colors"] as Button).get_global_rect().get_center())
		check(not bool(layout.group_info("colors")["collapsed"]), "expanded icon reopens group")
		app.dock_toggle.grab_focus()
		await key(window, KEY_SPACE)
		check(bool(layout.container_info("right")["minimized"]), "keyboard minimizes dock")
		if not bool(layout.container_info("right")["minimized"]):
			return
		var rail: Button = app.dock_rail_buttons["colors"]
		await capture("rail-" + suffix, rail, window)
		await click(window, rail.get_global_rect().get_center())
		check(app.dock_flyout.visible, "rail opens flyout")
		var flyout: Button = app.dock_flyout_tabs.get_node("Tab_colors") as Button
		await capture("flyout-" + suffix, flyout, window)
		var layers: Button = app.dock_flyout_tabs.get_node("Tab_layers") as Button
		layers.grab_focus()
		await key(window, KEY_SPACE)
		check(layout.group_info("colors")["active"] == "layers" and app.dock_flyout.visible, "keyboard activates flyout Layers")
		check(layers_view.get_parent() == app.dock_flyout_body, "flyout moves original Layers view")
		app.dock_toggle.grab_focus()
		await key(window, KEY_SPACE)
		check(not bool(layout.container_info("right")["minimized"]) and not app.dock_flyout.visible, "keyboard returns expanded dock")
		layout.select_panel("colors")
		app._render_dock()
		var host_id: String = app.float_group("colors")
		check(not host_id.is_empty(), "float grouped panel")
		if host_id.is_empty():
			return
		await frames(12)
		var host: DrawingFloatingHost = app.floating_hosts[host_id]
		await capture("floating-" + suffix, host.tab_buttons["colors"], window)
		await click(window, (host.tab_buttons["layers"] as Button).get_global_rect().get_center())
		check(layout.group_info("colors")["active"] == "layers" and host.visible, "pointer selects floating Layers without dismissing host")
		check(host.is_ancestor_of(layers_view), "floating host owns original Layers view")
		var fallback: Button = host.tab_buttons["sample_panel"]
		fallback.grab_focus()
		await key(window, KEY_SPACE)
		check(layout.group_info("colors")["active"] == "sample_panel" and host.is_ancestor_of(extra), "fallback icon keyboard activation")
		check(layout.move_group("colors", "right", 0), "return group to dock for next scale")
		layout.select_panel("colors")
		app._render_dock()
		await frames(10)
		check(layout.owner_of("colors") == "right" and app.dock_tab_buttons.has("colors"), "redock restores icon and ownership")
	check(effective_filter(app.canvas) == art_filter and art_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "artwork filter remains nearest")
	check(effective_filter(app.dock_views["colors"]) == picker_filter, "expanded panel content filter unchanged")
	check(doc.revision == revision and doc.history_length() == history and doc.is_dirty() == dirty, "panel transitions preserve artwork and history")

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1280, 840)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(15)
	await exercise(app, root, "standalone")
	print("T312_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T312_NATIVE_PASSED")
	quit(1 if failures else 0)
