extends SceneTree
## T-090: View/Window checkable commands must retain their state when moved to More.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T090_OVERFLOW_FAILED: " + description)


func frames(count: int = 6) -> void:
	for _i: int in range(count):
		await process_frame


func more_id(popup: PopupMenu, label: String) -> int:
	for i: int in range(popup.item_count):
		if popup.get_item_text(i) == label:
			return i
	return -1


func check_more_item(top: Control, name: String, checked: bool) -> void:
	var popup: PopupMenu = top.more_menu.get_popup()
	var id: int = more_id(popup, name)
	check(id >= 0, "More contains %s" % name)
	if id >= 0:
		check(popup.is_item_checkable(id) and popup.is_item_checked(id) == checked,
			"More mirrors real checkable state: %s = %s" % [name, checked])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(300, 600)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	app.size = Vector2(300, 600)
	await frames(12)
	var top: Control = app.top_bar
	top._refresh_layout()
	var more: PopupMenu = top.more_menu.get_popup()
	check(top.more_menu.visible and not top._menus[2].visible and not top._menus[6].visible,
		"narrow workspace exposes View and Window in the More popup")
	check_more_item(top, "View › Show grid", app.canvas.show_grid)
	check_more_item(top, "View › Pixel grid at high zoom", app.canvas.show_pixel_grid)
	check_more_item(top, "Window › Show document tabs", app.show_document_tabs)
	var file_id: int = more_id(more, "View › Zoom in")
	check(file_id >= 0 and not more.is_item_checkable(file_id),
		"ordinary overflow commands remain uncheckable")

	var grid_before: bool = app.canvas.show_grid
	app._toggle_grid()
	check(app.canvas.show_grid != grid_before, "real View grid handler changes canvas")
	check_more_item(top, "View › Show grid", app.canvas.show_grid)
	app._toggle_pixel_grid()
	check_more_item(top, "View › Pixel grid at high zoom", app.canvas.show_pixel_grid)
	var tabs_id: int = more_id(more, "Window › Show document tabs")
	if tabs_id >= 0:
		top._more_selected(tabs_id)
	check(not app.show_document_tabs and not top._menus[6].get_popup().is_item_checked(2),
		"More dispatch toggles actual tab strip and original Window check state")
	check_more_item(top, "Window › Show document tabs", false)

	# Rebuilding the overflow menu must preserve updated state; no stale ticks.
	top._refresh_layout()
	check_more_item(top, "View › Show grid", app.canvas.show_grid)
	check_more_item(top, "View › Pixel grid at high zoom", app.canvas.show_pixel_grid)
	check_more_item(top, "Window › Show document tabs", false)
	var view_popup: PopupMenu = top._menus[2].get_popup()
	view_popup.set_item_disabled(0, true)
	top._refresh_layout()
	var disabled_id: int = more_id(more, "View › Zoom in")
	check(disabled_id >= 0 and more.is_item_disabled(disabled_id),
		"overflow reflects source command availability")
	view_popup.set_item_disabled(0, false)

	root.size = Vector2i(1280, 760)
	app.size = Vector2(1280, 760)
	await frames(12)
	top._refresh_layout()
	check(top._menus[2].visible and top._menus[6].visible and not top.more_menu.visible,
		"wide viewport restores original View and Window menus")
	check(view_popup.is_item_checked(3) == app.canvas.show_grid and
		view_popup.is_item_checked(5) == app.canvas.show_pixel_grid and
		not top._menus[6].get_popup().is_item_checked(2),
		"real popup states persist when More disappears")
	app._toggle_document_tabs()
	check(app.show_document_tabs and top._menus[6].get_popup().is_item_checked(2),
		"visible menu toggle synchronizes direct popup")

	root.size = Vector2i(300, 600)
	app.size = Vector2(300, 600)
	await frames(12)
	top._refresh_layout()
	check_more_item(top, "Window › Show document tabs", true)
	check_more_item(top, "View › Show grid", app.canvas.show_grid)
	var help_id: int = more_id(more, "Help › About Drawing workspace")
	check(help_id >= 0, "unrelated hidden Help command remains available")
	if help_id >= 0:
		top._more_selected(help_id)
		check(app.get_node("WorkspaceAbout").visible,
			"More preserves original callable dispatch for non-toggle actions")
		app.get_node("WorkspaceAbout").hide()

	print("T090_OVERFLOW: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T090_OVERFLOW_PASSED: %d checks" % checks)
	quit(1 if failures > 0 else 0)
