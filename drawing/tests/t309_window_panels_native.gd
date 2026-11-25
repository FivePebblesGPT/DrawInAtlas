extends "t304_selection_menu_native.gd"
## Individual Window menu recovery with real native popup interaction.
const PREFS: String = "user://t309-native-layout.json"

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T309_NATIVE_FAILED: " + description)

func screenshot(name: String) -> void:
	var folder: String = OS.get_environment("T309_SCREENSHOTS")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		DisplayServer.screen_get_image(0).save_png(folder.path_join(name + ".png"))

func open_app() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_settings_path = PREFS
	app.preferences_persistence_enabled = false
	var future_panel: Label = Label.new()
	future_panel.text = "Swatches fixture"
	app.initial_extra_panels = {"swatches": future_panel}
	root.add_child(app)
	return app

func window_popup(app: Control) -> PopupMenu:
	return app.top_bar._menus[7].get_popup()

func checked(popup: PopupMenu, label: String) -> bool:
	var index: int = find_item(popup, label)
	return index >= 0 and popup.is_item_checkable(index) and popup.is_item_checked(index)

func open_window_menu(app: Control, window: Window) -> PopupMenu:
	var button: MenuButton = app.top_bar._menus[7]
	if not button.visible:
		button = app.top_bar.more_menu
	await click(window, button.get_global_rect().get_center())
	var popup: PopupMenu = button.get_popup()
	check(popup.visible, "native Window/More menu opens by pointer")
	return popup

func invoke_key(popup: PopupMenu, label: String) -> void:
	var item: int = find_item(popup, label)
	check(item >= 0, "menu item reachable: " + label)
	if item >= 0:
		popup.set_focused_item(item)
		await popup_key("Return")
		await frames(6)

func native_pointer(point: Vector2i, click_button: bool) -> void:
	var helper: String = ProjectSettings.globalize_path("res://tests/x11_test_pointer.py")
	if not FileAccess.file_exists(helper):
		helper = ProjectSettings.globalize_path("res://../tests/x11_test_pointer.py")
	var result: int = OS.execute("python3", PackedStringArray([helper, str(point.x), str(point.y), "click" if click_button else "move"]))
	if result != 0:
		check(false, "actual X11 pointer dispatch")
	await frames(2)

func invoke_pointer(popup: PopupMenu, label: String) -> void:
	var item: int = find_item(popup, label)
	check(item >= 0 and popup.visible, "pointer target available: " + label)
	if item < 0 or not popup.visible:
		return
	# Scan the real native popup's hover response, not a hard-coded row height.
	# This protects functional hit testing across theme font changes.
	var p: Vector2i = popup.position + Vector2i(int(popup.size.x * 0.5), 3)
	for y: int in range(3, popup.size.y - 2, 8):
		p.y = popup.position.y + y
		await native_pointer(p, false)
		if popup.get_focused_item() == item:
			await native_pointer(p, true)
			await frames(6)
			return
	check(false, "native mouse could not reach " + label)
	popup.hide()

func run() -> void:
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("DrawingNativeTiles"):
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(40, 40)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: Control = open_app()
	await frames(12)
	var popup: PopupMenu = window_popup(app)
	check(find_item(popup, "Float selected dock group") < 0, "unwanted convenience command removed")
	for label: String in ["Colors", "Layers", "History", "Brushes", "Text Options", "Asset Browser", "Swatches"]:
		var item: int = find_item(popup, label)
		check(item >= 0 and popup.is_item_checkable(item), "individual checked entry: " + label)
	if failures:
		quit(1)
		return
	check(checked(popup, "Colors") and checked(popup, "Layers") and not checked(popup, "Text Options") and not checked(popup, "Asset Browser"), "initial visibility including lazy and hidden panels")
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var history: int = doc.history_length()
	var dirty: bool = doc.is_dirty()
	var layout: DrawingDockLayout = app.dock_layout
	check(layout.merge_groups("layers", "colors", 1), "group two panels")
	app._render_dock()
	var host_id: String = app.float_group("colors")
	var other_id: String = app.float_group("history")
	check(not host_id.is_empty() and not other_id.is_empty(), "two independent floating frames")
	if host_id.is_empty() or other_id.is_empty():
		quit(1)
		return
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	var other: DrawingFloatingHost = app.floating_hosts[other_id]
	host.set_host_rect(Rect2(150, 105, 330, 340))
	other.set_host_rect(Rect2(520, 110, 310, 300))
	await frames(8)
	var frame: Rect2 = Rect2(host.position, host.size)
	var colors: Control = app.dock_views["colors"]
	var layers: Control = app.dock_views["layers"]
	await click(root, (host.get_node("FloatingColumn/FloatingTitleBar/HideHost") as Button).get_global_rect().get_center())
	await click(root, (other.get_node("FloatingColumn/FloatingTitleBar/HideHost") as Button).get_global_rect().get_center())
	check(not host.visible and not other.visible, "close buttons hide both hosts")
	check(not checked(popup, "Colors") and not checked(popup, "Layers") and not checked(popup, "History"), "effective hidden states reflected in menu")
	popup = await open_window_menu(app, root)
	await screenshot("window-hidden")
	await invoke_pointer(popup, "Layers")
	check(host.visible and not other.visible, "pointer restores only requested host")
	check(host.tab_buttons.keys() == ["layers"] and host.is_ancestor_of(layers) and not colors.is_visible_in_tree(), "only requested tab restored using original Control")
	check(layout.owner_of("colors") == host_id and layout.owner_of("layers") == host_id and layout.group_info("colors")["panels"] == ["colors", "layers"], "group and ownership unchanged")
	check(Rect2(host.position, host.size) == frame, "original floating frame preserved")
	check(checked(window_popup(app), "Layers") and not checked(window_popup(app), "Colors") and not checked(window_popup(app), "History"), "individual state updated immediately")
	popup = await open_window_menu(app, root)
	await screenshot("window-one-restored")
	popup.hide()
	check(doc.revision == revision and doc.history_length() == history and doc.is_dirty() == dirty, "workspace restore never edits artwork")
	var partial: Dictionary = layout.snapshot()
	check(app._save_workspace_layout(), "persist partially restored group")
	app.queue_free()
	await frames(10)
	app = open_app()
	await frames(18)
	layout = app.dock_layout
	host = app.floating_hosts[host_id]
	other = app.floating_hosts[other_id]
	check(app.layout_recovery_status == "loaded" and layout.snapshot() == partial, "partial visibility survives workspace restart")
	check(host.visible and not other.visible and host.tab_buttons.keys() == ["layers"], "relaunch restores only requested panel")
	check(Rect2(host.position, host.size) == frame, "relaunch restores original frame")
	popup = await open_window_menu(app, root)
	await invoke_key(popup, "Colors")
	check(host.visible and not other.visible and host.tab_buttons.keys() == ["colors", "layers"], "keyboard restores peer in same group without unrelated host")
	check(layout.group_info("colors")["active"] == "colors" and host.is_ancestor_of(app.dock_views["colors"]), "restored peer active and original view")
	await screenshot("window-both-restored")
	# Repeated reveal is idempotent, not a visibility toggle.
	popup = await open_window_menu(app, root)
	await invoke_key(popup, "Colors")
	check(host.visible and host.tab_buttons.size() == 2, "checked entry reveals without hiding or duplicating")
	# A runtime peer is listed without a hardcoded menu entry.
	var late: Label = Label.new()
	late.text = "Late panel fixture"
	check(app.register_workspace_panel("late_panel", late), "register future panel after startup")
	check(checked(window_popup(app), "Late Panel"), "runtime registration reflected in menu")
	app._toggle_dock()
	await frames(8)
	popup = await open_window_menu(app, root)
	await invoke_key(popup, "Text Options")
	check(layout.container_info("right")["minimized"] and layout.container_info("right")["flyout_group"] == "text_options" and app.text_panel.is_visible_in_tree(), "Window reveals hidden panel in minimized dock flyout")
	check(not app.text_edit.editable, "Window creates no text draft")
	await screenshot("window-flyout")
	popup = await open_window_menu(app, root)
	await invoke_key(popup, "Text Options")
	check(app.dock_flyout.visible and app.text_panel.is_visible_in_tree(), "reselecting active flyout does not close it")
	app._toggle_dock()
	await frames(8)
	popup = await open_window_menu(app, root)
	await invoke_key(popup, "Asset Browser")
	check(app.asset_browser != null and checked(window_popup(app), "Asset Browser") and app.asset_browser.is_visible_in_tree(), "lazy browser opens without duplicate menu entry")
	var asset_host_id: String = app.float_group(layout.group_of("asset_browser"))
	check(not asset_host_id.is_empty(), "float lazy browser")
	app.hide_floating_host(asset_host_id)
	check(not checked(window_popup(app), "Asset Browser"), "browser hidden reflected")
	check(app._save_workspace_layout(), "persist registered lazy browser")
	app.queue_free()
	await frames(10)
	app = open_app()
	await frames(18)
	layout = app.dock_layout
	check(app.asset_browser != null and layout.owner_of("asset_browser") == asset_host_id and not checked(window_popup(app), "Asset Browser"), "lazy browser layout survives restart without opening catalog")
	check(app.asset_browser.index.root_path.is_empty(), "recreating UI never authorizes previous Objects catalog")
	root.size = Vector2i(800, 600)
	root.content_scale_factor = 1.5
	await frames(15)
	popup = await open_window_menu(app, root)
	check(popup == app.top_bar.more_menu.get_popup(), "narrow/HiDPI Window commands are in More")
	check(not checked(popup, "Window › Asset Browser") and checked(popup, "Window › Colors"), "overflow mirrors hidden and available state")
	popup.scroll_to_item(find_item(popup, "Window › Asset Browser"))
	await frames(6)
	await screenshot("window-narrow-hidpi")
	await invoke_key(popup, "Window › Asset Browser")
	check(app.floating_hosts[asset_host_id].visible and app.asset_browser.is_visible_in_tree(), "overflow restores lazy browser")
	check(checked(window_popup(app), "Asset Browser"), "direct checkmark synchronized after overflow action")
	check(not app.floating_hosts[other_id].visible, "unrelated host remains hidden through all restores")
	await screenshot("window-browser-restored")
	# Move a group's last visible member away: hidden peers stay owned and
	# an empty floating frame must not remain over the artwork.
	host = app.floating_hosts[host_id]
	app.hide_floating_host(host_id)
	app._reveal_workspace_panel("layers")
	check(host.tab_buttons.keys() == ["layers"], "second close restores only chosen peer again")
	check(app._dock_apply(DrawingDockDrag.PANEL, "layers", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 0}), "redock last visible peer")
	await frames(5)
	check(not host.visible and layout.owner_of("colors") == host_id and not checked(window_popup(app), "Colors"), "empty host hides without losing its hidden member")
	app._reveal_workspace_panel("colors")
	check(host.visible and host.tab_buttons.keys() == ["colors"] and layout.owner_of("layers") == "right", "original hidden peer remains individually recoverable after redock")
	app.show_hidden_floating_hosts()
	check(app.floating_hosts[other_id].visible and checked(window_popup(app), "History"), "explicit bulk action remains available")
	app.reset_workspace_layout()
	await frames(8)
	check(app.floating_hosts.is_empty() and not checked(window_popup(app), "Text Options") and checked(window_popup(app), "Colors"), "reset updates checks and keeps default Text hidden")
	app.queue_free()
	await frames(8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("T309_NATIVE: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T309_NATIVE_PASSED")
	quit(1 if failures else 0)
