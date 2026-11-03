extends SceneTree
## T-064: duplicate an attached nested placement without copying source artwork.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CHILD_DUPLICATE_FAILED: " + name)


func _source(name: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	var edit: DrawingEditSession = doc.begin_edit(String(layer.value), doc.revision).value
	edit.fill_rect(Rect2i(0, 0, 1, 1), color)
	edit.commit()
	return doc


func _row(lib: AtlasObjectLibrary, parent_id: String, child_id: String) -> Dictionary:
	for row: Dictionary in lib.children_for_asset(parent_id):
		if String(row["id"]) == child_id:
			return row
	return {}


func _ids(lib: AtlasObjectLibrary, parent_id: String) -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in lib.children_for_asset(parent_id):
		ids.append(String(row["id"]))
	return ids


func _erase(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in dir.get_directories():
		_erase(path.path_join(name))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-duplicate-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var parent: DrawingResult = lib.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var source: DrawingResult = lib.create_asset(_source("Child", 0xff00ff00), "Child")
	var another: DrawingResult = lib.create_asset(_source("Other", 0xffff0000), "Other")
	_check(parent.ok and source.ok and another.ok, "publish three independent pixel sources")
	if not parent.ok or not source.ok or not another.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var sid: String = String(source.value)
	var a: DrawingResult = lib.attach_child(pid, 0, sid, Transform2D(0.0, Vector2(4, 4)))
	var b: DrawingResult = lib.attach_child(pid, 1, String(another.value), Transform2D(0.0, Vector2(4, 4)))
	_check(a.ok and b.ok, "attach overlapping published children")
	if not a.ok or not b.ok:
		quit(1)
		return
	var aid: String = String(a.value)
	var bid: String = String(b.value)
	var parent_revision: int = int(lib.asset_info(pid)["revision"])
	var source_hash: String = String(lib.asset_info(sid)["sha256"])
	var root_hash: String = String(lib.asset_info(pid)["sha256"])
	var row: Dictionary = _row(lib, pid, aid)
	var rev: int = lib.children_revision(pid)
	var before: Dictionary = lib.export_index()
	_check(not lib.duplicate_child_instance(pid, aid, rev + 1,
		String(row["generation"]), int(row["revision"])).ok,
		"stale parent revision rejects duplicate")
	_check(not lib.duplicate_child_instance(pid, aid, rev,
		"incorrect-generation", int(row["revision"])).ok,
		"wrong child generation rejects duplicate")
	_check(not lib.duplicate_child_instance(pid, aid, rev,
		String(row["generation"]), int(row["revision"]) + 1).ok,
		"stale child revision rejects duplicate")
	_check(not lib.duplicate_child_instance(pid, "unknown", rev,
		String(row["generation"]), int(row["revision"])).ok,
		"unknown child cannot be duplicated")
	for bad_offset: Vector2 in [Vector2(INF, 0.0), Vector2(NAN, 3.0), Vector2(1.0e38, 1.0e38)]:
		_check(not lib.duplicate_child_instance(pid, aid, rev, String(row["generation"]),
			int(row["revision"]), bad_offset).ok, "invalid or overflowing duplicate transform rejected")
	_check(lib.export_index() == before, "all invalid duplicates preserve the entire registry")
	lib.publication_guard = func() -> bool: return false
	_check(not lib.duplicate_child_instance(pid, aid, rev,
		String(row["generation"]), int(row["revision"])).ok and lib.export_index() == before,
		"durable-write veto is atomic")
	lib.publication_guard = Callable()
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(not session.duplicate_selected().ok and not session.can_undo(),
		"duplicate requires a selected child")
	_check(session.select_child(aid).ok and session.label_selected("Doorway").ok,
		"label original child through established parent history")
	_check(session.set_selected_visibility(false).ok and session.set_selected_visibility(true).ok,
		"visibility edits remain reversible before duplication")
	_check(session.translate_selected(Vector2(2, -1)).ok, "source may be transformed before duplication")
	var current: Dictionary = _row(lib, pid, aid)
	var previous_selection: String = session.selected_child_id
	var copied: DrawingResult = session.duplicate_selected(Vector2(1, 2))
	_check(copied.ok and session.can_undo() and not session.can_redo(), "duplicate creates one reversible edit")
	if not copied.ok:
		quit(1)
		return
	var cid: String = String(copied.value)
	var duplicate: Dictionary = _row(lib, pid, cid)
	_check(not duplicate.is_empty() and cid != aid and
		String(duplicate["generation"]) != String(current["generation"]),
		"duplicate has fresh stable ID and generation")
	_check(duplicate["source_id"] == sid and int(duplicate["revision"]) == 0 and
		duplicate["metadata"] == current["metadata"] and duplicate["visible"] == current["visible"],
		"duplicate shares published source but copies parent-local layout metadata")
	_check(duplicate["transform"][4] == float(current["transform"][4]) + 1.0 and
		duplicate["transform"][5] == float(current["transform"][5]) + 2.0 and
		duplicate["transform"].slice(0, 4) == current["transform"].slice(0, 4),
		"duplicate has offset origin and identical affine basis")
	_check(_ids(lib, pid) == [aid, cid, bid] and session.selected_child_id == cid,
		"duplicate inserts immediately above original and becomes selected")
	_check(lib.children_revision(pid) == rev + 5 and lib.asset_info(pid)["revision"] == parent_revision and
		lib.asset_info(pid)["sha256"] == root_hash and lib.asset_info(sid)["sha256"] == source_hash,
		"copy commits graph only, never republishing source pixels")
	var placed: DrawingResult = lib.place(pid, "map", "floor", "D0", Transform2D.IDENTITY)
	_check(placed.ok, "place parent containing both referenced children")
	var original_point: Vector2 = Vector2(float(current["transform"][4]) + 0.5,
		float(current["transform"][5]) + 0.5)
	var copied_point: Vector2 = original_point + Vector2(1, 2)
	var hit_original: DrawingResult = lib.hit_test_path(String(placed.value), original_point)
	var hit_copy: DrawingResult = lib.hit_test_path(String(placed.value), copied_point)
	_check(hit_original.ok and hit_copy.ok and
		String((hit_original.value["path"] as PackedStringArray)[0]) == aid and
		String((hit_copy.value["path"] as PackedStringArray)[0]) == cid,
		"original and duplicate have independent hit paths")
	var pixels: DrawingResult = lib.render_source_tree(pid, Rect2i(0, 0, 14, 14))
	_check(pixels.ok and pixels.value.get_pixelv(Vector2i(int(original_point.x), int(original_point.y))).g > 0.9 and
		pixels.value.get_pixelv(Vector2i(int(copied_point.x), int(copied_point.y))).g > 0.9,
		"both instances render the same published source pixels")
	_check(session.undo().ok and _ids(lib, pid) == [aid, bid] and session.selected_child_id == previous_selection,
		"Undo removes only new instance and returns selection to original")
	_check(session.redo().ok and _ids(lib, pid) == [aid, cid, bid] and session.selected_child_id == cid,
		"Redo restores identical placement identity and sibling position")
	_check(String(_row(lib, pid, cid)["generation"]) == String(duplicate["generation"]),
		"replayed duplicate keeps original generation")
	_check(session.undo().ok and session.undo().ok and _ids(lib, pid) == [aid, bid],
		"mixed history can undo duplicate and prior transform")
	_check(session.redo().ok and session.redo().ok and _ids(lib, pid) == [aid, cid, bid],
		"mixed history replays transform then duplicate")
	_check(session.translate_selected(Vector2(3, 0)).ok and
		_row(lib, pid, aid)["transform"] == current["transform"],
		"moving duplicated instance does not move original")
	_check(session.undo().ok, "Undo movement of copy")
	_check(session.undo().ok and session.select_child(aid).ok and session.label_selected("New branch").ok and
		not session.can_redo(), "new branch after duplicate Undo discards abandoned Redo")
	var stale: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(stale.select_child(aid).ok, "other editor holds the published revision")
	_check(session.duplicate_selected(Vector2.ZERO).ok and stale.is_stale(),
		"new duplicate invalidates concurrent editor with intentional overlap")
	var locked_snapshot: Dictionary = lib.export_index()
	_check(not stale.duplicate_selected().ok and not stale.undo().ok and
		lib.export_index() == locked_snapshot,
		"concurrent stale editor cannot publish or replay")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reloaded.load().ok and _ids(reloaded, pid).size() == 3 and
		_row(reloaded, pid, session.selected_child_id)["metadata"].get("label") == "New branch",
		"disk reload retains instance identity, order, and copied metadata")
	var extra_id: String = session.selected_child_id
	_check(reloaded.asset_info(sid)["sha256"] == source_hash and
		_row(reloaded, pid, extra_id)["source_id"] == sid,
		"disk reload uses same unchanged published artwork")
	var copy_root: String = OS.get_cache_dir().path_join("t064-duplicate-copy-" + DrawingDocument.new_id())
	DirAccess.make_dir_recursive_absolute(copy_root)
	var copy_path: String = copy_root.path_join("Duplicate.scn")
	var portable: DrawingResult = reloaded.copy_objects_to(copy_path)
	var target: AtlasObjectLibrary = AtlasObjectLibrary.new(copy_path)
	_check(portable.ok and target.load().ok and _ids(target, pid) == _ids(reloaded, pid),
		"portable copy retains both independently identified shared-source instances")
	_check(target.asset_info(sid)["sha256"] == source_hash and
		_row(target, pid, extra_id)["metadata"] == _row(reloaded, pid, extra_id)["metadata"],
		"copied registry preserves source hash and child metadata")
	_erase(copy_root)
	# The duplicate must not resolve a replaced or missing source, even when
	# its in-memory registry record and child ID are otherwise current.
	var actual_source: String = folder.path_join(String(reloaded.asset_info(sid)["path"]))
	var missing_source: String = actual_source + ".temporarily-missing"
	var before_missing: Dictionary = reloaded.export_index()
	_check(DirAccess.rename_absolute(actual_source, missing_source) == OK,
		"temporarily remove the published source without changing registry metadata")
	var existing: Dictionary = _row(reloaded, pid, aid)
	_check(not reloaded.duplicate_child_instance(pid, aid, reloaded.children_revision(pid),
		String(existing["generation"]), int(existing["revision"])).ok and
		reloaded.export_index() == before_missing,
		"missing published source refuses duplicate without touching the index")
	_check(DirAccess.rename_absolute(missing_source, actual_source) == OK and
		reloaded.asset_exists(sid), "restore and revalidate the same source hash")

	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reloaded, pid)
	_check(inspector.duplicate_button != null and inspector.duplicate_button.disabled,
		"inspector duplication action disabled without a selection")
	_check(inspector.duplicate_button.tooltip_text.contains("source pixels are shared") and
		inspector.duplicate_button.tooltip_text.contains("Undo"),
		"control describes linked source semantics and undo")
	var index: int = inspector._rows.find(aid)
	inspector.child_list.select(index)
	inspector.child_list.item_selected.emit(index)
	_check(not inspector.duplicate_button.disabled, "inspector enables duplication for linked source")
	var ids_before_ui: Array[String] = _ids(reloaded, pid)
	inspector.duplicate_button.pressed.emit()
	var ui_copy: String = inspector.session.selected_child_id
	_check(_ids(reloaded, pid).size() == ids_before_ui.size() + 1 and
		ui_copy != aid and _ids(reloaded, pid).find(ui_copy) == _ids(reloaded, pid).find(aid) + 1,
		"live duplicate button creates adjacent linked instance")
	_check(inspector.details.text.contains("Undo available") and inspector.session.can_undo(),
		"UI confirms transaction is reversible")
	inspector.undo_button.pressed.emit()
	_check(_ids(reloaded, pid) == ids_before_ui and inspector.session.selected_child_id == aid,
		"UI Undo removes new instance and restores selection")
	inspector.redo_button.pressed.emit()
	_check(_ids(reloaded, pid).find(ui_copy) == _ids(reloaded, pid).find(aid) + 1,
		"UI Redo restores same duplicated identity")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			inspector.size = Vector2i(420, 600)
			inspector.show()
			await process_frame
			await process_frame
			var picture: Image = inspector.get_texture().get_image()
			var status: Error = picture.save_png(argument.trim_prefix("--screenshot=")) if picture != null else ERR_CANT_OPEN
			_check(picture != null and picture.get_width() >= 390 and status == OK,
				"native narrow inspector screenshot captured")
	var external: DrawingResult = reloaded.attach_child(pid, reloaded.children_revision(pid),
		String(another.value), Transform2D.IDENTITY)
	var ui_index: Dictionary = reloaded.export_index()
	inspector.duplicate_button.pressed.emit()
	_check(external.ok and reloaded.export_index() == ui_index and
		inspector.details.text.contains("reload"), "stale inspector refuses duplicate and prompts reload")
	inspector.reload_button.pressed.emit()
	_check(inspector.duplicate_button.disabled and inspector.session.selected_child_id.is_empty(),
		"explicit reload clears stale selection and controls")
	inspector.queue_free()
	await process_frame
	# Exercise the provisional 64-child limit without 64 separate publications.
	var children: Array = reloaded.asset_info(pid).get("children", []).duplicate(true)
	while children.size() < AtlasObjectChildGraph.MAX_CHILDREN_PER_SOURCE:
		var extra: Dictionary = children[0].duplicate(true)
		extra["id"] = AtlasObjectLibrary._new_id("child")
		extra["generation"] = AtlasObjectLibrary._new_id("generation")
		extra["revision"] = 0
		children.append(extra)
	var capped: DrawingResult = reloaded._replace_children(pid,
		reloaded.children_revision(pid), children)
	_check(capped.ok and reloaded.children_for_asset(pid).size() == 64,
		"fill parent to validated 64-child graph limit")
	var capped_row: Dictionary = _row(reloaded, pid, aid)
	var full_snapshot: Dictionary = reloaded.export_index()
	_check(not reloaded.duplicate_child_instance(pid, aid, reloaded.children_revision(pid),
		String(capped_row["generation"]), int(capped_row["revision"])).ok and
		reloaded.export_index() == full_snapshot,
		"limit refusal retains all sibling IDs and unchanged revisions")
	# Separate the UI fixture from the limit snapshot by reloading its original
	# revision in a fresh copied campaign before exercising live button actions.
	_erase(folder)
	print("T064_CHILD_DUPLICATE_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
