extends SceneTree
## Standalone OS close must honor pending paint and every dirty Drawing/Object
## tab. Embedded Atlas owns its own application quit policy.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T133_WINDOW_QUIT_FAILED: " + description)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func make_app(parent: Node) -> Control:
	var app: Control = load("res://main.tscn").instantiate()
	app.start_blank_document = false
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	parent.add_child(app)
	await frames(3)
	return app


func seed_pixel(app: Control, color: int) -> void:
	var doc: DrawingDocument = app.current_document()
	var edit: DrawingEditSession = doc.begin_edit(app.current_layer(), doc.revision).value
	check(edit != null and edit._stage(11, 12, color).ok and edit.commit().ok,
		"seed exact pending-to-save pixel")


func pending_brush(app: Control) -> void:
	var brush: Control = app.canvas
	brush.tool = "Brush"
	brush.brush_width = 48.0
	brush.color_rgba = 0xff4d9731
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(200):
		var t: float = float(i) / 199.0
		path.append(Vector2(80.5 + 135.0 * t, 135.5 + 55.0 * sin(t * TAU * 7.0)))
	brush.start_gesture(brush.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		brush.update_gesture(brush.pixel_to_position(path[i]))
	brush.finish_gesture(brush.pixel_to_position(path[path.size() - 1]))


func test_standalone_close(base: String) -> void:
	var original_policy: bool = auto_accept_quit
	var app: Control = await make_app(root)
	check(not auto_accept_quit and app.get("_window_quit_guard_enabled") == true,
		"standalone top-level workspace owns the OS quit policy")
	if not app.has_method("_request_window_quit"):
		check(false, "standalone window close handling exists")
		app.queue_free()
		await frames(3)
		return
	app.new_drawing()
	var doc: DrawingDocument = app.current_document()
	var destination: String = base.path_join("standalone-sentinel.drawing")
	app._save_file(destination)
	check(FileAccess.file_exists(destination) and not doc.is_dirty(),
		"standalone save is clean before pending stroke")
	pending_brush(app)
	check(app.canvas.has_pending_stroke(), "released brush has unpublished pixels")
	var before_revision: int = doc.revision
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(app.tabs.size() == 1 and app.current_document() == doc and
		app.canvas.has_pending_stroke() and doc.revision == before_revision,
		"window close cannot discard an unpublished brush transaction")
	check(app.get("_window_quit_requested") != true and
		app.status.text.contains("Stroke still processing"),
		"rejected OS close is visible and does not arm a later quit")
	var spins: int = 0
	while app.canvas.has_pending_stroke() and spins < 800:
		await process_frame
		spins += 1
	check(spins < 800 and doc.is_dirty(), "normal frame-budgeted stroke commits after refusal")
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(app.close_dialog.visible and app.tabs.size() == 1 and
		app.get("_window_quit_requested") == true,
		"dirty standalone tab triggers Save/Discard/Cancel instead of exiting")
	app.close_dialog.hide()
	app.close_dialog.canceled.emit()
	check(app.tabs.size() == 1 and app.get("_window_quit_requested") != true,
		"Cancel revokes the OS close request without deleting the dirty document")
	app.queue_free()
	await frames(3)
	check(auto_accept_quit == original_policy, "standalone restores prior SceneTree quit policy")


func test_embedded_atlas() -> void:
	var original_policy: bool = auto_accept_quit
	var host: Node = Node.new()
	root.add_child(host)
	var app: Control = await make_app(host)
	check(app.get("_window_quit_guard_enabled") != true and
		auto_accept_quit == original_policy,
		"embedded workspace never changes Atlas host quit policy")
	app.new_drawing()
	seed_pixel(app, 0xff112233)
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(app.tabs.size() == 1 and app.get("_window_quit_requested") != true,
		"embedded workspace does not capture its host window close")
	host.queue_free()
	await frames(2)
	check(auto_accept_quit == original_policy, "Atlas host policy remains unchanged after teardown")


func test_multi_tab_save_cancel_discard(base: String) -> void:
	var host: Node = Node.new()
	root.add_child(host)
	var app: Control = await make_app(host)
	if not app.has_method("_request_window_quit"):
		check(false, "multi-tab window quit handling exists")
		host.queue_free()
		await frames(2)
		return
	app.new_drawing()
	var first: DrawingDocument = app.current_document()
	seed_pixel(app, 0xffaabbcc)
	app.new_drawing()
	var second: DrawingDocument = app.current_document()
	var second_layer: String = app.current_layer()
	seed_pixel(app, 0xff123456)
	app.new_drawing() # Last tab is saved and can close without prompting.
	app._save_file(base.path_join("clean-third.drawing"))
	check(not app.current_document().is_dirty(), "third tab is saved before window quit")
	app._request_window_quit()
	await frames(2)
	check(app.tabs.size() == 2 and int(app.get("_closing_index")) == 1 and
		app.close_dialog.visible, "clean tab closes; next dirty tab prompts in order")
	app.close_dialog.hide()
	app.close_dialog.canceled.emit()
	check(app.tabs.size() == 2 and app.current_document() == second and
		app.get("_window_quit_requested") != true,
		"Cancel stops multi-tab close without touching either dirty document")
	app._request_window_quit()
	check(app.close_dialog.visible and int(app.get("_closing_index")) == 1,
		"a new close attempt resumes at the dirty tab")
	app.close_dialog.confirmed.emit()
	await frames(2)
	check(app.save_dialog.visible and app.tabs.size() == 2,
		"Save choice uses existing Save As flow for unnamed document")
	var saved: String = base.path_join("window-save.drawing")
	app.save_dialog.hide()
	app.save_dialog.file_selected.emit(saved)
	await frames(2)
	check(FileAccess.file_exists(saved) and app.tabs.size() == 1 and
		app.current_document() == first and app.close_dialog.visible,
		"saved tab closes and next dirty tab is offered a separate decision")
	var loaded: DrawingResult = DrawingFileIO.open_with_frame(saved)
	check(loaded.ok, "saved second tab can reopen after window-close Save As")
	if loaded.ok:
		var reopened: DrawingDocument = loaded.value["document"] as DrawingDocument
		var recovered: DrawingResult = reopened.read_pixel(second_layer, 11, 12)
		check(recovered.ok and int(recovered.value) == 0xff123456,
			"saved tab contains exact RGBA8 from correct document")
	app.close_dialog.custom_action.emit("discard")
	await frames(2)
	check(app.tabs.is_empty() and app.get("_window_quit_requested") != true,
		"explicit Discard closes final tab without changing Atlas host quit policy")
	host.queue_free()
	await frames(2)


func test_local_object_quit(base: String) -> void:
	var host: Node = Node.new()
	root.add_child(host)
	var app: Control = await make_app(host)
	if not app.has_method("_request_window_quit"):
		check(false, "Object window quit handling exists")
		host.queue_free()
		await frames(2)
		return
	app.new_object()
	var session: DrawingObjectEditorSession = app.current_object()
	check(session != null and session.is_dirty(),
		"new Object source has unpublished metadata and pixels")
	app._request_window_quit()
	check(app.close_dialog.visible and app.tabs.size() == 1 and
		app.get("_window_quit_requested") == true,
		"window close asks explicit permission before discarding a dirty Object")
	app.close_dialog.hide()
	app.close_dialog.canceled.emit()
	check(app.current_object() == session and session.is_dirty() and
		app.get("_window_quit_requested") != true,
		"cancelling Object close leaves the private source untouched")
	app._request_window_quit()
	app.close_dialog.confirmed.emit()
	await frames(2)
	check(app.save_dialog.visible and app.current_object() == session,
		"Object Save choice opens its existing local portable publisher")
	var destination: String = base.path_join("saved-object.drawing")
	app.save_dialog.hide()
	app.save_dialog.file_selected.emit(destination)
	await frames(2)
	check(FileAccess.file_exists(destination) and app.tabs.is_empty() and
		app.get("_window_quit_requested") != true,
		"saved Object closes only after successful portable publication")
	check(DrawingObjectEditorFile.open(destination).ok,
		"standalone Object Save from window close remains reopenable")
	host.queue_free()
	await frames(2)


func run() -> void:
	var directory: String = ProjectSettings.globalize_path("user://t133-window-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "test destination created")
	await test_standalone_close(directory)
	await test_embedded_atlas()
	await test_multi_tab_save_cancel_discard(directory)
	await test_local_object_quit(directory)
	if failures == 0:
		print("T133_WINDOW_QUIT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T133_WINDOW_QUIT_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
