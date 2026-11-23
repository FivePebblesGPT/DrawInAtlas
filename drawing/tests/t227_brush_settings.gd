extends SceneTree
## T-227: mapped MyPaint density, fail-closed preferences, compact shared UI.
const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")
const PREFS: Script = preload("res://addons/drawing/workspace_preferences.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T227_SETTINGS_FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for preset: String in SETTINGS.PRESETS:
		var data: Dictionary = SETTINGS.preset_data(preset)
		var settings: Dictionary = data["settings"]
		var base: float = SETTINGS.default_density(preset)
		check(base >= SETTINGS.DENSITY_MIN and base <= SETTINGS.DENSITY_MAX,
			"supported finite bundled density for " + preset)
		check((settings["dabs_per_actual_radius"] as Dictionary)["inputs"].is_empty(),
			"no unexpected density input curve for " + preset)
		check(SETTINGS.configured_preset(preset, 1.0, SETTINGS.default_hardness(preset)) ==
			FileAccess.get_file_as_string(SETTINGS.FILES[preset]),
			"unchanged default remains exact bundled native bytes " + preset)
		var mapped: Dictionary = JSON.parse_string(SETTINGS.configured_preset(preset, 0.55, 0.4, 6.5))
		check(is_equal_approx(float(mapped["settings"]["dabs_per_actual_radius"]["base_value"]), 6.5) and
			mapped["settings"]["dabs_per_actual_radius"]["inputs"] == settings["dabs_per_actual_radius"]["inputs"],
			"native actual-radius setting mapped without destroying curves for " + preset)
		check(mapped["settings"]["radius_logarithmic"]["inputs"] == settings["radius_logarithmic"]["inputs"] and
			mapped["settings"]["opaque_multiply"]["inputs"] == settings["opaque_multiply"]["inputs"],
			"pressure/speed pigment dynamics retained for " + preset)
	for invalid: float in [0.0, 0.5, 9.0, NAN, INF, -0.5]:
		check(SETTINGS.configured_preset("hard", 1.0, 1.0, invalid).is_empty(),
			"invalid density rejected before native " + str(invalid))
	var older: Dictionary = {"schema": 2, "record_selection_history": false,
		"brush": {"preset": "ink", "width": 96.0, "opacity": 0.4, "hardness": {"ink": 0.4}}}
	check((PREFS.decode(older).get("brush", {}) as Dictionary).get("density", null) == {},
		"schema-v2 preferences remain valid without invented density")
	var new_prefs: Dictionary = {"schema": PREFS.VERSION, "record_selection_history": false,
		"brush": {"preset": "ink", "width": 96.0, "opacity": 0.4,
		"hardness": {"ink": 0.4}, "density": {"ink": 5.25}}}
	check(float(PREFS.decode(new_prefs)["brush"]["density"]["ink"]) == 5.25,
		"new per-preset density survives strict preference decode")
	check(not PREFS.decode(JSON.parse_string(JSON.stringify(new_prefs))).is_empty(),
		"version 3 round trips through actual JSON numbers")
	for invalid: Variant in [NAN, INF, 0.5, 8.5, "8", null]:
		var corrupt: Dictionary = new_prefs.duplicate(true)
		corrupt["brush"]["density"]["ink"] = invalid
		check(PREFS.decode(corrupt).is_empty(), "invalid persisted density fails closed")
	var app: Control = load("res://main.tscn").instantiate()
	app.preferences_persistence_enabled = false
	app.layout_persistence_enabled = false
	root.add_child(app)
	for i: int in range(10):
		await process_frame
	var panel: DrawingBrushPanel = app.brush_panel
	check(panel.preset_buttons.size() == SETTINGS.PRESETS.size(),
		"all native brush presets have selectable panel actions")
	for preset: String in SETTINGS.PRESETS:
		var button: Button = panel.preset_buttons[preset]
		check(button.tooltip_text.contains(" — ") and button.accessibility_name.contains("brush preset") and
			button.focus_mode == Control.FOCUS_ALL,
			"native brush preset has tooltip and keyboard access: " + preset)
	var original_revision: int = app.current_document().revision
	var original_dirty: bool = app.current_document().is_dirty()
	app._select_brush_preset("ink")
	panel.density_input.value = 7.25
	check(is_equal_approx(app.canvas.brush_density, 7.25) and
		app.brush_density_overrides["ink"] == 7.25, "panel density reaches canonical Canvas authority")
	app._set_brush_density(NAN)
	check(app.canvas.brush_density == 7.25, "nonfinite UI setter rejected")
	app._select_brush_preset("hard")
	check(is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("hard")),
		"other preset retains native density")
	app._select_brush_preset("ink")
	check(is_equal_approx(panel.density_input.value, 7.25), "returning restores own density")
	app._change_tool("Eraser")
	check(is_equal_approx(app.canvas.brush_density, 7.25), "Eraser shares density setting")
	app._reset_selected_brush()
	check(not app.brush_density_overrides.has("ink") and
		is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("ink")),
		"reset clears only active density override")
	check(app.current_document().revision == original_revision and
		app.current_document().is_dirty() == original_dirty,
		"settings do not edit document or history")
	app.queue_free()
	await process_frame
	print("T227_SETTINGS: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
