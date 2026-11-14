extends SceneTree
## T-095: draining duplicate or selection-rejected samples must not schedule
## a fresh Canvas draw when the detached preview has not changed. Check actual
## frame draw callbacks, not just a synthetic counter in the drain function.

const INK: int = 0x9554a2d8
const AREA: Rect2i = Rect2i(-16, -16, 65, 65)

var checks: int = 0
var failures: int = 0
var draw_count: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_NOOP_REDRAW_FAILED: " + label)

func on_draw() -> void:
	draw_count += 1

func make_document(name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name, 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	return {"doc": doc, "layer": layer}

func make_canvas(setup: Dictionary) -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(340, 240)
	canvas.document = setup["doc"]
	canvas.layer_id = setup["layer"]
	canvas.brush_width = 12.0
	canvas.color_rgba = INK
	canvas.zoom = 7.86
	canvas.draw.connect(on_draw)
	root.add_child(canvas)
	return canvas

func snapshot(doc: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	check(result.ok, "source rendered")
	return result.value.get_data() if result.ok else PackedByteArray()

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func test_duplicate_and_real_preview() -> void:
	var setup: Dictionary = make_document("noop-redraw")
	var doc: DrawingDocument = setup["doc"]
	var reference: Dictionary = make_document("noop-redraw-reference")
	var first: Vector2i = Vector2i(9, 11)
	var second: Vector2i = Vector2i(21, 11)
	var initial: PackedByteArray = snapshot(doc)
	var canvas: Control = make_canvas(setup)
	await settle()
	canvas.start_gesture(canvas.pixel_to_position(Vector2(first) + Vector2(0.5, 0.5)))
	check(canvas.session != null and canvas.session._preview_epoch > 0,
		"stationary pointer-down produced initial preview")
	await settle()
	var drawn_after_dab: int = draw_count
	var staged_before: int = int(canvas._metrics["segments_staged"])
	for i: int in range(24):
		canvas.paint_to(first)
		canvas._drain_segments(256)
		await process_frame
	await settle()
	check(int(canvas._metrics["segments_staged"]) >= staged_before + 24,
		"all duplicate waypoints staged, not dropped")
	check(draw_count == drawn_after_dab,
		"24 already-covered batches do not schedule a Canvas redraw")
	var first_epoch: int = canvas.session._preview_epoch
	canvas.paint_to(second)
	canvas._drain_segments(256)
	check(canvas.session._preview_epoch > first_epoch,
		"a new swept region changes the detached preview generation")
	await settle()
	check(draw_count > drawn_after_dab,
		"new pixels still schedule a Canvas redraw")
	var changed_draws: int = draw_count
	for i: int in range(8):
		canvas.paint_to(second)
		canvas._drain_segments(256)
		await process_frame
	await settle()
	check(draw_count == changed_draws,
		"returning to a fully covered endpoint does not draw again")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(second) + Vector2(0.5, 0.5)))
	var spins: int = 0
	while canvas.session != null and spins < 200:
		canvas._drain_segments(256)
		spins += 1
	check(canvas.session == null and doc.revision == 2,
		"release commits exactly one edit despite duplicate backlog")
	await settle()
	check(draw_count > changed_draws, "commit still schedules final redraw")

	var reference_doc: DrawingDocument = reference["doc"]
	var reference_edit: DrawingEditSession = reference_doc.begin_edit(reference["layer"],
		reference_doc.revision).value
	check(reference_edit.paint_path(PackedVector2Array([
		Vector2(first) + Vector2(0.5, 0.5),
		Vector2(second) + Vector2(0.5, 0.5)]), INK, 12.0).ok,
		"independent source-space reference path succeeds")
	check(reference_edit.commit().ok, "reference commit")
	var committed: PackedByteArray = snapshot(doc)
	check(committed == snapshot(reference_doc), "source bytes equal independent stroke")
	check(doc.undo().ok and snapshot(doc) == initial, "Undo restores exact source")
	check(doc.redo().ok and snapshot(doc) == committed, "Redo restores exact source")
	canvas.queue_free()
	await settle()

func test_selection_rejected() -> void:
	var setup: Dictionary = make_document("masked-noop")
	var doc: DrawingDocument = setup["doc"]
	var original: PackedByteArray = snapshot(doc)
	var canvas: Control = make_canvas(setup)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-10, -10, 3, 3), true)
	canvas.set_selection_mask(mask)
	await settle()
	var point: Vector2i = Vector2i(15, 13)
	canvas.start_gesture(canvas.pixel_to_position(Vector2(point) + Vector2(0.5, 0.5)))
	check(canvas.session != null and canvas.session._preview_epoch == 0,
		"masked initial dab owns empty detached preview")
	await settle()
	var previous_draws: int = draw_count
	for i: int in range(16):
		canvas.paint_to(point)
		canvas._drain_segments(256)
		await process_frame
	await settle()
	check(draw_count == previous_draws,
		"fully masked sample queue does not trigger any image redraw")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(point) + Vector2(0.5, 0.5)))
	check(canvas.session == null and doc.revision == 1,
		"empty selection-limited stroke does not publish a revision")
	check(snapshot(doc) == original, "masked stroke leaves exact source unchanged")
	canvas.queue_free()
	await settle()

func run() -> void:
	await test_duplicate_and_real_preview()
	await test_selection_rejected()
	print("T095_NOOP_REDRAW_RESULT checks=%d failures=%d draws=%d" % [checks, failures, draw_count])
	if failures == 0:
		print("T095_NOOP_REDRAW_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
