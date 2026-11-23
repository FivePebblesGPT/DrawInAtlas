extends SceneTree
## T-227: embedded Atlas shares native Brush settings without host history edits.
const SETTINGS: Script = preload("res://addons/drawing/brush_settings.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T227_ATLAS_FAILED: " + description)

func frames(n: int = 5) -> void:
	for _i: int in range(n):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(DisplayServer.get_name() != "headless" and
		ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"Atlas boots shared Rust Hokusai extension under X11")
	if failures:
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1140, 760)
	var atlas: Control = Control.new()
	root.add_child(atlas)
	atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.preferences_persistence_enabled = false
	app.layout_persistence_enabled = false
	atlas.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(16)
	var panel: DrawingBrushPanel = app.brush_panel
	check(panel == app.dock_views["brushes"],
		"embedded Atlas host shares the canonical Brushes panel")
	check(panel.preset_buttons.size() == 4 and panel.density_input.focus_mode == Control.FOCUS_ALL,
		"Atlas exposes four native preview buttons and accessible density")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok,
		"Atlas campaign and drawing registry initialized")
	var atlas_doc: DrawingDocument = registry.document_at("world", "ground", 1, true).value
	var atlas_history: int = atlas_doc.history_length()
	var atlas_revision: int = atlas_doc.revision
	var drawing_revision: int = app.current_document().revision
	var drawing_dirty: bool = app.current_document().is_dirty()
	panel.preset_buttons["airbrush"].pressed.emit()
	panel.density_input.value = 6.25
	panel.width_input.value = 96.0
	check(app.selected_brush_preset == "airbrush" and
		is_equal_approx(app.canvas.brush_density, 6.25) and app.canvas.brush_width == 96.0,
		"Atlas panel controls same Hokusai settings authority")
	app._change_tool("Eraser")
	check(app.canvas.tool == "Eraser" and app.canvas.brush_density == 6.25,
		"Atlas Eraser shares selected brush density")
	app._select_brush_preset("ink")
	check(is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("ink")),
		"native default is restored for distinct preset")
	app._select_brush_preset("airbrush")
	check(app.canvas.brush_density == 6.25 and panel.density_input.value == 6.25,
		"return to preset restores density and panel selection")
	var host_id: String = app.float_group("brushes")
	await frames(9)
	check(not host_id.is_empty() and app.brush_panel == panel and
		app.dock_layout.owner_of("brushes") == host_id,
		"floating Brushes view remains unique in Atlas")
	app.hide_floating_host(host_id)
	app.show_hidden_floating_hosts()
	await frames(7)
	check(panel == app.brush_panel and app.floating_hosts[host_id].visible,
		"hidden floating host restores original compact Brushes")
	app._reset_selected_brush()
	check(is_equal_approx(app.canvas.brush_density, SETTINGS.default_density("airbrush")) and
		app.canvas.brush_width == 3.0, "Atlas reset clears preset override")
	check(atlas_doc.revision == atlas_revision and atlas_doc.history_length() == atlas_history and
		app.current_document().revision == drawing_revision and
		app.current_document().is_dirty() == drawing_dirty,
		"changes to shared tool settings are not Atlas or Drawing history edits")
	check(app.get_parent() == atlas and not app._window_quit_guard_enabled,
		"Atlas still owns top-level window and lifetime")
	print("T227_ATLAS: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
