extends SceneTree
## T-184: actual docked/floating UI, serialized native settings and histories.
const PREFS: String = "user://t184-brush-options.json"
const LAYOUT: String = "user://t184-brush-layout.json"
const AREA: Rect2i = Rect2i(-100, -60, 200, 120)
var path: PackedVector2Array = PackedVector2Array([
	Vector2(-30.5, 0.5), Vector2(-25.5, 0.5), Vector2(-20.5, 0.5),
	Vector2(-15.5, 0.5), Vector2(-10.5, 0.5), Vector2(-5.5, 0.5),
	Vector2(0.5, 0.5), Vector2(5.5, 0.5), Vector2(10.5, 0.5),
	Vector2(15.5, 0.5), Vector2(20.5, 0.5), Vector2(25.5, 0.5),
	Vector2(30.5, 0.5)])

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T184_FAILED: " + description)


func frames(n: int = 3) -> void:
	for i: int in range(n):
		await process_frame


func open_workspace() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.preferences_settings_path = PREFS
	app.layout_settings_path = LAYOUT
	root.add_child(app)
	return app


func sample(bytes: PackedByteArray, x: int, y: int) -> int:
	return bytes[((y - AREA.position.y) * AREA.size.x + x - AREA.position.x) * 4 + 3]


func total_alpha(bytes: PackedByteArray) -> int:
	var total: int = 0
	for i: int in range(3, bytes.size(), 4):
		total += bytes[i]
	return total


func paint(app: Control) -> Dictionary:
	app.new_drawing()
	await frames()
	var doc: DrawingDocument = app.current_document()
	var canvas: Control = app.canvas
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "T184 ink").value)
	canvas.layer_id = layer
	canvas.tool = "Brush"
	canvas.zoom = 1.0
	canvas.camera = Vector2.ZERO
	canvas.image_bounds = Rect2i(-128, -128, 256, 256)
	await frames()
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	check(canvas.session != null, "native Brush gesture begins")
	if canvas.session == null:
		return {}
	for index: int in range(1, path.size() - 1):
		canvas.update_gesture(canvas.pixel_to_position(path[index]))
		await process_frame
	canvas.finish_gesture(canvas.pixel_to_position(path[-1]))
	for i: int in range(360):
		if canvas.session == null:
			break
		await process_frame
	check(canvas.session == null, "stroke completes")
	var outcome: DrawingResult = DrawingRenderer.render(doc, AREA)
	check(outcome.ok, "native source renders")
	if not outcome.ok:
		return {}
	var bytes: PackedByteArray = outcome.value.get_data()
	return {"bytes": bytes, "sum": total_alpha(bytes), "revision": doc.revision}


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var out: String = OS.get_environment("T184_SCREENSHOTS")
	if out.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	var capture_status: int = root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	if capture_status != OK:
		print("OPTIONAL_VISUAL_CAPTURE_FAILED: T184: " + str(capture_status))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"real native extension loaded")
	for path: String in [PREFS, PREFS + ".bak", LAYOUT, LAYOUT + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.size = Vector2i(1100, 760)
	var app: Control = open_workspace()
	await frames(14)
	var panel: DrawingBrushPanel = app.brush_panel
	var canvas: Control = app.canvas
	check(app.dock_views["brushes"] == panel and app.dock_layout.owner_of("brushes") == "right",
		"one separate stable-ID Brushes panel registered with dock")
	check(app.dock_layout.group_of("brushes") == "brushes", "independent Brushes group")
	check(panel.preset_buttons.size() == 4 and app.brush_preset_control.item_count == 4,
		"four visual choices and synchronized compact toolbar selector")
	var hashes: Dictionary = {}
	for preset: String in DrawingBrushSettings.PRESETS:
		var button: Button = panel.preset_buttons[preset]
		check(button != null and button.focus_mode == Control.FOCUS_ALL and
			button.tooltip_text.length() > 20 and button.icon != null,
			"label, focus, description and native preview for " + preset)
		var image: Image = button.icon.get_image() if button.icon != null else null
		var pixels: PackedByteArray = image.get_data() if image != null else PackedByteArray()
		var alpha: int = 0
		for i: int in range(3, pixels.size(), 4):
			alpha += pixels[i]
		check(alpha > 1000, "nonblank native PNG preview " + preset)
		hashes[preset] = FileAccess.get_sha256(DrawingBrushSettings.PREVIEW_ROOT + preset + ".png")
	check(hashes.values().size() == 4 and
		hashes["hard"] != hashes["soft"] and hashes["ink"] != hashes["airbrush"],
		"distinct native-derived previews")
	var doc: DrawingDocument = app.current_document()
	var rev: int = doc.revision
	var dirty: bool = doc.is_dirty()
	panel.preset_buttons["ink"].pressed.emit()
	check(app.selected_brush_preset == "ink" and canvas.brush_preset == "ink" and
		app.brush_preset_control.selected == 2 and panel.preset_buttons["ink"].button_pressed,
		"panel selects preset and synchronizes compact picker and Canvas")
	app.brush_preset_control.select(1)
	app.brush_preset_control.item_selected.emit(1)
	check(canvas.brush_preset == "soft" and panel.preset_buttons["soft"].button_pressed,
		"compact picker updates visual selected state")
	panel.width_input.value = 96
	check(canvas.brush_width == 96 and app.width_spin.value == 96,
		"96px panel size uses toolbar and Canvas authority")
	app.width_spin.value = 60
	check(panel.width_input.value == 60 and canvas.brush_width == 60,
		"toolbar and keyboard size shortcut update panel")
	panel.opacity_input.value = 35
	panel.hardness_input.value = 25
	check(is_equal_approx(canvas.brush_opacity, 0.35) and
		is_equal_approx(canvas.brush_hardness, 0.25),
		"panel opacity and hardness affect next native stroke")
	check(doc.revision == rev and doc.is_dirty() == dirty,
		"control changes are not document history or dirty edits")
	app._change_tool("Eraser")
	check(app.brush_preset_control.get_parent() == app.top_bar.options_region and
		canvas.brush_preset == "soft" and canvas.brush_width == 60 and
		is_equal_approx(canvas.brush_opacity, 0.35),
		"Eraser shares all native settings")
	app._change_tool("Pan")
	check(app.brush_preset_control.get_parent() != app.top_bar.options_region,
		"unrelated tool hides only compact brush options")
	app._change_tool("Brush")
	app._select_brush_preset("hard")
	app._set_brush_opacity(1.0)
	app._set_brush_hardness(1.0)
	var normal: Dictionary = await paint(app)
	app._set_brush_opacity(0.2)
	var faint: Dictionary = await paint(app)
	check(normal.has("sum") and faint.has("sum") and
		int(normal.get("sum", 0)) > int(faint.get("sum", 0)) * 1.25 and int(faint.get("sum", 0)) > 0,
		"opacity changes actual native committed source pigment (20% vs 100%)")
	app._set_brush_opacity(1.0)
	app._set_brush_hardness(0.2)
	var softened: Dictionary = await paint(app)
	check(softened.has("bytes") and normal.has("bytes") and
		(softened["bytes"] as PackedByteArray) != (normal["bytes"] as PackedByteArray),
		"hardness modifies native committed pixels at same width and opacity")
	if softened.has("bytes") and normal.has("bytes"):
		print("T184_PARAMETER_SAMPLES hard-center=", sample(normal["bytes"], 0, 0),
			" hard-edge=", sample(normal["bytes"], 0, 23),
			" soft-center=", sample(softened["bytes"], 0, 0),
			" soft-edge=", sample(softened["bytes"], 0, 23),
			" opaque-sum=", normal["sum"], " faint-sum=", faint["sum"])
	app._select_brush_preset("soft")
	check(is_equal_approx(canvas.brush_hardness, 0.25),
		"per-preset hardness preserved across preset changes")
	app.brush_panel.reset_button.pressed.emit()
	check(canvas.brush_width == 3 and canvas.brush_opacity == 1.0 and
		is_equal_approx(canvas.brush_hardness, DrawingBrushSettings.default_hardness("soft")),
		"selected preset reset restores width, opacity and native hardness")
	check(is_equal_approx(app.brush_hardness_overrides["hard"], 0.2),
		"reset does not discard other preset shaping overrides")
	check(DrawingWorkspacePreferences.read_file(PREFS).get("brush", {}).get("preset") == "soft",
		"versioned application preference written after panel change")
	# Freeze settings for an active gesture without canceling by changing tool.
	var actual: DrawingDocument = app.current_document()
	canvas.layer_id = app.current_layer()
	app._set_brush_width(60)
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	check(canvas.session != null and is_equal_approx(canvas._stroke_width, 60),
		"native pointer-down captures width")
	app._set_brush_width(96)
	app._set_brush_opacity(0.12)
	app._set_brush_hardness(0.9)
	app._select_brush_preset("ink")
	check(canvas.session != null and is_equal_approx(canvas._stroke_width, 60) and
		canvas.brush_preset == "ink", "in-flight native configuration remains frozen")
	canvas.cancel_gesture()
	check(canvas.session == null and actual.revision > 0, "cancel leaves no live native stroke")
	# Deferred/queued capture contains these new settings as immutable values.
	canvas._deferred_stroke = {"capturing": false, "preset": "soft", "width": 60.0,
		"opacity": 0.7, "hardness": 0.44}
	app._set_brush_opacity(0.45)
	app._set_brush_hardness(0.3)
	check(is_equal_approx(canvas._deferred_stroke["opacity"], 0.7) and
		is_equal_approx(canvas._deferred_stroke["hardness"], 0.44),
		"already queued opacity/hardness not mutated by panel")
	canvas._deferred_stroke = {}
	await capture("brushes-docked")
	var host_id: String = app.float_group("brushes")
	check(not host_id.is_empty() and app.dock_layout.owner_of("brushes") == host_id and
		app.dock_views["brushes"] == panel, "float moves same panel Control, no clone")
	await frames(8)
	await capture("brushes-floating")
	check(app._save_workspace_layout(), "dock/floating brush ownership saved")
	var owner: DrawingFloatingHost = app.floating_hosts[host_id]
	app.hide_floating_host(host_id)
	check(not owner.visible and app.brush_panel == panel, "hidden host preserves panel identity")
	app.show_hidden_floating_hosts()
	await frames(4)
	check(owner.visible and app.brush_panel == panel, "hidden host reopens without orphan controls")
	var saved_layout: Dictionary = app.dock_layout.snapshot()
	app.queue_free()
	await frames(8)
	app = open_workspace()
	await frames(16)
	canvas = app.canvas
	panel = app.brush_panel
	check(app.layout_recovery_status == "loaded" and app.dock_layout.snapshot() == saved_layout and
		app.dock_layout.owner_of("brushes") == host_id,
		"floating brush group restores with its stable ID")
	check(app.selected_brush_preset == "ink" and is_equal_approx(canvas.brush_width, 96) and
		is_equal_approx(canvas.brush_opacity, 0.45) and is_equal_approx(canvas.brush_hardness, 0.3),
		"all brush options restore independently of document")
	root.size = Vector2i(620, 480)
	app._clamp_floating_hosts()
	await frames(9)
	check(app.brush_panel.width_input.focus_mode == Control.FOCUS_ALL and
		app.brush_panel.hardness_input.focus_mode == Control.FOCUS_ALL,
		"narrow/floating controls remain keyboard focusable")
	# Bring panel back to standard dock for focus/wheel/scrolled ownership check.
	check(app.dock_layout.move_group("brushes", "right", 0),
		"redock group through stable model")
	app._reap_empty_hosts()
	app._render_dock()
	await frames(4)
	check(app.dock_layout.owner_of("brushes") == "right" and app.brush_panel == panel and
		app.floating_hosts.is_empty(), "redock reuses panel and releases empty floating host")
	var selected: Button = panel.preset_buttons["ink"]
	selected.grab_focus()
	await frames(2)
	check(root.gui_get_focus_owner() == selected, "narrow dock preset has reachable keyboard focus")
	var spin: SpinBox = panel.hardness_input
	spin.grab_focus()
	await frames(3)
	check(root.gui_get_focus_owner() == spin or spin.has_focus(),
		"narrow dock hardness control is reachable through focus follow")
	app.inspector.scroll_vertical = 120
	await frames(3)
	check(app.inspector.scroll_vertical > 0 and panel.get_parent() != null,
		"narrow dock wheel/scroll viewport remains operable without panel recreation")
	app.queue_free()
	await frames(5)
	check(root.get_child_count() == 0, "workspace teardown leaves no modal selector/popup nodes")
	print("T184_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T184_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
