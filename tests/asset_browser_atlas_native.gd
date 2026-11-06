extends SceneTree
## Native T-065: actual atlas sidebar browser drag source, target, and display.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T065_ATLAS_BROWSER_NATIVE_FAILED: " + label)


func _erase_tree(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for f: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d: String in folder.get_directories():
		_erase_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var dir: String = OS.get_cache_dir().path_join("t065-atlas-native-" + DrawingDocument.new_id())
	var shell: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = shell.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = dir.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(shell)
	for frame: int in range(6):
		await process_frame
	_check(editor.canvas.get_viewport() != null and editor.canvas.size.x > 100,
		"Atlas canvas has native usable dimensions")
	var lib: AtlasObjectLibrary = editor.drawing_composition.library
	var art: DrawingDocument = DrawingDocument.new("native-obj", 16)
	var layer: DrawingResult = art.create_layer(DrawingLayerNode.RASTER, "Art")
	_check(layer.ok, "native Object source created")
	var published: DrawingResult = lib.create_asset(art, "Native drag source")
	_check(published.ok, "native Object published")
	editor.sidebar.select_view(&"Layers")
	editor.asset_browser_toggle.pressed.emit()
	await process_frame
	var browser: DrawingAssetBrowserPanel = editor.asset_browser_panel
	_check(browser.visible and browser.index.entries.size() == 1,
		"Atlas Layers reveals the shared browser")
	_check(browser.assets.size.x > 60 and browser.assets.size.y > 60,
		"drag source ItemList has real layout")
	var row: int = browser.assets.get_item_at_position(Vector2(8, 8), true)
	_check(row == 0, "first source has a hit-testable native row")
	var token: Variant = browser.assets._get_drag_data(Vector2(8, 8))
	_check(token is Dictionary and token.get("id", "") == published.value,
		"native Godot ItemList provides source-identity drag data")
	var canvas_point: Vector2 = editor.canvas.size * Vector2(0.68, 0.43)
	_check(editor.canvas._can_drop_data(canvas_point, token),
		"native Atlas canvas accepts a published browser drag")
	var expected: Vector2 = editor.canvas.local_to_document(canvas_point)
	editor.canvas._drop_data(canvas_point, token)
	await process_frame
	var ids: Array[String] = lib.instances_for_asset(String(published.value))
	_check(ids.size() == 1, "native drop creates exactly one published linked placement")
	if ids.size() == 1:
		var placed: Dictionary = lib.instance_info(ids[0])
		var transform: Array = placed["transform"]
		_check(Vector2(float(transform[4]), float(transform[5])).distance_to(expected) < 0.01,
			"native drop preserves precise view-relative coordinates")
		_check(placed["status"] == "linked", "native object remains a live source binding")
	var screenshot: String = OS.get_environment("T065_ATLAS_BROWSER_SCREENSHOT")
	if not screenshot.is_empty():
		for frame: int in range(3):
			await process_frame
		var image: Image = DisplayServer.screen_get_image(0)
		_check(image != null and image.get_width() > 0 and image.save_png(screenshot) == OK,
			"screenshot saved from native viewport")
	browser.assets.select(0)
	browser._update_open_button()
	browser.open_button.pressed.emit()
	await process_frame
	_check(editor.object_editor_window != null,
		"browser Edit Source opens separate Atlas Object Editor")
	shell.queue_free()
	await process_frame
	_erase_tree(dir)
	print("T065_ATLAS_BROWSER_NATIVE_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
