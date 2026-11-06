extends SceneTree
## T-064: reversible sibling draw order without copying or mutating Object pixels.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T064_CHILD_ORDER_FAILED: " + reason)


func _source(name: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	var edit: DrawingEditSession = doc.begin_edit(String(layer.value), doc.revision).value
	edit.fill_rect(Rect2i(0, 0, 1, 1), color)
	edit.commit()
	return doc


func _ids(lib: AtlasObjectLibrary, parent_id: String) -> Array[String]:
	var values: Array[String] = []
	for item: Dictionary in lib.children_for_asset(parent_id):
		values.append(String(item["id"]))
	return values


func _row(lib: AtlasObjectLibrary, parent_id: String, child_id: String) -> Dictionary:
	for item: Dictionary in lib.children_for_asset(parent_id):
		if String(item["id"]) == child_id:
			return item
	return {}


func _color(lib: AtlasObjectLibrary, parent_id: String) -> Color:
	var image: DrawingResult = lib.render_source_tree(parent_id, Rect2i(5, 5, 1, 1))
	return image.value.get_pixel(0, 0) if image.ok else Color.TRANSPARENT


func _hit(lib: AtlasObjectLibrary, placed_id: String) -> String:
	var result: DrawingResult = lib.hit_test_path(placed_id, Vector2(5.5, 5.5))
	if not result.ok or not result.value is Dictionary:
		return ""
	var path: PackedStringArray = result.value.get("path", PackedStringArray())
	return String(path[0]) if path.size() > 0 else ""


func _erase(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in directory.get_directories():
		_erase(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-order-" + DrawingDocument.new_id())
	var path: String = folder.path_join("Campaign.scn")
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	var parent: DrawingResult = lib.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var green: DrawingResult = lib.create_asset(_source("Green", 0xff00ff00), "Green")
	var blue: DrawingResult = lib.create_asset(_source("Blue", 0xffff0000), "Blue")
	var yellow: DrawingResult = lib.create_asset(_source("Yellow", 0xff00ffff), "Yellow")
	_check(parent.ok and green.ok and blue.ok and yellow.ok, "create four immutable Object sources")
	if not parent.ok or not green.ok or not blue.ok or not yellow.ok:
		quit(1)
		return
	var pid: String = String(parent.value)
	var placement: Transform2D = Transform2D(0.0, Vector2(5, 5))
	var one: DrawingResult = lib.attach_child(pid, 0, String(green.value), placement)
	var two: DrawingResult = lib.attach_child(pid, 1, String(blue.value), placement)
	var three: DrawingResult = lib.attach_child(pid, 2, String(yellow.value), placement)
	_check(one.ok and two.ok and three.ok, "attach three overlapping sibling instances")
	if not one.ok or not two.ok or not three.ok:
		quit(1)
		return
	var a: String = String(one.value)
	var b: String = String(two.value)
	var c: String = String(three.value)
	var first_order: Array[String] = [a, b, c]
	var instance: DrawingResult = lib.place(pid, "world", "ground", "D0", Transform2D.IDENTITY)
	_check(instance.ok and _ids(lib, pid) == first_order, "persisted insertion order is initial draw order")
	var placed_id: String = String(instance.value)
	var timeline: AtlasEditHistory = AtlasEditHistory.new()
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	timeline.reset(campaign)
	var adapter: AtlasDrawingComposition = AtlasDrawingComposition.new(timeline, lib)
	_check(adapter.attach_campaign(campaign).ok, "Atlas composition observes child ordering signals")
	var region: Rect2i = Rect2i(0, 0, 12, 12)
	var initial_map: DrawingResult = adapter.render_region("world", "ground", 0, region)
	_check(initial_map.ok and initial_map.value.get_pixel(5, 5).r > 0.9 and
		initial_map.value.get_pixel(5, 5).g > 0.9,
		"initial composed Atlas preview paints last yellow sibling")
	_check(_color(lib, pid).r > 0.9 and _color(lib, pid).g > 0.9 and
		_hit(lib, placed_id) == c, "last yellow sibling paints above blue and green")
	var originals: Dictionary = lib.export_index()
	var revision: int = lib.children_revision(pid)
	var old_a: Dictionary = _row(lib, pid, a)
	_check(not lib.reorder_child(pid, a, revision + 1, String(old_a["generation"]),
		int(old_a["revision"]), 2).ok, "stale parent index is refused")
	_check(not lib.reorder_child(pid, a, revision, "wrong-generation",
		int(old_a["revision"]), 2).ok, "stale child generation is refused")
	_check(not lib.reorder_child(pid, a, revision, String(old_a["generation"]),
		int(old_a["revision"]) + 1, 2).ok, "stale child revision is refused")
	for bad_index: int in [-1, 3, 999]:
		_check(not lib.reorder_child(pid, a, revision, String(old_a["generation"]),
			int(old_a["revision"]), bad_index).ok, "invalid destination fails closed")
	_check(not lib.reorder_child(pid, "missing", revision, String(old_a["generation"]),
		int(old_a["revision"]), 1).ok and lib.export_index() == originals,
		"unknown child and failed moves cannot mutate stored index")
	var session: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(not session.move_selected_order(1).ok and not session.can_undo(),
		"no-selection reorder fails without adding history")
	_check(session.select_child(a).ok, "select oldest child by stable identity")
	_check(not session.move_selected_order(2).ok and lib.children_revision(pid) == revision,
		"only unit step sibling moves are accepted")
	_check(session.move_selected_order(-1).ok and session.move_selected_order(-1).value == false and
		not session.can_undo() and lib.children_revision(pid) == revision,
		"backward edge no-op preserves history and index revision")
	lib.publication_guard = func() -> bool: return false
	_check(not session.move_selected_order(1).ok and lib.export_index() == originals and
		not session.can_undo(), "failed durable publication leaves index and history untouched")
	lib.publication_guard = Callable()
	_check(session.move_selected_order(1).ok and _ids(lib, pid) == [b, a, c] and
		session.can_undo() and session.selected_child_id == a,
		"forward move swaps adjacent siblings, keeping selection")
	_check(session.move_selected_order(1).ok and _ids(lib, pid) == [b, c, a],
		"second forward move makes selected green child topmost")
	var moved: Dictionary = _row(lib, pid, a)
	_check(_color(lib, pid).g > 0.9 and _color(lib, pid).r < 0.1 and _hit(lib, placed_id) == a,
		"reordered green sibling wins renderer and hit-test in same coordinate")
	var changed_map: DrawingResult = adapter.render_region("world", "ground", 0, region)
	_check(changed_map.ok and changed_map.value.get_pixel(5, 5).g > 0.9 and
		changed_map.value.get_pixel(5, 5).r < 0.1,
		"reorder invalidates cached Atlas preview and composites new top sibling")
	_check(moved["generation"] == old_a["generation"] and moved["source_id"] == old_a["source_id"] and
		moved["transform"] == old_a["transform"] and int(moved["revision"]) == int(old_a["revision"]) + 2,
		"reorder advances only child layout revision and preserves stable instance transform")
	_check(lib.asset_info(pid)["revision"] == 1 and lib.asset_info(String(green.value))["revision"] == 1,
		"reordering never republishes source artwork")
	_check(session.move_selected_order(1).ok and session.move_selected_order(1).value == false and
		_ids(lib, pid) == [b, c, a], "front edge no-op doesn't move a child")
	_check(session.undo().ok and _ids(lib, pid) == [b, a, c] and _hit(lib, placed_id) == c,
		"Undo restores preceding sibling paint and hit order")
	_check(session.undo().ok and _ids(lib, pid) == first_order and
		int(_row(lib, pid, a)["revision"]) == int(old_a["revision"]) + 4,
		"second Undo restores original order with monotonic child revisions")
	_check(session.redo().ok and session.redo().ok and _ids(lib, pid) == [b, c, a] and
		_hit(lib, placed_id) == a, "Redo restores two moves with original identities")
	_check(session.undo().ok and session.move_selected_order(-1).ok and
		_ids(lib, pid) == [a, b, c] and not session.can_redo(),
		"divergent move drops abandoned Redo branch")
	_check(session.move_selected_order(1).ok and session.move_selected_order(1).ok and
		session.toggle_selected_visibility().ok and _hit(lib, placed_id) == c,
		"hide topmost reordered child exposes prior visible sibling")
	_check(session.undo().ok and _hit(lib, placed_id) == a,
		"mixed history Undo restores green topmost visibility")
	_check(session.undo().ok and _ids(lib, pid) == [b, a, c],
		"mixed history Undo reverts last order change without changing visibility")
	_check(session.redo().ok and session.redo().ok and _ids(lib, pid) == [b, c, a] and
		_hit(lib, placed_id) == c, "mixed Redo restores order and hidden flag independently")
	_check(session.undo().ok and session.detach_selected().ok and _ids(lib, pid) == [b, c],
		"structural removal of reordered child retains remaining sibling order")
	_check(session.undo().ok and _ids(lib, pid) == [b, c, a] and _hit(lib, placed_id) == a,
		"Undo removal restores exact position and active sibling rendering")
	var stale: AtlasObjectChildEditSession = AtlasObjectChildEditSession.new(lib, pid)
	_check(stale.select_child(a).ok, "concurrent editor observes reordered child")
	_check(session.move_selected_order(-1).ok and stale.is_stale(),
		"changed parent order invalidates concurrent editor snapshot")
	var stable_index: Dictionary = lib.export_index()
	_check(not stale.move_selected_order(-1).ok and not stale.undo().ok and
		lib.export_index() == stable_index, "stale session cannot overwrite persisted order")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(path)
	_check(reloaded.load().ok and _ids(reloaded, pid) == _ids(lib, pid) and
		_hit(reloaded, placed_id) == _hit(lib, placed_id), "disk reload preserves order and hit precedence")
	_check(reloaded.asset_info(pid)["sha256"] == lib.asset_info(pid)["sha256"],
		"source checksum remains exact across all reorder and history changes")
	var inspector: AtlasObjectChildInspector = AtlasObjectChildInspector.new()
	root.add_child(inspector)
	await process_frame
	inspector.bind_parent(reloaded, pid)
	_check(inspector.backward_button != null and inspector.forward_button != null and
		inspector.backward_button.disabled and inspector.forward_button.disabled,
		"live sibling-order controls are disabled before selection")
	_check(inspector.forward_button.focus_mode != Control.FOCUS_NONE and
		inspector.backward_button.tooltip_text.contains("Undo"),
		"buttons are focusable and explain reversible painter order")
	var select_index: int = inspector._rows.find(a)
	inspector.child_list.select(select_index)
	inspector.child_list.item_selected.emit(select_index)
	_check(not inspector.backward_button.disabled and not inspector.forward_button.disabled and
		inspector.details.text.contains("sibling order"),
		"middle sibling enables both buttons and reports current position")
	var order_before_ui: Array[String] = _ids(reloaded, pid)
	inspector.forward_button.pressed.emit()
	_check(inspector.forward_button.disabled and not inspector.backward_button.disabled and
		_ids(reloaded, pid) == [b, c, a] and inspector.session.can_undo(),
		"Bring forward commits exactly one reorder and disables front boundary")
	inspector.undo_button.pressed.emit()
	_check(_ids(reloaded, pid) == order_before_ui and inspector.session.can_redo(),
		"live inspector Undo restores sibling order")
	inspector.redo_button.pressed.emit()
	_check(_ids(reloaded, pid) == [b, c, a], "live inspector Redo restores paint precedence")
	inspector.backward_button.pressed.emit()
	_check(_ids(reloaded, pid) == order_before_ui and not inspector.forward_button.disabled,
		"Send backward restores middle order through same transaction")
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.pressed = true
	shortcut.ctrl_pressed = true
	shortcut.alt_pressed = true
	shortcut.keycode = KEY_DOWN
	inspector._unhandled_key_input(shortcut)
	_check(_ids(reloaded, pid) == [b, c, a],
		"Ctrl+Alt+Down keyboard equivalent moves selected sibling forward")
	shortcut.keycode = KEY_UP
	inspector._unhandled_key_input(shortcut)
	_check(_ids(reloaded, pid) == order_before_ui,
		"Ctrl+Alt+Up keyboard equivalent reverses the order move")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			inspector.size = Vector2i(420, 600)
			inspector.show()
			await process_frame
			await process_frame
			var picture: Image = inspector.get_texture().get_image()
			var saved: Error = picture.save_png(argument.trim_prefix("--screenshot=")) if picture != null else ERR_CANT_OPEN
			_check(picture != null and picture.get_width() >= 390 and saved == OK,
				"native 420px inspector screenshot records sibling-order actions")
	var changed: DrawingResult = reloaded.transform_child(pid, a, reloaded.children_revision(pid),
		AtlasObjectChildEditSession._transform(_row(reloaded, pid, a)).translated_local(Vector2.RIGHT))
	var before_stale_ui: Dictionary = reloaded.export_index()
	inspector.forward_button.pressed.emit()
	_check(changed.ok and reloaded.export_index() == before_stale_ui and
		inspector.details.text.contains("reload"),
		"stale inspector refuses reorder and displays Reload guidance")
	inspector.reload_button.pressed.emit()
	_check(inspector.backward_button.disabled and inspector.forward_button.disabled and
		inspector.session.selected_child_id.is_empty(),
		"explicit Reload clears stale selection and disables reorder controls")
	inspector.queue_free()
	await process_frame
	_erase(folder)
	print("T064_CHILD_ORDER_%s (%d checks; %d failed)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
