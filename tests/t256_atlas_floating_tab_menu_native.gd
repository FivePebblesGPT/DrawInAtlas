extends SceneTree
## T-256: the same floating tab context contract survives Atlas embedding.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T256_ATLAS_FAILED: " + label)


func frames(count: int = 5) -> void:
	for _step: int in range(count):
		await process_frame


func click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
		await frames(4)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var atlas_host: Control = Control.new()
	root.add_child(atlas_host)
	atlas_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	atlas_host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	var revision: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	var host_id: String = app.float_group("colors")
	check(not host_id.is_empty(), "Atlas floats Colors")
	await frames(8)
	var host: DrawingFloatingHost = app.floating_hosts[host_id]
	host.set_host_rect(Rect2(250, 130, 300, 380))
	check(app.move_group_to_floating("layers", host_id), "Atlas floats Layers into Colors")
	await frames(8)
	var group_id: String = app.dock_layout.group_of("colors")
	var owner: Dictionary = app.dock_layout.snapshot()
	var menu: PopupMenu = host.get_node_or_null("FloatingPanelContextMenu") as PopupMenu
	check(menu != null, "Atlas receives floating menu from shared Drawing package")
	if menu == null:
		print("T256_ATLAS: %d checks; %d failed" % [checks, failures])
		quit(1)
		return
	await click((host.tab_buttons["layers"] as Control).get_global_rect().get_center())
	check(menu.visible and host._menu_panel_id == "layers", "Atlas RMB targets clicked icon")
	check(owner == app.dock_layout.snapshot(), "Atlas RMB never publishes a history/layout edit")
	menu.hide()
	await frames(4)
	host._floating_panel_menu_action(3)
	await frames(8)
	check(app.dock_layout.owner_of("layers") == "right" and
		app.dock_layout.owner_of("colors") == host_id,
		"Dock panel context changes one owner, not the entire floating group")
	var after_move: Dictionary = app.dock_layout.snapshot()
	host._floating_panel_menu_action(4)
	check(app.dock_layout.snapshot() == after_move,
		"late menu callback for a redocked tab cannot move its old floating group")
	check(app.current_document().revision == revision and app.current_document().is_dirty() == dirty,
		"Atlas document/history unchanged after context transfer")
	check(app.get_parent() == atlas_host and app.dock_layout.group_info(group_id).has("id"),
		"Atlas host context unchanged and surviving group is valid")
	print("T256_ATLAS: %d checks; %d failed" % [checks, failures])
	print("T256_ATLAS_PASSED" if failures == 0 else "T256_ATLAS_FAILED")
	quit(1 if failures else 0)
