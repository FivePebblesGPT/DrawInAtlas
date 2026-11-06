extends SceneTree
## T-065: shared Drawing Asset Browser -> Atlas linked placement boundary.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T065_ATLAS_BROWSER_FAILED: " + description)


func _erase_tree(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for filename: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in folder.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t065-browser-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(3):
		await process_frame
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var panel: DrawingAssetBrowserPanel = editor.asset_browser_panel
	_check(panel != null and panel.atlas_host_mode, "Atlas embeds canonical shared browser in Layers")
	_check(not panel.visible and editor.asset_browser_toggle != null,
		"browser starts collapsed without forcing an extra window")
	var doc: DrawingDocument = DrawingDocument.new("atlas-browser-a", 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Art")
	_check(layer.ok, "creates portable source artwork")
	var created: DrawingResult = library.create_asset(doc, "Banner")
	_check(created.ok, "publishes first source through Atlas registry")
	var doc_b: DrawingDocument = DrawingDocument.new("atlas-browser-b", 16)
	var created_b: DrawingResult = library.create_asset(doc_b, "Banner")
	_check(created_b.ok, "different stable IDs may share a display name")
	editor.sidebar.select_view(&"Layers")
	editor.asset_browser_toggle.pressed.emit()
	await process_frame
	_check(panel.visible and panel.index.root_path == library.root_path,
		"opening browser automatically selects current campaign Objects root")
	_check(panel.assets.item_count == 2 and panel.index.entries.size() == 2,
		"browser discovers both published sources without mixing Drawings map documents")
	_check(panel.find_child("PlaceAsset", true, false) != null,
		"place action exists for keyboard use")
	var import_button: Button = panel.find_child("ImportAsset", true, false) as Button
	var export_button: Button = panel.find_child("ExportAsset", true, false) as Button
	_check(import_button != null and export_button != null and not import_button.visible and not export_button.visible,
		"Atlas browser hides standalone file-copy actions that bypass registry")
	var selected_row: int = -1
	for i: int in range(panel._visible_entries.size()):
		if panel._visible_entries[i]["id"] == String(created.value):
			selected_row = i
	_check(selected_row >= 0, "published source appears by stable ID")
	if selected_row < 0:
		_finish(scene, folder)
		return
	panel.assets.select(selected_row)
	panel._update_open_button()
	var token: Dictionary = panel._drag_entry_for_row(selected_row)
	_check(token.get("kind") == "drawing-object-source-v1" and
		String(token.get("id")) == String(created.value), "drag captures exact source identity")
	_check(editor._valid_browser_source(token), "active registry authorizes unchanged published token")
	var at: Vector2 = Vector2(135, 125)
	_check(editor.canvas._can_drop_data(at, token), "canvas advertises native Control drop target")
	_check(not editor.canvas._can_drop_data(at, {"kind": "unrelated"}),
		"canvas rejects unrelated drag payload")
	var before: int = library.instance_ids().size()
	var world: Vector2 = editor.canvas.local_to_document(at)
	editor.canvas._drop_data(at, token)
	_check(library.instance_ids().size() == before + 1,
		"dropping shared-browser source creates exactly one linked instance")
	var instance_id: String = editor.drawing_composition.selected_instance_id
	var info: Dictionary = library.instance_info(instance_id)
	_check(info.get("source_id") == created.value and info.get("status") == "linked",
		"instance binds to original published stable ID")
	_check(info.get("map_id") == editor.canvas.map.id and
		info.get("floor_id") == editor.canvas.floor.id and
		info.get("detail_id") == "D%d" % editor.canvas.presented_detail_level,
		"drop uses current map, floor, and detail")
	var transform: Array = info.get("transform", [])
	_check(transform.size() == 6 and Vector2(float(transform[4]), float(transform[5])).distance_to(world) < 0.01,
		"drop position converted through current camera into document units")
	var edits_before: int = library.instance_ids().size()
	editor.canvas._drop_data(at, {"kind": "unknown"})
	_check(library.instance_ids().size() == edits_before,
		"rejected unrelated drag does not publish")
	var forged: Dictionary = token.duplicate(true)
	forged["path"] = folder.path_join("other.drawing")
	editor._on_browser_source_drop(forged, at)
	_check(library.instance_ids().size() == edits_before,
		"forged pathname cannot impersonate published source")
	forged = token.duplicate(true)
	forged["sha256"] = "f".repeat(64)
	editor._on_browser_source_drop(forged, at)
	_check(library.instance_ids().size() == edits_before,
		"forged source hash cannot publish")
	forged = token.duplicate(true)
	forged["revision"] = 123456
	editor._on_browser_source_drop(forged, at)
	_check(library.instance_ids().size() == edits_before,
		"stale source revision cannot publish")
	var changed_path: String = String(token["path"])
	var source_file: FileAccess = FileAccess.open(changed_path, FileAccess.READ_WRITE)
	_check(source_file != null, "published immutable source file is accessible for stale witness")
	if source_file != null:
		source_file.seek_end()
		source_file.store_8(42)
		source_file.close()
		editor._on_browser_source_drop(token, at)
		_check(library.instance_ids().size() == edits_before,
			"source changed after drag start cannot be placed")
	var other_token: Dictionary = panel._drag_entry_for_row(1 - selected_row)
	_check(editor._valid_browser_source(other_token), "unmodified source remains available")
	panel.assets.select(1 - selected_row)
	panel._update_open_button()
	var place_button: Button = panel.find_child("PlaceAsset", true, false) as Button
	_check(place_button != null and not place_button.disabled,
		"keyboard-accessible Place action enabled for valid selection")
	place_button.pressed.emit()
	_check(library.instance_ids().size() == edits_before + 1,
		"Place action uses same registry-checked placement as pointer drop")
	var center_info: Dictionary = library.instance_info(editor.drawing_composition.selected_instance_id)
	_check(Vector2(float(center_info["transform"][4]), float(center_info["transform"][5])).distance_to(
		editor.canvas.local_to_document(editor.canvas.size * 0.5)) < 0.01,
		"keyboard placement targets the viewport center")
	var second_count: int = library.instance_ids().size()
	panel.assets.select(1 - selected_row)
	panel._update_open_button()
	panel.open_selected()
	_check(editor.object_editor_window != null,
		"shared browser Edit Source invokes independent Atlas Object Editor")
	editor._on_sample(true)
	_check(editor.drawing_composition.library != library,
		"sample reset switches to a distinct campaign library")
	editor._on_browser_source_drop(other_token, at)
	_check(editor.drawing_composition.library.instance_ids().is_empty(),
		"drag from previous registry is rejected after campaign reset")
	_check(library.instance_ids().size() == second_count,
		"old library cannot be mutated by a new campaign's drop")
	_finish(scene, folder)


func _finish(scene: Node, folder: String) -> void:
	scene.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T065_ATLAS_BROWSER_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
