extends SceneTree
## T-064: nested uniform scaling shares transform history and registry safety.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CHILD_SCALE_FAILED: " + label)


func _source(name: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	var edit: DrawingEditSession = doc.begin_edit(String(layer.value), doc.revision).value
	edit.fill_rect(Rect2i(0, 0, 1, 1), color)
	edit.commit()
	return doc


func _record(lib: AtlasObjectLibrary, parent: String, child_id: String) -> Dictionary:
	for row: Dictionary in lib.children_for_asset(parent):
		if String(row["id"]) == child_id:
			return row
	return {}


func _transform(lib: AtlasObjectLibrary, parent: String, child_id: String) -> Transform2D:
	return AtlasObjectChildEditSession._transform(_record(lib, parent, child_id))


func _color(lib: AtlasObjectLibrary, parent: String, at: Vector2i) -> Color:
	var result: DrawingResult = lib.render_source_tree(parent, Rect2i(at, Vector2i.ONE))
	return result.value.get_pixel(0, 0) if result.ok else Color.TRANSPARENT


func _erase_tree(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for file: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in folder.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-scale-" + DrawingDocument.new_id())
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var parent: DrawingResult = lib.create_asset(_source("Root", 0xff0000ff), "Root")
	var child: DrawingResult = lib.create_asset(_source("Child", 0xff00ff00), "Child")
	var grand: DrawingResult = lib.create_asset(_source("Grand", 0xffff0000), "Grand")
	_check(parent.ok and child.ok and grand.ok, "publish three independent raster sources")
	if not parent.ok or not child.ok or not grand.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var cid: String = String(child.value)
	var gid: String = String(grand.value)
	var attached: DrawingResult = lib.attach_child(pid, 0, cid, Transform2D(0.0, Vector2(5, 3)))
	var nested: DrawingResult = lib.attach_child(cid, 0, gid, Transform2D(0.0, Vector2(2, 0)))
	_check(attached.ok and nested.ok, "attach nested grandchild independently of root position")
	if not attached.ok or not nested.ok:
		quit(1)
		return
	var child_id: String = String(attached.value)
	var grand_id: String = String(nested.value)
	var instance: DrawingResult = lib.place(pid, "world", "floor", "D0", Transform2D.IDENTITY)
	_check(instance.ok, "place root to test actual hit paths after resizing")
	_check(_color(lib, pid, Vector2i(5, 3)).g > 0.9 and
		_color(lib, pid, Vector2i(7, 3)).b > 0.9,
		"original child and grandchild pixels render separately")
	var original: Dictionary = _record(lib, pid, child_id).duplicate(true)
	var original_rev: int = lib.children_revision(pid)
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(not session.scale_selected(1.1).ok and lib.children_revision(pid) == original_rev,
		"a child must be selected before scale changes")
	_check(session.select_child(child_id).ok and not session.can_undo(), "select stable child")
	_check(session.scale_selected(1.0).ok and not session.can_undo() and
		lib.children_revision(pid) == original_rev, "unit scale is a no-op")
	for invalid: float in [0.0, -1.0, INF, NAN]:
		_check(not session.scale_selected(invalid).ok and lib.children_revision(pid) == original_rev,
			"invalid or nonfinite factor is rejected without revision change")
	lib.publication_guard = func() -> bool: return false
	_check(not session.scale_selected(1.1).ok and lib.export_index()["assets"].size() == 3 and
		not session.can_undo(), "refused registry publication creates no history step")
	lib.publication_guard = Callable()
	_check(session.scale_selected(2.0).ok and session.can_undo(),
		"scaling creates one parent-scoped transform history entry")
	var scaled: Dictionary = _record(lib, pid, child_id)
	var basis: Transform2D = _transform(lib, pid, child_id)
	_check(basis.origin == Vector2(5, 3) and basis.x == Vector2(2, 0) and
		basis.y == Vector2(0, 2), "uniform scale changes basis but never the translation")
	_check(String(scaled["id"]) == child_id and scaled["generation"] == original["generation"] and
		scaled["source_id"] == cid and scaled["visible"] == original["visible"],
		"scale preserves instance identity, source and visibility")
	_check(int(scaled["revision"]) == int(original["revision"]) + 1 and
		lib.children_revision(pid) == original_rev + 1 and lib.asset_info(pid)["revision"] == 1,
		"parent graph advances without republishing any source pixels")
	_check(lib.asset_info(cid)["revision"] == 1 and lib.children_revision(cid) == 1 and
		_transform(lib, cid, grand_id).origin == Vector2(2, 0),
		"neither child pixels nor grandchild's parent-local transform changes")
	_check(_color(lib, pid, Vector2i(9, 3)).b > 0.9 and
		_color(lib, pid, Vector2i(7, 3)).a == 0.0,
		"grandchild pixel moves to scaled composite location")
	var scaled_hit: DrawingResult = lib.hit_test_path(String(instance.value), Vector2(9.5, 3.5))
	_check(scaled_hit.ok and scaled_hit.value is Dictionary and
		(scaled_hit.value as Dictionary).get("path", PackedStringArray()) ==
		PackedStringArray([child_id, grand_id]), "nested source hit path follows scaled geometry")
	_check(session.undo().ok and _transform(lib, pid, child_id).x == Vector2.RIGHT and
		_color(lib, pid, Vector2i(7, 3)).b > 0.9,
		"Undo restores original basis and original composite rendering")
	_check(session.redo().ok and _transform(lib, pid, child_id).x == Vector2(2, 0) and
		_color(lib, pid, Vector2i(9, 3)).b > 0.9,
		"Redo reapplies scale without generating new child IDs")
	_check(session.undo().ok and session.scale_selected(0.5).ok and not session.can_redo(),
		"divergent smaller scale discards old redo branch")
	var smaller: Transform2D = _transform(lib, pid, child_id)
	_check(smaller.x == Vector2(0.5, 0) and smaller.origin == Vector2(5, 3),
		"shrink keeps origin and parent-local axes")
	_check(session.undo().ok and session.redo().ok and
		_transform(lib, pid, child_id).x == Vector2(0.5, 0),
		"smaller scale remains reversible")
	# Nonuniform, rotated, and mirrored children retain their original basis directions.
	var rotated: Transform2D = Transform2D(PI / 3.0, Vector2(-7, 8)).scaled_local(Vector2(-2, 3))
	_check(session.set_selected_transform(rotated).ok and
		_transform(lib, pid, child_id).origin == Vector2(-7, 8),
		"parent-local mirrored/nonuniform rotation is accepted")
	var mirror_det: float = rotated.determinant()
	_check(session.scale_selected(1.25).ok and
		is_equal_approx(_transform(lib, pid, child_id).determinant(), mirror_det * 1.5625) and
		_transform(lib, pid, child_id).origin == Vector2(-7, 8),
		"positive scale preserves mirror handedness, rotation and origin")
	_check(session.undo().ok and _transform(lib, pid, child_id) == rotated,
		"scale history restores exact nonuniform/mirrored affine basis")
	var external: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(external.select_child(child_id).ok, "second writer observes current nested instance")
	_check(session.scale_selected(1.1).ok and external.is_stale(),
		"new scale makes a concurrent parent-scoped session stale")
	var stable_index: Dictionary = lib.export_index()
	_check(not external.scale_selected(2.0).ok and not external.undo().ok and
		lib.export_index() == stable_index, "stale writer and history replay are rejected atomically")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	_check(reloaded.load().ok and _transform(reloaded, pid, child_id) ==
		_transform(lib, pid, child_id), "scaled/mirrored transform roundtrips on disk")
	_check(reloaded.asset_info(cid)["revision"] == 1 and
		reloaded.asset_info(gid)["revision"] == 1,
		"published child/grandchild source revisions survive unchanged")
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reloaded, pid)
	var grow: Button = inspector.actions_node().get_node("ScaleUp") as Button
	var shrink: Button = inspector.actions_node().get_node("ScaleDown") as Button
	_check(grow != null and shrink != null and grow.disabled and shrink.disabled,
		"live scale buttons are disabled without a selected child")
	_check(grow.focus_mode != Control.FOCUS_NONE and shrink.tooltip_text.contains("Undo"),
		"scale actions are keyboard focusable and explain Undo semantics")
	var selected_index: int = inspector._rows.find(child_id)
	inspector.child_list.select(selected_index)
	inspector.child_list.item_selected.emit(selected_index)
	_check(not grow.disabled and not shrink.disabled and inspector.details.text.contains("scale"),
		"selecting child enables scale controls with a current basis readout")
	var ui_before: Transform2D = _transform(reloaded, pid, child_id)
	grow.pressed.emit()
	_check(_transform(reloaded, pid, child_id).x.distance_to(ui_before.x * 1.1) < 0.00001 and
		inspector.session.can_undo(), "Grow button publishes exactly one scalable child history entry")
	inspector.undo_button.pressed.emit()
	_check(_transform(reloaded, pid, child_id).x.distance_to(ui_before.x) < 0.00001,
		"inspector Undo restores exact pre-button basis")
	inspector.redo_button.pressed.emit()
	_check(_transform(reloaded, pid, child_id).x.distance_to(ui_before.x * 1.1) < 0.00001,
		"inspector Redo restores growth")
	shrink.pressed.emit()
	_check(_transform(reloaded, pid, child_id).x.distance_to(ui_before.x * 0.99) < 0.00001,
		"Shrink button uses current size rather than an unrelated source edit")
	inspector.size = Vector2i(420, 560)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			inspector.show()
			await process_frame
			await process_frame
			var image: Image = inspector.get_texture().get_image()
			print("T064_SCALE_SCREENSHOT size=", inspector.size, " capture=", (image.get_size() if image != null else Vector2i.ZERO))
			var stored: Error = image.save_png(arg.trim_prefix("--screenshot=")) if image != null else ERR_CANT_OPEN
			_check(image != null and image.get_width() >= 300 and stored == OK,
				"native narrow inspector screenshot records scale actions")
	# An unrelated change invalidates UI actions without changing source pixels.
	var current: Dictionary = _record(reloaded, pid, child_id)
	var changed: DrawingResult = reloaded.transform_child(pid, child_id,
		reloaded.children_revision(pid), _transform(reloaded, pid, child_id).translated_local(Vector2(1, 0)))
	_check(changed.ok and current["id"] == child_id, "external editor publishes a new parent layout")
	var before_stale: Dictionary = reloaded.export_index()
	grow.pressed.emit()
	_check(reloaded.export_index() == before_stale and inspector.details.text.contains("reload"),
		"stale scale button refuses edit and explains reload to user")
	inspector.reload_button.pressed.emit()
	_check(grow.disabled and shrink.disabled and inspector.session.selected_child_id.is_empty(),
		"explicit Reload drops stale selection and leaves actions disabled")
	inspector.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CHILD_SCALE_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
