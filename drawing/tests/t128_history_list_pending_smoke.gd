extends SceneTree
## A History list jump must not bypass the pending Brush revision guard.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T128_HISTORY_LIST_FAILED: " + description)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func new_app() -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.start_blank_document = false
	root.add_child(app)
	await frames(4)
	app.new_drawing()
	return app


func paint_short(canvas: Control, pixel: Vector2, tint: int) -> void:
	canvas.tool = "Brush"
	canvas.color_rgba = tint
	canvas.brush_width = 3.0
	canvas.start_gesture(canvas.pixel_to_position(pixel))
	canvas.finish_gesture(canvas.pixel_to_position(pixel))


func release_long(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.color_rgba = 0xffab5b23
	canvas.brush_width = 44.0
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(Vector2(80.5 + 145.0 * t, 170.5 + sin(t * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


func await_commit(canvas: Control, max_frames: int = 750) -> bool:
	var elapsed: int = 0
	while canvas.has_pending_stroke() and elapsed < max_frames:
		await process_frame
		elapsed += 1
	return elapsed < max_frames


func alpha_at(document: DrawingDocument, pixel: Vector2i) -> int:
	var output: DrawingResult = DrawingRenderer.render(document, Rect2i(pixel, Vector2i.ONE))
	if not output.ok:
		return -1
	return roundi((output.value as Image).get_pixel(0, 0).a * 255.0)


func jump(app: Control, target: int) -> bool:
	app._refresh_history()
	var row: int = app._history_row_positions.find(target)
	if row < 0:
		return false
	app.history_list.select(row)
	app.history_list.item_selected.emit(row)
	return true


func selected_position(app: Control) -> int:
	var row: int = app.history_list.get_selected_items()[0] if app.history_list.get_selected_items().size() > 0 else -1
	return app._history_row_positions[row] if row >= 0 and row < app._history_row_positions.size() else -1


func test_backward_jump(base: String) -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	paint_short(app.canvas, Vector2(27.5, 32.5), 0xff347cde)
	check(await await_commit(app.canvas), "first committed Brush stroke")
	paint_short(app.canvas, Vector2(42.5, 47.5), 0xff41a25d)
	check(await await_commit(app.canvas), "second committed Brush stroke")
	check(alpha_at(doc, Vector2i(27, 32)) > 0 and alpha_at(doc, Vector2i(42, 47)) > 0,
		"two separately committed source pixels exist for History navigation")
	var cursor: int = doc.history_position()
	var revision: int = doc.revision
	check(cursor >= 2, "older History row exists")
	app._refresh_history()
	check(selected_position(app) == cursor, "History panel initially selects actual cursor")
	release_long(app.canvas)
	app.canvas.brush_width = 5.0
	app.canvas.color_rgba = 0xff30d0ab
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(29.5, 228.5)))
	app.canvas.update_gesture(app.canvas.pixel_to_position(Vector2(44.5, 233.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(60.5, 239.5)))
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"original Brush release and next queued gesture remain uncommitted")
	check(jump(app, cursor - 2), "History-list older row is selectable")
	check(doc.revision == revision and doc.history_position() == cursor,
		"older History selection cannot change the revision or cursor during Brush backlog")
	check(alpha_at(doc, Vector2i(27, 32)) > 0 and alpha_at(doc, Vector2i(42, 47)) > 0,
		"refused History jump retains earlier committed pixel source")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"refused History jump retains both detached Brush gestures")
	check(selected_position(app) == cursor,
		"History selection returns to the actual cursor after a blocked jump")
	check(app.status.text.contains("Stroke") and app.status.text.contains("History"),
		"refused History navigation gives a visible reason")
	check(jump(app, cursor), "selecting the current history cursor is a harmless no-op")
	check(doc.revision == revision and app.canvas.has_pending_stroke(),
		"same-row selection does not mutate revision or pending input")
	await frames(2)
	check(app.canvas.has_pending_stroke(), "blocked History jump does not cancel input on next frame")
	check(await await_commit(app.canvas), "queued gestures complete after rejected History jump")
	check(doc.revision == revision + 2 and doc.history_position() == cursor + 2,
		"two queued gestures publish as separate ordered history transactions")
	check(alpha_at(doc, Vector2i(80, 170)) > 0 and alpha_at(doc, Vector2i(44, 233)) > 0,
		"both pending gestures commit real pixels")
	var final_image: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 256, 256))
	check(final_image.ok, "post-release document renders to full RGBA8 snapshot")
	check(jump(app, cursor), "older History selection resumes after Brush commit")
	check(doc.history_position() == cursor, "History jump undoes exactly two newly committed gestures")
	check(alpha_at(doc, Vector2i(27, 32)) > 0 and alpha_at(doc, Vector2i(42, 47)) > 0,
		"History jump retains older committed strokes")
	check(alpha_at(doc, Vector2i(80, 170)) == 0 and alpha_at(doc, Vector2i(44, 233)) == 0,
		"History jump removes only two newly published strokes")
	check(jump(app, cursor + 2), "forward History selection works after Brush commit")
	var redone: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 256, 256))
	check(final_image.ok and redone.ok and
		(final_image.value as Image).get_data() == (redone.value as Image).get_data(),
		"back/forward History jumps reproduce exact final RGBA8 pixels")
	var saved: String = base.path_join("history-list.drawing")
	app._save_file(saved)
	var reopened: DrawingResult = DrawingFileIO.open_with_frame(saved)
	var roundtrip: DrawingResult = DrawingRenderer.render(reopened.value["document"],
		Rect2i(0, 0, 256, 256)) if reopened.ok else DrawingResult.failure("FILE", "Missing file")
	check(reopened.ok and roundtrip.ok and redone.ok and
		(roundtrip.value as Image).get_data() == (redone.value as Image).get_data(),
		"saved/reopened document preserves post-History source exactly")
	app.queue_free()
	await frames(2)


func test_forward_jump_during_pending() -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	paint_short(app.canvas, Vector2(27.5, 32.5), 0xff1234ab)
	check(await await_commit(app.canvas), "Redo branch source stroke commits")
	var old_cursor: int = doc.history_position()
	app._undo()
	var cursor: int = doc.history_position()
	var revision: int = doc.revision
	check(cursor == old_cursor - 1 and alpha_at(doc, Vector2i(27, 32)) == 0,
		"Redo test has an existing later History row")
	release_long(app.canvas)
	check(app.canvas.has_pending_stroke(), "Redo scenario has unpublished Brush paint")
	check(jump(app, old_cursor), "History-list future row is selectable")
	check(doc.revision == revision and doc.history_position() == cursor,
		"forward History jump is denied before any Redo revision")
	check(alpha_at(doc, Vector2i(27, 32)) == 0 and app.canvas.has_pending_stroke(),
		"denied Redo keeps prior paint undone without cancelling pending Brush")
	check(selected_position(app) == cursor, "denied forward jump resets selection to actual cursor")
	check(await await_commit(app.canvas), "pending Brush finishes after denied forward jump")
	check(doc.history_position() == cursor + 1 and doc.revision == revision + 1,
		"Brush publication creates exactly one new transaction")
	check(alpha_at(doc, Vector2i(27, 32)) == 0 and alpha_at(doc, Vector2i(80, 170)) > 0,
		"ordinary new commit replaces obsolete Redo branch")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t128-history-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "History fixtures directory available")
	await test_backward_jump(base)
	await test_forward_jump_during_pending()
	if failures == 0:
		print("T128_HISTORY_LIST_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T128_HISTORY_LIST_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
