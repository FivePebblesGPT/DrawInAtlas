extends SceneTree
## T-064: Alt+click selects a published nested hit in the canonical Atlas UI.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CANVAS_CHILD_FAILED: " + description)


func _source(name: String, packed_color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if layer.ok:
		var edit: DrawingEditSession = doc.begin_edit(String(layer.value), doc.revision).value
		edit.fill_rect(Rect2i(0, 0, 1, 1), packed_color)
		edit.commit()
	return doc


func _press(at: Vector2, modified: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.alt_pressed = modified
	return event


func _click(canvas: AtlasCanvas, at: Vector2, modified: bool) -> void:
	var down: InputEventMouseButton = _press(at, modified)
	canvas._gui_input(down)
	var up: InputEventMouseButton = _press(at, modified)
	up.pressed = false
	canvas._gui_input(up)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for child: String in directory.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-canvas-" + DrawingDocument.new_id())
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = folder.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(5):
		await process_frame
	var canvas: AtlasCanvas = editor.canvas
	var adapter: AtlasDrawingComposition = editor.drawing_composition
	var library: AtlasObjectLibrary = adapter.library
	_check(canvas.map != null and canvas.floor != null and library != null,
		"Atlas editor has an active map and canonical Object registry")
	var root_source: DrawingResult = library.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var child_source: DrawingResult = library.create_asset(_source("Child", 0xff00ff00), "Child")
	var grand_source: DrawingResult = library.create_asset(_source("Grandchild", 0xffff0000), "Grandchild")
	_check(root_source.ok and child_source.ok and grand_source.ok, "three published pixel sources")
	if not root_source.ok or not child_source.ok or not grand_source.ok:
		quit(1)
		return
	var pid: String = String(root_source.value)
	var cid: String = String(child_source.value)
	var gid: String = String(grand_source.value)
	var child: DrawingResult = library.attach_child(pid, 0, cid, Transform2D(0.0, Vector2(5, -3)))
	var grand: DrawingResult = library.attach_child(cid, 0, gid, Transform2D(0.0, Vector2(-2, 4)))
	_check(child.ok and grand.ok, "published nested chain")
	var placement: DrawingResult = adapter.place_asset(pid, canvas.map.id, canvas.floor.id,
		canvas.presented_detail_level, Transform2D(0.0, Vector2(20, 10)))
	_check(placement.ok, "place parent in current Atlas map")
	if not placement.ok or not child.ok or not grand.ok:
		quit(1)
		return
	var instance_id: String = String(placement.value)
	canvas.choose_tool(AtlasCanvas.Tool.ART_SELECT)
	canvas.camera_center = Vector2(20, 10)
	canvas.camera_zoom = 2.0
	var root_point: Vector2 = Vector2(20.5, 10.5)
	var child_point: Vector2 = Vector2(25.5, 7.5)
	var grand_point: Vector2 = Vector2(23.5, 11.5)
	_click(canvas, canvas.document_to_local(root_point), false)
	_check(adapter.selected_instance_id == instance_id and editor.object_source_manager == null,
		"normal click selects root placement without opening nested editor")
	_click(canvas, canvas.document_to_local(child_point), true)
	var manager: AtlasObjectSourceManager = editor.object_source_manager
	_check(manager != null, "Alt+click creates one shared Object Manager")
	if manager == null:
		quit(1)
		return
	var inspector: AtlasObjectChildInspector = manager.child_inspector
	_check(manager.visible and inspector.visible and inspector.session.parent_source_id == pid and
		inspector.session.selected_child_id == String(child.value),
		"Alt+click opens parent inspector and selects exact child")
	_check(adapter.selected_instance_id == instance_id,
		"nested click preserves original map-instance selection")
	_check(inspector.session.translate_selected(Vector2(2, 0)).ok and inspector.session.can_undo(),
		"canvas-selected child can be transformed using shared parent history")
	var shifted_hit: Vector2 = child_point + Vector2(2, 0)
	_click(canvas, canvas.document_to_local(shifted_hit), true)
	_check(inspector.session.parent_source_id == pid and inspector.session.can_undo() and
		inspector.session.selected_child_id == String(child.value),
		"reselecting same parent retains its undo timeline")
	_check(inspector.session.undo().ok, "canvas-sourced selection participates in child undo")
	_click(canvas, canvas.document_to_local(grand_point), true)
	_check(inspector.session.parent_source_id == cid and inspector.session.selected_child_id == String(grand.value),
		"deep hit selects grandchild in immediate parent source, not root")
	_check(adapter.selected_instance_id == instance_id,
		"nested source navigation retains map placement context")
	_check(inspector.child_list.get_selected_items().size() == 1 and
		inspector.child_list.item_count == 1 and manager.library == library,
		"visible inspector highlights published grandchild in the same registry")
	var screenshot: String = OS.get_environment("T064_CANVAS_SCREENSHOT")
	if not screenshot.is_empty():
		for frame: int in range(4):
			await process_frame
		var image: Image = DisplayServer.screen_get_image(0)
		_check(image != null and image.get_width() > 0 and image.save_png(screenshot) == OK,
			"native Atlas nested selection screenshot captured")
	_check(not editor._on_object_child_hit_requested("other-instance", grand_point).ok,
		"forged instance ID cannot switch inspector")
	_check(not editor._on_object_child_hit_requested(instance_id, Vector2(INF, 0)).ok,
		"nonfinite coordinate rejected")
	var previous_parent: String = inspector.session.parent_source_id
	_check(not editor._on_object_child_hit_requested(instance_id, Vector2(25, 50)).ok and
		inspector.session.parent_source_id == previous_parent,
		"transparent canvas click cannot change active child parent")
	var old_map: String = canvas.map.id
	var before_stale: String = inspector.session.selected_child_id
	canvas.map = AtlasMapDocument.new("Other map")
	_check(not editor._on_object_child_hit_requested(instance_id, grand_point).ok and
		inspector.session.selected_child_id == before_stale,
		"map changes prevent stale nested clicks")
	canvas.map = editor.campaign.get_map(old_map)
	var changed: DrawingResult = library.attach_child(cid, library.children_revision(cid), gid)
	_check(changed.ok and inspector.session.is_stale(), "external child edit stales inspector cursor")
	_check(not manager.focus_child_from_canvas(cid, String(grand.value)).ok and
		inspector.session.is_stale(), "repeat click cannot silently reset stale undo history")
	_check(library.instance_info(instance_id).get("source_id") == pid and
		library.asset_info(pid)["revision"] == 1,
		"canvas selection does not republish any Object source")
	manager.hide()
	inspector.hide()
	scene.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CANVAS_CHILD_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
