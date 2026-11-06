extends SceneTree
## T-065 targeted X11 pointer witness. An external XTEST driver performs the
## actual window-system press/move/release; this script only observes the app.

var checks: int = 0
var failures: int = 0
var _observed_drop: Vector2 = Vector2.INF
var _drop_count: int = 0


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T065_POINTER_FAILED: " + label)


func _initialize() -> void:
	call_deferred("_run")


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for entry: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(entry))
	for entry: String in directory.get_directories():
		_erase_tree(path.path_join(entry))
	DirAccess.remove_absolute(path)


func _wait_marker(path: String, max_msec: int = 18000) -> bool:
	var deadline: int = Time.get_ticks_msec() + max_msec
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(path):
			return true
		await process_frame
	return false


func _write_marker(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("ready\n")
		file.close()


func _run() -> void:
	var handshake: String = OS.get_environment("T065_POINTER_HANDSHAKE")
	if handshake.is_empty() or not DirAccess.dir_exists_absolute(handshake):
		push_error("T065_POINTER_FAILED: T065_POINTER_HANDSHAKE must be a writable directory")
		quit(2)
		return
	var campaign_root: String = OS.get_cache_dir().path_join("t065-pointer-" + DrawingDocument.new_id())
	var shell: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = shell.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = campaign_root.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(shell)
	for frame: int in range(10):
		await process_frame
	var document: DrawingDocument = DrawingDocument.new("pointer-source", 16)
	_check(document.create_layer(DrawingLayerNode.RASTER, "Art").ok, "source document created")
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	editor.canvas.object_source_dropped.connect(func(_source: Dictionary, pointer: Vector2) -> void:
		_observed_drop = pointer
		_drop_count += 1)
	var published: DrawingResult = library.create_asset(document, "Pointer drag source")
	_check(published.ok, "source published in current campaign")
	editor.sidebar.select_view(&"Layers")
	editor.asset_browser_toggle.pressed.emit()
	for frame: int in range(10):
		await process_frame
	var browser: DrawingAssetBrowserPanel = editor.asset_browser_panel
	_check(browser.visible and browser.assets.item_count == 1, "published row is visible in Atlas")
	var source: Vector2 = browser.assets.global_position + Vector2(55.0, 32.0)
	var local_target: Vector2 = editor.canvas.size * Vector2(0.55, 0.52)
	var target: Vector2 = editor.canvas.global_position + local_target
	var window_position: Vector2i = DisplayServer.window_get_position()
	var source_screen: Vector2 = source + Vector2(window_position)
	var target_screen: Vector2 = target + Vector2(window_position)
	_check(browser.assets.get_global_rect().has_point(source) and \
		browser.assets.get_item_at_position(Vector2(55, 32), true) == 0,
		"drag starts on hit-testable Object source")
	_check(editor.canvas.get_global_rect().has_point(target), "drop ends inside Atlas canvas")
	var ready: Dictionary = {"source": [source_screen.x, source_screen.y],
		"target": [target_screen.x, target_screen.y],
		"invalid": [source_screen.x + 80.0, source_screen.y + 120.0],
		"window": [window_position.x, window_position.y]}
	var ready_file: FileAccess = FileAccess.open(handshake.path_join("ready.json"), FileAccess.WRITE)
	if ready_file == null:
		push_error("T065_POINTER_FAILED: cannot write pointer handshake")
		quit(2)
		return
	ready_file.store_string(JSON.stringify(ready))
	ready_file.close()
	print("T065_POINTER_READY ", JSON.stringify(ready))
	_check(await _wait_marker(handshake.path_join("clicked")), "XTEST click phase completed")
	_check(library.instance_ids().is_empty() and browser.assets.get_selected_items().size() == 1,
		"ordinary source click selects without placing or dragging")
	_write_marker(handshake.path_join("drag_ready"))
	var saw_drag: bool = false
	var deadline: int = Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < deadline and not FileAccess.file_exists(handshake.path_join("dropped")):
		if editor.canvas.get_viewport().gui_is_dragging():
			saw_drag = true
		await process_frame
	_check(saw_drag, "real OS mouse movement begins Godot GUI drag")
	_check(_drop_count == 1 and _observed_drop.is_finite(), "native Godot Control delivered one canvas drop coordinate")
	var placements: Array[String] = library.instances_for_asset(String(published.value))
	_check(placements.size() == 1, "real OS mouse release places exactly one linked instance")
	if placements.size() == 1:
		var state: Dictionary = library.instance_info(placements[0])
		var transform: Array = state["transform"]
		_check(state["status"] == "linked", "dragged instance is a live link")
		_check(Vector2(float(transform[4]), float(transform[5])).distance_to(editor.canvas.local_to_document(_observed_drop)) < 0.01,
			"native release places exactly at the canvas callback coordinate")
		_check(_observed_drop.distance_to(local_target) < 80.0,
			"release remains within the intended canvas target region")
	_write_marker(handshake.path_join("cancel_ready"))
	_check(await _wait_marker(handshake.path_join("cancelled")), "XTEST rejected-target phase completed")
	for frame: int in range(3):
		await process_frame
	_check(library.instance_ids().size() == 1 and _drop_count == 1,
		"drag release back onto browser does not create another Atlas instance")
	_check(not editor.canvas.get_viewport().gui_is_dragging(), "invalid drop clears native drag state")
	_write_marker(handshake.path_join("escape_ready"))
	_check(await _wait_marker(handshake.path_join("escaped")), "XTEST Escape cancellation phase completed")
	for frame: int in range(3):
		await process_frame
	_check(library.instance_ids().size() == 1 and _drop_count == 1,
		"Esc cancels another drag without publishing an instance")
	_check(not editor.canvas.get_viewport().gui_is_dragging(), "Esc restores the native drag state")
	var screenshot_path: String = OS.get_environment("T065_POINTER_SCREENSHOT")
	if not screenshot_path.is_empty():
		var screenshot: Image = DisplayServer.screen_get_image(0)
		_check(screenshot != null and screenshot.save_png(screenshot_path) == OK,
			"pointer-driven Atlas viewport captured")
	shell.queue_free()
	await process_frame
	_erase_tree(campaign_root)
	print("T065_POINTER_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
