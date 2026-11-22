extends SceneTree
## T-252 Atlas: same real native ColorPicker transaction inside hosted Drawing.
## Atlas campaign pixels/history must not change through UI-only color edits.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T252_ATLAS_FAILED: " + label)


func frames(count: int = 4) -> void:
	for _i: int in range(count):
		await process_frame


func pointer(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func click(control: Control) -> void:
	pointer(control.get_global_rect().get_center(), true)
	await frames(2)
	pointer(control.get_global_rect().get_center(), false)
	await frames(4)


func remove_tree(path: String) -> void:
	var folder: DirAccess = DirAccess.open(path)
	if folder == null:
		return
	for file: String in folder.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in folder.get_directories():
		remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1240, 790)
	var host: Control = Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.preferences_persistence_enabled = false
	app.layout_persistence_enabled = false
	host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	check(not app._window_quit_guard_enabled and app.get_parent() == host,
		"Atlas owns window; Drawing embeds one canonical workspace")
	check(app.dock_layout.move_group("colors", "right", 0), "Colors visible in Atlas dock")
	app._render_dock()
	await frames(8)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok,
		"real Atlas campaign and Drawing registry attached")
	var atlas: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var id: String = str(atlas.create_layer(DrawingLayerNode.RASTER, "Keep pixels").value)
	var tile: PackedByteArray = PackedByteArray()
	tile.resize(64 * 64 * 4)
	tile.encode_u32(0, 0x00CC7733)
	atlas._nodes[id].tiles["0,0"] = DrawingRasterTile.from_rgba8(64, tile)
	var source: PackedByteArray = (atlas.request_chunk(id, "0,0").value as DrawingRasterTile).to_rgba8()
	var rev: int = atlas.revision
	var hcount: int = atlas.history_length()
	var local_rev: int = app.current_document().revision
	var local_dirty: bool = app.current_document().is_dirty()
	var before: Color = Color8(48, 71, 137, 255)
	app._set_foreground(before)
	app.recent_colors.clear()
	await click(app.background_button)
	var background_initial: Color = app.color_background
	var start: Vector2 = app.color_advanced.get_global_rect().position + Vector2(36, 54)
	check(app.inspector.get_global_rect().has_point(start),
		"Atlas embedded picker has a visible, real pointer target")
	pointer(start, true)
	await frames(2)
	var observed: Dictionary = {}
	for step: int in range(19):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = start + Vector2(float(step) * 4.0, float(step % 4) * 4.0)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await frames(2)
		observed[app._pack_color(app.color_background)] = true
		check(app.recent_colors.is_empty() and app.active_color == before,
			"Atlas picker held step %d neither records gradients nor repaints FG" % step)
	pointer(start + Vector2(72, 8), false)
	await frames(8)
	check(observed.size() > 7 and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(background_initial),
		"Atlas release records exactly previous settled BG despite many live updates")
	check(app.canvas.color_rgba == app._pack_color(before) and
		app.color_hex.text == "#" + app.color_background.to_html(true).to_upper(),
		"Atlas BG edit retains unchanged brush paint and synchronized exact hex")
	check(atlas.revision == rev and atlas.history_length() == hcount and
		(atlas.request_chunk(id, "0,0").value as DrawingRasterTile).to_rgba8() == source,
		"Atlas external history and exact hidden RGBA8 tiles unchanged")
	check(app.current_document().revision == local_rev and app.current_document().is_dirty() == local_dirty,
		"embedded local drawing remains non-dirty after picker gestures")
	var path: String = ProjectSettings.globalize_path("user://t252-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(path) == OK, "temporary Atlas generation directory created")
	var file: String = path.path_join("Palette.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, file)
	check(saved.ok, "Atlas campaign saves unchanged after UI-only palette gestures")
	if saved.ok:
		var opened: AtlasStoreResult = AtlasCampaignBundle.load(file)
		check(opened.error == OK and opened.registry != null, "saved Atlas campaign reopens")
		if opened.error == OK and opened.registry != null:
			var document: DrawingDocument = opened.registry.document_at("world", "ground", 1, true).value
			check((document.request_chunk(id, "0,0").value as DrawingRasterTile).to_rgba8() == source,
				"campaign reload preserves exact tile bytes, independent of ColorPicker state")
	remove_tree(path)
	app.queue_free()
	host.queue_free()
	await frames()
	print("T252_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T252_ATLAS_PASSED" if failures == 0 else "T252_ATLAS_FAILED")
	quit(0 if failures == 0 else 1)
