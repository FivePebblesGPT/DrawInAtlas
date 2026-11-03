extends SceneTree
## T-064: structural child edits and reversible, source-safe parent-local history.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T064_CHILD_STRUCTURE_FAILED: " + label)


func _ids(library: AtlasObjectLibrary, parent_id: String) -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in library.children_for_asset(parent_id):
		ids.append(String(row["id"]))
	return ids


func _row(library: AtlasObjectLibrary, parent_id: String, child_id: String) -> Dictionary:
	for record: Dictionary in library.children_for_asset(parent_id):
		if record["id"] == child_id:
			return record
	return {}


func _erase_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for subdir: String in dir.get_directories():
		_erase_tree(path.path_join(subdir))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-structure-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var document: DrawingDocument = DrawingDocument.new("T064 structure", 16)
	var parent: DrawingResult = library.create_asset(document, "Parent")
	var first: DrawingResult = library.create_asset(document, "A")
	var second: DrawingResult = library.create_asset(document, "B")
	_check(parent.ok and first.ok and second.ok, "publish available independent sources")
	if not parent.ok or not first.ok or not second.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var aid: String = String(first.value)
	var bid: String = String(second.value)
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(library, pid)
	var attached: DrawingResult = session.attach_source(aid, Transform2D(0.0, Vector2(-8, 4)))
	_check(attached.ok and session.can_undo() and not session.can_redo(),
		"attach creates an undoable parent-local action")
	var child_a: String = String(attached.value)
	var original: Dictionary = _row(library, pid, child_a)
	_check(original.get("source_id") == aid and session.selected_child_id == child_a and
		original["transform"][4] == -8.0, "attach uses exact source, selection and local transform")
	_check(library.asset_info(pid)["revision"] == 1 and library.children_revision(pid) == 1,
		"attaching does not republish parent pixels")
	_check(session.undo().ok and library.children_for_asset(pid).is_empty() and
		session.selected_child_id.is_empty(), "undo attach removes only the new instance")
	_check(not session.can_undo() and session.can_redo(), "structural undo exposes redo")
	_check(session.redo().ok and _ids(library, pid) == [child_a] and
		_row(library, pid, child_a)["generation"] == original["generation"],
		"redo attach restores exact stable child identity")
	_check(int(_row(library, pid, child_a)["revision"]) > int(original["revision"]),
		"restoring a removed instance advances its child revision")
	_check(session.translate_selected(Vector2(3, 1)).ok and
		_row(library, pid, child_a)["transform"][4] == -5.0,
		"transform and attachment share the same history")
	_check(session.undo().ok and _row(library, pid, child_a)["transform"][4] == -8.0,
		"first undo reverses transform, not attachment")
	_check(session.undo().ok and library.children_for_asset(pid).is_empty(),
		"second undo reverses attachment")
	_check(session.redo().ok and session.redo().ok and
		_row(library, pid, child_a)["transform"][4] == -5.0,
		"redo replays attach then translation in order")
	var attached_b: DrawingResult = session.attach_source(bid)
	_check(attached_b.ok and session.selected_child_id == String(attached_b.value),
		"attach second child selects the new instance")
	var child_b: String = String(attached_b.value)
	var child_b_generation: String = String(_row(library, pid, child_b)["generation"])
	var another: DrawingResult = session.attach_source(aid)
	_check(another.ok and _ids(library, pid).size() == 3, "attach multiple independent children")
	var child_c: String = String(another.value)
	_check(session.select_child(child_b).ok and session.detach_selected().ok and
		_ids(library, pid) == [child_a, child_c], "detach selected middle child preserves sibling order")
	_check(session.selected_child_id.is_empty() and session.can_undo(),
		"detach clears selection but enables structural undo")
	_check(session.undo().ok and _ids(library, pid) == [child_a, child_b, child_c] and
		_row(library, pid, child_b)["generation"] == child_b_generation,
		"undo detach restores original index and identity")
	_check(session.redo().ok and _ids(library, pid) == [child_a, child_c],
		"redo detach removes the same middle identity")
	_check(session.undo().ok and _ids(library, pid) == [child_a, child_b, child_c],
		"repeated structural history remains reversible")
	_check(session.select_child(child_b).ok and session.detach_selected().ok,
		"new removal after undo replaces abandoned redo branch")
	_check(session.can_undo() and not session.can_redo(),
		"structural edit invalidates divergent redo")
	var before_failure: Dictionary = library.export_index()
	_check(not session.attach_source(pid).ok and library.export_index() == before_failure,
		"self-link rejected by graph validator without publication")
	_check(not session.attach_source("missing-source").ok and library.export_index() == before_failure,
		"unknown child source rejected without publication")
	_check(not session.attach_source(aid, Transform2D(Vector2.ZERO, Vector2.ZERO,
		Vector2.ZERO)).ok and library.export_index() == before_failure,
		"singular transform rejected without publication")
	_check(session.can_undo() and not session.can_redo(),
		"failed attaches do not insert history entries")
	library.publication_guard = func() -> bool: return false
	_check(not session.attach_source(aid).ok and library.export_index() == before_failure,
		"failed atomic attach does not mutate graph or history")
	_check(not session.detach_selected().ok and library.export_index() == before_failure,
		"failed atomic detach does not mutate graph or history")
	library.publication_guard = Callable()
	_check(session.undo().ok and session.can_redo(),
		"history is still usable after refused publications")
	var stale_session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(library, pid)
	_check(stale_session.select_child(child_b).ok, "another session can select a current child")
	var valid_attach: DrawingResult = session.attach_source(bid)
	_check(valid_attach.ok, "primary session can publish another child")
	var stale_snapshot: Dictionary = library.export_index()
	_check(stale_session.is_stale() and not stale_session.detach_selected().ok and
		stale_snapshot == library.export_index(), "concurrent revision blocks stale structural detach")
	_check(not stale_session.attach_source(aid).ok and stale_snapshot == library.export_index(),
		"concurrent revision blocks stale structural attach")
	var saved: Dictionary = _row(library, pid, String(valid_attach.value)).duplicate(true)
	saved.erase("status")
	var before_replay: Dictionary = library.export_index()
	_check(not library._restore_child_snapshot(pid, library.children_revision(pid), saved, 0).ok and
		library.export_index() == before_replay, "duplicate stable child ID cannot be restored")
	_check(not library._restore_child_snapshot(pid, library.children_revision(pid), saved, 999).ok and
		library.export_index() == before_replay, "invalid restored sibling index rejected")
	var changed: Dictionary = saved.duplicate(true)
	changed["id"] = "child-safe-unique"
	changed["source_id"] = pid
	_check(not library._restore_child_snapshot(pid, library.children_revision(pid), changed, 0).ok and
		library.export_index() == before_replay, "restored self-cycle fails closed")
	var opened: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	_check(opened.load().ok and _ids(opened, pid) == _ids(library, pid),
		"parent registry reload preserves exact source order")
	# Exercise the actual Inspector's attach/remove selectors and button callbacks.
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(opened, pid)
	_check(inspector.attach_button != null and inspector.detach_button != null and
		inspector.source_picker.item_count >= 2 and not inspector._candidate_ids.has(pid),
		"inspector exposes source picker and explicit structural actions")
	inspector.source_filter.text = "not-found-in-catalog"
	inspector.refresh()
	_check(inspector.attach_button.disabled and inspector.source_picker.item_count == 0,
		"unmatched search disables attachment without selecting a fallback")
	inspector.source_filter.text = "A"
	inspector.refresh()
	_check(inspector.source_picker.item_count >= 1 and not inspector.attach_button.disabled,
		"filtered published-source search enables only matching source choices")
	inspector.source_filter.text = ""
	inspector.refresh()
	var choose: int = inspector._candidate_ids.find(aid)
	inspector.source_picker.select(choose)
	var initial_size: int = opened.children_for_asset(pid).size()
	inspector.attach_button.pressed.emit()
	_check(opened.children_for_asset(pid).size() == initial_size + 1 and
		inspector.session.selected_child_id == _ids(opened, pid).back(),
		"Attach button creates/selects a new child from the explicit source picker")
	var new_child: String = inspector.session.selected_child_id
	inspector.detach_button.pressed.emit()
	_check(opened.children_for_asset(pid).size() == initial_size and
		_row(opened, pid, new_child).is_empty(), "Remove button detaches instance, not its source")
	inspector.undo_button.pressed.emit()
	_check(opened.children_for_asset(pid).size() == initial_size + 1 and
		inspector.session.selected_child_id == new_child,
		"inspector Undo restores detached child with stable identity")
	inspector.undo_button.pressed.emit()
	_check(opened.children_for_asset(pid).size() == initial_size and
		_row(opened, pid, new_child).is_empty(), "inspector second Undo removes original attachment")
	inspector.redo_button.pressed.emit()
	inspector.redo_button.pressed.emit()
	_check(opened.children_for_asset(pid).size() == initial_size and
		_row(opened, pid, new_child).is_empty(), "inspector redo replays attach then detach")
	var child_metadata: Dictionary = opened.asset_info(aid)
	_check(int(child_metadata["revision"]) == 1 and opened.asset_exists(aid),
		"attach/remove never changes immutable child source pixels")
	inspector.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CHILD_STRUCTURE_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
