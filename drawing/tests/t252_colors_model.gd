extends SceneTree
## T-252: one recent pigment per settled ColorPicker/SpinBox gesture.
## Intermediate drag positions are live previews, not history entries.

const COLORS: String = "user://t252-standalone-colors-v1.json"
var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T252_MODEL_FAILED: " + message)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COLORS + suffix))
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(8)
	var doc: DrawingDocument = app.current_document()
	var revision: int = doc.revision
	var dirty: bool = doc.is_dirty()
	var history: int = doc.history_length()
	var first: Color = app.active_color
	check(app.foreground_button.get_parent().get_child_count() == 3 and
		app.color_swatch_buttons.size() == 8,
		"FG, Swap and BG share one row; restore-previous buttons absent")
	check(app.color_top_strip.get_child_count() == 2 and
		app.color_top_strip.get_child(1).name == "RecentBars" and
		app.color_top_strip.get_child(1).get_child_count() == 6,
		"vertical recents occupy second half without a heading")
	app.recent_colors.clear()
	app._begin_color_edit()
	var distinct: Dictionary = {}
	for step: int in range(1, 26):
		var intermediate: Color = Color8(step * 8, 40, 208 - step * 5, 255)
		app.color_advanced.color_changed.emit(intermediate)
		distinct[app._pack_color(app.active_color)] = true
		check(app.recent_colors.is_empty(), "no intermediate color recorded at step %d" % step)
	check(distinct.size() > 20 and app.canvas.color_rgba == app._pack_color(app.active_color),
		"all intermediate pixels preview to the brush while history stays empty")
	var settled: Color = app.active_color
	app._finish_color_edit()
	check(app.recent_colors.size() == 1 and app._pack_color(app.recent_colors[0]) == app._pack_color(first),
		"one settled gesture remembers only its original pigment")
	check(app._visible_recent_colors().size() == 1 and app._pack_color(app._visible_recent_colors()[0]) == app._pack_color(first),
		"current color is excluded but previous settled entry is available")
	app._begin_color_edit()
	app.color_advanced.color_changed.emit(Color8(15, 80, 100, 255))
	app._cancel_color_edit()
	check(app.active_color == settled and not app._color_edit_pending and
		app.recent_colors.size() == 1 and app.canvas.color_rgba == app._pack_color(settled),
		"cancel rolls back live preview without a recent color")
	app._begin_color_edit()
	app.color_advanced.color_changed.emit(first)
	app.color_advanced.color_changed.emit(settled)
	app._finish_color_edit()
	check(app.recent_colors.size() == 1 and app._pack_color(app.recent_colors[0]) == app._pack_color(first),
		"roundtrip/no-op picker gesture does not change history")
	app._begin_color_edit()
	app.color_advanced.color_changed.emit(Color8(99, 155, 205, 0))
	app._color_swatch_pressed("Background")
	check(app.color_edit_background and app.active_color == Color8(99, 155, 205, 0) and
		app._pack_color(app.recent_colors[0]) == app._pack_color(settled),
		"role switch commits FG once with exact hidden RGB and then switches role")
	var frozen_fg: Color = app.active_color
	var bg_initial: Color = app.color_background
	app._begin_color_edit()
	for step: int in range(17):
		app.color_advanced.color_changed.emit(Color8(step + 7, step + 29, 72, 0))
	check(app.active_color == frozen_fg and app.recent_colors.size() == 2,
		"BG drag neither paints nor records intermediate colors")
	app._finish_color_edit()
	check(app._pack_color(app.recent_colors[0]) == app._pack_color(bg_initial) and
		app._pack_color(app.color_background) == app._pack_color(Color8(23, 45, 72, 0)),
		"BG release records only previous settled BG, exact alpha-zero RGB")
	app._color_swatch_pressed("Foreground")
	app.color_hex.text = "#01020300"
	app._commit_hex()
	check(app.active_color == Color8(1, 2, 3, 0) and
		app.recent_colors.size() == 4 and app._pack_color(app.recent_colors[0]) == app._pack_color(frozen_fg),
		"Enter/hex commit is one explicit edit and preserves hidden RGB")
	app._use_recent_color(0)
	check(app.active_color == frozen_fg and app._pack_color(app.recent_colors[0]) == app._pack_color(Color8(1, 2, 3, 0)),
		"recent selection commits one previous color and makes selected value current")
	app._swap_colors()
	check(app.active_color == Color8(23, 45, 72, 0) and app.color_background == frozen_fg,
		"Swap operates on settled roles without intermediate colors")
	app._reset_colors()
	check(app.active_color == Color.BLACK and app.color_background == Color.WHITE,
		"Default resets both settled pigments")
	check(app.recent_colors.size() <= 6 and
		app._visible_recent_colors().all(func(c: Color) -> bool:
			return app._pack_color(c) not in [app._pack_color(app.active_color), app._pack_color(app.color_background)]),
		"history stays bounded, deduplicated and filters both current roles")
	# Native picker keyboard arrows settle on key-up, not repeated color_changed.
	app._color_swatch_pressed("Foreground")
	app.recent_colors.clear()
	app.color_advanced.grab_focus()
	await frames()
	var initial_keyboard: Color = app.active_color
	var right_key: InputEventKey = InputEventKey.new()
	right_key.keycode = KEY_RIGHT
	right_key.pressed = true
	app._track_color_input(right_key)
	for step: int in range(12):
		app.color_advanced.color_changed.emit(Color8(step * 5 + 33, 50, 90, 255))
	check(app._color_edit_pending and app.recent_colors.is_empty(),
		"keyboard repeats edit live pigment without recording intermediate colors")
	right_key.pressed = false
	app._track_color_input(right_key)
	await frames(3)
	check(not app._color_edit_pending and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(initial_keyboard),
		"keyboard release records one previous settled color")
	# Text fields inside Godot's picker should not commit on every key release;
	# they commit when the field submits or loses focus.
	var line: LineEdit = LineEdit.new()
	app.color_advanced.add_child(line)
	line.grab_focus()
	await frames(2)
	app.recent_colors.clear()
	var before_text: Color = app.active_color
	var char_key: InputEventKey = InputEventKey.new()
	char_key.keycode = KEY_A
	char_key.unicode = 97
	char_key.pressed = true
	app._track_color_input(char_key)
	for step: int in range(7):
		app.color_advanced.color_changed.emit(Color8(90 + step, 75, 63, 255))
		char_key.pressed = false
		app._track_color_input(char_key)
		char_key.pressed = true
	check(app._color_edit_pending and app.recent_colors.is_empty(),
		"native picker text editing stays pending across repeated key-up events")
	line.release_focus()
	await frames(2)
	check(not app._color_edit_pending and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(before_text),
		"native picker text field focus loss creates only one recent entry")
	line.queue_free()
	# RGBA8 SpinBox dragging shares the pending gesture state rather than
	# recording one value_changed for every small increment.
	app.recent_colors.clear()
	var before_spin: Color = app.active_color
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = app.color_rgb[0].get_global_rect().get_center()
	mouse.pressed = true
	app._track_color_input(mouse)
	for step: int in range(11):
		app.color_rgb[0].value = float(100 + step)
	check(app._color_edit_pending and app.recent_colors.is_empty(),
		"RGBA spin gesture does not flood recents")
	mouse.pressed = false
	app._track_color_input(mouse)
	await frames(3)
	check(not app._color_edit_pending and app.recent_colors.size() == 1 and
		app._pack_color(app.recent_colors[0]) == app._pack_color(before_spin),
		"RGBA spin gesture commits exactly once on mouse release")
	check(doc.revision == revision and doc.is_dirty() == dirty and doc.history_length() == history,
		"palette operations never create content history or dirty artwork")
	check(DrawingColorHistorySettings.decode({}).is_empty() and
		DrawingColorHistorySettings.decode({"schema": 1, "editing_background": false,
			"foreground": "#GG0000FF", "background": "#FFFFFFFF", "recent": []}).is_empty(),
		"corrupt schema and invalid pigment hex are rejected")
	check(DrawingColorHistorySettings.decode({"schema": 1, "editing_background": false,
		"foreground": "#01020300", "background": "#FFFFFFFF", "recent": ["#DDEEAAFF", "#DDEEAAFF"]}).is_empty(),
		"duplicate persisted colors rejected rather than silently reordered")
	check(DrawingColorHistorySettings.decode({"schema": 1, "editing_background": false,
		"foreground": "#01020300", "background": "#FFFFFFFF", "recent": ["#00000000"].duplicate() +
		["#01010100", "#02020200", "#03030300", "#04040400", "#05050500", "#06060600"]}).is_empty(),
		"oversized persisted color history rejected")
	var saved_colors: Array[Color] = app.recent_colors.duplicate()
	var saved_fg: Color = app.active_color
	var saved_bg: Color = app.color_background
	app.preferences_persistence_enabled = true
	app.recent_colors_settings_path = COLORS
	app._save_color_history()
	var decoded: Dictionary = DrawingColorHistorySettings.read_file(COLORS)
	check(not decoded.is_empty() and decoded["foreground"] == saved_fg and
		decoded["background"] == saved_bg and decoded["recent"] == saved_colors,
		"atomic color preference preserves exact current roles and bounded recents")
	app.queue_free()
	await frames(3)
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.layout_persistence_enabled = false
	reopened.preferences_persistence_enabled = true
	reopened.recent_colors_settings_path = COLORS
	root.add_child(reopened)
	await frames(8)
	check(reopened.active_color == saved_fg and reopened.color_background == saved_bg and
		reopened.recent_colors == saved_colors and reopened.canvas.color_rgba == reopened._pack_color(saved_fg),
		"relaunch restores pigments/recents into UI and brush without changing artwork")
	check(reopened.current_document().history_length() == 0 and reopened.current_document().revision == 2,
		"color preferences remain separate from serialized document history")
	var persisted: Array[Color] = reopened.recent_colors.duplicate()
	reopened._color_swatch_pressed("Foreground")
	reopened._begin_color_edit()
	reopened.color_advanced.color_changed.emit(Color8(150, 20, 100, 255))
	reopened._cancel_color_edit()
	check(DrawingColorHistorySettings.read_file(COLORS)["recent"] == persisted,
		"canceled picker preview cannot publish to persisted recent colors")
	reopened.queue_free()
	await frames(3)
	var source_path: String = ProjectSettings.globalize_path(COLORS)
	check(DirAccess.rename_absolute(source_path, source_path + ".bak") == OK,
		"simulate interrupted color preference replacement")
	var corrupt: FileAccess = FileAccess.open(COLORS, FileAccess.WRITE)
	corrupt.store_string("!".repeat(1024))
	corrupt.close()
	check(DrawingColorHistorySettings.read_file(COLORS)["recent"] == saved_colors,
		"oversized current file safely recovers last committed backup")
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COLORS + suffix))
	print("T252_MODEL: %d checks; %d failures" % [checks, failures])
	print("T252_MODEL_PASSED" if failures == 0 else "T252_MODEL_FAILED")
	quit(0 if failures == 0 else 1)
