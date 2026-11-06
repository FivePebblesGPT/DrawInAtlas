extends SceneTree
## T-089: X11 pointer, keyboard, Tree row controls and framebuffer witnesses.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T089_NATIVE_FAILED: " + description)


func frames(count: int = 4) -> void:
	for _index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func click_at(pos: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = pos
		event.global_position = pos
		root.push_input(event, true)
		await process_frame


func click_row(workspace: Control, node_id: String, button_index: int = -1) -> bool:
	var tree: Tree = workspace.layers
	var item: TreeItem = tree.get_root().get_first_child()
	while item != null and String(item.get_metadata(0)) != node_id:
		item = item.get_next()
	if item == null:
		return false
	var rect: Rect2 = tree.get_item_area_rect(item, 0, button_index)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	var target: Vector2 = tree.global_position + rect.get_center()
	if button_index < 0:
		target.x = tree.global_position.x + 18.0
	await click_at(target)
	return true


func render_pixel(workspace: Control, pixel: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var location: Vector2i = Vector2i(workspace.canvas.global_position +
		workspace.canvas.pixel_to_position(pixel))
	if image == null or image.is_empty() or location.x < 0 or location.y < 0 or \
		location.x >= image.get_width() or location.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(location)


func seed_layer(doc: DrawingDocument, layer: String, rgba: int) -> void:
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	if edit != null:
		check(edit._stage(0, 0, rgba).ok and edit.commit().ok, "seed one source pixel")
	else:
		check(false, "open seed transaction")


func key(code: Key, ctrl: bool = false, alt: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.ctrl_pressed = ctrl
		event.alt_pressed = alt
		root.push_input(event, true)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "software or physical display required")
		quit(1)
		return
	root.size = Vector2i(1120, 800)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var workspace: Control = load("res://main.tscn").instantiate()
	workspace.layout_persistence_enabled = false
	root.add_child(workspace)
	await frames(8)
	var doc: DrawingDocument = workspace.current_document()
	var bottom: String = workspace.current_layer()
	var parent_id: String = doc.node_metadata(bottom)["parent"]
	workspace.canvas.zoom = 4.0
	workspace.canvas.camera = Vector2.ZERO
	workspace.canvas.show_grid = false
	seed_layer(doc, bottom, 0xff0000ff) # red
	workspace._add_layer()
	var top: String = workspace.current_layer()
	seed_layer(doc, top, 0xff00ff00) # green
	workspace._after_edit()
	await frames(6)
	var green: Color = render_pixel(workspace, Vector2(0.5, 0.5))
	check(green.g > green.r + 0.25, "native framebuffer shows top green raster")
	var item: TreeItem = workspace.layers.get_root().get_first_child()
	var top_item: TreeItem
	while item != null:
		if String(item.get_metadata(0)) == top:
			top_item = item
			break
		item = item.get_next()
	check(top_item != null and top_item.get_button_count(0) == 2,
		"each row has direct eye and lock buttons")
	check(await click_row(workspace, top, 0), "locate real eye button rect")
	await frames(5)
	check(doc.node_metadata(top)["visible"] == false and
		workspace.selected_layer_node() == top, "clicked row eye toggles exactly that layer")
	var red: Color = render_pixel(workspace, Vector2(0.5, 0.5))
	check(red.r > red.g + 0.25, "eye click changes actual framebuffer composition")
	check(await click_row(workspace, top, 0), "click row eye second time")
	await frames(5)
	check(doc.node_metadata(top)["visible"] == true and
		render_pixel(workspace, Vector2(0.5, 0.5)).g > 0.70, "second eye restores visible pixels")
	check(await click_row(workspace, bottom, 1), "locate non-selected row lock button rect")
	await frames(3)
	check(doc.node_metadata(bottom)["locked"] == true and
		doc.node_metadata(top)["locked"] == false,
		"lock click targets clicked row, not active paint layer")
	check(not doc.begin_edit(bottom, doc.revision).ok and
		doc.begin_edit(top, doc.revision).ok, "row lock changes eligibility, not visibility")
	# A group can be selected by pointer but does not become a paintable target.
	check(await click_row(workspace, parent_id), "find group row for pointer selection")
	await frames(2)
	check(workspace.selected_layer_node() == parent_id and workspace.current_layer().is_empty()
		and workspace.canvas.layer_id.is_empty(), "pointer-selected group disables painting")
	check(await click_row(workspace, parent_id, 0), "click group eye")
	await frames(4)
	check(not doc.node_metadata(parent_id)["visible"] and
		not doc.begin_edit(top, doc.revision).ok, "group visibility propagates to children")
	var hidden: Color = render_pixel(workspace, Vector2(0.5, 0.5))
	check(hidden.r > green.r + 0.25 and hidden.g < green.g - 0.05,
		"hidden group removes its pixels from native framebuffer")
	check(await click_row(workspace, parent_id, 0), "show group again")
	await frames(4)
	check(doc.node_metadata(parent_id)["visible"] and
		render_pixel(workspace, Vector2(0.5, 0.5)).g > 0.70, "group eye restores composite")
	# Keyboard with Tree focus: Ctrl+Alt+L and Ctrl+Alt+V are row-local.
	workspace.layers.grab_focus()
	key(KEY_L, true, true)
	await frames(2)
	check(doc.node_metadata(parent_id)["locked"] == true,
		"focused layer tree handles keyboard group lock")
	key(KEY_L, true, true)
	await frames(2)
	check(doc.node_metadata(parent_id)["locked"] == false,
		"keyboard can unlock selected group")
	# Reparent and reorder with stable IDs and native selection.
	workspace._add_group()
	var child_group: String = workspace.selected_layer_node()
	check(doc.node_metadata(child_group)["parent"] == parent_id and
		workspace.current_layer().is_empty(), "new group under selected group")
	workspace._add_layer()
	var child_layer: String = workspace.selected_layer_node()
	check(doc.node_metadata(child_layer)["parent"] == child_group and
		workspace.current_layer() == child_layer, "new raster under nested group")
	workspace._outdent_selected_layer()
	check(doc.node_metadata(child_layer)["parent"] == parent_id,
		"outdent reparents row beside its parent group")
	workspace.layers.grab_focus()
	key(KEY_UP, true, true)
	await frames(2)
	check(doc.node_metadata(child_layer)["parent"] == parent_id,
		"keyboard row reorder preserves chosen parent and stable ID")
	var moved_index: int = doc.list_children(parent_id).find(child_layer)
	workspace._undo()
	check(doc.list_children(parent_id).find(child_layer) != moved_index,
		"Undo reverses keyboard reorder")
	workspace._redo()
	check(doc.list_children(parent_id).find(child_layer) == moved_index,
		"Redo repeats keyboard reorder")
	# File and Object-editor tab must share the canonical package and UI behavior.
	var saved_path: String = ProjectSettings.globalize_path("user://t089-native.drawing")
	workspace._save_file(saved_path)
	var opened: DrawingResult = DrawingFileIO.open(saved_path)
	check(opened.ok, "save/open after pointer and keyboard mutations")
	if opened.ok:
		var loaded: DrawingDocument = opened.value as DrawingDocument
		check(loaded.list_children(parent_id) == doc.list_children(parent_id) and
			loaded.node_metadata(bottom)["locked"] and loaded.node_metadata(top)["visible"],
			"save/reopen preserves order, eye and lock")
		check(int(loaded.read_pixel(bottom, 0, 0).value) == 0xff0000ff and
			int(loaded.read_pixel(top, 0, 0).value) == 0xff00ff00,
			"canonical RGBA8 survives structural edits")
	workspace.new_object()
	await frames(4)
	var object_group: String = workspace.current_document().node_metadata(workspace.current_layer())["parent"]
	workspace._select_layer_node(object_group, false)
	workspace._add_group()
	check(workspace.current_object() != null and
		workspace.current_document().node_metadata(workspace.selected_layer_node())["parent"] == object_group,
		"Object Editor reuses exact same layer UI/hierarchy")
	# Short viewport is a separate native layout smoke, without changing source data.
	root.size = Vector2i(880, 550)
	await frames(4)
	check(workspace.layers.size.y > 0 and workspace.layers.get_root().get_child_count() > 0 and
		workspace.layers.get_root().get_child_count() <= workspace.ROW_PAGE,
		"short viewport keeps a bounded, populated layer tree")
	workspace.queue_free()
	await frames(2)
	if failures == 0:
		print("T089_NATIVE_PASSED: %d checks" % checks)
	else:
		printerr("T089_NATIVE_FAILED: %d/%d" % [failures, checks])
	quit(1 if failures != 0 else 0)
