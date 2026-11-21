extends SceneTree
## T-227: native Hokusai pixel, freeze, Undo/Redo, Save/Open and compact UX.
const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")
const AREA: Rect2i = Rect2i(-96, -80, 192, 160)
const PATH: Array[Vector2] = [Vector2(-48.5, 0.5), Vector2(-32.5, 0.5),
	Vector2(-16.5, 0.5), Vector2(0.5, 0.5), Vector2(16.5, 0.5),
	Vector2(32.5, 0.5), Vector2(48.5, 0.5)]
const PREF_PATH: String = "user://t227-brush-preferences.json"
const LAYOUT_PATH: String = "user://t227-brush-layout.json"
const SAVE_PATH: String = "user://t227-density-native.drawing"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T227_NATIVE_FAILED: " + label)

func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame

func open_app(persist: bool = false) -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.preferences_persistence_enabled = persist
	app.layout_persistence_enabled = persist
	app.preferences_settings_path = PREF_PATH
	app.layout_settings_path = LAYOUT_PATH
	root.add_child(app)
	return app

func close_app(app: Control) -> void:
	root.remove_child(app)
	app.queue_free()
	await frames(7)

func alpha_sum(bytes: PackedByteArray) -> int:
	var sum: int = 0
	for i: int in range(3, bytes.size(), 4):
		sum += bytes[i]
	return sum

func paint(app: Control, density: float, width: float = 16.0,
		mutate_after_down: bool = false) -> Dictionary:
	app._select_brush_preset("hard")
	app._set_brush_width(width)
	app._set_brush_opacity(0.55)
	app._set_brush_density(density)
	app._change_tool("Brush")
	var doc: DrawingDocument = app.current_document()
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Native density").value)
	var canvas: Control = app.canvas
	canvas.layer_id = layer
	canvas.zoom = 1.0
	canvas.camera = Vector2.ZERO
	canvas.image_bounds = Rect2i(-128, -128, 256, 256)
	var revision: int = doc.revision
	var elapsed_start: int = Time.get_ticks_usec()
	canvas.start_gesture(canvas.pixel_to_position(PATH[0]))
	check(canvas.session != null and canvas._active_brush_backend == "Hokusai",
		"real native Hokusai gesture started")
	if canvas.session == null:
		return {}
	if mutate_after_down:
		app._set_brush_density(1.0)
		app._set_brush_opacity(0.1)
		app._select_brush_preset("airbrush")
	for i: int in range(1, PATH.size() - 1):
		canvas.update_gesture(canvas.pixel_to_position(PATH[i]))
		await process_frame
	canvas.finish_gesture(canvas.pixel_to_position(PATH[-1]))
	for _i: int in range(360):
		if canvas.session == null:
			break
		await process_frame
	var elapsed_us: int = Time.get_ticks_usec() - elapsed_start
	check(canvas.session == null and doc.revision == revision + 1,
		"native single-commit stroke finishes")
	var result: DrawingResult = DrawingRenderer.render(doc, AREA)
	check(result.ok, "native source renders immutable RGBA8")
	return {"pixels": result.value.get_data() if result.ok else PackedByteArray(),
		"layer": layer, "elapsed_us": elapsed_us}

func capture(label: String) -> void:
	var folder: String = OS.get_environment("T227_SCREENSHOTS")
	if folder.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK,
		"native screenshot: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(DisplayServer.get_name() != "headless" and
		ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"real X11 and Rust extension")
	if failures:
		quit(1)
		return
	for path: String in [PREF_PATH, PREF_PATH + ".bak", LAYOUT_PATH, LAYOUT_PATH + ".bak", SAVE_PATH]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1060, 720)
	var app: Control = open_app(true)
	await frames(16)
	var panel: DrawingBrushPanel = app.brush_panel
	check(panel.preset_grid.columns == 2 and panel.preset_grid.get_child_count() == 4,
		"two-column visual preset selector displayed")
	check(panel.get_global_rect().size.x <= 285.0 and panel.density_input.size.x > 50.0,
		"compact panel fits standard dock without horizontal overflow")
	check(panel.density_input.focus_mode == Control.FOCUS_ALL and
		panel.density_input.tooltip_text.contains("Native dabs") and
		panel.density_input.accessibility_name.contains("Dabs/r"),
		"density edit has accessible name and documented native meaning")
	var first_revision: int = app.current_document().revision
	var first_dirty: bool = app.current_document().is_dirty()
	app._select_brush_preset("soft")
	panel.density_input.value = 7.0
	app._set_brush_width(96.0)
	check(app.canvas.brush_density == 7.0 and
		app.brush_density_overrides.get("soft") == 7.0 and
		app.canvas.brush_width == 96.0, "panel controls native 96px + density")
	app._change_tool("Eraser")
	check(app.canvas.brush_density == 7.0 and app.canvas.brush_width == 96.0,
		"Eraser uses same native settings authority")
	check(app.current_document().revision == first_revision and
		app.current_document().is_dirty() == first_dirty, "settings alone never edit history")
	await capture("compact")
	for scale: float in [1.5, 2.0]:
		root.size = Vector2i(1160, 800)
		root.content_scale_factor = scale
		await frames(9)
		check(panel.preset_grid.columns == 2 and panel.density_input.is_visible_in_tree() and
			panel.get_global_rect().size.x < root.size.x * 0.55,
			"HiDPI compact panel retains two-column selector and density field: " + str(scale))
		await capture("scale-" + str(int(scale * 100)))
	root.content_scale_factor = 1.0
	root.size = Vector2i(1060, 720)
	await frames(8)

	await close_app(app)
	app = open_app(true)
	await frames(14)

	check(app.selected_brush_preset == "soft" and app.canvas.brush_width == 96.0 and
		app.canvas.brush_density == 7.0 and app.brush_panel.density_input.value == 7.0,
		"relaunch restores per-preset density and 96px width")
	app._select_brush_preset("ink")
	check(is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("ink")),
		"other preset retains real bundled default")
	app._select_brush_preset("soft")
	check(app.canvas.brush_density == 7.0, "selected preset restores its own override")
	var before: int = app.current_document().revision
	app.canvas._capture_deferred_stroke(app.canvas.pixel_to_position(Vector2(0.5, 0.5)))
	check(is_equal_approx(float(app.canvas._deferred_stroke.get("density", -1.0)), 7.0),
		"queued gesture captures density at pointer down")
	app._set_brush_density(2.0)
	check(float(app.canvas._deferred_stroke.get("density", -1.0)) == 7.0,
		"queued gesture density stays frozen after UI change")
	app.canvas._discard_deferred_stroke()
	check(app.current_document().revision == before, "queued cancellation is non-dirty")
	root.size = Vector2i(520, 620)
	await frames(12)
	app.inspector.ensure_control_visible(app.brush_panel.density_input)
	await frames(6)
	check(app.brush_panel.density_input.is_visible_in_tree() and
		app.brush_panel.density_input.focus_mode == Control.FOCUS_ALL and
		(app.inspector.scroll_vertical > 0 or app.brush_panel.density_input.get_global_rect().end.y <= app.inspector.get_global_rect().end.y), "narrow dock keeps density control visible or scrollable")
	app.brush_panel.density_input.grab_focus()
	await frames()
	check(app.brush_panel.density_input.has_focus(), "keyboard focus works in narrow viewport")
	var host_id: String = app.float_group("brushes")
	await frames(9)
	check(not host_id.is_empty() and app.brush_panel.get_parent() != app.dock_stash,
		"single compact Brushes view reparented into floating host")
	await capture("floating")
	app.reset_workspace_layout()
	await frames(8)
	root.size = Vector2i(1060, 720)
	await frames(8)
	app._reset_selected_brush()
	check(is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("soft")) and
		not app.brush_density_overrides.has("soft"), "reset returns to bundled density")
	await close_app(app)
	var low_app: Control = open_app()
	await frames(8)
	var low: Dictionary = await paint(low_app, 1.0)
	await close_app(low_app)
	var high_app: Control = open_app()
	await frames(8)
	var high: Dictionary = await paint(high_app, 8.0)
	var pixels: PackedByteArray = high.get("pixels", PackedByteArray())
	var low_pixels: PackedByteArray = low.get("pixels", PackedByteArray())
	check(not pixels.is_empty() and pixels != low_pixels and
		alpha_sum(pixels) > 0 and alpha_sum(low_pixels) > 0,
		"different native density yields distinct committed RGBA8")
	print("T227_DENSITY_NATIVE_OUTPUT low=%d high=%d" % [alpha_sum(low_pixels), alpha_sum(pixels)])
	var doc: DrawingDocument = high_app.current_document()
	check(doc.undo().ok, "density-controlled native stroke Undo")
	var undone: DrawingResult = DrawingRenderer.render(doc, AREA)
	check(undone.ok and alpha_sum(undone.value.get_data()) == 0,
		"Undo restores transparent raster")
	check(doc.redo().ok, "density-controlled native stroke Redo")
	check(DrawingRenderer.render(doc, AREA).value.get_data() == pixels,
		"Redo restores exact native RGBA8")
	var cancel_revision: int = doc.revision
	var cancel_history: int = doc.history_length()
	var canvas: Control = high_app.canvas
	canvas.layer_id = str(high["layer"])
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-20.5, 1.5)))
	check(canvas.session != null, "cancel fixture starts native stroke")
	canvas.update_gesture(canvas.pixel_to_position(Vector2(15.5, 1.5)))
	canvas.cancel_gesture()
	await frames(4)
	check(canvas.session == null and doc.revision == cancel_revision and
		doc.history_length() == cancel_history and
		DrawingRenderer.render(doc, AREA).value.get_data() == pixels,
		"cancelled native stroke preserves exact pixels and history")
	var file: String = ProjectSettings.globalize_path(SAVE_PATH)
	check(DrawingFileIO.save(doc, file).ok, "persist native stroke in .drawing")
	var restored: DrawingResult = DrawingFileIO.open(file)
	check(restored.ok and DrawingRenderer.render(restored.value, AREA).value.get_data() == pixels,
		"Save/Open retains exact pixels and hidden RGB")
	await close_app(high_app)
	var frozen_app: Control = open_app()
	await frames(8)
	var frozen: Dictionary = await paint(frozen_app, 8.0, 16.0, true)
	check(alpha_sum(frozen.get("pixels", PackedByteArray())) > alpha_sum(low_pixels),
		"native in-flight density remains high after panel changes")
	await close_app(frozen_app)
	var wide_app: Control = open_app()
	await frames(8)
	var wide: Dictionary = await paint(wide_app, 8.0, 96.0)
	check(not (wide.get("pixels", PackedByteArray()) as PackedByteArray).is_empty() and
		alpha_sum(wide["pixels"]) > alpha_sum(pixels) and
		int(wide["elapsed_us"]) < 10000000,
		"bounded 96px native stroke produces coverage within sanity budget")
	print("T227_NATIVE_96PX elapsed_us=%d" % int(wide.get("elapsed_us", -1)))
	await close_app(wide_app)
	for path: String in [SAVE_PATH, PREF_PATH, PREF_PATH + ".bak", LAYOUT_PATH, LAYOUT_PATH + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("T227_NATIVE: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
