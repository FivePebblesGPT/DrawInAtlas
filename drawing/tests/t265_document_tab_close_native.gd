extends SceneTree
## T-265: clipped document tab rectangles must never redirect a close click.

var checks: int = 0
var failures: int = 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T265_NATIVE_FAILED: " + description)

func frames(count: int = 5) -> void:
	for _i: int in range(count):
		await process_frame

func click(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await frames(3)

func global_tab_point(bar: TabBar, local: Vector2) -> Vector2:
	return bar.get_global_transform_with_canvas() * local

func close_point(bar: TabBar, index: int) -> Vector2:
	var rect: Rect2 = bar.get_tab_rect(index)
	return global_tab_point(bar, rect.position + Vector2(rect.size.x - 18.0, rect.size.y * 0.5))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 window required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(930, 760)
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	await frames(20)
	# Force real TabBar clipping and horizontal scrolling with 13 unsaved tabs.
	while app.tabs.size() < 13:
		app.new_drawing()
	for i: int in range(app.tab_bar.tab_count):
		app.tab_bar.set_tab_title(i, "Very long document %d xxxxxxxx" % i)
	await frames(10)
	var bar: TabBar = app.tab_bar
	check(bar.clip_tabs and bar.tab_count == 13 and bar.size.x < 800.0,
		"13-tab strip is clipped in an actual narrow window")
	var count_before: int = app.tabs.size()
	var hidden_doc: DrawingDocument = app.tabs[0]["document"] as DrawingDocument
	var hidden_id: String = hidden_doc.id
	check(hidden_doc.mark_published(hidden_doc.revision).ok and not hidden_doc.is_dirty(),
		"hidden first document is clean and could be silently destroyed by a wrong close")
	for scale: float in [1.0, 1.5, 2.0]:
		root.content_scale_factor = scale
		await frames(10)
		# Selecting the last tab scrolls the first ten outside the rendered strip.
		app._activate(bar.tab_count - 1)
		await frames(6)
		var stale: Vector2 = close_point(bar, 0)
		var stale_local: Vector2 = bar.get_global_transform_with_canvas().affine_inverse() * stale
		var real_index: int = bar.get_tab_idx_at_point(stale_local)
		check(real_index != 0,
			"%.1fx hidden first tab cannot own clipped pointer (native hit %d)" % [scale, real_index])
		check(app._tab_close_hit(stale) == real_index,
			"%.1fx close hit resolves rendered tab %d, never hidden tab 0" % [scale, real_index])
		var visible_close: Vector2 = close_point(bar, bar.tab_count - 1)
		check(app._tab_close_hit(visible_close) == bar.tab_count - 1,
			"%.1fx last visible tab close is correctly targeted" % scale)
		var content_point: Vector2 = global_tab_point(bar, Vector2(40.0, bar.size.y * 0.5))
		check(app._tab_close_hit(content_point) == -1,
			"%.1fx body of visible tab is not a close button" % scale)
		var outside: Vector2 = global_tab_point(bar, Vector2(bar.size.x + 30.0, bar.size.y * 0.5))
		check(app._tab_close_hit(outside) == -1,
			"%.1fx outside clipped strip cannot close a document" % scale)
		# At 100%, exercise the actual viewport event dispatch and dirty prompt.
		if scale == 1.0:
			await click(stale)
			check(app.close_dialog.visible and app._closing_index == real_index and
				app.tabs.size() == count_before and app.active_tab == count_before - 1 and
				(app.tabs[0]["document"] as DrawingDocument).id == hidden_id,
				"visible inactive close prompts for its own tab, never silently deletes saved hidden tab")
			app.close_dialog.hide()
			app._cancel_pending_close()
			check(app.tabs.size() == count_before and app._closing_index == -1,
				"cancel preserves all thirteen documents and clears close target")
	# Scrolling back to the first tab restores close targeting, not a stale index.
	root.content_scale_factor = 1.0
	app._activate(0)
	await frames(7)
	var first: Vector2 = close_point(bar, 0)
	check(bar.get_tab_idx_at_point(bar.get_global_transform_with_canvas().affine_inverse() * first) == 0 and
		app._tab_close_hit(first) == 0,
		"scrolling back targets the actual first document close glyph")
	await click(first)
	check(app.tabs.size() == count_before - 1 and
		(app.tabs[0]["document"] as DrawingDocument).id != hidden_id and
		app._closing_index == -1,
		"clicking genuinely visible saved first tab closes only that tab without a prompt")
	print("T265_NATIVE: %d checks; %d failures" % [checks, failures])
	print("T265_NATIVE_PASSED" if failures == 0 else "T265_NATIVE_FAILED")
	quit(1 if failures else 0)
