extends SceneTree
## T-261: Atlas-hosted ColorPicker interruption cannot leak to host timeline.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T261_ATLAS_FAILED: " + label)


func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame


func pointer(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func move(position: Vector2, held: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1360, 810)
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.preferences_persistence_enabled = false
	app.layout_persistence_enabled = false
	host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(20)
	check(not app._window_quit_guard_enabled, "Atlas remains window owner")
	check(app.dock_layout.move_group("colors", "right", 0), "Colors visible in Atlas dock")
	app._render_dock()
	await frames(8)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok,
		"real Atlas campaign and native Drawing registry")
	var atlas: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var layer: String = str(atlas.create_layer(DrawingLayerNode.RASTER, "Keep pixels").value)
	var tile: PackedByteArray = PackedByteArray()
	tile.resize(64 * 64 * 4)
	tile.encode_u32(0, 0x00BB6633)
	atlas._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(64, tile)
	var exact: PackedByteArray = (atlas.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8()
	var revision: int = atlas.revision
	var history: int = atlas.history_length()
	var foreground: Color = Color8(29, 87, 157, 0)
	app._set_foreground(foreground)
	app.recent_colors.clear()
	app.inspector.scroll_vertical = 0
	await frames(6)
	var point: Vector2 = app.color_advanced.get_global_rect().position + Vector2(37, 51)
	check(app.inspector.get_global_rect().has_point(point), "Atlas embedded native picker visible")
	pointer(point, true)
	await frames(2)
	for i: int in range(10):
		move(point + Vector2(float(i) * 4.0, float(i % 4) * 5.0), true)
		await frames(2)
	check(app._color_edit_pending and app.active_color != foreground and app.recent_colors.is_empty(),
		"Atlas held native drag previews without recents")
	app.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(4)
	check(app.active_color == foreground and app.recent_colors.is_empty() and not app._color_edit_pending,
		"Atlas interrupted drag rolls back exact alpha-zero FG")
	app.color_advanced.color_changed.emit(Color8(180, 60, 70, 0))
	await frames(3)
	check(app.active_color == foreground and app.recent_colors.is_empty(),
		"post-focus stale ColorPicker notification discarded")
	# Do not provide the old mouse-up: the next press is the recovery signal.
	pointer(point + Vector2(60, 25), true)
	await frames(2)
	for i: int in range(6):
		move(point + Vector2(60 + float(i) * 2.0, 28), true)
		await frames(2)
	pointer(point + Vector2(70, 28), false)
	await frames(6)
	check(not app._color_edit_pending and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(foreground),
		"Atlas first recovered press makes exactly one settled recent color")
	var settled: Color = app.active_color
	app.recent_colors.clear()
	pointer(point, true)
	await frames(2)
	move(point + Vector2(12, 15), true)
	await frames(3)
	move(point + Vector2(15, 17), false)
	await frames(3)
	check(not app._color_edit_pending and app.active_color == settled and app.recent_colors.is_empty(),
		"Atlas missing mouse-up cancels native preview without recording recents")
	check(atlas.revision == revision and atlas.history_length() == history and
		(atlas.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == exact,
		"Atlas source exact RGBA8 and native history remain unchanged")
	app.queue_free()
	host.queue_free()
	await frames()
	print("T261_ATLAS: %d checks; %d failures" % [checks, failures])
	print("T261_ATLAS_PASSED" if failures == 0 else "T261_ATLAS_FAILED")
	quit(0 if failures == 0 else 1)
