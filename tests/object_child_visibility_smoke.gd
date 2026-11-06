extends SceneTree
## T-064: reversible nested visibility through one published parent layout.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CHILD_VISIBILITY_FAILED: " + label)


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


func _color(lib: AtlasObjectLibrary, root_id: String, at: Vector2i) -> Color:
	var rendered: DrawingResult = lib.render_source_tree(root_id, Rect2i(at, Vector2i.ONE))
	return rendered.value.get_pixel(0, 0) if rendered.ok else Color.TRANSPARENT


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
	var folder: String = OS.get_cache_dir().path_join("t064-visibility-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var parent: DrawingResult = lib.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var child: DrawingResult = lib.create_asset(_source("Child", 0xff00ff00), "Child")
	var grandchild: DrawingResult = lib.create_asset(_source("Grandchild", 0xffff0000), "Grandchild")
	_check(parent.ok and child.ok and grandchild.ok, "publish independent source pixels")
	if not parent.ok or not child.ok or not grandchild.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var cid: String = String(child.value)
	var gid: String = String(grandchild.value)
	var joined: DrawingResult = lib.attach_child(pid, 0, cid, Transform2D(0.0, Vector2(5, 0)))
	var deep: DrawingResult = lib.attach_child(cid, 0, gid, Transform2D(0.0, Vector2(2, 0)))
	_check(joined.ok and deep.ok, "attach child and grandchild with independent transforms")
	var child_id: String = String(joined.value)
	var original: Dictionary = _row(lib, pid, child_id).duplicate(true)
	var placement: DrawingResult = lib.place(pid, "world", "ground", "D0", Transform2D.IDENTITY)
	_check(placement.ok and _color(lib, pid, Vector2i(5, 0)).g > 0.9 and
		_color(lib, pid, Vector2i(7, 0)).b > 0.9, "source and descendant initially render")
	var instance_id: String = String(placement.value)
	var timeline: AtlasEditHistory = AtlasEditHistory.new()
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	timeline.reset(campaign)
	var adapter: AtlasDrawingComposition = AtlasDrawingComposition.new(timeline, lib)
	_check(adapter.attach_campaign(campaign).ok, "Atlas composition listens to published child changes")
	var region: Rect2i = Rect2i(0, -1, 12, 4)
	var before_map: DrawingResult = adapter.render_region("world", "ground", 0, region)
	_check(before_map.ok and before_map.value.get_pixel(5, 1).g > 0.9,
		"Atlas map caches visible nested child")
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(session.select_child(child_id).ok and session.selected_record()["visible"],
		"select linked child in parent-local inspector")
	var rev: int = lib.children_revision(pid)
	var generation: String = String(original["generation"])
	_check(not lib.set_child_visibility(pid, child_id, rev + 1,
		generation, int(original["revision"]), false).ok,
		"stale parent revision cannot hide child")
	_check(not lib.set_child_visibility(pid, child_id, rev,
		"replaced-generation", int(original["revision"]), false).ok,
		"incorrect stable generation cannot mutate child")
	_check(not lib.set_child_visibility(pid, child_id, rev,
		generation, int(original["revision"]) + 1, false).ok,
		"stale child revision cannot mutate child")
	_check(not lib.set_child_visibility(pid, "missing-child", rev,
		generation, int(original["revision"]), false).ok,
		"unknown child ID cannot mutate parent")
	_check(lib.children_revision(pid) == rev and _row(lib, pid, child_id) == original,
		"failed optimistic checks do not dirty parent or child")
	var no_op: DrawingResult = session.set_selected_visibility(true)
	_check(no_op.ok and no_op.value == false and not session.can_undo() and
		lib.children_revision(pid) == rev, "already-visible request is a true no-op")
	lib.publication_guard = func() -> bool: return false
	var snapshot: Dictionary = lib.export_index()
	_check(not session.set_selected_visibility(false).ok and lib.export_index() == snapshot and
		not session.can_undo(), "vetoed publication leaves index and history intact")
	lib.publication_guard = Callable()
	_check(session.toggle_selected_visibility().ok and session.can_undo(),
		"Hide child publishes exactly one parent-local action")
	var hidden: Dictionary = _row(lib, pid, child_id)
	_check(not hidden["visible"] and hidden["id"] == original["id"] and
		hidden["generation"] == original["generation"] and
		hidden["source_id"] == original["source_id"] and
		hidden["transform"] == original["transform"],
		"hidden reference retains stable ID, generation, source and transform")
	_check(int(hidden["revision"]) == int(original["revision"]) + 1 and
		lib.children_revision(pid) == rev + 1 and lib.asset_info(pid)["revision"] == 1,
		"child/layout revision advances without republishing parent pixels")
	_check(_color(lib, pid, Vector2i(0, 0)).r > 0.9 and
		_color(lib, pid, Vector2i(5, 0)).a == 0.0 and
		_color(lib, pid, Vector2i(7, 0)).a == 0.0,
		"hidden child removes all descendants but not root pixels")
	var map_hidden: DrawingResult = adapter.render_region("world", "ground", 0, region)
	_check(map_hidden.ok and map_hidden.value.get_pixel(5, 1).a == 0.0,
		"published Hide invalidates cached Atlas composition")
	var hit_hidden: DrawingResult = lib.hit_test_path(instance_id, Vector2(5.5, 0.5))
	_check(hit_hidden.ok and (hit_hidden.value == false or (hit_hidden.value is Dictionary and
		(hit_hidden.value as Dictionary).get("path", PackedStringArray()).is_empty())),
		"hidden child and descendants cannot be hit through Atlas canvas")
	_check(session.select_child(child_id).ok and not session.selected_record()["visible"],
		"inspector can still select hidden instance for restoration")
	_check(session.set_selected_visibility(false).ok and not session.can_redo(),
		"repeated hide does not add history or change visibility")
	_check(session.undo().ok and _row(lib, pid, child_id)["visible"] and
		_color(lib, pid, Vector2i(7, 0)).b > 0.9,
		"Undo restores child and grandchild rendering")
	_check(session.redo().ok and not _row(lib, pid, child_id)["visible"],
		"Redo re-hides same child with stable identity")
	_check(session.undo().ok and session.toggle_selected_visibility().ok and
		not session.can_redo(), "new hide after Undo discards divergent redo branch")
	_check(session.undo().ok and session.can_redo(),
		"history remains reusable after divergent branch")
	var other: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(other.select_child(child_id).ok, "independent session can select same source child")
	_check(session.set_selected_visibility(false).ok and other.is_stale(),
		"external visibility edit invalidates another inspector cursor")
	var stale_index: Dictionary = lib.export_index()
	_check(not other.toggle_selected_visibility().ok and not other.undo().ok and
		lib.export_index() == stale_index, "stale inspector cannot replay over newer parent")
	var reopened: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reopened.load().ok and not _row(reopened, pid, child_id)["visible"],
		"hidden state round-trips in published Object registry")
	_check(_color(reopened, pid, Vector2i(5, 0)).a == 0.0 and
		_color(reopened, pid, Vector2i(7, 0)).a == 0.0,
		"reload preserves hidden child and all descendants")
	var fresh: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(reopened, pid)
	_check(fresh.select_child(child_id).ok and fresh.toggle_selected_visibility().ok and
		_color(reopened, pid, Vector2i(5, 0)).g > 0.9,
		"reopened parent can show the same published child again")
	_check(reopened.asset_info(cid)["revision"] == 1 and reopened.asset_info(gid)["revision"] == 1,
		"visibility never modifies immutable child or grandchild pixel-source revisions")
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reopened, pid)
	_check(inspector.visibility_button != null and inspector.visibility_button.disabled,
		"live inspector has Hide/Show button disabled until child selection")
	var index: int = inspector._rows.find(child_id)
	_check(index >= 0, "live inspector lists existing hidden/visible instance")
	inspector.child_list.select(index)
	inspector.child_list.item_selected.emit(index)
	_check(not inspector.visibility_button.disabled and inspector.visibility_button.text == "Hide selected",
		"selecting visible child enables Hide affordance")
	inspector.visibility_button.pressed.emit()
	_check(not _row(reopened, pid, child_id)["visible"] and
		inspector.visibility_button.text == "Show selected" and
		inspector.child_list.get_item_text(index).contains("hidden"),
		"actual Hide button marks hidden child and enables Show")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			inspector.show()
			await process_frame
			await process_frame
			var image: Image = inspector.get_texture().get_image()
			_check(image != null and image.get_width() >= 390 and
				image.save_png(arg.trim_prefix("--screenshot=")) == OK,
				"native inspector framebuffer shows Hide/Show state")
	inspector.undo_button.pressed.emit()
	_check(_row(reopened, pid, child_id)["visible"] and
		inspector.visibility_button.text == "Hide selected", "inspector Undo restores visibility")
	inspector.redo_button.pressed.emit()
	_check(not _row(reopened, pid, child_id)["visible"] and
		inspector.visibility_button.text == "Show selected", "inspector Redo re-hides child")
	inspector.visibility_button.pressed.emit()
	_check(_row(reopened, pid, child_id)["visible"] and
		inspector.visibility_button.text == "Hide selected", "inspector Show reveals source again")
	inspector.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CHILD_VISIBILITY_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
