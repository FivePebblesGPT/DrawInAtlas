extends SceneTree
## T-226: real Atlas-hosted single Drawing view, external history and persistence.

const TILE_SIZE: int = 64
const ORIGINAL: int = 0x006a35c2 # Transparent pixel retains hidden straight RGB.
var checks: int = 0
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("T226_ATLAS_FAILED: " + label)

func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame

func click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await frames(3)

func remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for entry: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(entry))
	for entry: String in directory.get_directories():
		remove_tree(path.path_join(entry))
	DirAccess.remove_absolute(path)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 760)
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var workspace: Control = load("res://addons/drawing/workspace.gd").new()
	workspace.layout_persistence_enabled = false
	workspace.preferences_persistence_enabled = false
	host.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(15)
	check(workspace.get_parent() == host and not workspace._window_quit_guard_enabled,
		"Atlas owns top-level window; Drawing retains only its embedded view")
	check(workspace.dock_views["colors"] != null and workspace.color_advanced is ColorPicker and
		workspace.color_picker_scroll.get_parent() == workspace.dock_views["colors"],
		"embedded Atlas uses exact same scrollable native picker")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, TILE_SIZE).ok,
		"native Atlas campaign and drawing registry initialized")
	var atlas_doc: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer: String = str(atlas_doc.create_layer(DrawingLayerNode.RASTER, "Pigment-untouched").value)
	var tile: PackedByteArray = PackedByteArray()
	tile.resize(TILE_SIZE * TILE_SIZE * 4)
	tile.encode_u32(0, ORIGINAL)
	atlas_doc._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(TILE_SIZE, tile)
	var baseline: PackedByteArray = (atlas_doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8()
	var history: int = atlas_doc.history_length()
	var revision: int = atlas_doc.revision
	var document_revision: int = workspace.current_document().revision
	var dirty: bool = workspace.current_document().is_dirty()
	check(atlas_doc.external_history and baseline.decode_u32(0) == ORIGINAL,
		"Atlas external history and hidden-RGB tile baseline are intact")
	check(workspace.dock_layout.move_group("colors", "right", 0), "bring Colors into visible dock")
	workspace._render_dock()
	await frames(8)
	await click(workspace.background_button)
	check(workspace.color_edit_background and workspace.color_advanced.color == workspace.color_background,
		"Atlas pointer selects BG for native picker")
	var brush_before: int = workspace.canvas.color_rgba
	workspace.color_hex.text = "#13579B00"
	workspace._commit_hex()
	check(workspace.color_background == Color8(19, 87, 155, 0) and
		workspace.active_color != workspace.color_background and
		workspace.canvas.color_rgba == brush_before,
		"Atlas BG edit preserves straight hidden RGB without changing paint")
	var chosen: Color = Color8(215, 99, 18, 161)
	workspace.color_advanced.color_changed.emit(chosen)
	check(workspace.color_background == chosen and workspace.color_hex.text == "#D76312A1" and
		workspace.canvas.color_rgba == brush_before,
		"Atlas native picker signal edits only current BG")
	await click(workspace.foreground_button)
	workspace.recent_colors.clear()
	workspace._remember_recent(chosen)
	workspace._remember_recent(workspace.active_color)
	workspace._refresh_color_controls()
	await frames(7)
	check(not workspace.color_recent_buttons[0].visible and not workspace.color_recent_buttons[1].visible and
		workspace.recent_colors.size() == 2,
		"Atlas recents hide both active FG and BG without discarding their history")
	# Use a distinct color so the first filtered bar is visible to the pointer.
	workspace._remember_recent(Color8(2, 74, 132, 33))
	workspace._refresh_color_controls()
	await frames(7)
	await click(workspace.color_recent_buttons[0])
	check(workspace.active_color == Color8(2, 74, 132, 33) and
		workspace.canvas.color_rgba == workspace._pack_color(workspace.active_color),
		"Atlas recent-bar pointer changes FG paint, not document raster")
	check(workspace.current_document().revision == document_revision and
		workspace.current_document().is_dirty() == dirty,
		"Atlas-embedded UI pigment changes leave workspace artwork and history untouched")
	check(atlas_doc.history_length() == history and atlas_doc.revision == revision and
		(atlas_doc.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == baseline,
		"external Atlas history and exact native raster are unchanged")
	var directory: String = ProjectSettings.globalize_path("user://t226-atlas-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create temporary Atlas generation")
	var path: String = directory.path_join("Colors.scn")
	var saved: DrawingResult = AtlasCampaignBundle.save(campaign, registry, null, path)
	check(saved.ok, "Atlas generation saves after palette-only interactions")
	if saved.ok:
		var opened: AtlasStoreResult = AtlasCampaignBundle.load(path)
		check(opened.error == OK and opened.registry != null, "Atlas generation reopens")
		if opened.error == OK:
			var restored: DrawingResult = opened.registry.document_at("world", "ground", 1)
			check(restored.ok and
				(restored.value.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == baseline,
				"RGBA8 zero-alpha hidden RGB survives Atlas Save/Open exactly")
	remove_tree(directory)
	check(not DirAccess.dir_exists_absolute(directory), "Atlas temporary generation cleaned")
	print("T226_ATLAS: %d checks; %d failed" % [checks, failed])
	print("T226_ATLAS_PASSED" if failed == 0 else "T226_ATLAS_FAILED")
	quit(0 if failed == 0 else 1)
