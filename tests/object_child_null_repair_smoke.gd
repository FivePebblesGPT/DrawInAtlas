extends SceneTree
## T-064: explicit NULL-child source repair, history and inspector UI.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CHILD_REPAIR_FAILED: " + label)


func _source(label: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(label, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if layer.ok:
		var edit: DrawingResult = doc.begin_edit(String(layer.value), doc.revision)
		if edit.ok:
			edit.value.fill_rect(Rect2i(0, 0, 1, 1), color)
			edit.value.commit()
	return doc


func _child(lib: AtlasObjectLibrary, parent_id: String, child_id: String) -> Dictionary:
	for child: Dictionary in lib.children_for_asset(parent_id):
		if child["id"] == child_id:
			return child
	return {}


func _pixel(lib: AtlasObjectLibrary, source_id: String, point: Vector2i) -> Color:
	var result: DrawingResult = lib.render_source_tree(source_id, Rect2i(point, Vector2i.ONE))
	return (result.value as Image).get_pixel(0, 0) if result.ok else Color.TRANSPARENT


func _erase(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in dir.get_directories():
		_erase(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-null-repair-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var parent: DrawingResult = library.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var removed: DrawingResult = library.create_asset(_source("Old", 0xff00ff00), "Old")
	var replacement: DrawingResult = library.create_asset(_source("Replacement", 0xffff0000), "Replacement")
	var indirect: DrawingResult = library.create_asset(_source("Indirect", 0xffffffff), "Indirect")
	_check(parent.ok and removed.ok and replacement.ok and indirect.ok, "publish independent sources")
	if not parent.ok or not removed.ok or not replacement.ok or not indirect.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var old_id: String = String(removed.value)
	var new_id: String = String(replacement.value)
	var cycle_id: String = String(indirect.value)
	var attached: DrawingResult = library.attach_child(pid, 0, old_id,
		Transform2D(0.0, Vector2(7, -5)))
	_check(attached.ok and library.attach_child(cycle_id, 0, pid).ok,
		"create child and indirect cycle candidate")
	var child_id: String = String(attached.value)
	var original: Dictionary = _child(library, pid, child_id)
	_check(original["status"] == "linked" and _pixel(library, pid, Vector2i(7, -5)).g > 0.9,
		"nested source initially renders its old pixel")
	var preview: DrawingResult = library.preview_delete_asset(old_id)
	_check(preview.ok and preview.value["child_bindings"].size() == 1,
		"delete confirmation identifies nested reference")
	_check(library.delete_asset(old_id, "null", preview.value).ok,
		"delete retains explicitly selected NULL reference")
	var missing: Dictionary = _child(library, pid, child_id)
	_check(missing["status"] == "NULL" and missing["placeholder"] and
		missing["source_id"] == old_id and missing["generation"] == original["generation"] and
		missing["transform"] == original["transform"],
		"NULL retains child source identity, stable generation and transform")
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(library, pid)
	_check(session.select_child(child_id).ok and not session.can_undo(),
		"fresh session selects the missing child without inventing history")
	var before: Dictionary = library.export_index()
	var revision: int = int(missing["revision"])
	var parent_rev: int = library.children_revision(pid)
	_check(not library.repair_child_placeholder(pid, child_id, parent_rev + 1,
		String(missing["generation"]), revision, new_id).ok,
		"reject stale parent generation")
	_check(not library.repair_child_placeholder(pid, child_id, parent_rev,
		"wrong-generation", revision, new_id).ok,
		"reject mismatched child generation")
	_check(not library.repair_child_placeholder(pid, child_id, parent_rev,
		String(missing["generation"]), revision + 1, new_id).ok,
		"reject stale child revision")
	_check(not library.repair_child_placeholder(pid, child_id, parent_rev,
		String(missing["generation"]), revision, old_id).ok,
		"missing retired source cannot be chosen as replacement")
	var cyclic: DrawingResult = session.repair_selected(cycle_id)
	_check(not cyclic.ok and cyclic.code == "CHILD_CYCLE" and library.export_index() == before,
		"indirect cycle rejected by the full graph validator without publication")
	var direct: DrawingResult = session.repair_selected(pid)
	_check(not direct.ok and direct.code == "CHILD_CYCLE" and library.export_index() == before,
		"direct self-cycle rejected with no mutation")
	_check(not session.can_undo() and not session.can_redo(),
		"failed repairs do not create undo entries")
	library.publication_guard = func() -> bool: return false
	var denied: DrawingResult = session.repair_selected(new_id)
	_check(not denied.ok and library.export_index() == before and not session.can_undo(),
		"publication veto keeps NULL and leaves history unchanged")
	library.publication_guard = Callable()
	var repaired: DrawingResult = session.repair_selected(new_id)
	_check(repaired.ok and repaired.value == child_id and session.can_undo() and not session.can_redo(),
		"explicit replacement repairs one child and records one history action")
	var bound: Dictionary = _child(library, pid, child_id)
	_check(bound["status"] == "linked" and not bound["placeholder"] and
		bound["source_id"] == new_id and bound["metadata"].get("null_origin_source_id", "") == old_id,
		"repaired binding records original NULL source identity")
	_check(bound["generation"] == missing["generation"] and bound["id"] == missing["id"] and
		bound["transform"] == missing["transform"] and int(bound["revision"]) == revision + 1,
		"no child relocation or duplicate identity; child revision advances once")
	_check(library.asset_info(pid)["revision"] == 1 and
		_pixel(library, pid, Vector2i(7, -5)).b > 0.9,
		"replacement source immediately renders without modifying parent source pixels")
	var snap: Dictionary = library.export_index()
	_check(not session.repair_selected(new_id).ok and library.export_index() == snap,
		"cannot repair an already linked child")
	_check(session.undo().ok and _child(library, pid, child_id)["status"] == "NULL" and
		_child(library, pid, child_id)["source_id"] == old_id and session.can_redo(),
		"undo returns the exact original NULL binding")
	_check(_child(library, pid, child_id)["metadata"] == missing["metadata"] and
		int(_child(library, pid, child_id)["revision"]) > int(bound["revision"]),
		"undo restores original metadata but monotonically advances revision")
	_check(session.redo().ok and _child(library, pid, child_id)["source_id"] == new_id and
		_child(library, pid, child_id)["metadata"].get("null_origin_source_id") == old_id,
		"redo recreates original explicit binding without changing identity")
	_check(session.undo().ok and session.redo().ok,
		"repeated undo/redo is stable despite advancing child revisions")
	_check(session.translate_selected(Vector2(2, 0)).ok and
		_child(library, pid, child_id)["transform"][4] == 9.0,
		"translation follows repaired binding on the same history timeline")
	_check(session.undo().ok and _child(library, pid, child_id)["transform"][4] == 7.0,
		"transform undo does not undo source repair")
	_check(session.undo().ok and _child(library, pid, child_id)["status"] == "NULL",
		"second undo returns to original deleted source")
	_check(session.redo().ok and _child(library, pid, child_id)["status"] == "linked",
		"repair can be replayed after transform history")
	var reopened: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reopened.load().ok and _child(reopened, pid, child_id)["source_id"] == new_id and
		_child(reopened, pid, child_id)["metadata"].get("null_origin_source_id") == old_id,
		"registry reload preserves repaired source and origin metadata")
	_check(_pixel(reopened, pid, Vector2i(7, -5)).b > 0.9,
		"reopened parent renders the replacement nested source")
	var stale_session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(reopened, pid)
	_check(stale_session.select_child(child_id).ok, "select repaired child in another session")
	var earlier: Dictionary = reopened.export_index()
	_check(reopened.transform_child(pid, child_id, reopened.children_revision(pid),
		Transform2D(0.0, Vector2(10, -6))).ok, "simulate independent concurrent parent edit")
	var changed: Dictionary = reopened.export_index()
	_check(stale_session.is_stale() and not stale_session.repair_selected(new_id).ok and
		changed == reopened.export_index(), "stale session cannot overwrite concurrent binding")
	_check(not stale_session.undo().ok and not stale_session.redo().ok and
		changed == reopened.export_index(), "stale session cannot replay older operations")
	_check(earlier != changed, "external transform updates the index atomically")
	# Test the real inspector controls on a separate fresh missing child.
	var second: DrawingResult = reopened.attach_child(pid, reopened.children_revision(pid), new_id)
	_check(second.ok, "attach a second current child for independent NULL handling")
	var second_id: String = String(second.value)
	# Turning it into an explicit NULL must use deletion, preserving the first repaired child as NULL too.
	var pending_delete: DrawingResult = reopened.preview_delete_asset(new_id)
	_check(pending_delete.ok and reopened.delete_asset(new_id, "null", pending_delete.value).ok,
		"delete replacement produces NULL children with stable IDs")
	var new_target: DrawingResult = reopened.create_asset(_source("New target", 0xff80ffff), "New target")
	_check(new_target.ok, "publish a verified replacement for the inspector")
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reopened, pid)
	_check(inspector.repair_button != null and inspector.repair_button.disabled,
		"inspector exposes repair button disabled until NULL selection")
	var row_index: int = inspector._rows.find(second_id)
	inspector.child_list.select(row_index)
	inspector.child_list.item_selected.emit(row_index)
	_check(row_index >= 0 and not inspector.repair_button.disabled,
		"selecting NULL enables explicit repair action")
	var target_index: int = inspector._candidate_ids.find(String(new_target.value))
	_check(target_index >= 0, "replacement picker lists verified published sources")
	inspector.source_picker.select(target_index)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			inspector.show()
			await process_frame
			await process_frame
			var snapshot: Image = inspector.get_texture().get_image()
			_check(snapshot != null and snapshot.get_width() >= 390 and
				snapshot.save_png(argument.trim_prefix("--screenshot=")) == OK,
				"native inspector screenshot captures the NULL repair affordance")
	inspector.repair_button.pressed.emit()
	_check(_child(reopened, pid, second_id)["source_id"] == String(new_target.value) and
		_child(reopened, pid, second_id)["status"] == "linked" and inspector.repair_button.disabled,
		"actual Repair button rebinds selected NULL and disables until next NULL")
	_check(inspector.undo_button.disabled == false, "inspector exposes repair in local undo timeline")
	inspector.undo_button.pressed.emit()
	_check(_child(reopened, pid, second_id)["status"] == "NULL" and
		not inspector.repair_button.disabled, "inspector Undo restores NULL and repair affordance")
	inspector.redo_button.pressed.emit()
	_check(_child(reopened, pid, second_id)["status"] == "linked" and
		inspector.repair_button.disabled, "inspector Redo restores chosen linked source")
	inspector.queue_free()
	await process_frame
	_erase(folder)
	print("T064_CHILD_REPAIR_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
