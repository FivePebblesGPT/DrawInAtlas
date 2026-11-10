extends SceneTree
## T-092 deterministic contracts: read-only history labels and app preference persistence.
const PREF_FILE: String = "user://t092-model-preferences.json"
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T092_MODEL_FAILED: " + label)

func frames(n: int = 3) -> void:
	for _i: int in range(n):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_FILE + ".bak"))
	check(DrawingWorkspacePreferences.decode({}).is_empty(), "missing schema rejected")
	check(DrawingWorkspacePreferences.decode({"schema": 5, "record_selection_history": true}).is_empty(), "future schema rejected")
	check(DrawingWorkspacePreferences.decode({"schema": 1, "record_selection_history": 1}).is_empty(), "nonboolean toggle rejected")
	check(DrawingWorkspacePreferences.read_file(PREF_FILE).is_empty(), "no settings defaults safely")
	check(DrawingWorkspacePreferences.save_file(PREF_FILE, true), "atomic preference write true")
	check(DrawingWorkspacePreferences.read_file(PREF_FILE).get("record_selection_history") == true,
		"preference reopens independently")
	check(DrawingWorkspacePreferences.save_file(PREF_FILE, false), "atomic replacement false")
	check(DrawingWorkspacePreferences.read_file(PREF_FILE).get("record_selection_history") == false,
		"updated preference reopens")
	check(not FileAccess.file_exists(PREF_FILE + ".bak") and not FileAccess.file_exists(PREF_FILE + ".tmp"),
		"successful write cleans transient files")
	var overflow: FileAccess = FileAccess.open(PREF_FILE, FileAccess.WRITE)
	overflow.store_buffer(PackedByteArray()); overflow.store_string("x".repeat(2100)); overflow.close()
	check(DrawingWorkspacePreferences.read_file(PREF_FILE).is_empty(), "oversized settings rejected")
	check(DrawingWorkspacePreferences.save_file(PREF_FILE, true), "recover invalid settings")
	var absolute: String = ProjectSettings.globalize_path(PREF_FILE)
	check(DirAccess.rename_absolute(absolute, absolute + ".bak") == OK,
		"simulate interrupted replacement")
	check(DrawingWorkspacePreferences.read_file(PREF_FILE).get("record_selection_history") == true,
		"backup fallback preserves last committed preference")
	check(DrawingWorkspacePreferences.save_file(PREF_FILE, false), "backup repaired by next write")
	var doc: DrawingDocument = DrawingDocument.new("t092-history")
	check(doc.history_length() == 0 and doc.history_position() == 0 and doc.history_summaries().is_empty(),
		"new model has empty history")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink", -1, true).value)
	check(layer == "ink" and doc.history_summaries() == ["Add · Ink"], "create history uses stable layer name")
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(edit._stage(-4, 9, 0x00aa55ee).ok and edit.commit().ok, "exact hidden-RGB raster edit")
	check(doc.history_summaries() == ["Add · Ink", "Raster edit · Ink"] and doc.history_position() == 2,
		"one committed brush step with label and index")
	check(doc.rename_layer(layer, "Ink 2", true).ok and doc.set_visibility(layer, false, true).ok,
		"rename and visibility are structural gestures")
	check(doc.history_summaries()[-2] == "Rename · Ink 2" and doc.history_summaries()[-1] == "Visibility · Ink 2",
		"structural descriptions preserve meaning")
	var before_revision: int = doc.revision
	check(doc.undo().ok and doc.history_position() == 3 and doc.revision > before_revision,
		"undo moves cursor backwards while revision increases")
	check(doc.redo().ok and doc.history_position() == 4,
		"redo moves cursor independently")
	check(doc.history_summaries(2, 1).size() == 1 and doc.history_summaries(2, 1)[0] == "Rename · Ink 2",
		"bounded history summary slices")
	var selection_doc: DrawingDocument = DrawingDocument.new("t092-selection")
	selection_doc.record_selection_history = true
	var before: DrawingHistoryContext = DrawingHistoryContext.new()
	before.document_id = selection_doc.id
	var after: DrawingHistoryContext = before.detached_copy()
	after.selection_mask = DrawingSelection.new(Rect2i(-3, -3, 4, 4), true)
	check(selection_doc.record_selection_change(before, after), "selection enabled by preference")
	check(selection_doc.history_summaries() == ["Selection"] and selection_doc.revision == 0,
		"selection history not content revision")
	check(selection_doc.undo().ok and selection_doc.history_position() == 0 and selection_doc.revision == 0,
		"selection-only undo preserves monotonic revision")
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_settings_path = PREF_FILE
	root.add_child(app)
	await frames(5)
	check(not app.record_selection_history and not app.selection_history_toggle.button_pressed,
		"workspace restores false preference before creating tab")
	check(not app.current_document().record_selection_history, "new document inherits saved setting")
	var rev: int = app.current_document().revision
	var dirty: bool = app.current_document().is_dirty()
	app._selection_history_preference_changed(true)
	check(app.record_selection_history and app.current_document().record_selection_history,
		"preference applies immediately without a document edit")
	check(app.current_document().revision == rev and app.current_document().is_dirty() == dirty,
		"preference does not affect revision or dirty state")
	check(DrawingWorkspacePreferences.read_file(PREF_FILE)["record_selection_history"],
		"workspace preference saved without document save")
	app.new_drawing()
	check(app.current_document().record_selection_history and app.tabs.size() == 2,
		"new tab uses same application preference")
	app._selection_history_preference_changed(false)
	check(not (app.tabs[0]["document"] as DrawingDocument).record_selection_history and
		not (app.tabs[1]["document"] as DrawingDocument).record_selection_history,
		"preference changes propagate to all already opened tabs")
	check(app.history_label.text == "0 / 0" and app.status.text.contains("history 0/0") and
		not app.status.text.contains("revision"), "user-facing cursor replaces raw revision")
	check(app.history_list.item_count == 1 and app.history_undo.disabled and app.history_redo.disabled,
		"empty History is compact and actions disabled")
	check(not app.color_advanced.visible and app.color_swatch_buttons.size() == 10,
		"compact palette and six recent swatches initialize")
	app._set_foreground(Color8(10, 20, 30, 40))
	check(app.active_color == Color8(10, 20, 30, 40) and app.color_hex.text == "#0A141E28",
		"foreground is RGBA8 and hex mirrors alpha")
	check(app.canvas.color_rgba == app._pack_color(app.active_color), "foreground feeds brush without artwork")
	check(app.recent_colors.size() == 1 and app.recent_colors[0] == app.previous_foreground,
		"previous foreground added to recent palette")
	app.color_hex.text = "#AABBCCDD"
	app._commit_hex()
	check(app.active_color == Color8(170, 187, 204, 221), "hex accepts full RGBA")
	app.color_hex.text = "not a color"
	app._commit_hex()
	check(app.active_color == Color8(170, 187, 204, 221) and app.color_hex.text == "#AABBCCDD",
		"malformed hex is rejected without changing paint")
	# Only the advertised #RRGGBB/#RRGGBBAA forms are valid. Godot's
	# Color.html_is_valid also accepts bare and abbreviated hex by default.
	var strict_before: Color = app.active_color
	var strict_brush: int = app.canvas.color_rgba
	for malformed: String in ["abc", "#abc", "#abcd", "aabbcc", "aabbccdd",
			"#12345", "#1234567", "#123456789", "#AABBCCDG", "#00FF00 00"]:
		app.color_hex.text = malformed
		app._commit_hex()
		check(app.active_color == strict_before and app.canvas.color_rgba == strict_brush and
			app.color_hex.text == "#AABBCCDD", "reject noncanonical hex: " + malformed)
	app.color_hex.text = "#00aBcD"
	app._commit_hex()
	check(app.active_color == Color8(0, 171, 205, 255) and app.color_hex.text == "#00ABCDFF",
		"six-digit mixed-case hex supplies opaque alpha and canonical RGBA")
	app.color_hex.text = "  #12345600  "
	app._commit_hex()
	check(app.active_color == Color8(18, 52, 86, 0) and app.color_hex.text == "#12345600",
		"trimmed eight-digit hex retains hidden RGB at zero alpha")
	app.color_hex.text = "#AABBCCDD"
	app._commit_hex()
	app.color_rgb[0].value = 17
	check(roundi(app.active_color.r * 255) == 17 and roundi(app.active_color.a * 255) == 221,
		"RGB field changes one channel and retains alpha")
	check(app.color_rgb.size() == 4 and int(app.color_rgb[3].value) == 221,
		"RGBA editor exposes existing alpha without a popup")
	app.color_rgb[3].value = 34
	var brush_before: Color = app.active_color
	var brush_rgba: int = app.canvas.color_rgba
	check(roundi(brush_before.a * 255) == 34 and brush_rgba == app._pack_color(brush_before),
		"alpha edit changes foreground brush and preserves RGB")
	app._color_swatch_pressed("Background")
	check(app.color_edit_background and app.color_hex.text == "#FFFFFFFF" and
		app.active_color == brush_before and app.canvas.color_rgba == brush_rgba,
		"background chip selects a distinct target instead of swapping brush pigments")
	app.color_hex.text = "#33445566"
	app._commit_hex()
	check(app.color_background == Color8(51, 68, 85, 102) and
		app.previous_background == Color.WHITE and app.active_color == brush_before and
		app.canvas.color_rgba == brush_rgba,
		"background hex changes only the secondary pigment and preserves its undo swatch")
	app.color_rgb[3].value = 0
	check(app.color_background == Color8(51, 68, 85, 0) and
		app.active_color == brush_before and app.color_hex.text == "#33445500",
		"background RGBA editing retains hidden RGB at alpha zero")
	app._color_swatch_pressed("Previous BG")
	check(app.color_background == Color8(51, 68, 85, 102) and
		app.active_color == brush_before and app.color_edit_background,
		"previous background restores background, not foreground")
	app._color_swatch_pressed("Foreground")
	check(not app.color_edit_background and app.color_hex.text == "#11BBCC22" and
		app.active_color == brush_before,
		"foreground chip returns the RGBA editor to brush pigment")
	app._swap_colors()
	check(app.active_color == Color8(51, 68, 85, 102) and app.color_background == brush_before and
		app.canvas.color_rgba == app._pack_color(app.active_color),
		"Swap alone exchanges both pigments with exact alpha")
	app._reset_colors()
	check(app.active_color == Color.BLACK and app.color_background == Color.WHITE and
		app.canvas.color_rgba == app._pack_color(Color.BLACK),
		"Default explicitly restores black foreground and white background")
	app._color_swatch_pressed("Background")
	app._set_selected_color(Color8(19, 77, 88, 99))
	check(app.color_background == Color8(19, 77, 88, 99) and app.active_color == Color.BLACK,
		"advanced picker target route respects selected background")
	app._toggle_advanced_picker()
	check(app.color_advanced.visible, "advanced picker accessible only when expanded")
	app._toggle_advanced_picker()
	check(not app.color_advanced.visible, "advanced picker closes to compact state")
	check(app.current_document().revision == rev and app.current_document().is_dirty() == dirty,
		"all color operations leave artwork and revision untouched")
	app.queue_free()
	await frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_FILE))
	print("T092_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T092_MODEL_PASSED")
	quit(0 if failures == 0 else 1)
