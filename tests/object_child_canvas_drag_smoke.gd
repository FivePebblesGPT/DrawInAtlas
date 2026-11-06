extends SceneTree
## T-064: real canvas event dispatch into one optimistic child history commit.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CANVAS_DRAG_FAILED: " + description)


func _source(name: String, color: int) -> DrawingDocument:
	var document: DrawingDocument = DrawingDocument.new(name, 16)
	var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if created.ok:
		var session: DrawingEditSession = document.begin_edit(String(created.value), document.revision).value
		session.fill_rect(Rect2i(0, 0, 1, 1), color)
		session.commit()
	return document


func _button(at: Vector2, pressed: bool, alt: bool = true) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	event.alt_pressed = alt
	return event


func _start(canvas: AtlasCanvas, at: Vector2) -> void:
	canvas._gui_input(_button(canvas.document_to_local(at), true))


func _move(canvas: AtlasCanvas, at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.document_to_local(at)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(event)


func _end(canvas: AtlasCanvas, at: Vector2) -> void:
	canvas._gui_input(_button(canvas.document_to_local(at), false))


func _transform(library: AtlasObjectLibrary, parent: String, child: String) -> Transform2D:
	for row: Dictionary in library.children_for_asset(parent):
		if row["id"] == child:
			return AtlasObjectChildEditSession._transform(row)
	return Transform2D.IDENTITY


func _position(library: AtlasObjectLibrary, parent: String, child: String) -> Vector2:
	return _transform(library, parent, child).origin


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
	var folder: String = OS.get_cache_dir().path_join("t064-drag-" + DrawingDocument.new_id())
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
		"running Atlas editor hosts the real canvas and Object registry")
	var root_asset: DrawingResult = library.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var child_asset: DrawingResult = library.create_asset(_source("Child", 0xff00ff00), "Child")
	var grand_asset: DrawingResult = library.create_asset(_source("Grand", 0xffff0000), "Grand")
	_check(root_asset.ok and child_asset.ok and grand_asset.ok, "publish three independent sources")
	if not root_asset.ok or not child_asset.ok or not grand_asset.ok:
		quit(1)
		return
	var pid: String = String(root_asset.value)
	var cid: String = String(child_asset.value)
	var gid: String = String(grand_asset.value)
	var child_transform: Transform2D = Transform2D(-PI / 3.0, Vector2(6, -4)).scaled_local(Vector2(1.5, 0.8))
	var grand_transform: Transform2D = Transform2D(0.0, Vector2(-2, 5))
	var attached: DrawingResult = library.attach_child(pid, 0, cid, child_transform)
	var nested: DrawingResult = library.attach_child(cid, 0, gid, grand_transform)
	_check(attached.ok and nested.ok, "publish a parent→child→grandchild graph")
	var child_id: String = String(attached.value)
	var grand_id: String = String(nested.value)
	var root_transform: Transform2D = Transform2D(PI / 2.0, Vector2(50, 30))
	var placed: DrawingResult = adapter.place_asset(pid, canvas.map.id, canvas.floor.id,
		canvas.presented_detail_level, root_transform)
	_check(placed.ok, "place rotated root in active map")
	if not placed.ok or not attached.ok or not nested.ok:
		quit(1)
		return
	var instance_id: String = String(placed.value)
	canvas.choose_tool(AtlasCanvas.Tool.ART_SELECT)
	canvas.camera_center = Vector2(50, 30)
	canvas.camera_zoom = 8.0
	var at_child: Vector2 = root_transform * (child_transform * Vector2(0.5, 0.5))
	var initial_parent_revision: int = library.children_revision(pid)
	_start(canvas, at_child)
	_check(not canvas._nested_drag.is_empty() and editor.object_source_manager == null,
		"Alt+press defers popup, captures immutable published child hit")
	_check(adapter.selected_instance_id == instance_id,
		"press selects the root without moving its placement")
	_move(canvas, at_child + root_transform.basis_xform(Vector2(3, -2)))
	_check(canvas._nested_drag_moved and library.children_revision(pid) == initial_parent_revision,
		"drag guide does not publish a child transform before release")
	var screenshot: String = OS.get_environment("T064_DRAG_SCREENSHOT")
	if not screenshot.is_empty():
		for frame: int in range(3):
			await process_frame
		var image: Image = DisplayServer.screen_get_image(0)
		_check(image != null and image.get_width() > 0 and image.save_png(screenshot) == OK,
			"native framebuffer captured while preview is uncommitted")
	var released: Vector2 = at_child + root_transform.basis_xform(Vector2(3, -2))
	_end(canvas, released)
	_check(canvas._nested_drag.is_empty() and library.children_revision(pid) == initial_parent_revision + 1,
		"release commits exactly one child graph revision")
	_check(_position(library, pid, child_id).distance_to(Vector2(9, -6)) < 0.001,
		"root-rotated world delta becomes correct parent-local translation")
	_check(library.instance_info(instance_id).get("revision") == 0 and library.asset_info(cid)["revision"] == 1,
		"drag changes no root instance transform or child source pixels")
	var inspector: AtlasObjectChildInspector = editor.object_source_manager.child_inspector
	_check(inspector.session.parent_source_id == pid and inspector.session.selected_child_id == child_id and
		inspector.session.can_undo(), "existing inspector owns the sole drag history action")
	_check(inspector.session.undo().ok and _position(library, pid, child_id) == Vector2(6, -4),
		"undo restores exact original child transform")
	_check(inspector.session.redo().ok and _position(library, pid, child_id) == Vector2(9, -6),
		"redo restores the moved child through same history")
	# Small motion stays a click; no source publication or spurious history item.
	var shifted_child: Vector2 = root_transform * Vector2(9.5, -5.5)
	var before: int = library.children_revision(pid)
	_start(canvas, shifted_child)
	_end(canvas, shifted_child + Vector2(0.1, 0))
	_check(library.children_revision(pid) == before and inspector.session.can_undo(),
		"subthreshold Alt+click only focuses the child, no phantom transform")
	# A deeper child uses the full ancestor frame, not root coordinates.
	var current_child: Transform2D = _transform(library, pid, child_id)
	_check(current_child.x.distance_to(child_transform.x) < 0.001 and
		current_child.y.distance_to(child_transform.y) < 0.001,
		"parent child rotation and nonuniform scale remain unchanged by translation")
	var at_grand: Vector2 = root_transform * (current_child * (grand_transform * Vector2(0.5, 0.5)))
	var grand_delta: Vector2 = (root_transform * current_child).basis_xform(Vector2(2, 3))
	_start(canvas, at_grand)
	_move(canvas, at_grand + grand_delta)
	_end(canvas, at_grand + grand_delta)
	_check(library.children_revision(cid) == 2 and
		_position(library, cid, grand_id).distance_to(Vector2(0, 8)) < 0.002,
		"deep drag commits exact immediate-parent-local transform")
	_check(inspector.session.parent_source_id == cid and inspector.session.selected_child_id == grand_id,
		"deep drag selects the grandchild in its actual source owner")
	_check(inspector.session.undo().ok and _position(library, cid, grand_id) == Vector2(-2, 5),
		"grandchild move has reversible independent parent history")
	# No-op, escape, pointer exit, focus loss and tool change must not publish.
	var current: Vector2 = root_transform * (current_child * (grand_transform * Vector2(0.5, 0.5)))
	var baseline: int = library.children_revision(cid)
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	canvas._gui_input(escape)
	_end(canvas, current + Vector2(3, 1))
	_check(canvas._nested_drag.is_empty() and library.children_revision(cid) == baseline,
		"Escape cancels preview without a child mutation")
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	canvas._on_canvas_mouse_exited()
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline,
		"pointer exit discards the drag before a release over editor chrome")
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	canvas.cancel_edit() # This is the same callback used for OS focus loss.
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline,
		"focus loss cancels the pending child transform")
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	canvas.choose_tool(AtlasCanvas.Tool.PAN)
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline and canvas._nested_drag.is_empty(),
		"changing the tool cancels the drag")
	canvas.choose_tool(AtlasCanvas.Tool.ART_SELECT)
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	var original_map: AtlasMapDocument = canvas.map
	canvas.map = AtlasMapDocument.new("Temporary navigation")
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline,
		"map switch during a pointer drag cannot commit to a different map")
	canvas.map = original_map
	_start(canvas, current)
	_end(canvas, Vector2(-10000000, -10000000))
	_check(library.children_revision(cid) == baseline,
		"release outside the canvas discards the pending child gesture")
	# External registry publication during a gesture must win; never overwrite.
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	var external: DrawingResult = library.attach_child(pid, library.children_revision(pid), gid,
		Transform2D(0.0, Vector2(24, 8)))
	_check(external.ok, "external parent graph mutation is durable mid-drag")
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline and inspector.session.is_stale() == false,
		"unrelated graph publication rejects pending move without corrupting child session")
	# Stale top-level placement also invalidates a press-time child token.
	_start(canvas, current)
	_move(canvas, current + Vector2(3, 1))
	var old_instance_revision: int = int(library.instance_info(instance_id)["revision"])
	var changed_root: DrawingResult = library.transform_instance(instance_id, old_instance_revision, root_transform.translated_local(Vector2(1, 0)))
	_check(changed_root.ok, "root placement updated by another writer")
	_end(canvas, current + Vector2(3, 1))
	_check(library.children_revision(cid) == baseline,
		"changed root placement prevents a stale child drag commit")
	_check(not editor._on_object_child_drag_requested({"instance_id": instance_id,
		"path": PackedStringArray(["forged"]), "start": current, "map_id": canvas.map.id,
		"floor_id": canvas.floor.id, "detail": canvas.presented_detail_level,
		"instance": library.instance_info(instance_id), "registry_hash": library._index_hash},
		current + Vector2(10, 0)).ok, "forged child path cannot publish a transform")
	_check(not editor._on_object_child_drag_requested({}, Vector2(INF, 0)).ok,
		"nonfinite or empty drag request is rejected")
	var loaded: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var reload: DrawingResult = loaded.load()
	_check(reload.ok and _position(loaded, pid, child_id).distance_to(Vector2(9, -6)) < 0.002 and
		_position(loaded, cid, grand_id).distance_to(Vector2(-2, 5)) < 0.002,
		"disk reload matches only committed child positions")
	if editor.object_source_manager != null:
		editor.object_source_manager.hide()
		inspector.hide()
	scene.queue_free()
	await process_frame
	_erase_tree(folder)
	print("T064_CANVAS_DRAG_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
