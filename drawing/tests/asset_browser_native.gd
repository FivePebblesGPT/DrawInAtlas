extends SceneTree
## Targeted T-065 real Control pointer/keyboard and renderer witness.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T065_NATIVE_FAILED: " + description)

func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame

func click(position: Vector2) -> void:
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = position
	mouse.global_position = position
	mouse.pressed = true
	root.push_input(mouse, true)
	await frames(4)
	mouse.pressed = false
	root.push_input(mouse, true)
	await frames(5)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native display required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var objects: String = ProjectSettings.globalize_path("user://t065-native-" + DrawingDocument.new_id() + "/Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "create portable fixture")
	var source: DrawingDocument = DrawingDocument.new("asset-native")
	check(source.create_layer(DrawingLayerNode.RASTER, "Pixels").ok, "create source layer")
	check(DrawingObjectEditorFile.save(source, objects.path_join("native.drawing"), "Native Object",
		Vector2i.ZERO, Rect2i(), 1).ok, "write portable source")
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.initial_asset_browser_root = objects
	root.add_child(app)
	await frames(15)
	var panel: DrawingAssetBrowserPanel = app.asset_browser
	check(panel != null and app.dock_layout.owner_of("asset_browser") == "right", "host pre-registers dock peer before layout restore")
	check(panel.assets.item_count == 1, "asset row is present in native dock")
	var rail_info: Array[Dictionary] = app.dock_layout.rail_icons("right")
	check(rail_info.size() == 4 and rail_info[-1]["panel"] == "asset_browser", "browser has its own group and icon")
	panel.search.grab_focus()
	await frames(8)
	check(panel.search.has_focus() and panel.search.is_visible_in_tree(), "keyboard focus scrolls browser into view")
	app.inspector.scroll_vertical = int(app.inspector.get_v_scroll_bar().max_value)
	await frames(10)
	var point: Vector2 = panel.assets.get_global_rect().position + panel.assets.get_item_rect(0).get_center()
	check(panel.assets.get_global_rect().has_point(point), "asset row has a native pointer target")
	await click(point)
	check(panel.selected_asset_id() == "asset-native" and not panel.open_button.disabled, "real pointer selects source without publication")
	await click(panel.open_button.get_global_rect().get_center())
	check(app.tabs.size() == 2 and app.current_object() != null and app.current_object().source_id == "asset-native", "pointer Open enters Object Editor tab")
	check(not source.is_dirty(), "browser selection and open do not edit saved source")
	var host_id: String = app.float_group("asset_browser")
	check(not host_id.is_empty() and app.dock_layout.owner_of("asset_browser") == host_id,
		"Asset Browser group can float without duplicate panel ownership")
	var host: DrawingFloatingHost = app.floating_hosts.get(host_id) as DrawingFloatingHost
	check(host != null and host.visible and panel.is_inside_tree(),
		"floating host keeps the original live Asset Browser Control")
	app.hide_floating_host(host_id)
	check(not host.visible and app.dock_layout.owner_of("asset_browser") == host_id,
		"hide preserves panel source and ownership")
	app.show_hidden_floating_hosts()
	check(host.visible, "Window recovery reopens hidden Asset Browser")
	root.size = Vector2i(560, 470)
	await frames(9)
	check(host.get_global_rect().end.x <= 561.0 and host.get_global_rect().end.y <= 471.0,
		"floating browser clamps to narrower client window")
	root.size = Vector2i(1280, 800)
	await frames(7)
	var thumb: Image = root.get_texture().get_image()
	check(thumb != null and not thumb.is_empty(), "native framebuffer is available")
	var target: String = OS.get_environment("T065_SCREENSHOTS")
	if not target.is_empty() and thumb != null:
		DirAccess.make_dir_recursive_absolute(target)
		check(thumb.save_png(target.path_join("asset-browser-native.png")) == OK, "review screenshot")
	print("T065_NATIVE: %d passed; %d failed" % [checks, failures])
	if failures == 0:
		print("T065_NATIVE_PASSED")
	quit(1 if failures else 0)
