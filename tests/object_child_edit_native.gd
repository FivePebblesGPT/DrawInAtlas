extends SceneTree
## Targeted native T-064 inspector rendering and keyboard/pointer-safe controls.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T064_CHILD_EDIT_NATIVE_FAILED: " + label)


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
	var folder: String = OS.get_cache_dir().path_join("t064-native-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var document: DrawingDocument = DrawingDocument.new("T064 native", 16)
	var parent: DrawingResult = library.create_asset(document, "Parent")
	var child: DrawingResult = library.create_asset(document, "Child")
	_check(parent.ok and child.ok, "native editor has published sources")
	if not parent.ok or not child.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var cid: String = String(child.value)
	var added: DrawingResult = library.attach_child(pid, 0, cid,
		Transform2D(0.0, Vector2(12, -4)))
	_check(added.ok, "native test has one linked child")
	var manager: AtlasObjectSourceManager = AtlasObjectSourceManager.new()
	root.add_child(manager)
	await process_frame
	manager.bind_library(library)
	manager.popup_centered()
	manager.sources.select(manager._source_ids.find(pid))
	manager._update_actions()
	manager.children_button.pressed.emit()
	for frame: int in range(4):
		await process_frame
	var inspector: AtlasObjectChildInspector = manager.child_inspector
	_check(manager.visible and inspector.visible and inspector.child_list.item_count == 1,
		"native windows show the parent-local child list")
	var row_rect: Rect2 = inspector.child_list.get_item_rect(0)
	_check(row_rect.size.x > 0 and row_rect.size.y > 0 and inspector.child_list.size.y > 0,
		"native list row is visibly laid out")
	inspector.child_list.select(0)
	inspector.child_list.item_selected.emit(0)
	_check(not (inspector.actions_node().get_node("MoveRight") as Button).disabled and
		not inspector.open_button.disabled, "selected child exposes transform and source editing")
	var original: Dictionary = library.children_for_asset(pid)[0]
	(inspector.actions_node().get_node("MoveRight") as Button).pressed.emit()
	_check(library.children_for_asset(pid)[0]["transform"][4] == 13.0,
		"native move control updates parent-local translation")
	inspector.undo_button.pressed.emit()
	_check(library.children_for_asset(pid)[0]["transform"][4] == 12.0 and
		library.children_for_asset(pid)[0]["generation"] == original["generation"],
		"native undo preserves child identity")
	inspector.redo_button.pressed.emit()
	_check(library.children_for_asset(pid)[0]["transform"][4] == 13.0,
		"native redo replays child transform")
	var opened: Array[String] = []
	manager.open_source_requested.connect(func(source: String) -> void: opened.append(source))
	inspector.open_button.pressed.emit()
	_check(opened == [cid], "native Edit child source routes to existing Object Editor request")
	_check(inspector.source_picker.item_count == 1 and not inspector.attach_button.disabled,
		"native inspector exposes a focusable source picker and Attach action")
	var choose: int = inspector._candidate_ids.find(cid)
	inspector.source_picker.select(choose)
	inspector.attach_button.pressed.emit()
	_check(library.children_for_asset(pid).size() == 2 and not inspector.detach_button.disabled,
		"native Attach action publishes a second stable child")
	var new_child: String = inspector.session.selected_child_id
	inspector.detach_button.pressed.emit()
	_check(library.children_for_asset(pid).size() == 1,
		"native Remove detaches selected child without deleting source")
	inspector.undo_button.pressed.emit()
	_check(library.children_for_asset(pid).size() == 2 and
		inspector.session.selected_child_id == new_child,
		"native Undo recovers the same child instance")
	inspector.redo_button.pressed.emit()
	_check(library.children_for_asset(pid).size() == 1 and
		library.asset_exists(cid), "native Redo removes only the child reference")
	var before_invalid: Dictionary = library.export_index()
	_check(not inspector._candidate_ids.has(pid) and
		library.export_index() == before_invalid,
		"native source picker excludes recursive parent/self links")
	var shot: String = OS.get_environment("T064_CHILD_SCREENSHOT")
	if not shot.is_empty():
		for frame: int in range(3):
			await process_frame
		var image: Image = DisplayServer.screen_get_image(0)
		_check(image != null and image.get_width() > 0 and image.save_png(shot) == OK,
			"native inspector screenshot recorded")
	manager.hide()
	inspector.hide()
	manager.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CHILD_EDIT_NATIVE_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
