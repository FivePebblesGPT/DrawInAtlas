extends SceneTree
## T-065 Atlas host integration: sidebar, keyboard access, place, NULL and repair.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T065_MANAGER_NATIVE_FAILED: " + label)


func _erase_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in dir.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t065-atlas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(5):
		await process_frame
	var manager_button: Button = editor.layer_panel.get_parent().get_node("ObjectAssetManagerButton") as Button
	_check(manager_button != null and manager_button.text.contains("Object Assets"),
		"Atlas Layers sidebar exposes the source manager")
	_check(editor.drawing_composition != null and editor.drawing_composition.library != null,
		"manager has the canonical campaign-owned Object registry")
	var registry: AtlasObjectLibrary = editor.drawing_composition.library
	var doc: DrawingDocument = DrawingDocument.new("native-source", 16)
	var group: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP, "Visible")
	_check(group.ok, "source group initialized")
	var source_a: DrawingResult = registry.create_asset(doc, "Banner")
	var source_b: DrawingResult = registry.create_asset(doc, "Banner")
	_check(source_a.ok and source_b.ok, "Atlas can register two distinct same-named sources")
	if not source_a.ok or not source_b.ok:
		quit(1)
		return
	manager_button.pressed.emit()
	await process_frame
	var manager: AtlasObjectSourceManager = editor.object_source_manager
	_check(manager != null and manager.visible and manager.library == registry,
		"sidebar button opens library-bound Atlas source manager")
	_check(manager.sources.item_count == 2 and manager.missing.item_count == 0,
		"manager shows both saved sources, no spurious NULL")
	var chosen: String = String(source_a.value)
	var replacement: String = String(source_b.value)
	manager.sources.select(manager._source_ids.find(chosen))
	manager._update_actions()
	var map_id: String = editor.canvas.map.id
	var floor_id: String = editor.canvas.floor.id
	manager.place_button.pressed.emit()
	await process_frame
	var instance_ids: Array[String] = registry.instances_for_asset(chosen)
	_check(instance_ids.size() == 1, "Place creates one linked Atlas instance, not an editor tab")
	if instance_ids.is_empty():
		quit(1)
		return
	var instance_id: String = instance_ids[0]
	var info: Dictionary = registry.instance_info(instance_id)
	_check(info["map_id"] == map_id and info["floor_id"] == floor_id,
		"placement binds to current Atlas map/floor")
	_check(info["detail_id"] == "D%d" % editor.canvas.presented_detail_level,
		"placement records presented detail level")
	_check(info["status"] == "linked" and editor.drawing_composition.selected_instance_id == instance_id,
		"linked instance becomes the active Atlas selection")
	var before_map: Dictionary = registry.instance_info(instance_id)
	manager._ask_delete()
	_check(manager._pending_delete.get("asset_id") == chosen,
		"Delete Source captures exact stable ID")
	manager._delete_with_policy("null")
	_check(registry.instance_info(instance_id)["status"] == "NULL" and manager.missing.item_count == 1,
		"Keep NULL retains selection-compatible missing instance")
	manager.sources.select(manager._source_ids.find(replacement))
	manager.missing.select(0)
	manager._update_actions()
	manager.repair_button.pressed.emit()
	await process_frame
	var restored: Dictionary = registry.instance_info(instance_id)
	_check(restored["status"] == "linked" and restored["source_id"] == replacement,
		"repair action explicitly selects a replacement stable ID")
	_check(restored["generation"] == before_map["generation"] and restored["transform"] == before_map["transform"],
		"repair preserves original instance identity and geometry")
	manager.hide()
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_B
	shortcut.ctrl_pressed = true
	shortcut.shift_pressed = true
	editor._unhandled_key_input(shortcut)
	await process_frame
	_check(manager.visible, "Ctrl+Shift+B reopens existing source manager")
	_check(manager.missing.item_count == 0 and manager.sources.item_count == 1,
		"manager refreshes resolved NULL without duplicate source IDs")
	# Source Import/Export are Atlas-owned transactions, not standalone copies.
	var external: String = folder.path_join("native-portable.drawing")
	var incoming: DrawingDocument = DrawingDocument.new("native-portable-id", 16)
	_check(DrawingObjectEditorFile.save(incoming, external, "Native imported",
		Vector2i(3, 4), Rect2i(0, 0, 8, 8), 7).ok,
		"native test creates portable Object source")
	manager._ask_import()
	manager.import_dialog.hide()
	manager._import_portable(external)
	await process_frame
	_check(registry.asset_exists(incoming.id) and manager.sources.item_count == 2,
		"native manager imports and displays registered portable source")
	manager.sources.select(manager._source_ids.find(incoming.id))
	manager._update_actions()
	_check(not manager.export_button.disabled, "published portable source offers Export")
	manager._ask_export()
	_check(manager._pending_export.get("id", "") == incoming.id,
		"native Export dialog freezes selected source ID")
	manager.export_dialog.hide()
	var exported: String = folder.path_join("native-export.drawing")
	manager._export_portable(exported)
	var exported_doc: DrawingResult = DrawingObjectEditorFile.open(exported)
	_check(exported_doc.ok and exported_doc.value["source_id"] == incoming.id and
		exported_doc.value["name"] == "Native imported",
		"native Export reconstructs correct portable identity and metadata")
	var reread: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	_check(reread.load().ok and reread.instance_info(instance_id)["source_id"] == replacement,
		"published rebind survives a fresh campaign registry load")
	var screenshot_path: String = OS.get_environment("T065_MANAGER_SCREENSHOT")
	if not screenshot_path.is_empty():
		for frame: int in range(3):
			await process_frame
		var image: Image = DisplayServer.screen_get_image(0)
		_check(image != null and image.get_width() > 0 and 			image.save_png(screenshot_path) == OK, "native Atlas source manager screenshot saved")
	manager.hide()
	scene.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T065_MANAGER_NATIVE_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
