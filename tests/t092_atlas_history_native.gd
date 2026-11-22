extends SceneTree
## T-092: embedded Drawing History/Preferences must never seize Atlas global history.
## Execute with the mandatory native GDExtension and real software X11 display.

const TILE_SIZE: int = 64
const PIGMENT: int = 0x00337799 # Zero alpha retains the source's hidden RGB.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T092_ATLAS_FAILED: " + label)


func frames(count: int = 4) -> void:
	for _i: int in range(count):
		await process_frame


func context(document: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.document_id = document.id
	result.selected_layer_ids.append(layer)
	return result


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var host: Control = Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var app: Control = load("res://addons/drawing/workspace.gd").new()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	host.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(16)
	check(app.get_parent() == host and not app._window_quit_guard_enabled,
		"embedded workspace leaves window lifetime to Atlas")
	check(not app.record_selection_history and app.current_document().history_length() == 0,
		"fresh embedded Drawing starts with local history and selection logging off")

	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, TILE_SIZE).ok,
		"Atlas registry owns a real shared Drawing document")
	var selected: DrawingResult = registry.document_at("world", "ground", 1, true)
	check(selected.ok, "Atlas detail resolves")
	if not selected.ok:
		quit(1)
		return
	var document: DrawingDocument = selected.value as DrawingDocument
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Atlas ink").value)
	var global_history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	global_history.active_map_id = "world"
	var begun: DrawingResult = document.begin_edit(layer, document.revision)
	check(begun.ok, "native Atlas edit session opens")
	if not begun.ok:
		quit(1)
		return
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	check(edit.fill_rect(Rect2i(-1, 1, 1, 1), PIGMENT).ok,
		"signed RGBA8 hidden-RGB pixel staged")
	var ctx: DrawingHistoryContext = context(document, layer)
	var committed: DrawingResult = global_history.commit_drawing(edit, ctx, ctx)
	check(committed.ok and global_history.can_undo() and not document.can_undo() and
		document.external_history,
		"one Atlas-owned native history event, no local Drawing Undo")
	var starting_revision: int = document.revision
	var starting_pixel: int = int(document.read_pixel(layer, -1, 1).value)
	check(starting_pixel == PIGMENT, "native pixel source has exact zero-alpha RGB")

	# Integration adapter: the common view displays the same host-owned document;
	# no duplicate workspace/history implementation exists inside Atlas.
	app.tabs[0]["document"] = document
	app.tabs[0]["layer"] = layer
	app.tabs[0]["selected_node"] = layer
	app._activate(0)
	await frames(5)
	app._refresh_history()
	check(app.canvas.document == document and app.current_document() == document,
		"shared Drawing view is bound to the real Atlas-owned document")
	check(app.history_list.item_count == 1 and
		app.history_list.get_item_text(0) == "History owned by host" and
		app.history_undo.disabled and app.history_redo.disabled and
		app._history_row_positions.is_empty(),
		"History panel names Atlas ownership and disables local playback")
	check(app.history_label.text == "0 / 0" and app.status.text.contains("history 0/0"),
		"History cursor exposes no misleading local revision")

	app._selection_history_preference_changed(true)
	await frames(3)
	check(app.record_selection_history and app.selection_history_toggle.button_pressed and
		document.record_selection_history,
		"Edit Preferences propagates selection logging to current document")
	var foreground: int = app.canvas.color_rgba
	app._color_swatch_pressed("Background")
	app.color_hex.text = "#AABBCC00"
	app._commit_hex()
	check(app.color_background == Color8(170, 187, 204, 0) and
		app.canvas.color_rgba == foreground,
		"embedded BG color keeps exact hidden RGB and leaves Brush foreground")
	check(document.revision == starting_revision and
		int(document.read_pixel(layer, -1, 1).value) == PIGMENT and
		global_history.can_undo() and not document.can_undo(),
		"UI-only preference/color changes leave Atlas tile/history untouched")
	app._history_item_selected(0)
	check(app.history_list.item_count == 1 and global_history.can_undo() and
		int(document.read_pixel(layer, -1, 1).value) == PIGMENT,
		"clicking host-owned History placeholder cannot replay Atlas commands")

	app.new_drawing()
	check(app.tabs.size() == 2 and app.current_document() != document and
		app.current_document().record_selection_history,
		"new local tab inherits the independent application preference")
	app._selection_history_preference_changed(false)
	check(not document.record_selection_history and
		not app.current_document().record_selection_history,
		"disabling selection logging propagates across local and Atlas tabs")
	app._activate(0)
	app._refresh_history()
	check(app.current_document() == document and app.history_undo.disabled and
		app.history_redo.disabled and app.history_list.item_count == 1,
		"switching back cannot turn Atlas history into local history")
	check(global_history.undo() and int(document.read_pixel(layer, -1, 1).value) == 0,
		"global Atlas Undo still restores native tile")
	check(global_history.redo() and int(document.read_pixel(layer, -1, 1).value) == PIGMENT,
		"global Atlas Redo retains hidden RGB without a local history entry")
	check(document.external_history and document.history_length() == 0,
		"external History authority survives the preference/tab/Undo sequence")
	app.queue_free()
	host.queue_free()
	await frames()
	print("T092_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0:
		print("T092_ATLAS_PASSED")
	quit(0 if failures == 0 else 1)
