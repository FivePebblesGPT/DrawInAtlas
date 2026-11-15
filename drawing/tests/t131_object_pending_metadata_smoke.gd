extends SceneTree
## Object source rename and Save As target staging must be fail-closed.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T131_OBJECT_META_FAILED: " + label)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func await_commit(canvas: Control, limit: int = 800) -> bool:
	var elapsed: int = 0
	while canvas.has_pending_stroke() and elapsed < limit:
		await process_frame
		elapsed += 1
	return elapsed < limit


func queued_paint(canvas: Control) -> void:
	canvas.tool = "Brush"
	canvas.brush_width = 44.0
	canvas.color_rgba = 0xff3456ac
	var path: PackedVector2Array = PackedVector2Array()
	for index: int in range(210):
		var ratio: float = float(index) / 209.0
		path.append(Vector2(80.5 + ratio * 142.0,
			170.5 + sin(ratio * TAU * 7.0) * 60.0))
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for index: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[index]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))
	canvas.brush_width = 5.0
	canvas.color_rgba = 0xff23c17a
	canvas.start_gesture(canvas.pixel_to_position(Vector2(40.5, 240.5)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(50.5, 245.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(65.5, 252.5)))


func alpha_at(doc: DrawingDocument, point: Vector2i) -> int:
	var rendered: DrawingResult = DrawingRenderer.render(doc, Rect2i(point, Vector2i.ONE))
	return roundi((rendered.value as Image).get_pixel(0, 0).a * 255.0) if rendered.ok else -1


func run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.start_blank_document = false
	root.add_child(app)
	await frames(4)
	app.new_object()
	var session: DrawingObjectEditorSession = app.current_object()
	check(session != null, "standalone Object Editor session exists")
	if session == null:
		quit(1)
		return
	var initial_name: String = session.name
	session.variant_name = "previous candidate"
	var publication: Dictionary = {"calls": 0, "seen_name": ""}
	session.save_as_publisher = func(draft: DrawingObjectEditorSession) -> DrawingResult:
		publication["calls"] = int(publication["calls"]) + 1
		publication["seen_name"] = draft.variant_name
		return DrawingResult.failure("REJECTED", "Simulated publisher failure")
	var starting_revision: int = session.document.revision
	var starting_history: int = session.document.history_position()
	queued_paint(app.canvas)
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"released paint and its queued successor are pending")
	app.rename_field.text = "New source name"
	app._rename_object()
	check(session.name == initial_name, "rename cannot change private source metadata during pending paint")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Rename Object"),
		"rename refusal is actionable")
	app.variant_name.text = "New variant name"
	app._save_as_named_object()
	check(session.variant_name == "previous candidate",
		"pending Save As does not stage a variant name before source authorization")
	check(int(publication["calls"]) == 0, "pending Save As cannot invoke the publisher")
	check(app.status.text.contains("Stroke") and app.status.text.contains("Save Object"),
		"Save As refusal is actionable")
	check(session.document.revision == starting_revision and
		session.document.history_position() == starting_history,
		"rejected object metadata actions cannot revise document history")
	check(app.canvas.has_pending_stroke() and not app.canvas._deferred_stroke.is_empty(),
		"rejected source metadata changes preserve both strokes")
	app.rename_field.text = "  " + initial_name + "  "
	app._rename_object()
	check(session.name == initial_name, "equivalent name remains safe while the stroke drains")
	check(await await_commit(app.canvas), "both strokes finish after refused metadata edits")
	check(session.document.revision == starting_revision + 2 and
		session.document.history_position() == starting_history + 2,
		"two independent stroke transactions commit in order")
	check(alpha_at(session.document, Vector2i(80, 170)) > 0 and
		alpha_at(session.document, Vector2i(45, 242)) > 0,
		"both strokes publish their canonical RGBA8 pixels")
	app.rename_field.text = "Renamed after commit"
	app._rename_object()
	check(session.name == "Renamed after commit" and session.is_dirty(),
		"Object rename resumes after the paint commits")
	app._save_as_named_object()
	check(int(publication["calls"]) == 1 and
		publication["seen_name"] == "New variant name",
		"idle Save As invokes publisher with the proposed variant name")
	check(session.variant_name == "previous candidate",
		"failed publisher restores the previous variant metadata")
	check(session.name == "Renamed after commit" and session.is_dirty(),
		"publisher failure retains source name and unpublished draft")
	# Malformed successful publisher results must also roll back proposed metadata.
	session.save_as_publisher = func(_draft: DrawingObjectEditorSession) -> DrawingResult:
		return DrawingResult.success({"unexpected": true})
	app._save_as_named_object()
	check(session.variant_name == "previous candidate" and session.is_dirty(),
		"malformed publication result also restores proposed metadata")
	# A successful Save As must still forward the proposed title, then clear it.
	session.save_as_publisher = func(draft: DrawingObjectEditorSession) -> DrawingResult:
		publication["seen_name"] = draft.variant_name
		return DrawingResult.success({"document": draft.document, "source_id": "test-variant",
			"source_revision": 1, "name": draft.variant_name,
			"origin": draft.origin, "bounds": draft.bounds})
	app._save_as_named_object()
	check(session.source_id == "test-variant" and session.name == "New variant name" and
		session.variant_name.is_empty(),
		"successful Save As uses the requested name and clears only its temporary target")
	check(publication["seen_name"] == "New variant name", "successful publisher receives intended title")
	check(alpha_at(session.document, Vector2i(45, 242)) > 0,
		"Save As retains queued Brush artwork")
	app.queue_free()
	await frames(2)
	if failures == 0:
		print("T131_OBJECT_META_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T131_OBJECT_META_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
