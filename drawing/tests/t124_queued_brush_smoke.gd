extends SceneTree
## Released strokes may drain asynchronously without dropping the next
## chronological Brush/Eraser press. Compare both complete source paths with
## an independent two-transaction document, including undo boundaries.

const AREA: Rect2i = Rect2i(-85, -80, 180, 160)
const FIRST: int = 0xb44183e9
const SECOND: int = 0xffa9421b
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T124_QUEUED_FAILED: " + label)


func make_target(name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	return {"document": doc, "layer": layer}


func first_path() -> PackedVector2Array:
	var path: PackedVector2Array = PackedVector2Array()
	for i: int in range(210):
		var t: float = float(i) / 209.0
		path.append(Vector2(-35.5 + 66.0 * t,
			-16.5 + sin(t * TAU * 8.0) * 29.0))
	return path


func second_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-28.5, 28.5), Vector2(-12.5, 22.5),
		Vector2(6.5, 18.5), Vector2(24.5, 27.5), Vector2(36.5, 32.5)])


func capture(canvas: Control, path: PackedVector2Array) -> void:
	canvas.start_gesture(canvas.pixel_to_position(path[0]))
	for i: int in range(1, path.size()):
		canvas.update_gesture(canvas.pixel_to_position(path[i]))
	canvas.finish_gesture(canvas.pixel_to_position(path[path.size() - 1]))


func deferred(canvas: Control) -> Dictionary:
	var value: Variant = canvas.get("_deferred_stroke")
	return value if value is Dictionary else {}


func wait_until_finished(canvas: Control, max_frames: int = 600) -> bool:
	var frame: int = 0
	while (canvas.session != null or not deferred(canvas).is_empty()) and frame < max_frames:
		await process_frame
		frame += 1
	return frame < max_frames


func compare_pixels(a: DrawingDocument, b: DrawingDocument, label: String) -> void:
	var ra: DrawingResult = DrawingRenderer.render(a, AREA)
	var rb: DrawingResult = DrawingRenderer.render(b, AREA)
	check(ra.ok and rb.ok and ra.value.get_data() == rb.value.get_data(), label)


func scenario(release_before_promotion: bool, erase_second: bool = false) -> void:
	var setup: Dictionary = make_target("queued")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	canvas.color_rgba = FIRST
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	var one: PackedVector2Array = first_path()
	var two: PackedVector2Array = second_path() if not erase_second else PackedVector2Array(
		[Vector2(-22.5, -18.5), Vector2(0.5, -14.5), Vector2(19.5, -20.5)])
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-65, -65, 130, 130), true)
	check(mask.combine_rectangle(Rect2i(4, -5, 6, 10), "Subtract"),
		"selection hole prepared for both transactions")
	canvas.set_selection_mask(mask)
	capture(canvas, one)
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
		"long first stroke leaves an unfinished release backlog")
	canvas.brush_width = 9.0
	canvas.color_rgba = SECOND
	canvas.tool = "Eraser" if erase_second else "Brush"
	canvas.start_gesture(canvas.pixel_to_position(two[0]))
	check(not deferred(canvas).is_empty() and doc.revision == revision,
		"second press is buffered without publishing or replacing the first edit")
	for i: int in range(1, two.size() - 1):
		canvas.update_gesture(canvas.pixel_to_position(two[i]))
	if release_before_promotion:
		canvas.finish_gesture(canvas.pixel_to_position(two[two.size() - 1]))
		check(not bool(deferred(canvas).get("capturing", true)),
			"second mouse-up is retained before the first commit")
		# Navigation and future tool settings must not rewrite either source path.
		canvas.zoom = 3.0
		canvas.camera = Vector2(17, -19)
		canvas.tool = "Pan"
		canvas.brush_width = 2.0
		canvas.color_rgba = 0xff000000
		check(not deferred(canvas).is_empty(),
			"released queued source samples survive zoom, pan and toolbar changes")
	else:
		var count: int = 0
		while not deferred(canvas).is_empty() and count < 550:
			await process_frame
			count += 1
		check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.CAPTURING,
			"held second press is promoted when first commit finishes")
		canvas.update_gesture(canvas.pixel_to_position(two[two.size() - 1]))
		canvas.finish_gesture(canvas.pixel_to_position(two[two.size() - 1]))
	check(await wait_until_finished(canvas), "both strokes drain in bounded frames")
	check(doc.revision == revision + 2, "two independent edits publish chronologically")
	var ref_setup: Dictionary = make_target("queued-reference")
	var oracle: DrawingDocument = ref_setup["document"]
	var edit1: DrawingEditSession = oracle.begin_edit(ref_setup["layer"], oracle.revision).value
	check(edit1.paint_path(one, FIRST, 40.0, false, mask).ok and edit1.commit().ok,
		"independent first edit oracle")
	var edit2: DrawingEditSession = oracle.begin_edit(ref_setup["layer"], oracle.revision).value
	check(edit2.paint_path(two, SECOND, 9.0, erase_second, mask).ok and edit2.commit().ok,
		"independent second edit oracle")
	compare_pixels(doc, oracle, "two Brush paths retain exact canonical bytes")
	check(doc.undo().ok and oracle.undo().ok, "first Undo removes only second stroke")
	compare_pixels(doc, oracle, "first Undo leaves first stroke intact")
	check(doc.undo().ok and oracle.undo().ok, "second Undo removes first stroke")
	compare_pixels(doc, oracle, "both Undo transactions match oracle")
	check(doc.redo().ok and oracle.redo().ok and doc.redo().ok and oracle.redo().ok,
		"both Redo transactions restore both strokes")
	compare_pixels(doc, oracle, "both Redo transactions match original pixels")
	canvas.queue_free()
	await process_frame


func overflow_scenario() -> void:
	var setup: Dictionary = make_target("overflow")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	capture(canvas, first_path())
	check(canvas._stroke_phase == canvas.StrokePhase.DRAINING, "overflow guard starts with backlog")
	var errors: Array[String] = []
	canvas.canvas_error.connect(func(message: String) -> void: errors.append(message))
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	for i: int in range(4096):
		canvas.update_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	check(deferred(canvas).is_empty() and not errors.is_empty(),
		"excess input fails visibly and releases bounded capture memory")
	check(await wait_until_finished(canvas), "original released stroke still finishes")
	check(doc.revision == revision + 1, "no overflow fragment becomes an edit")
	canvas.queue_free()
	await process_frame


func failed_predecessor_scenario() -> void:
	var setup: Dictionary = make_target("failed-predecessor")
	var doc: DrawingDocument = setup["document"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(400, 340)
	canvas.document = doc
	canvas.layer_id = setup["layer"]
	canvas.zoom = 2.0
	canvas.brush_width = 40.0
	root.add_child(canvas)
	await process_frame
	var revision: int = doc.revision
	capture(canvas, first_path())
	canvas.start_gesture(canvas.pixel_to_position(Vector2(0.5, 0.5)))
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(8.5, 2.5)))
	check(not deferred(canvas).is_empty(), "pending second release held before failed commit")
	var errors: Array[String] = []
	canvas.canvas_error.connect(func(message: String) -> void: errors.append(message))
	canvas.session.expected_revision += 1  # Fault injection: stale commit, no document mutation.
	canvas._commit_stroke()
	check(deferred(canvas).is_empty() and canvas.session == null,
		"failed predecessor never promotes or leaks the queued second session")
	check(doc.revision == revision and not errors.is_empty(),
		"failed predecessor reports an error and publishes neither stroke")
	canvas.queue_free()
	await process_frame


func run() -> void:
	await scenario(true)
	await scenario(false)
	await scenario(true, true)
	await scenario(false, true)
	await overflow_scenario()
	await failed_predecessor_scenario()
	if failures == 0:
		print("T124_QUEUED_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T124_QUEUED_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
