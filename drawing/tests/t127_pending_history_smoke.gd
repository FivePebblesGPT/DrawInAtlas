extends SceneTree
## Undo/Redo must not revise the document under a detached Brush transaction.
## Escape remains the intentional way to cancel a pending stroke.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T127_HISTORY_FAILED: " + description)


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


func paint_short(canvas: Control, pixel: Vector2, tint: int = 0xff3377b8) -> void:
	canvas.tool = "Brush"
	canvas.color_rgba = tint
	canvas.brush_width = 3.0
	canvas.start_gesture(canvas.pixel_to_position(pixel))
	canvas.finish_gesture(canvas.pixel_to_position(pixel))


func release_long(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.brush_width = 44.0
	canvas.color_rgba = 0xffa95320
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
	var image_result: DrawingResult = DrawingRenderer.render(document, Rect2i(pixel, Vector2i.ONE))
	if not image_result.ok:
		return -1
	return roundi((image_result.value as Image).get_pixel(0, 0).a * 255.0)


func test_undo_while_queued(base: String) -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	paint_short(app.canvas, Vector2(30.5, 35.5))
	check(await await_commit(app.canvas), "initial short stroke commits")
	check(alpha_at(doc, Vector2i(30, 35)) > 0, "prior Undo candidate exists")
	app._save_file(base.path_join("undo-baseline.drawing"))
	check(not doc.is_dirty(), "document is clean before unpublished input")
	var prior_revision: int = doc.revision
	release_long(app.canvas)
	app.canvas.brush_width = 5.0
	app.canvas.color_rgba = 0xff11ab84
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(29.5, 228.5)))
	app.canvas.update_gesture(app.canvas.pixel_to_position(Vector2(44.5, 233.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(60.5, 239.5)))
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"release backlog owns both current and queued strokes")
	app._undo()
	check(doc.revision == prior_revision, "Undo cannot mutate the revision under unpublished input")
	check(app.canvas.has_pending_stroke(), "Undo preserves active and queued Brush edits")
	check(not app.canvas._deferred_stroke.is_empty(), "Undo retains the ordered successor")
	check(alpha_at(doc, Vector2i(30, 35)) > 0, "Undo does not remove previous committed paint")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Undo"),
		"rejected Undo provides an actionable user-visible warning")
	var undo_key: InputEventKey = InputEventKey.new()
	undo_key.pressed = true
	undo_key.ctrl_pressed = true
	undo_key.keycode = KEY_Z
	app._unhandled_key_input(undo_key)
	app.history_undo.pressed.emit()
	check(doc.revision == prior_revision and app.canvas.has_pending_stroke(),
		"Ctrl+Z and History Undo button share the pending-transaction guard")
	await frames(2)
	check(app.canvas.has_pending_stroke(), "revision remains stable through subsequent drain frames")
	check(await await_commit(app.canvas), "both strokes complete after rejected Undo")
	check(doc.revision == prior_revision + 2, "pending and queued strokes commit as separate transactions")
	check(alpha_at(doc, Vector2i(30, 35)) > 0, "prior paint survived both new transactions")
	check(alpha_at(doc, Vector2i(80, 170)) > 0, "first pending stroke actually publishes paint")
	check(alpha_at(doc, Vector2i(44, 233)) > 0, "queued successor publishes an independent painted region")
	var committed_image: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 256, 256))
	check(committed_image.ok, "committed source can be rendered byte-for-byte")
	var before_undo: int = doc.revision
	app._undo()
	app._undo()
	check(doc.revision == before_undo + 2, "Undo resumes after commit for both new transactions")
	check(alpha_at(doc, Vector2i(30, 35)) > 0, "two Undos preserve the earlier stroke")
	check(alpha_at(doc, Vector2i(80, 170)) == 0 and alpha_at(doc, Vector2i(44, 233)) == 0,
		"two Undos remove both newer paint regions")
	app._redo()
	app._redo()
	check(doc.revision == before_undo + 4, "Redo resumes after commit in chronological order")
	check(alpha_at(doc, Vector2i(30, 35)) > 0, "redo does not corrupt earlier paint")
	var redone_image: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 256, 256))
	check(redone_image.ok and committed_image.ok and
		(redone_image.value as Image).get_data() == (committed_image.value as Image).get_data(),
		"two Redos restore the exact committed RGBA8 image")
	var saved: String = base.path_join("post-history.drawing")
	app._save_file(saved)
	var loaded: DrawingResult = DrawingFileIO.open_with_frame(saved)
	var loaded_image: DrawingResult = DrawingRenderer.render(
		loaded.value["document"], Rect2i(0, 0, 256, 256)) if loaded.ok else DrawingResult.failure("FILE", "Missing file")
	check(loaded.ok and loaded_image.ok and redone_image.ok and
		(loaded_image.value as Image).get_data() == (redone_image.value as Image).get_data(),
		"saved/reopened document retains all history-published RGBA8 pixels")
	app.queue_free()
	await frames(2)


func test_redo_while_pending() -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	paint_short(app.canvas, Vector2(30.5, 35.5))
	check(await await_commit(app.canvas), "redo setup stroke commits")
	app._undo()
	check(alpha_at(doc, Vector2i(30, 35)) == 0, "redo setup leaves undone prior paint")
	var prior_revision: int = doc.revision
	release_long(app.canvas)
	check(app.canvas.has_pending_stroke(), "redo scenario has pending stroke")
	app._redo()
	check(doc.revision == prior_revision, "Redo cannot revise document while a stroke is pending")
	check(alpha_at(doc, Vector2i(30, 35)) == 0, "Redo does not publish older paint under pending edit")
	check(app.canvas.has_pending_stroke(), "Redo does not cancel the uncommitted stroke")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Redo"),
		"rejected Redo provides an actionable warning")
	var redo_key: InputEventKey = InputEventKey.new()
	redo_key.pressed = true
	redo_key.ctrl_pressed = true
	redo_key.keycode = KEY_Y
	app._unhandled_key_input(redo_key)
	redo_key.keycode = KEY_Z
	redo_key.shift_pressed = true
	app._unhandled_key_input(redo_key)
	app.history_redo.pressed.emit()
	check(doc.revision == prior_revision and app.canvas.has_pending_stroke(),
		"Ctrl+Y, Ctrl+Shift+Z and History Redo button cannot bypass the guard")
	await frames(2)
	check(app.canvas.has_pending_stroke(), "redo refusal preserves the session across frame drains")
	check(await await_commit(app.canvas), "new paint commits despite denied Redo")
	check(doc.revision == prior_revision + 1, "new edit publishes exactly once")
	check(alpha_at(doc, Vector2i(30, 35)) == 0, "normal history branch replacement drops old Redo")
	var new_paint_alpha: int = alpha_at(doc, Vector2i(80, 170))
	check(new_paint_alpha > 0, "new stroke has actual committed pixels")
	app._undo()
	check(alpha_at(doc, Vector2i(80, 170)) == 0, "Undo after commit removes new pixels")
	app._redo()
	check(alpha_at(doc, Vector2i(80, 170)) == new_paint_alpha,
		"Redo after commit restores exact new paint")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t127-history-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "history fixtures directory available")
	await test_undo_while_queued(base)
	await test_redo_while_pending()
	if failures == 0:
		print("T127_HISTORY_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T127_HISTORY_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
