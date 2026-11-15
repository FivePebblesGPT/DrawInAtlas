extends SceneTree
## A released Brush transaction remains owned by its document until commit.
## Switching the active document must not silently abandon unpublished pixels.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T126_TAB_SWITCH_FAILED: " + description)


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


func release_brush(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.brush_width = 44.0
	canvas.color_rgba = 0xff2975c2
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(Vector2(80.5 + 145.0 * t, 170.5 + sin(t * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


func await_commit(canvas: Control, max_frames: int = 750) -> bool:
	var count: int = 0
	while canvas.has_pending_stroke() and count < max_frames:
		await process_frame
		count += 1
	return count < max_frames


func test_tab_switch_and_inactive_close(base: String) -> void:
	var app: Control = await new_app()
	app.new_drawing()
	app._save_file(base.path_join("active-baseline.drawing"))
	var original: DrawingDocument = app.current_document()
	var revision: int = original.revision
	release_brush(app.canvas)
	app.canvas.brush_width = 7.0
	app.canvas.color_rgba = 0xff92b513
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(29.5, 229.5)))
	app.canvas.update_gesture(app.canvas.pixel_to_position(Vector2(59.5, 237.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(65.5, 240.5)))
	check(not app.canvas._deferred_stroke.is_empty(),
		"chronologically queued second stroke belongs to the same document")
	check(app.canvas.has_pending_stroke() and not original.is_dirty(),
		"unpublished stroke is pending on a clean document")
	app._cycle_tab(-1)
	check(app.active_tab == 1 and app.current_document() == original,
		"keyboard tab cycling refuses to discard unpublished pixels")
	check(app.canvas.has_pending_stroke(), "keyboard rejection retains the original edit session")
	app._activate(1)
	check(app.canvas.has_pending_stroke(), "same-tab TabBar callback cannot reset an active stroke")
	app._activate(0)
	check(app.active_tab == 1 and app.current_document() == original,
		"direct activation refuses an unsafe document swap")
	app.tab_bar.current_tab = 0
	check(app.active_tab == 1 and app.tab_bar.current_tab == 1,
		"TabBar selection and workspace selection remain synchronized on refusal")
	app._request_close_tab(0)
	check(app.tabs.size() == 2 and app.active_tab == 1 and app.canvas.has_pending_stroke(),
		"closing an inactive tab cannot tear down the active stroke")
	app._close_index(0)
	check(app.tabs.size() == 2 and app.canvas.has_pending_stroke(),
		"internal tab removal cannot silently bypass the pending-stroke gate")
	app._closing_index = 0
	app._save_and_close()
	check(app._closing_index == -1 and not app._close_after_save and
		app.active_tab == 1 and app.canvas.has_pending_stroke(),
		"stale Save and Close intent cannot switch documents or save the wrong tab")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Close"),
		"document-switch refusal is visible")
	check(await await_commit(app.canvas), "blocked switch leaves Brush draining normally")
	check(original.revision == revision + 2 and original.is_dirty(),
		"the exact original document receives the published transaction")
	app._cycle_tab(-1)
	check(app.active_tab == 0, "tab cycling resumes after commit")
	app._cycle_tab(1)
	check(app.active_tab == 1 and app.current_document() == original,
		"returning to the edited tab preserves its source identity")
	var saved_path: String = base.path_join("switched.drawing")
	app._save_file(saved_path)
	var opened: DrawingResult = DrawingFileIO.open_with_frame(saved_path)
	check(opened.ok, "document remains persistable after safe tab switch")
	if opened.ok:
		var current: DrawingResult = DrawingRenderer.render(original, Rect2i(0, 0, 256, 256))
		var saved: DrawingResult = DrawingRenderer.render(opened.value["document"], Rect2i(0, 0, 256, 256))
		check(current.ok and saved.ok and current.value.get_data() == saved.value.get_data(),
			"post-switch file roundtrip contains the complete Brush pixels")
	var undo_second: DrawingResult = original.undo()
	var undo_first: DrawingResult = original.undo()
	check(undo_second.ok and undo_first.ok and original.revision == revision + 4,
		"both independently committed strokes remain undoable after switching")
	var redo_first: DrawingResult = original.redo()
	var redo_second: DrawingResult = original.redo()
	check(redo_first.ok and redo_second.ok and original.revision == revision + 6,
		"both chronological strokes remain redoable after switching")
	app.queue_free()
	await frames(2)


func test_document_creation_and_open(base: String) -> void:
	var app: Control = await new_app()
	var path: String = base.path_join("baseline.drawing")
	app._save_file(path)
	var original: DrawingDocument = app.current_document()
	var counter: int = app.new_counter
	var image: Image = Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var raster_path: String = base.path_join("image.png")
	check(image.save_png(raster_path) == OK, "valid raster Open fixture created")
	release_brush(app.canvas)
	check(app.canvas.has_pending_stroke(), "new/open scenario starts with pending source pixels")
	app.new_drawing()
	check(app.tabs.size() == 1 and app.new_counter == counter,
		"New does not create an orphan tab during a pending stroke")
	app.new_object()
	check(app.tabs.size() == 1 and app.current_object() == null,
		"New Object does not corrupt the original Drawing tab")
	app._open_file(path)
	check(app.tabs.size() == 1 and app.current_document() == original,
		"Open .drawing refuses to replace a draining canvas")
	app._open_file(raster_path)
	check(app.tabs.size() == 1 and app.current_document() == original,
		"Open raster refuses to replace a draining canvas")
	app._open_object_file(base.path_join("invalid-object.drawing"))
	check(app.tabs.size() == 1 and app.status.text.contains("Stroke"),
		"Object Open fails closed before accessing a pending session")
	var draft: DrawingDocument = DrawingDocument.new()
	var object_session: DrawingObjectEditorSession = DrawingObjectEditorSession.new(draft, "", 0, "Draft")
	var refused: DrawingResult = app.attach_object_session(object_session)
	check(not refused.ok and app.tabs.size() == 1 and app.active_tab == 0,
		"Atlas-hosted Object attachment cannot switch away from uncommitted pixels")
	check(app.canvas.has_pending_stroke(), "all rejected operations retain the stroke")
	check(await await_commit(app.canvas), "unpublished edit finishes after all refusals")
	check(original.is_dirty(), "original document becomes dirty rather than losing its edits")
	app._open_file(path)
	check(app.tabs.size() == 2 and app.active_tab == 1,
		"normal Drawing Open resumes after commit")
	app._open_file(raster_path)
	check(app.tabs.size() == 3 and app.active_tab == 2,
		"normal raster Open resumes after commit")
	var attached: DrawingResult = app.attach_object_session(object_session)
	check(attached.ok and app.tabs.size() == 4 and app.current_object() == object_session,
		"Atlas-hosted Object attachment resumes after commit")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t126-tabs-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "fixtures directory available")
	await test_tab_switch_and_inactive_close(base)
	await test_document_creation_and_open(base)
	if failures == 0:
		print("T126_TAB_SWITCH_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T126_TAB_SWITCH_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
