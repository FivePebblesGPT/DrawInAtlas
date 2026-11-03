extends SceneTree
## T-065 Atlas UI actions and explicit two-choice deletion/NULL recovery.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T065_MANAGER_FAILED: " + label)


func _erase_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for subdirectory: String in dir.get_directories():
		_erase_tree(path.path_join(subdirectory))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t065-manager-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var source: DrawingDocument = DrawingDocument.new("object-document", 16)
	var group: DrawingResult = source.create_layer(DrawingLayerNode.GROUP, "Source")
	_check(group.ok, "create source group")
	var added: DrawingResult = library.create_asset(source, "Lantern")
	var other: DrawingResult = library.create_asset(source, "Lantern")
	_check(added.ok and other.ok, "publish same-name, distinct-ID sources")
	if not added.ok or not other.ok:
		quit(1)
		return
	var primary: String = String(added.value)
	var replacement: String = String(other.value)
	var created: DrawingResult = library.place(primary, "world", "main", "D0")
	_check(created.ok, "link instance for source manager")
	var manager: AtlasObjectSourceManager = AtlasObjectSourceManager.new()
	root.add_child(manager)
	await process_frame
	manager.bind_library(library)
	_check(manager.sources.item_count == 2 and manager.missing.item_count == 0,
		"manager lists both published sources without invented missing rows")
	var primary_index: int = manager._source_ids.find(primary)
	manager.sources.select(primary_index)
	manager._update_actions()
	_check(manager.selected_source_id() == primary and not manager.edit_button.disabled,
		"published row enables explicit actions")
	_check(manager.repair_button.disabled, "repair disabled until a NULL is selected")
	var opened_ids: Array[String] = []
	var placed_ids: Array[String] = []
	manager.open_source_requested.connect(func(id: String) -> void: opened_ids.append(id))
	manager.place_source_requested.connect(func(id: String) -> void: placed_ids.append(id))
	manager.edit_button.pressed.emit()
	manager.place_button.pressed.emit()
	_check(opened_ids == [primary] and placed_ids == [primary],
		"Edit Source and Place actions forward stable source ID, not display name")
	manager._ask_delete()
	_check(manager._pending_delete.get("asset_id") == primary,
		"delete confirmation locks selected published ID")
	_check(manager._pending_delete.get("bindings", []).size() == 1,
		"confirmation displays exact reference count")
	manager.delete_confirmation.canceled.emit()
	_check(manager._pending_delete.is_empty() and library.asset_exists(primary),
		"Cancel cannot delete a source")
	manager._ask_delete()
	var old_revision: int = int(library.instance_info(String(created.value))["revision"])
	_check(library.set_instance_visibility(String(created.value), old_revision, false).ok,
		"concurrent edit changes the library while confirmation is visible")
	manager._delete_with_policy("remove")
	_check(library.asset_exists(primary) and library.instance_info(String(created.value))["status"] == "linked",
		"stale confirmation cannot Remove references")
	_check(manager.details.text.contains("changed"), "UI explains stale confirmation")
	manager._ask_delete()
	manager._delete_with_policy("null")
	_check(not library.asset_exists(primary) and manager.missing.item_count == 1,
		"Keep NULL retires source but preserves visible missing placement")
	_check(manager.sources.item_count == 1 and manager.sources.get_item_text(0).contains("unused"),
		"unused replacement remains selectable and labeled")
	manager.sources.select(manager._source_ids.find(replacement))
	manager.missing.select(0)
	manager._update_actions()
	_check(not manager.repair_button.disabled,
		"explicit source and NULL selection enables Repair")
	var prior: Dictionary = library.instance_info(String(created.value))
	manager.repair_button.pressed.emit()
	var repaired: Dictionary = library.instance_info(String(created.value))
	_check(repaired["status"] == "linked" and repaired["source_id"] == replacement,
		"Repair button publishes selected target identity")
	_check(repaired["generation"] == prior["generation"] and repaired["transform"] == prior["transform"],
		"UI repair retains stable instance generation and transform")
	_check(manager.missing.item_count == 0 and manager.repair_button.disabled,
		"repair refresh removes resolved NULL and disables further repair")
	manager.bind_library(null)
	_check(manager.sources.item_count == 0 and manager.missing.item_count == 0,
		"rebinding to no library clears stale view")
	manager.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T065_MANAGER_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
