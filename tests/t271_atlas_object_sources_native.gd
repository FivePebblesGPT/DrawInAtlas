extends SceneTree
## T-271: published Object discovery in the Atlas consumer of the shared
## Drawing browser. X11 pointer interactions; physical OS dialogs not tested.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T271_ATLAS_FAILED: " + label)


func frames(count: int = 4) -> void:
	for _index: int in range(count):
		await process_frame


func click(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	var position: Vector2 = control.get_global_rect().get_center()
	if not control.get_global_rect().has_point(position):
		return false
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		root.push_input(event, true)
		await frames(3)
	return true


func erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories():
		erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1340, 900)
	var folder: String = ProjectSettings.globalize_path("user://t271-atlas-" + DrawingDocument.new_id())
	var shell: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = shell.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(shell)
	await frames(10)
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	check(library != null and editor.canvas.map != null and editor.canvas.floor != null,
		"Atlas starts with its own campaign-backed Object library")
	check(editor.asset_browser_panel != null and not editor.asset_browser_panel.visible and
		library.asset_ids().is_empty(), "Atlas does not guess an external Object root")

	var document: DrawingDocument = DrawingDocument.new("t271-published-id", 16)
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pigment")
	check(layer.ok, "published Object has a raster layer")
	if layer.ok:
		var begun: DrawingResult = document.begin_edit(String(layer.value), document.revision)
		check(begun.ok, "published Object begins exact RGBA8 edit")
		if begun.ok:
			var edit: DrawingEditSession = begun.value as DrawingEditSession
			check(edit.fill_rect(Rect2i(-3, 2, 1, 1), 0x00332211).ok and edit.commit().ok,
				"published Object contains signed hidden RGB")
	var published: DrawingResult = library.create_asset(document, "Atlas object")
	check(published.ok and String(published.value).begins_with("asset-") and
		String(published.value) != document.id,
		"campaign publication assigns one independent immutable asset ID")
	var source_id: String = String(published.value) if published.ok else ""
	var asset: Dictionary = library.asset_info(source_id)
	var source_path: String = library._absolute(String(asset.get("path", "")))
	var digest: String = FileAccess.get_sha256(source_path)
	check(not digest.is_empty() and library.asset_exists(source_id),
		"published portable source is hashed and exists")
	var map_id: String = editor.canvas.map.id
	var undo_before: bool = editor.edits.can_undo()
	var dirty_before: bool = editor.edits.is_dirty()
	editor.sidebar.select_view(&"Layers")
	await frames(5)
	check(await click(editor.asset_browser_toggle), "native browser-toggle click delivered")
	await frames(8)
	var browser: DrawingAssetBrowserPanel = editor.asset_browser_panel
	check(browser.visible and browser.assets.item_count == 1 and
		browser.index.root_path == library.root_path,
		"Atlas browser lists only the current verified campaign source")
	check(browser.assets.get_item_tooltip(0).contains(source_id),
		"listed source exposes exact stable ID")
	var item_position: Vector2 = browser.assets.get_global_rect().position + \
		browser.assets.get_item_rect(0).get_center()
	check(browser.assets.get_global_rect().has_point(item_position),
		"source row is visible in the real Atlas layout")
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = item_position
		event.global_position = item_position
		root.push_input(event, true)
		await frames(3)
	check(browser.selected_asset_id() == source_id and not browser.open_button.disabled,
		"native row click selects published source identity")
	var token: Dictionary = browser._drag_entry_for_row(0)
	check(editor._valid_browser_source(token), "browser token is explicitly authorized")
	check(await click(browser.open_button), "native Object Editor Open click delivered")
	await frames(9)
	check(editor.object_editor_window != null and editor.object_editor_window.workspace != null,
		"Open creates the shared Object Editor rather than a map placement")
	if editor.object_editor_window != null and editor.object_editor_window.workspace != null:
		var workspace: Control = editor.object_editor_window.workspace
		check(workspace.tabs.size() == 1 and workspace.current_object() != null and
			workspace.current_object().source_id == source_id,
			"dedicated Object Editor tab retains exact published source ID")
		var opened_document: DrawingDocument = workspace.current_document()
		var opened_children: Array[String] = opened_document.list_children() if opened_document != null \
			else [] as Array[String]
		var opened_pixel: DrawingResult = opened_document.read_pixel(opened_children[0], -3, 2) \
			if not opened_children.is_empty() else DrawingResult.failure("NO_LAYER", "Missing Object raster")
		check(opened_pixel.ok and int(opened_pixel.value) == 0x00332211,
			"native Object Editor preserves published signed alpha-zero hidden RGB")
	check(library.instances_for_asset(source_id).is_empty() and
		editor.drawing_composition.selected_instance_id.is_empty(),
		"opening source never silently places or selects a map instance")
	check(editor.canvas.map.id == map_id and editor.edits.can_undo() == undo_before and
		editor.edits.is_dirty() == dirty_before,
		"source discovery leaves Atlas map, global Undo and dirty state unchanged")
	check(FileAccess.get_sha256(source_path) == digest,
		"opening source never rewrites the published file")
	var screenshot_path: String = OS.get_environment("T271_ATLAS_SCREENSHOT")
	if not screenshot_path.is_empty():
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		check(screenshot != null and screenshot.save_png(screenshot_path) == OK,
			"Atlas source browser framebuffer screenshot saved")
	# Refreshing from the exact verified listing cannot authorize a changed file.
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.WRITE)
	check(source_file != null, "source fixture can be deliberately corrupted")
	if source_file != null:
		source_file.store_string("corrupted, unverified source")
		source_file.close()
	check(not editor._valid_browser_source(token),
		"previously selected token is rejected after source bytes change")
	var tabs_before: int = editor.object_editor_window.workspace.tabs.size() \
		if editor.object_editor_window != null else 0
	editor._on_browser_open_source(source_path)
	await frames(3)
	check(editor.object_editor_window != null and
		editor.object_editor_window.workspace.tabs.size() == tabs_before and
		library.instances_for_asset(source_id).is_empty(),
		"stale source cannot open an unauthorized tab or place a linked instance")
	check(editor.edits.can_undo() == undo_before and editor.edits.is_dirty() == dirty_before,
		"rejected source retains the Atlas history cursor and savepoint")
	shell.queue_free()
	await frames(5)
	erase_tree(folder)
	print("T271_ATLAS: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T271_ATLAS_PASSED")
	quit(1 if failures else 0)
