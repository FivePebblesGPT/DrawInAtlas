extends SceneTree
## T-064: stable, reversible parent-owned labels for repeated nested instances.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T064_CHILD_LABEL_FAILED: " + reason)


func _source(name: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	var edit: DrawingEditSession = doc.begin_edit(String(layer.value), doc.revision).value
	edit.fill_rect(Rect2i(0, 0, 1, 1), color)
	edit.commit()
	return doc


func _row(lib: AtlasObjectLibrary, parent_id: String, child_id: String) -> Dictionary:
	for item: Dictionary in lib.children_for_asset(parent_id):
		if String(item["id"]) == child_id:
			return item
	return {}


func _label(lib: AtlasObjectLibrary, parent_id: String, child_id: String) -> String:
	return String(_row(lib, parent_id, child_id).get("metadata", {}).get("label", ""))


func _erase(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for child: String in directory.get_directories():
		_erase(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-label-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var parent: DrawingResult = lib.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var source: DrawingResult = lib.create_asset(_source("Shared child", 0xff00ff00), "Shared child")
	_check(parent.ok and source.ok, "publish independent parent and reusable child pixels")
	if not parent.ok or not source.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var sid: String = String(source.value)
	var one: DrawingResult = lib.attach_child(pid, 0, sid, Transform2D.IDENTITY)
	var two: DrawingResult = lib.attach_child(pid, 1, sid, Transform2D(0.0, Vector2(4, 2)))
	_check(one.ok and two.ok, "attach two instances of the same published source")
	if not one.ok or not two.ok:
		quit(1)
		return
	var a: String = String(one.value)
	var b: String = String(two.value)
	var before_hash: String = String(lib.asset_info(sid)["sha256"])
	var before_revision: int = int(lib.asset_info(pid)["revision"])
	var original: Dictionary = lib.export_index()
	var row: Dictionary = _row(lib, pid, a)
	var rev: int = lib.children_revision(pid)
	_check(not lib.set_child_label(pid, a, rev + 1, String(row["generation"]),
		int(row["revision"]), "Near door").ok, "stale parent revision rejected")
	_check(not lib.set_child_label(pid, a, rev, "other-generation",
		int(row["revision"]), "Near door").ok, "stale child generation rejected")
	_check(not lib.set_child_label(pid, a, rev, String(row["generation"]),
		int(row["revision"]) + 1, "Near door").ok, "stale child revision rejected")
	_check(not lib.set_child_label(pid, "missing", rev, String(row["generation"]),
		int(row["revision"]), "Near door").ok, "unknown instance rejected")
	for invalid: String in [" trailing ", "\tTabbed", "line\nbreak", "bad\rreturn", "x".repeat(65)]:
		_check(not lib.set_child_label(pid, a, rev, String(row["generation"]),
			int(row["revision"]), invalid).ok, "invalid instance label rejected")
	_check(lib.export_index() == original and not lib._child_label_valid(" \t"),
		"invalid labels leave source and index unchanged")
	var no_change: DrawingResult = lib.set_child_label(pid, a, rev,
		String(row["generation"]), int(row["revision"]), "")
	_check(no_change.ok and no_change.value == false and lib.children_revision(pid) == rev,
		"clearing an already empty label is a no-op")
	lib.publication_guard = func() -> bool: return false
	var refused: DrawingResult = lib.set_child_label(pid, a, rev, String(row["generation"]),
		int(row["revision"]), "Near door")
	_check(not refused.ok and lib.export_index() == original,
		"publication veto leaves no staged label or revision")
	lib.publication_guard = Callable()
	var annotated: Array = lib.asset_info(pid).get("children", []).duplicate(true)
	(annotated[0]["metadata"] as Dictionary)["inventory_tag"] = "keep-me"
	var annotated_commit: DrawingResult = lib._replace_children(pid, rev, annotated)
	_check(annotated_commit.ok, "pre-existing unrelated child metadata may be published")
	rev = lib.children_revision(pid)
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(not session.label_selected("No selection").ok and not session.can_undo(),
		"cannot label an unselected child")
	_check(session.select_child(a).ok, "select first instance by stable ID")
	_check(session.label_selected("Near door").ok and _label(lib, pid, a) == "Near door" and
		_label(lib, pid, b).is_empty(), "label only the selected duplicate instance")
	_check(_row(lib, pid, a)["metadata"].get("inventory_tag") == "keep-me",
		"renaming retains unrelated primitive child metadata")
	_check(lib.children_revision(pid) == rev + 1 and
		int(_row(lib, pid, a)["revision"]) == int(row["revision"]) + 1,
		"label publication increments graph and child revision")
	_check(lib.asset_info(pid)["revision"] == before_revision and
		lib.asset_info(sid)["sha256"] == before_hash, "instance label never publishes or changes artwork")
	_check(session.label_selected("Near door").ok and session.label_selected("Near door").value == false and
		lib.children_revision(pid) == rev + 1, "reapplying identical label is a history-free no-op")
	_check(session.can_undo() and not session.can_redo(), "label creates one child history entry")
	_check(session.undo().ok and _label(lib, pid, a).is_empty(), "Undo removes initial label key")
	_check(session.redo().ok and _label(lib, pid, a) == "Near door", "Redo restores exact label")
	_check(session.label_selected("North doorway").ok and _label(lib, pid, a) == "North doorway",
		"later rename changes only parent-owned metadata")
	_check(session.undo().ok and _label(lib, pid, a) == "Near door",
		"Undo rename restores prior label")
	_check(session.redo().ok and _label(lib, pid, a) == "North doorway",
		"Redo rename restores updated label")
	_check(session.label_selected("").ok and not _row(lib, pid, a)["metadata"].has("label") and
		_row(lib, pid, a)["metadata"].get("inventory_tag") == "keep-me",
		"explicit blank removes only label metadata, not other annotations")
	_check(session.undo().ok and _label(lib, pid, a) == "North doorway",
		"Undo clear restores the old label")
	_check(session.translate_selected(Vector2(3, 0)).ok and
		session.set_selected_visibility(false).ok, "mixed transform and visibility follow same history")
	_check(session.undo().ok and session.undo().ok and session.undo().ok and
		_label(lib, pid, a) == "Near door", "mixed Undo reverses visibility, transform and latest label")
	_check(session.redo().ok and session.redo().ok and session.redo().ok and
		_label(lib, pid, a) == "North doorway" and not bool(_row(lib, pid, a)["visible"]),
		"mixed Redo restores label, transform and visibility")
	_check(session.undo().ok and session.label_selected("Changed branch").ok and
		not session.can_redo(), "new label edit after Undo discards abandoned Redo")
	var stale: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(stale.select_child(a).ok, "second editor sees persisted child identity")
	_check(session.label_selected("Active editor").ok and stale.is_stale(),
		"new label invalidates concurrent editor")
	var stable_index: Dictionary = lib.export_index()
	_check(not stale.label_selected("Stale edit").ok and not stale.undo().ok and
		lib.export_index() == stable_index, "stale editor cannot overwrite newer label")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reloaded.load().ok and _label(reloaded, pid, a) == "Active editor" and
		_label(reloaded, pid, b).is_empty(), "disk reload preserves independent per-instance labels")
	_check(reloaded.asset_info(sid)["sha256"] == before_hash and
		String(_row(reloaded, pid, a)["id"]) == a,
		"save preserves child identity and original published source")
	var copy_folder: String = OS.get_cache_dir().path_join("t064-label-copy-" + DrawingDocument.new_id())
	DirAccess.make_dir_recursive_absolute(copy_folder)
	var copy_path: String = copy_folder.path_join("Copied.scn")
	var copied: DrawingResult = reloaded.copy_objects_to(copy_path)
	var copy_library: AtlasObjectLibrary = AtlasObjectLibrary.new(copy_path)
	_check(copied.ok and copy_library.load().ok, "published Objects component copies with instance labels")
	_check(_label(copy_library, pid, a) == "Active editor" and _label(copy_library, pid, b).is_empty() and
		_row(copy_library, pid, a)["metadata"].get("inventory_tag") == "keep-me",
		"portable component copy retains labels and other parent-owned metadata")
	var copy_row: Dictionary = _row(copy_library, pid, a)
	var changed_copy: DrawingResult = copy_library.set_child_label(pid, a,
		copy_library.children_revision(pid), String(copy_row["generation"]),
		int(copy_row["revision"]), "Renamed in copy")
	_check(changed_copy.ok and _label(copy_library, pid, a) == "Renamed in copy" and
		_label(reloaded, pid, a) == "Active editor", "copied instance labels are independent from source campaign")
	_erase(copy_folder)
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reloaded, pid)
	_check(inspector.instance_label != null and inspector.apply_label_button != null and
		inspector.apply_label_button.disabled, "inspector label controls disabled until selection")
	_check(inspector.instance_label.tooltip_text.contains("does not rename") and
		inspector.apply_label_button.tooltip_text.contains("Undo"),
		"label control distinguishes instance from source and documents Undo")
	var idx: int = inspector._rows.find(a)
	inspector.child_list.select(idx)
	inspector.child_list.item_selected.emit(idx)
	_check(not inspector.apply_label_button.disabled and
		inspector.instance_label.text == "Active editor", "live inspector loads selected instance label")
	_check(inspector.child_list.get_item_text(idx).contains("Active editor (Shared child)"),
		"list shows custom label while preserving source identity")
	_check(inspector.child_list.get_item_tooltip(idx).contains("Instance: Active editor") and
		inspector.child_list.get_item_tooltip(idx).contains(sid),
		"full custom label and stable source ID remain readable in narrow tooltip")
	inspector.instance_label.text = "Kitchen entrance"
	inspector.apply_label_button.pressed.emit()
	_check(_label(reloaded, pid, a) == "Kitchen entrance" and inspector.session.can_undo(),
		"Apply label commits a reversible change")
	inspector.undo_button.pressed.emit()
	_check(_label(reloaded, pid, a) == "Active editor", "inspector Undo restores original label")
	inspector.redo_button.pressed.emit()
	_check(_label(reloaded, pid, a) == "Kitchen entrance", "inspector Redo reapplies label")
	idx = inspector._rows.find(b)
	inspector.child_list.select(idx)
	inspector.child_list.item_selected.emit(idx)
	_check(inspector.instance_label.text.is_empty(), "switching duplicates updates label editor")
	inspector.instance_label.text = "Back door"
	inspector.instance_label.text_submitted.emit("Back door")
	_check(_label(reloaded, pid, b) == "Back door" and _label(reloaded, pid, a) == "Kitchen entrance",
		"Enter commits selected duplicate independently")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			inspector.size = Vector2i(420, 600)
			inspector.show()
			await process_frame
			await process_frame
			var picture: Image = inspector.get_texture().get_image()
			var saved: Error = picture.save_png(argument.trim_prefix("--screenshot=")) if picture != null else ERR_CANT_OPEN
			_check(picture != null and picture.get_width() >= 390 and saved == OK,
				"native 420px inspector screenshot records instance label fields")
	var external: DrawingResult = reloaded.set_child_label(pid, b, reloaded.children_revision(pid),
		String(_row(reloaded, pid, b)["generation"]), int(_row(reloaded, pid, b)["revision"]), "External")
	var before_stale: Dictionary = reloaded.export_index()
	inspector.instance_label.text = "Overwrite"
	inspector.apply_label_button.pressed.emit()
	_check(external.ok and reloaded.export_index() == before_stale and
		inspector.details.text.contains("reload"), "stale inspector refuses overwrite and prompts Reload")
	inspector.reload_button.pressed.emit()
	_check(inspector.apply_label_button.disabled and inspector.session.selected_child_id.is_empty(),
		"explicit Reload clears stale history and disables label apply")
	inspector.queue_free()
	await process_frame
	_erase(folder)
	print("T064_CHILD_LABEL_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
