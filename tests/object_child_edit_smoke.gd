extends SceneTree
## T-064: parent-scoped transform history and live nested selection UI.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T064_CHILD_EDIT_FAILED: " + label)


func _position(library: AtlasObjectLibrary, parent: String, child_id: String) -> Vector2:
	for record: Dictionary in library.children_for_asset(parent):
		if record["id"] == child_id:
			return Vector2(float(record["transform"][4]), float(record["transform"][5]))
	return Vector2.INF


func _erase_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in dir.get_directories():
		_erase_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-edit-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var doc: DrawingDocument = DrawingDocument.new("nested-edit", 16)
	_check(doc.create_layer(DrawingLayerNode.GROUP, "Content").ok, "prepare source")
	var a: DrawingResult = library.create_asset(doc, "Parent")
	var b: DrawingResult = library.create_asset(doc, "Child")
	var c: DrawingResult = library.create_asset(doc, "Sibling")
	_check(a.ok and b.ok and c.ok, "publish independent sources")
	if not a.ok or not b.ok or not c.ok:
		quit(1)
		return
	var aid: String = String(a.value)
	var bid: String = String(b.value)
	var cid: String = String(c.value)
	var attached: DrawingResult = library.attach_child(aid, 0, bid,
		Transform2D(0.0, Vector2(-3, 5)))
	var sibling: DrawingResult = library.attach_child(aid, 1, cid)
	_check(attached.ok and sibling.ok, "attach two children with independent identity")
	var child_id: String = String(attached.value)
	var sibling_id: String = String(sibling.value)
	var stable: Dictionary = library.children_for_asset(aid)[0].duplicate(true)
	var editor: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(library, aid)
	_check(editor.select_child(child_id).ok and editor.selected_record()["id"] == child_id,
		"selection resolves stable child record")
	_check(not editor.select_child("nonexistent").ok and editor.selected_child_id == child_id,
		"invalid selection leaves previous child selected")
	_check(editor.translate_selected(Vector2(4, -2)).ok and
		_position(library, aid, child_id) == Vector2(1, 3), "move publishes parent-local translation")
	_check(library.children_revision(aid) == 3 and library.asset_info(aid)["revision"] == 1,
		"transform advances graph revision without publishing child pixels")
	_check(library.children_for_asset(aid)[0]["generation"] == stable["generation"] and
		library.children_for_asset(aid)[0]["source_id"] == bid and
		library.children_for_asset(aid)[0]["revision"] == 1 and
		library.children_for_asset(aid)[1]["revision"] == 0,
		"transform preserves stable identity and untouched sibling")
	_check(editor.can_undo() and not editor.can_redo(), "transform creates one history step")
	_check(editor.undo().ok and _position(library, aid, child_id) == Vector2(-3, 5),
		"undo restores original local position")
	_check(library.children_for_asset(aid)[0]["revision"] == 2,
		"undo increases child revision rather than replaying an old revision")
	_check(editor.can_redo() and editor.redo().ok and
		_position(library, aid, child_id) == Vector2(1, 3), "redo repeats transform")
	_check(library.children_for_asset(aid)[0]["revision"] == 3,
		"redo keeps child optimistic revision monotonic")
	_check(not editor.can_redo() and not editor.redo().ok,
		"history refuses redo beyond its current cursor")
	_check(editor.undo().ok and editor.translate_selected(Vector2(0, 6)).ok and
		not editor.can_redo() and _position(library, aid, child_id) == Vector2(-3, 11),
		"new transform after undo discards abandoned redo branch")
	_check(editor.rotate_selected(PI / 2.0).ok,
		"nested instance rotates without modifying its child source")
	var transformed: Dictionary = editor.selected_record()
	_check(is_equal_approx(float(transformed["transform"][0]), 0.0) and
		is_equal_approx(float(transformed["transform"][1]), 1.0),
		"local rotation is persisted in the published child transform")
	_check(editor.undo().ok and editor.redo().ok, "rotation has reversible edit history")
	var clean: Dictionary = library.export_index()
	_check(not editor.translate_selected(Vector2.INF).ok and library.export_index() == clean,
		"non-finite gesture rejected without publication")
	_check(not editor.set_selected_transform(Transform2D(Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO)).ok and library.export_index() == clean,
		"singular transform rejected without a history entry")
	library.publication_guard = func() -> bool: return false
	_check(not editor.translate_selected(Vector2.ONE).ok and library.export_index() == clean,
		"failed durable publication leaves pixels, graph and history unchanged")
	library.publication_guard = Callable()
	_check(editor.undo().ok, "history remains usable after failed publication")
	var old_child_revision: int = library.children_for_asset(aid)[0]["revision"]
	_check(library.transform_child(aid, sibling_id, library.children_revision(aid),
		Transform2D(0.0, Vector2(8, 2))).ok, "external edit advances parent revision")
	var stale_snapshot: Dictionary = library.export_index()
	_check(editor.is_stale() and not editor.undo().ok and
		library.export_index() == stale_snapshot, "stale history cannot overwrite concurrent sibling")
	_check(not editor.select_child(sibling_id).ok, "stale parent requires explicit reload")
	editor.bind_parent(library, aid)
	_check(not editor.can_undo() and not editor.can_redo() and
		editor.selected_child_id.is_empty(), "reloading clears unsafe old parent history")
	_check(editor.select_child(sibling_id).ok and editor.translate_selected(Vector2.LEFT).ok,
		"after reload the sibling can be edited independently")
	_check(library.children_for_asset(aid)[0]["revision"] == old_child_revision,
		"independent sibling changes do not bump first child's revision")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	_check(reloaded.load().ok and _position(reloaded, aid, sibling_id) == Vector2(7, 2),
		"nested transform is durable across registry reload")
	# Exercise the real UI and prevent stale campaign shortcuts from targeting old data.
	var manager: AtlasObjectSourceManager = AtlasObjectSourceManager.new()
	root.add_child(manager)
	await process_frame
	manager.bind_library(library)
	manager.sources.select(manager._source_ids.find(aid))
	manager._update_actions()
	_check(manager.children_button != null and not manager.children_button.disabled,
		"Atlas Object Manager exposes nested editor for a published source")
	manager._open_children()
	var inspector: AtlasObjectChildInspector = manager.child_inspector
	_check(inspector.session.parent_source_id == aid and inspector.child_list.item_count == 2,
		"child inspector lists both unique instances")
	var selected_index: int = inspector._rows.find(child_id)
	inspector.child_list.select(selected_index)
	inspector.child_list.item_selected.emit(selected_index)
	_check(inspector.session.selected_child_id == child_id and
		not inspector.open_button.disabled, "live list selection binds exact child instance")
	var opened_ids: Array[String] = []
	manager.open_source_requested.connect(func(id: String) -> void: opened_ids.append(id))
	inspector.open_button.pressed.emit()
	_check(opened_ids == [bid], "Edit child source routes into existing Object Editor")
	var before_ui: Vector2 = _position(library, aid, child_id)
	(inspector.actions_node().get_node("MoveRight") as Button).pressed.emit()
	_check(_position(library, aid, child_id) == before_ui + Vector2.RIGHT,
		"real transform button publishes child-local movement")
	inspector.undo_button.pressed.emit()
	_check(_position(library, aid, child_id) == before_ui and not inspector.redo_button.disabled,
		"child inspector undo restores transform and exposes redo")
	inspector.redo_button.pressed.emit()
	_check(_position(library, aid, child_id) == before_ui + Vector2.RIGHT,
		"child inspector redo publishes the transformation again")
	var shortcut_move: InputEventKey = InputEventKey.new()
	shortcut_move.pressed = true
	shortcut_move.keycode = KEY_UP
	shortcut_move.alt_pressed = true
	inspector._unhandled_key_input(shortcut_move)
	_check(_position(library, aid, child_id) == before_ui + Vector2(1, -1),
		"Alt+Up moves the selected child in parent-local coordinates")
	var shortcut_undo: InputEventKey = InputEventKey.new()
	shortcut_undo.pressed = true
	shortcut_undo.keycode = KEY_Z
	shortcut_undo.ctrl_pressed = true
	inspector._unhandled_key_input(shortcut_undo)
	_check(_position(library, aid, child_id) == before_ui + Vector2.RIGHT,
		"Ctrl+Z undoes only the latest child transform")
	shortcut_undo.shift_pressed = true
	inspector._unhandled_key_input(shortcut_undo)
	_check(_position(library, aid, child_id) == before_ui + Vector2(1, -1),
		"Ctrl+Shift+Z redoes the child transform")
	var unrelated: InputEventKey = InputEventKey.new()
	unrelated.pressed = true
	unrelated.keycode = KEY_Z
	inspector._unhandled_key_input(unrelated)
	_check(_position(library, aid, child_id) == before_ui + Vector2(1, -1),
		"unmodified Z is ignored and cannot mutate a child")
	var edit_revision: int = library.children_revision(aid)
	_check(library.transform_child(aid, sibling_id, edit_revision, Transform2D.IDENTITY).ok,
		"external change while child inspector is open")
	var before_stale: Dictionary = library.export_index()
	(inspector.actions_node().get_node("MoveLeft") as Button).pressed.emit()
	_check(library.export_index() == before_stale and inspector.details.text.contains("reload"),
		"stale live inspector blocks an edit and displays recovery guidance")
	inspector.reload_button.pressed.emit()
	_check(inspector.session.selected_child_id.is_empty() and inspector.undo_button.disabled,
		"explicit Reload discards stale history and selection")
	manager.bind_library(reloaded)
	_check(inspector.session.library == null and not inspector.visible,
		"campaign rebinding closes and invalidates child inspector")
	manager._open_children()
	_check(inspector.session.library == reloaded and inspector.session.parent_source_id == aid
		and not inspector.session.can_undo(),
		"reopening after a campaign reload starts a fresh history against the new registry")
	manager.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CHILD_EDIT_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
