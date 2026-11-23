extends SceneTree
## T-184 native app witness: visual preset panel, settings and dock ownership.
## Run under X11 with both native drawing classes; actual committed RGBA8 is
## inspected rather than treating a MyPaint JSON setting as evidence of output.

const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")
const PREFERENCES: Script = preload("res://addons/drawing/workspace_preferences.gd")
const AREA: Rect2i = Rect2i(-80, -40, 160, 80)
const PREF_PATH: String = "user://t184-brush-panel-preferences.json"
const LAYOUT_PATH: String = "user://t184-brush-panel-layout.json"
const PATH: Array[Vector2] = [Vector2(-27.5, 0.5), Vector2(-16.5, 0.5),
	Vector2(-5.5, 0.5), Vector2(5.5, 0.5), Vector2(16.5, 0.5), Vector2(27.5, 0.5)]

var checks: int = 0
var failures: int = 0


func check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T184_FAILED: " + reason)


func frames(count: int = 3) -> void:
	for _index: int in range(count):
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


func alpha_sum(pixels: PackedByteArray) -> int:
	var result: int = 0
	for index: int in range(3, pixels.size(), 4):
		result += pixels[index]
	return result


func alpha_at(pixels: PackedByteArray, x: int, y: int) -> int:
	return pixels[((y - AREA.position.y) * AREA.size.x + x - AREA.position.x) * 4 + 3]


func stroke(app: Control, tool: String = "Brush", mutate_after_down: bool = false) -> PackedByteArray:
	var canvas: Control = app.canvas
	app._change_tool(tool)
	canvas.zoom = 1.0
	canvas.camera = Vector2.ZERO
	canvas.image_bounds = Rect2i(-128, -128, 256, 256)
	var document: DrawingDocument = app.current_document()
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "T184 native").value)
	canvas.layer_id = layer
	app.set_meta("t184_last_layer", layer)
	var prior: int = document.revision
	canvas.start_gesture(canvas.pixel_to_position(PATH[0]))
	check(canvas.session != null, "native session starts")
	if canvas.session == null:
		return PackedByteArray()
	if mutate_after_down:
		app._set_brush_opacity(0.1)
		app._set_brush_hardness(0.25)
		app._select_brush_preset("soft")
		app._set_brush_width(96.0)
	for index: int in range(1, PATH.size() - 1):
		canvas.update_gesture(canvas.pixel_to_position(PATH[index]))
		await process_frame
	canvas.finish_gesture(canvas.pixel_to_position(PATH[-1]))
	for _index: int in range(360):
		if canvas.session == null:
			break
		await process_frame
	check(canvas.session == null, "native transaction drains")
	var output: DrawingResult = DrawingRenderer.render(document, AREA)
	check(output.ok and document.revision == prior + 1, "native stroke committed once")
	return output.value.get_data() if output.ok else PackedByteArray()


func sample_native(preset: String, opacity: float, hardness: float,
		mutate_after_down: bool = false) -> PackedByteArray:
	var app: Control = open_app()
	await frames()
	app._select_brush_preset(preset)
	app._set_brush_width(24.0)
	app._set_brush_opacity(opacity)
	app._set_brush_hardness(hardness)
	var result: PackedByteArray = await stroke(app, "Brush", mutate_after_down)
	await close_app(app)
	return result


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	check(DisplayServer.get_name() != "headless" and
		ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"real graphical native Hokusai backend loaded")
	if failures:
		quit(1)
		return
	root.size = Vector2i(1060, 740)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LAYOUT_PATH + ".bak"))
	var app: Control = open_app(true)
	await frames(14)
	var panel: DrawingBrushPanel = app.brush_panel
	check(panel != null and app.dock_views.get("brushes") == panel and
		app.dock_layout.owner_of("brushes") == "right", "one separate Brushes view and dock ID")
	check(app.dock_layout.group_of("brushes") == "brushes", "Brushes has own movable group")
	var document: DrawingDocument = app.current_document()
	var revision: int = document.revision
	var dirty: bool = document.is_dirty()
	var signatures: Dictionary = {}
	for preset: String in SETTINGS.PRESETS:
		var button: Button = panel.preset_buttons[preset]
		check(button.icon != null and button.focus_mode == Control.FOCUS_ALL and
			button.tooltip_text.length() > 12, "native preview, keyboard and behavior label: " + preset)
		var image: Image = button.icon.get_image()
		var alpha: PackedByteArray = image.get_data()
		check(not image.is_empty() and alpha_sum(alpha) > 0,
			"native raster preview contains source-backed pixels: ")
		signatures[preset] = FileAccess.get_sha256(SETTINGS.PREVIEW_ROOT + preset + ".png")
		button.pressed.emit()
		check(app.canvas.brush_preset == preset and app.selected_brush_preset == preset and
			app.brush_preset_control.selected == SETTINGS.PRESETS.find(preset) and
			button.button_pressed, "panel -> Canvas + compact picker synchronized: " + preset)
		var original: Dictionary = SETTINGS.preset_data(preset)["settings"]
		var mapped: Dictionary = JSON.parse_string(SETTINGS.configured_preset(preset, 0.4, 0.3))
		check(not mapped.is_empty() and
			absf(float(mapped["settings"]["opaque"]["base_value"]) -
			float(original["opaque"]["base_value"]) * 0.4) < 0.0001 and
			is_equal_approx(float(mapped["settings"]["hardness"]["base_value"]), 0.3),
			"native opaque base and hardness are configured: " + preset)
		check(mapped["settings"]["opaque"]["inputs"] == original["opaque"]["inputs"] and
			mapped["settings"]["opaque_multiply"]["inputs"] == original["opaque_multiply"]["inputs"],
			"native pressure/speed curves preserved: " + preset)
	check(signatures.values().size() == 4 and signatures.values()[0] != signatures.values()[1] and
		signatures.values()[1] != signatures.values()[2] and signatures.values()[2] != signatures.values()[3] and
		signatures.values()[0] != signatures.values()[3], "all four preview pixels are distinct")
	check(SETTINGS.configured_preset("bad", 1.0, 1.0).is_empty() and
		SETTINGS.configured_preset("hard", -0.1, 1.0).is_empty() and
		SETTINGS.configured_preset("hard", NAN, 1.0).is_empty(),
		"invalid preset, range, and nonfinite values rejected")
	panel.width_input.value = 96.0
	panel.opacity_input.value = 45.0
	panel.hardness_input.value = 30.0
	check(app.canvas.brush_width == 96.0 and is_equal_approx(app.canvas.brush_opacity, 0.45) and
		is_equal_approx(app.canvas.brush_hardness, 0.3), "panel 96px/opacity/hardness reach Canvas")
	app.brush_preset_control.select(0)
	app.brush_preset_control.item_selected.emit(0)
	check(panel.preset_buttons["hard"].button_pressed and
		is_equal_approx(panel.hardness_input.value, SETTINGS.default_hardness("hard") * 100.0),
		"compact picker changes visual active preset and native default")
	app.width_spin.value = 70.0
	check(panel.width_input.value == 70.0, "toolbar size mirrors panel")
	app._change_tool("Eraser")
	check(app.canvas.brush_preset == "hard" and app.canvas.brush_width == 70.0 and
		is_equal_approx(app.canvas.brush_opacity, 0.45), "Eraser shares live native brush authority")
	app._change_tool("Pan")
	app._change_tool("Brush")
	check(panel.width_input.value == 70.0 and panel.preset_buttons["hard"].button_pressed,
		"tool switches preserve selection/size")
	panel.reset_button.pressed.emit()
	check(app.canvas.brush_width == 3.0 and app.canvas.brush_opacity == 1.0 and
		app.canvas.brush_hardness == SETTINGS.default_hardness("hard"),
		"reset restores native preset hardness plus shared defaults")
	check(document.revision == revision and document.is_dirty() == dirty,
		"only editing brush controls never creates art/history")
	var saved: Dictionary = PREFERENCES.read_file(PREF_PATH)
	check(saved.get("brush", {}).get("preset") == "hard" and
		is_equal_approx(float(saved.get("brush", {}).get("width", -1)), 3.0),
		"brush preference atomically persisted")
	# Per-preset hardness, opacity and width survive a workspace relaunch.
	app._select_brush_preset("soft")
	app._set_brush_hardness(0.42)
	app._set_brush_opacity(0.64)
	app._set_brush_width(96.0)
	await close_app(app)
	app = open_app(true)
	await frames(12)
	panel = app.brush_panel
	check(app.selected_brush_preset == "soft" and app.canvas.brush_width == 96.0 and
		is_equal_approx(app.canvas.brush_opacity, 0.64) and
		is_equal_approx(app.canvas.brush_hardness, 0.42), "brush preferences restore across relaunch")
	app._select_brush_preset("hard")
	check(is_equal_approx(app.canvas.brush_hardness, SETTINGS.default_hardness("hard")),
		"per-preset hardness does not bleed onto other brushes")
	app._select_brush_preset("soft")
	check(is_equal_approx(app.canvas.brush_hardness, 0.42), "saved per-preset override restored")
	var invalid: Dictionary = {"schema": 2, "record_selection_history": false,
		"brush": {"preset": "hard", "width": 96.0, "opacity": 2.0, "hardness": {}}}
	check(PREFERENCES.decode(invalid).is_empty() and
		PREFERENCES.decode({"schema": 1, "record_selection_history": true})["record_selection_history"],
		"v2 validation rejects corrupt controls and migrates v1")
	# Dock/scroll/view ownership use the same workspace model as existing panels.
	root.size = Vector2i(430, 610)
	await frames(15)
	check(app.dock_tab_buttons.has("brushes") and panel.get_parent() == app.dock_group_frames["brushes"],
		"narrow dock keeps Brushes as native Control")
	panel.reset_button.grab_focus()
	await frames(5)
	check(panel.reset_button.has_focus() and panel.reset_button.focus_mode == Control.FOCUS_ALL,
		"narrow keyboard focus reaches scrolled parameter control")
	app.inspector.ensure_control_visible(panel.reset_button)
	await frames(5)
	check(app.inspector.scroll_vertical > 0 or
		panel.reset_button.get_global_rect().end.y <= app.inspector.get_global_rect().end.y,
		"Brushes focused control is visible, with scrolling only when needed")
	app.inspector.scroll_vertical = 0
	await frames(4)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.position = app.inspector.get_global_rect().position + Vector2(7.0, 65.0)
	wheel.global_position = wheel.position
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel, true)
	await frames(8)
	check(app.inspector.scroll_vertical > 0, "actual mouse wheel scrolls narrow Brushes panel")
	var host_id: String = app.float_group("brushes")
	await frames(8)
	check(not host_id.is_empty() and app.dock_layout.owner_of("brushes") == host_id and
		app.dock_views["brushes"] == panel, "float reparents the one Brushes view")
	app.hide_floating_host(host_id)
	check(not app.floating_hosts[host_id].visible and app.dock_layout.owner_of("brushes") == host_id,
		"hidden floating Brushes retains ownership")
	app.show_hidden_floating_hosts()
	check(app.floating_hosts[host_id].visible, "hidden Brushes host recovers")
	check(app._save_workspace_layout(), "floating Brushes layout saved")
	await close_app(app)
	app = open_app(true)
	await frames(20)
	check(app.layout_recovery_status == "loaded" and app.floating_hosts.size() == 1 and
		app.dock_layout.owner_of("brushes") == host_id, "floating Brushes layout restored")
	check(app.brush_panel.get_parent() != app.dock_stash, "single panel view restored into floating host")
	app.reset_workspace_layout()
	await frames(9)
	check(app.floating_hosts.is_empty() and app.dock_layout.owner_of("brushes") == "right",
		"reset removes floating host and reparents Brushes")
	var frozen_revision: int = app.current_document().revision
	app._select_brush_preset("hard")
	app._set_brush_opacity(1.0)
	app.canvas._capture_deferred_stroke(app.canvas.pixel_to_position(Vector2(0.5, 0.5)))
	var captured: Dictionary = app.canvas._deferred_stroke.duplicate(true)
	app._set_brush_opacity(0.2)
	app._select_brush_preset("ink")
	check(captured["preset"] == "hard" and captured["opacity"] == 1.0 and
		is_equal_approx(float(captured["hardness"]), SETTINGS.default_hardness("hard")) and
		app.canvas._deferred_stroke["preset"] == "hard" and
		app.canvas._deferred_stroke["opacity"] == 1.0,
		"queued gesture freezes preset/opacity before later edits")
	app.canvas._discard_deferred_stroke()
	check(app.current_document().revision == frozen_revision,
		"queued cancellation and reset do not edit document")
	await close_app(app)
	root.size = Vector2i(1060, 740)
	var full: PackedByteArray = await sample_native("hard", 1.0, 1.0)
	var light: PackedByteArray = await sample_native("hard", 0.15, 1.0)
	var soft_tip: PackedByteArray = await sample_native("hard", 1.0, 0.25)
	var frozen: PackedByteArray = await sample_native("hard", 1.0, 1.0, true)
	check(not full.is_empty() and alpha_sum(full) > 10000, "full native hard brush deposits pigment")
	check(alpha_sum(light) < alpha_sum(full) * 0.75,
		"native opacity parameter actually lowers committed RGBA8 coverage")
	check(alpha_at(soft_tip, 0, 11) < alpha_at(full, 0, 11) and
		alpha_sum(soft_tip) < alpha_sum(full), "native hardness parameter feathers committed edge")
	check(alpha_sum(frozen) > alpha_sum(light) * 1.5 and
		alpha_at(frozen, 0, 0) >= alpha_at(light, 0, 0),
		"changing panel controls during a native gesture does not retroactively alter it")
	# Eraser uses the same preset/native settings and retains exact Undo/Redo.
	var erase_app: Control = open_app()
	await frames()
	erase_app._select_brush_preset("hard")
	erase_app._set_brush_width(24.0)
	erase_app._set_brush_opacity(1.0)
	erase_app._set_brush_hardness(1.0)
	var painted: PackedByteArray = await stroke(erase_app)
	var erase_document: DrawingDocument = erase_app.current_document()
	var erase_canvas: Control = erase_app.canvas
	var eraser_revision: int = erase_document.revision
	erase_app._set_brush_opacity(0.7)
	erase_app._set_brush_hardness(0.6)
	erase_app._change_tool("Eraser")
	check(erase_canvas.brush_preset == "hard" and erase_canvas.brush_width == 24.0 and
		is_equal_approx(erase_canvas.brush_opacity, 0.7),
		"Eraser inherits the panel's live settings")
	check(erase_document.revision == eraser_revision,
		"changing native Eraser settings does not create document history")
	erase_canvas.layer_id = str(erase_app.get_meta("t184_last_layer"))
	erase_canvas.start_gesture(erase_canvas.pixel_to_position(PATH[0]))
	check(erase_canvas.session != null, "Eraser opens native tile transaction")
	if erase_canvas.session != null:
		for index: int in range(1, PATH.size() - 1):
			erase_canvas.update_gesture(erase_canvas.pixel_to_position(PATH[index]))
			await process_frame
		erase_canvas.finish_gesture(erase_canvas.pixel_to_position(PATH[-1]))
		for _index: int in range(360):
			if erase_canvas.session == null:
				break
			await process_frame
		check(erase_canvas.session == null, "Eraser native transaction drains")
		var erased_result: DrawingResult = DrawingRenderer.render(erase_document, AREA)
		check(erased_result.ok, "Eraser produces native source")
		if erased_result.ok:
			var erased: PackedByteArray = erased_result.value.get_data()
			print("T184_ERASE ", alpha_sum(painted), " -> ", alpha_sum(erased),
				" current_layer=", erase_app.current_layer(), " target=", erase_canvas.layer_id)
			check(alpha_sum(erased) < alpha_sum(painted) and
				alpha_sum(erased) > 0, "Eraser reduces source pigment with shared brush parameters")
			check(erase_document.undo().ok and
				DrawingRenderer.render(erase_document, AREA).value.get_data() == painted,
				"native Eraser Undo restores exact RGBA8")
			check(erase_document.redo().ok and
				DrawingRenderer.render(erase_document, AREA).value.get_data() == erased,
				"native Eraser Redo restores exact RGBA8")
	await close_app(erase_app)
	print("T184_NATIVE_EFFECTS ", JSON.stringify({"full_sum": alpha_sum(full),
		"light_sum": alpha_sum(light), "soft_tip_sum": alpha_sum(soft_tip),
		"frozen_sum": alpha_sum(frozen), "edge_full": alpha_at(full, 0, 11),
		"edge_soft": alpha_at(soft_tip, 0, 11)}))
	print("T184_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T184_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
