extends SceneTree
## Concurrent layer/clipboard mutations must not invalidate detached Brush paint.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T129_PENDING_EDIT_FAILED: " + label)


func frames(n: int = 3) -> void:
	for _i: int in range(n):
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


func release_long(canvas: Control, start: Vector2 = Vector2(80.5, 170.5)) -> void:
	canvas.tool = "Brush"
	canvas.brush_width = 44.0
	canvas.color_rgba = 0xff51b7da
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(start + Vector2(140.0 * t, sin(t * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


func queue_next(canvas: Control, start: Vector2 = Vector2(30.5, 227.5)) -> void:
	canvas.brush_width = 5.0
	canvas.color_rgba = 0xff21a05f
	canvas.start_gesture(canvas.pixel_to_position(start))
	canvas.update_gesture(canvas.pixel_to_position(start + Vector2(13.0, 5.0)))
	canvas.finish_gesture(canvas.pixel_to_position(start + Vector2(25.0, 12.0)))


func await_commit(canvas: Control, max_frames: int = 750) -> bool:
	var i: int = 0
	while canvas.has_pending_stroke() and i < max_frames:
		await process_frame
		i += 1
	return i < max_frames


func pixel_alpha(doc: DrawingDocument, point: Vector2i) -> int:
	var result: DrawingResult = DrawingRenderer.render(doc, Rect2i(point, Vector2i.ONE))
	return roundi((result.value as Image).get_pixel(0, 0).a * 255.0) if result.ok else -1


func test_layer_commands(base: String) -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	var first: String = app.current_layer()
	app._add_layer()
	var second: String = app.current_layer()
	app._select_layer_node(first)
	app._refresh_layers()
	check(doc.layer_count() >= 2 and first != second, "two layers ready for guarded structure commands")
	var initial_count: int = doc.layer_count()
	var initial_history: int = doc.history_position()
	var revision: int = doc.revision
	release_long(app.canvas)
	queue_next(app.canvas)
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"two gestures await publication before layer mutation")
	app._add_layer()
	check(doc.revision == revision and doc.layer_count() == initial_count, "add layer denied without revision")
	app._add_group()
	check(doc.revision == revision and doc.layer_count() == initial_count, "add group denied without revision")
	app._set_row_visibility(first)
	check(doc.revision == revision and bool(doc.node_metadata(first).get("visible", false)),
		"visibility change denied before source mutation")
	app._set_row_lock(first)
	check(doc.revision == revision and not bool(doc.node_metadata(first).get("locked", true)),
		"lock change denied before source mutation")
	app._move_selected_layer(1)
	check(doc.revision == revision and doc.history_position() == initial_history,
		"layer reorder denied before history mutation")
	app.layer_rename_field.text = "Concurrent rename"
	app._commit_layer_rename()
	check(doc.revision == revision and doc.node_metadata(first).get("name") != "Concurrent rename",
		"layer rename denied before history mutation")
	app._remove_layer()
	check(doc.revision == revision and doc.has_node(first), "remove layer denied before source mutation")
	app._select_layer_node(second)
	check(app.current_layer() == first and app.canvas.layer_id == first,
		"selecting a different layer cannot retarget the deferred source")
	check(app.layers.get_selected() != null and
		String(app.layers.get_selected().get_metadata(0)) == first,
		"rejected Tree selection visibly restores active layer")
	var row: TreeItem = app.layers.get_root().get_first_child()
	while row != null and String(row.get_metadata(0)) != second:
		row = row.get_next()
	check(row != null, "alternate Tree row available for real selection event")
	if row != null:
		row.select(0)
		app.layers.item_selected.emit()
	check(app.current_layer() == first and app.layers.get_selected() != null and
		String(app.layers.get_selected().get_metadata(0)) == first,
		"real Tree event also restores the painted source row")
	check(app.status.text.contains("Stroke"), "source edits show pending-stroke warning")
	await frames(2)
	check(app.canvas.has_pending_stroke(), "layer commands cannot cancel strokes on next frame")
	check(await await_commit(app.canvas), "both strokes finish after denied layer commands")
	check(doc.history_position() == initial_history + 2 and doc.revision == revision + 2,
		"exactly two paint transactions commit in their original order")
	check(pixel_alpha(doc, Vector2i(80, 170)) > 0 and pixel_alpha(doc, Vector2i(43, 232)) > 0,
		"source bytes from both guarded strokes survive")
	app._save_file(base.path_join("layer-guard.drawing"))
	var reopened: DrawingResult = DrawingFileIO.open_with_frame(base.path_join("layer-guard.drawing"))
	check(reopened.ok and pixel_alpha(reopened.value["document"], Vector2i(80, 170)) > 0,
		"portable Save/Open retains preserved Brush paint")
	app._add_group()
	check(doc.revision == revision + 3 and doc.layer_count() == initial_count + 1,
		"layer edits resume normally after pending strokes publish")
	app._undo()
	check(doc.layer_count() == initial_count, "post-commit structural Undo remains functional")
	app.queue_free()
	await frames(2)


func test_clipboard_and_text() -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(60, 95, 180, 155), true)
	app.canvas.set_selection_mask(mask)
	app._copy_selection()
	check(app.drawing_clipboard != null, "clipboard source prepared before pending stroke")
	var revision: int = doc.revision
	var history: int = doc.history_position()
	release_long(app.canvas)
	queue_next(app.canvas, Vector2(85.5, 227.5))
	check(app.canvas.has_pending_stroke(), "clipboard scenario has pending stroke")
	app._delete_selection()
	check(doc.revision == revision, "Delete pixels cannot revise source while Brush drains")
	app._cut_selection()
	check(doc.revision == revision, "Cut pixels cannot revise source while Brush drains")
	app._paste_selection()
	check(doc.revision == revision and doc.history_position() == history,
		"Paste pixels cannot revise source while Brush drains")
	app._commit_text_dialog()
	check(doc.revision == revision, "Text commit cannot insert a layer during pending paint")
	app._rasterize_text()
	check(doc.revision == revision, "text rasterization cannot revise source during pending paint")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"concurrent content commands retain both in-flight gestures")
	await frames(2)
	check(app.canvas.has_pending_stroke(), "clipboard commands do not invalidate session next frame")
	check(await await_commit(app.canvas), "queued strokes still publish after denied content edits")
	check(doc.history_position() == history + 2 and doc.revision == revision + 2,
		"content commands add no unexpected history before two paints")
	check(pixel_alpha(doc, Vector2i(80, 170)) > 0,
		"pending source paint persists after attempted clipboard mutations")
	app._add_layer()
	check(doc.revision == revision + 3, "normal document editing resumes after commit")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t129-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "test directory available")
	await test_layer_commands(base)
	await test_clipboard_and_text()
	if failures == 0:
		print("T129_PENDING_EDIT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T129_PENDING_EDIT_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
