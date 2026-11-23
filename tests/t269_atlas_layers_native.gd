extends SceneTree
## T-269: the same native Drawing layer view under Atlas uses the host's
## canonical raster tiles and history while nested-group controls repaint.

const STRIDE: int = 64
const RED: int = 0xff0000ff
const GREEN: int = 0xff00ff00
const HIDDEN: int = 0x00443322

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T269_ATLAS_FAILED: " + label)


func frames(count: int = 4) -> void:
	for _index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func seed_tile(document: DrawingDocument, layer: String, color: int) -> void:
	var data: PackedByteArray = PackedByteArray()
	data.resize(STRIDE * STRIDE * 4)
	data.encode_u32(0, color)
	data.encode_u32(4, HIDDEN)
	document._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(STRIDE, data)


func pixel(document: DrawingDocument, layer: String, x: int) -> int:
	var result: DrawingResult = document.read_pixel(layer, x, 0)
	return int(result.value) if result.ok else -1


func framebuffer_color(workspace: Control) -> Color:
	var capture: Image = root.get_texture().get_image()
	var position: Vector2i = Vector2i(root.get_final_transform() * (
		workspace.canvas.global_position + workspace.canvas.pixel_to_position(Vector2(0.5, 0.5))))
	if capture == null or capture.is_empty() or position.x < 0 or position.y < 0 or \
			position.x >= capture.get_width() or position.y >= capture.get_height():
		return Color(-1, -1, -1)
	return capture.get_pixelv(position)


func context(document: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.detail_group_id = "D1"
	result.document_id = document.id
	result.selected_layer_ids.append(layer)
	result.editor_mode = "surface_paint"
	result.has_focus = true
	return result


func click_eye(workspace: Control, node_id: String) -> bool:
	var tree: Tree = workspace.layers
	var item: TreeItem = tree.get_root().get_first_child()
	while item != null and String(item.get_metadata(0)) != node_id:
		item = item.get_next()
	if item == null:
		return false
	var rect: Rect2 = tree.get_item_area_rect(item, 0, 0)
	var position: Vector2 = tree.global_position + rect.get_center()
	if rect.size.x <= 0 or rect.size.y <= 0 or not tree.get_global_rect().has_point(position):
		return false
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		root.push_input(event, true)
		await process_frame
	return true


func erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories():
		erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real X11 framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 820)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"Atlas campaign and native Drawing detail initialized")
	var document: DrawingDocument = registry.document_at("world", "ground", 1, true).value as DrawingDocument
	check(document != null and document.external_history and document.tile_stride == STRIDE,
		"Atlas document owns the native raster and global history")
	if document == null:
		quit(1)
		return
	var bottom: String = String(document.create_layer(DrawingLayerNode.RASTER, "Lower").value)
	var group: String = String(document.create_layer(DrawingLayerNode.GROUP, "Upper Group").value)
	var upper: String = String(document.create_layer(DrawingLayerNode.RASTER, "Upper", group).value)
	seed_tile(document, bottom, RED)
	seed_tile(document, upper, GREEN)
	check(document.list_children(group) == [upper] and document.list_children().has(bottom),
		"native Atlas source keeps nested group IDs and ordering")
	check(pixel(document, bottom, 0) == RED and pixel(document, upper, 0) == GREEN and
		pixel(document, upper, 1) == HIDDEN,
		"canonical source holds two opaque layers and transparent hidden RGB")
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(12)
	workspace.tabs[0]["document"] = document
	workspace.tabs[0]["layer"] = upper
	workspace.tabs[0]["selected_node"] = upper
	workspace._activate(0)
	workspace.canvas.zoom = 5.0
	workspace.canvas.camera = Vector2.ZERO
	workspace.canvas.show_grid = false
	workspace.dock_layout.move_group("layers", "right", 0)
	workspace._render_dock()
	workspace._after_edit()
	await frames(8)
	check(workspace.current_document() == document and workspace.canvas.document == document and
		workspace.layers.get_root() != null,
		"Atlas embeds the canonical Drawing layer view, not a copied model")
	check(workspace.layers.get_root().get_child_count() >= 3 and
		workspace.history_undo.disabled and workspace.history_redo.disabled,
		"layer rows render while local History remains host-disabled")
	var first: Color = framebuffer_color(workspace)
	check(first.g > 0.70 and first.g > first.r + 0.30,
		"native Atlas framebuffer composites visible upper green layer")
	check(await click_eye(workspace, group), "real X11 eye-button rect is visible")
	await frames(8)
	check(not bool(document.node_metadata(group)["visible"]) and
		workspace.selected_layer_node() == upper,
		"group eye targets nested group without switching selected layer")
	var hidden: Color = framebuffer_color(workspace)
	check(hidden.r > 0.70 and hidden.r > hidden.g + 0.30,
		"hidden group reveals lower red layer in real framebuffer")
	check(await click_eye(workspace, group), "real X11 eye-button repeat targets group")
	await frames(8)
	check(bool(document.node_metadata(group)["visible"]) and framebuffer_color(workspace).g > 0.70,
		"second eye restores upper composition without altering source")
	workspace._apply_row_icon_action(group, 2) # ROW_LOCK
	await frames(4)
	check(bool(document.node_metadata(group)["locked"]) and
		not document.begin_edit(upper, document.revision).ok,
		"nested group lock denies edits to its children")
	workspace._apply_row_icon_action(group, 2)
	await frames(4)
	check(not bool(document.node_metadata(group)["locked"]),
		"group unlock restores edit eligibility")
	# An Atlas-owned edit must remain one global native transaction; the layer
	# UI must not manufacture an independent local Drawing Undo timeline.
	var started: DrawingResult = document.begin_edit(bottom, document.revision)
	check(started.ok, "native layer starts an Atlas edit transaction")
	if started.ok:
		var edit: DrawingEditSession = started.value as DrawingEditSession
		check(edit.fill_rect(Rect2i(-2, 3, 1, 1), HIDDEN).ok,
			"signed native tile stores zero-alpha hidden RGB")
		var ctx: DrawingHistoryContext = context(document, bottom)
		var committed: DrawingResult = history.commit_drawing(edit, ctx, ctx)
		check(committed.ok and history.can_undo() and not document.can_undo() and
			document.history_length() == 0,
			"one global Atlas command, no Drawing-local history")
		check(int(document.read_pixel(bottom, -2, 3).value) == HIDDEN,
			"signed tile source receives exact zero-alpha RGBA8")
		check(history.undo() and int(document.read_pixel(bottom, -2, 3).value) == 0,
			"Atlas Undo replays native layer delta")
		check(history.redo() and int(document.read_pixel(bottom, -2, 3).value) == HIDDEN,
			"Atlas Redo restores exact signed bytes")
	check(pixel(document, bottom, 0) == RED and pixel(document, upper, 0) == GREEN and
		pixel(document, upper, 1) == HIDDEN,
		"group toggles and history replay preserve original canonical layer pixels")
	var folder: String = ProjectSettings.globalize_path("user://t269-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK,
		"isolated Atlas campaign save folder exists")
	var path: String = folder.path_join("Layers.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	check(saved.ok, "Atlas campaign saves native nested layer geometry")
	if saved.ok:
		var loaded: AtlasStoreResult = AtlasCampaignBundle.load(path)
		check(loaded.error == OK and loaded.registry != null,
			"Atlas campaign reopens with layer source registry")
		if loaded.error == OK and loaded.registry != null:
			var reopened: DrawingResult = loaded.registry.document_at("world", "ground", 1)
			check(reopened.ok, "saved Atlas detail is still addressable")
			if reopened.ok:
				var restored: DrawingDocument = reopened.value as DrawingDocument
				check(restored.list_children(group) == [upper] and
					not bool(restored.node_metadata(group)["locked"]) and
					bool(restored.node_metadata(group)["visible"]),
					"Save/Open retains group child identity and visible/unlocked state")
				check(pixel(restored, bottom, 0) == RED and pixel(restored, upper, 0) == GREEN and
					int(restored.read_pixel(bottom, -2, 3).value) == HIDDEN,
					"Save/Open keeps native original and signed hidden-RGB bytes")
	erase_tree(folder)
	workspace.queue_free()
	host.queue_free()
	await frames()
	print("T269_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0:
		print("T269_ATLAS_PASSED")
	quit(0 if failures == 0 else 1)
