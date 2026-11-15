extends SceneTree
## A released, uncommitted Brush gesture must not be saved or closed as clean.

var checks: int = 0
var failures: int = 0


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T125_PENDING_FAILED: " + description)


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


func release_long_brush(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.color_rgba = 0xff254acb
	canvas.brush_width = 44.0
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(Vector2(80.5 + t * 145.0, 170.5 + sin(t * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


func await_commit(canvas: Control, max_frames: int = 700) -> bool:
	var count: int = 0
	while canvas.session != null and count < max_frames:
		await process_frame
		count += 1
	return count < max_frames


func test_save_during_backlog(base: String) -> void:
	var app: Control = await new_app()
	var path: String = base.path_join("saved.drawing")
	app._save_file(path)
	check(FileAccess.file_exists(path) and not app.current_document().is_dirty(),
		"saved baseline is clean before stroke")
	var sentinel: String = "external-file-sentinel\n"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "external sentinel opens")
	if file != null:
		file.store_string(sentinel)
		file.close()
	var before: int = app.current_document().revision
	release_long_brush(app.canvas)
	check(app.canvas.session != null and app.canvas._stroke_phase == app.canvas.StrokePhase.DRAINING,
		"release leaves a pending unpublished edit")
	check(app.current_document().revision == before and not app.current_document().is_dirty(),
		"document is still clean despite pending pixel work")
	app._save()
	check(FileAccess.get_file_as_string(path) == sentinel,
		"Save must not overwrite external content with stale pre-commit snapshot")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Save"),
		"Save rejection is visible rather than silently ignored")
	app._ask_save()
	check(not app.save_dialog.visible, "Save As must not open while Brush work is pending")
	app._save_file(path)
	check(FileAccess.get_file_as_string(path) == sentinel,
		"direct FileDialog completion also rejects pre-commit overwrite")
	# T-124 permits a second captured stroke while the first release drains.
	app.canvas.brush_width = 7.0
	app.canvas.start_gesture(app.canvas.pixel_to_position(Vector2(30.5, 230.5)))
	app.canvas.update_gesture(app.canvas.pixel_to_position(Vector2(67.5, 235.5)))
	app.canvas.finish_gesture(app.canvas.pixel_to_position(Vector2(71.5, 238.5)))
	check(not app.canvas._deferred_stroke.is_empty(),
		"second gesture is still awaiting its predecessor")
	app._save_file(path)
	check(FileAccess.get_file_as_string(path) == sentinel,
		"queued second gesture also blocks stale Save")
	check(await await_commit(app.canvas), "both released strokes finish without cancellation")
	check(app.current_document().revision == before + 2 and app.current_document().is_dirty(),
		"both chronological Brush edits reach the dirty document")
	app._save()
	check(not app.current_document().is_dirty() and FileAccess.get_file_as_string(path) != sentinel,
		"Save succeeds normally after Brush completion")
	var loaded: DrawingResult = DrawingFileIO.open_with_frame(path)
	var identical: bool = false
	if loaded.ok:
		var saved: DrawingDocument = loaded.value["document"] as DrawingDocument
		var a: DrawingResult = DrawingRenderer.render(saved, Rect2i(0, 0, 256, 256))
		var b: DrawingResult = DrawingRenderer.render(app.current_document(), Rect2i(0, 0, 256, 256))
		identical = a.ok and b.ok and a.value.get_data() == b.value.get_data()
	check(identical, "post-commit Save persists the exact Brush pixels")
	app.queue_free()
	await frames(2)


func test_close_during_backlog(base: String) -> void:
	var app: Control = await new_app()
	var path: String = base.path_join("closed.drawing")
	app._save_file(path)
	var before: int = app.current_document().revision
	release_long_brush(app.canvas)
	check(app.canvas.session != null, "close scenario starts during pending release")
	app._request_close_tab(app.active_tab)
	check(app.tabs.size() == 1 and app._closing_index == -1,
		"Close Tab cannot discard an unpublished Brush edit as if the tab were clean")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Close"),
		"Close Tab rejection is visible")
	if app.tabs.is_empty():
		app.queue_free()
		await frames(2)
		return
	check(await await_commit(app.canvas), "rejected close does not cancel the active stroke")
	check(app.current_document().revision == before + 1 and app.current_document().is_dirty(),
		"rejected close preserves committed stroke and dirty marker")
	app._request_close_tab(app.active_tab)
	check(app._closing_index == app.active_tab,
		"normal dirty-close confirmation is restored after commit")
	app._cancel_pending_close()
	app.close_dialog.hide()
	app._save_file(path)
	app._request_close_tab(app.active_tab)
	check(app.tabs.is_empty(), "clean document closes normally after committed Save")
	app.queue_free()
	await frames(2)


func test_object_publish_during_backlog(base: String) -> void:
	var app: Control = await new_app()
	app.new_object()
	check(app.current_object() != null, "local Object Editor has an independent publisher")
	var path: String = base.path_join("object.drawing")
	app.tabs[app.active_tab]["_target_path"] = path
	var before: int = app.current_document().revision
	release_long_brush(app.canvas)
	check(app.canvas.session != null, "Object source has pending Brush content")
	app._publish_object(false)
	check(not FileAccess.file_exists(path) and
		app.status.text.contains("Save Object"),
		"Object publisher does not publish a stale draft while Brush drains")
	check(await await_commit(app.canvas), "Object Brush finishes normally")
	check(app.current_document().revision == before + 1,
		"Object draft contains one committed Brush transaction")
	app._publish_object(false)
	var loaded: DrawingResult = DrawingObjectEditorFile.open(path)
	check(loaded.ok, "Object source publication resumes after Brush commit")
	if loaded.ok:
		var saved: DrawingDocument = loaded.value["document"] as DrawingDocument
		var a: DrawingResult = DrawingRenderer.render(saved, Rect2i(0, 0, 256, 256))
		var b: DrawingResult = DrawingRenderer.render(app.current_document(), Rect2i(0, 0, 256, 256))
		check(a.ok and b.ok and a.value.get_data() == b.value.get_data(),
			"Object publisher preserves exact post-commit RGBA8 pixels")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t125-persistence-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "fixture directory exists")
	await test_save_during_backlog(base)
	await test_close_during_backlog(base)
	await test_object_publish_during_backlog(base)
	if failures == 0:
		print("T125_PENDING_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T125_PENDING_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
