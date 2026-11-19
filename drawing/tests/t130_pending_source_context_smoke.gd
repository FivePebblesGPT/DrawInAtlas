extends SceneTree
## A pending Brush must retain its selection/frame context until it publishes.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T130_CONTEXT_FAILED: " + label)


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


func paint_queued(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.brush_width = 44.0
	canvas.color_rgba = 0xff3780cf
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(Vector2(80.5 + 140.0 * t, 170.5 + sin(t * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))
	canvas.brush_width = 5.0
	canvas.color_rgba = 0xff17af64
	canvas.start_gesture(canvas.pixel_to_position(Vector2(40.5, 240.5)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(50.5, 245.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(65.5, 252.5)))


func await_commit(canvas: Control, limit: int = 750) -> bool:
	var i: int = 0
	while canvas.has_pending_stroke() and i < limit:
		await process_frame
		i += 1
	return i < limit


func pixel_alpha(doc: DrawingDocument, point: Vector2i) -> int:
	var result: DrawingResult = DrawingRenderer.render(doc, Rect2i(point, Vector2i.ONE))
	return roundi((result.value as Image).get_pixel(0, 0).a * 255.0) if result.ok else -1


func test_deselect(base: String) -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(1, 1, 300, 300), true)
	app.canvas.set_selection_mask(mask)
	check(app.canvas.selection_mask.same_as(mask), "nonempty selected source prepared")
	var revision: int = doc.revision
	var history: int = doc.history_position()
	paint_queued(app.canvas)
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"two gestures are pending before clearing selection")
	app._deselect()
	check(app.canvas.selection_mask.same_as(mask), "Ctrl+D cannot remove source mask during pending stroke")
	check(doc.revision == revision and doc.history_position() == history,
		"rejected Deselect does not touch document history")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"clearing selection leaves both Brush gestures intact")
	check(app.status.text.contains("Stroke"), "Deselect refusal is actionable")
	await frames(2)
	# A fast native transaction may publish within these two frames. The
	# rejected Deselect must never mutate its source mask in either state.
	var still_pending: bool = app.canvas.has_pending_stroke()
	check(app.canvas.selection_mask.same_as(mask) and (still_pending or
		(doc.revision == revision + 2 and doc.history_position() == history + 2)),
		"Deselect retains source mask until both native gestures publish")
	check(await await_commit(app.canvas), "both Brush gestures complete after Deselect refusal")
	check(doc.revision == revision + 2 and doc.history_position() == history + 2,
		"both strokes create separate transactions")
	check(pixel_alpha(doc, Vector2i(80, 170)) > 0 and pixel_alpha(doc, Vector2i(45, 242)) > 0,
		"both source paths reach their correct pixels")
	app._deselect()
	check(not app.canvas.selection_mask.enabled, "Deselect resumes after commit")
	var path: String = base.path_join("selection.drawing")
	app._save_file(path)
	var opened: DrawingResult = DrawingFileIO.open_with_frame(path)
	check(opened.ok and pixel_alpha(opened.value["document"], Vector2i(80, 170)) > 0,
		"Save/Open retains the first painted pixel")
	app.queue_free()
	await frames(2)


func test_image_frame(base: String) -> void:
	var app: Control = await new_app()
	var doc: DrawingDocument = app.current_document()
	var old_frame: Rect2i = app.canvas.image_bounds
	var history: int = doc.history_position()
	var revision: int = doc.revision
	paint_queued(app.canvas)
	check(app.canvas.has_pending_stroke(), "two gestures pending before image frame edit")
	var requested: Rect2i = Rect2i(-12, -15, 340, 350)
	var parts: Array[int] = [requested.position.x, requested.position.y,
		requested.size.x, requested.size.y]
	for index: int in range(parts.size()):
		app.image_frame_fields[index].value = parts[index]
	app._apply_image_frame()
	check(app.canvas.image_bounds == old_frame and app.tabs[app.active_tab]["frame"] == old_frame,
		"image frame stays unchanged during unpublished paint")
	check(not bool(app.tabs[app.active_tab].get("frame_dirty", false)),
		"denied image frame edit cannot introduce metadata dirtiness")
	check(doc.revision == revision and doc.history_position() == history,
		"denied frame change leaves document history untouched")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"frame change cannot cancel pending or queued Brush")
	check(app.status.text.contains("Stroke"), "image-frame warning stays visible")
	check(await await_commit(app.canvas), "both Brush gestures commit after denied image frame")
	check(doc.history_position() == history + 2 and doc.revision == revision + 2,
		"frame request did not contribute extra history")
	app._apply_image_frame()
	check(app.canvas.image_bounds == requested and bool(app.tabs[app.active_tab]["frame_dirty"]),
		"image frame edit resumes and marks metadata dirty after commit")
	var path: String = base.path_join("frame.drawing")
	app._save_file(path)
	var opened: DrawingResult = DrawingFileIO.open_with_frame(path)
	check(opened.ok and opened.value["image_frame"] == requested,
		"saved Drawing frame contains the committed post-stroke metadata")
	check(opened.ok and pixel_alpha(opened.value["document"], Vector2i(45, 242)) > 0,
		"saved pixels include queued Brush successor")
	app.queue_free()
	await frames(2)


func test_object_frame() -> void:
	var app: Control = await new_app()
	app.new_object()
	var session: DrawingObjectEditorSession = app.current_object()
	check(session != null, "Object Editor context is available")
	if session == null:
		app.queue_free()
		return
	var before_origin: Vector2i = session.origin
	var before_bounds: Rect2i = session.bounds
	var revision: int = session.document.revision
	var history: int = session.document.history_position()
	paint_queued(app.canvas)
	check(app.canvas.has_pending_stroke(), "Object Brush has unpublished paint")
	var new_parts: Array[int] = [-25, 7, -30, -45, 360, 420]
	for index: int in range(new_parts.size()):
		app.frame_fields[index].value = new_parts[index]
	app._change_object_frame()
	check(session.origin == before_origin and session.bounds == before_bounds,
		"Object source frame cannot change underneath pending paint")
	check(app.canvas.asset_origin == before_origin and app.canvas.asset_bounds == before_bounds,
		"Object guide remains attached to original source frame")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"Object frame edit preserves both strokes")
	check(app.status.text.contains("Stroke"), "Object frame rejection is visible")
	check(await await_commit(app.canvas), "Object strokes complete before metadata edit")
	check(session.document.revision == revision + 2 and
		session.document.history_position() == history + 2,
		"Object frame edit adds no history before both Brush commits")
	app._change_object_frame()
	check(session.origin == Vector2i(-25, 7) and session.bounds == Rect2i(-30, -45, 360, 420),
		"Object frame editing resumes when strokes have finished")
	check(pixel_alpha(session.document, Vector2i(80, 170)) > 0,
		"Object source pixels remain after frame edit")
	app.queue_free()
	await frames(2)


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t130-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "test directory available")
	await test_deselect(base)
	await test_image_frame(base)
	await test_object_frame()
	if failures == 0:
		print("T130_CONTEXT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T130_CONTEXT_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
