extends SceneTree
## T-226: exact RGBA8 color history and independent native picker targets.

var checks: int = 0
var failed: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("T226_MODEL_FAILED: " + message)

func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(6)
	var doc: DrawingDocument = app.current_document()
	var initial_revision: int = doc.revision
	var initial_dirty: bool = doc.is_dirty()
	check(app.color_advanced is ColorPicker and app.color_advanced.visible,
		"full native picker is inline and visible by default")
	check(app.color_advanced.get_parent() == app.color_picker_scroll and
		app.color_picker_scroll.get_parent() == app.dock_views["colors"],
		"native picker lives in same panel view and has no popover")
	check(app.color_recent_buttons.size() == 6 and app.color_swatch_buttons.size() == 8 and
		app.foreground_button.get_parent().get_child_count() == 3,
		"single-row FG/Swap/BG and six bars have no redundant restore buttons")
	var hidden_a: Color = Color8(12, 47, 82, 0)
	var hidden_b: Color = Color8(13, 47, 82, 0)
	app._set_foreground(hidden_a)
	app._set_background(hidden_b)
	check(app._pack_color(app.active_color) != app._pack_color(app.color_background),
		"transparent colors retain distinct hidden RGB")
	app.recent_colors.clear()
	app._remember_recent(hidden_a)
	app._remember_recent(hidden_b)
	app._remember_recent(Color8(12, 47, 82, 0))
	check(app.recent_colors.filter(func(c: Color) -> bool: return app._pack_color(c) == app._pack_color(hidden_a)).size() == 1,
		"history deduplicates canonical hidden RGB and alpha")
	check(app._visible_recent_colors().is_empty(),
		"current FG/BG suppressed as display filter but remain stored")
	check(app.recent_colors.size() >= 2, "hidden current colors still remain in history")
	var third: Color = Color8(12, 47, 82, 255)
	app._remember_recent(third)
	check(app._visible_recent_colors().size() == 1 and app._pack_color(app._visible_recent_colors()[0]) == app._pack_color(third),
		"same RGB with distinct alpha remains a visible recent bar")
	app._color_swatch_pressed("Background")
	var brush_before: int = app.canvas.color_rgba
	app._use_recent_color(0)
	check(app.color_background == third and app.active_color == hidden_a and
		app.canvas.color_rgba == brush_before, "recent bar edits selected BG only")
	check(app._visible_recent_colors().any(func(c: Color) -> bool: return app._pack_color(c) == app._pack_color(hidden_b)),
		"formerly filtered background reappears after its color changes")
	app._color_swatch_pressed("Foreground")
	var new_fg: Color = Color8(88, 40, 219, 120)
	app.color_advanced.color_changed.emit(new_fg)
	check(app.active_color == new_fg and app.color_background == third and
		app.color_hex.text == "#5828DB78" and app.canvas.color_rgba == app._pack_color(new_fg),
		"native picker signal updates foreground, hex and paint only")
	app._color_swatch_pressed("Background")
	var new_bg: Color = Color8(90, 60, 30, 0)
	app.color_advanced.color_changed.emit(new_bg)
	check(app.color_background == new_bg and app.active_color == new_fg and
		app.color_hex.text == "#5A3C1E00" and app.color_advanced.color == new_bg and
		app.canvas.color_rgba == app._pack_color(new_fg),
		"native picker signal updates only background, including transparent hidden RGB")
	var bg_recent: int = -1
	for i: int in range(app._visible_recent_colors().size()):
		if app._pack_color(app._visible_recent_colors()[i]) == app._pack_color(third):
			bg_recent = i
	check(bg_recent >= 0, "previous BG remains retrievable after picker change")
	if bg_recent >= 0:
		app._use_recent_color(bg_recent)
	check(app.color_background == third, "recent bar restores BG independently")
	app._color_swatch_pressed("Foreground")
	var fg_recent: int = -1
	for i: int in range(app._visible_recent_colors().size()):
		if app._pack_color(app._visible_recent_colors()[i]) == app._pack_color(hidden_a):
			fg_recent = i
	check(fg_recent >= 0, "previous FG remains retrievable from recents")
	if fg_recent >= 0:
		app._use_recent_color(fg_recent)
	check(app.active_color == hidden_a and app.color_advanced.color == hidden_a,
		"recent foreground restores the exact pigment without extra restore buttons")
	for i: int in range(12):
		app._remember_recent(Color8(i + 100, i, 200, i + 5))
	check(app.recent_colors.size() == 6 and app._visible_recent_colors().size() <= 6,
		"recent history stays bounded across many colors")
	var packed: Array[int] = []
	for sample: Color in app.recent_colors:
		packed.append(app._pack_color(sample))
	var unique: Dictionary = {}
	for key: int in packed:
		unique[key] = true
	check(packed.size() == 6 and unique.size() == 6 and
		packed[0] == app._pack_color(Color8(111, 11, 200, 16)),
		"bounded history keeps newest canonical pixel identity")
	app._swap_colors()
	check(app.canvas.color_rgba == app._pack_color(app.active_color) and
		app.color_advanced.color == app._edited_color(), "swap updates active role consistently")
	app._reset_colors()
	check(app.active_color == Color.BLACK and app.color_background == Color.WHITE,
		"Default resets independently editable pigments")
	check(doc.revision == initial_revision and doc.is_dirty() == initial_dirty and
		doc.history_length() == 0, "all pigment changes are UI-only and non-dirty")
	app.queue_free()
	await frames(3)
	print("T226_MODEL: %d checks; %d failed" % [checks, failed])
	print("T226_MODEL_PASSED" if failed == 0 else "T226_MODEL_FAILED")
	quit(0 if failed == 0 else 1)
