extends SceneTree
## T-099: real pointer-held preview, bounded redraw coalescing, signed masked
## Brush/Eraser RGBA8 parity and source-space post-release navigation.
## Xvfb engine callbacks are not device input-to-photon timings.

const VIEW: Rect2i = Rect2i(-128, -128, 256, 256)
const INK: int = 0xb44387e5
const WIDTH: float = 96.0
const LIMIT: int = 240

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T099_PREVIEW_FAILED: " + label)


func input_button(canvas: Control, source: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func input_motion(canvas: Control, source: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = canvas.global_position + canvas.pixel_to_position(source)
	event.global_position = event.position
	root.push_input(event, true)


func path_points() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for row: int in range(4):
		var y: float = -78.5 + 52.0 * row
		for index: int in range(15):
			var column: int = index if row % 2 == 0 else 14 - index
			result.append(Vector2(-105.5 + 15.0 * column, y))
	return result


func render_bytes(doc: DrawingDocument) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(doc, VIEW)
	check(rendered.ok, "signed RGBA8 reference render succeeds")
	return (rendered.value as Image).get_data() if rendered.ok else PackedByteArray()


func run_stroke(canvas: Control, doc: DrawingDocument, layer: String,
		oracle: DrawingDocument, reference_layer: String, mask: DrawingSelection,
		erase: bool) -> void:
	var name: String = "Eraser" if erase else "Brush"
	canvas.tool = name
	canvas.camera = Vector2.ZERO
	canvas.zoom = 1.0
	canvas.brush_width = WIDTH
	canvas.color_rgba = INK
	canvas.set_selection_mask(mask)
	await process_frame
	var previous_revision: int = doc.revision
	var path: PackedVector2Array = path_points()
	var original_accumulation: bool = Input.use_accumulated_input
	input_button(canvas, path[0], true)
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.CAPTURING,
		name + " begins through actual pointer-down")
	for i: int in range(1, path.size()):
		input_motion(canvas, path[i])
	var pending: Dictionary = canvas._frame_input_backlog(Time.get_ticks_usec())
	check(int(pending.get("pending_input_count", 0)) > 5,
		name + " retains original input backlog while held")
	for frame: int in range(4):
		await process_frame
	check(canvas.session != null and canvas.dragging and
		canvas._stroke_phase == canvas.StrokePhase.CAPTURING and doc.revision == previous_revision,
		name + " stays held and unpublished across four actual frames")
	check(int(canvas._metrics.get("preview_frames", 0)) >= 2 and
		int(canvas._metrics.get("frame_preview_stage_submissions", 0)) >= 2,
		name + " draws changing live preview before pointer release")
	input_button(canvas, path[-1], false)
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
		name + " releases into a pending source-space transaction")
	canvas.zoom = 1.3
	canvas.camera = Vector2(20.0, -24.0)
	canvas.tool = "Pan"
	check(canvas.session != null and doc.revision == previous_revision,
		name + " survives post-release camera, zoom and tool changes")
	var frames: int = 0
	while canvas.session != null and frames < LIMIT:
		await process_frame
		frames += 1
	check(canvas.session == null and doc.revision == previous_revision + 1,
		name + " drains and publishes one atomic history entry")
	var stats: Dictionary = canvas.last_gesture_metrics
	check(int(stats.get("samples_received", -1)) == path.size() + 1,
		name + " receives all down/motion/up positions, no drops")
	check(int(stats.get("segments_staged", 0)) >= path.size() and
		int(stats.get("drain_calls", 0)) >= 2,
		name + " stages the complete interpolated path")
	check(canvas._pending_preview_drain_calls == 0 and
		canvas._pending_preview_first_us == 0 and Input.use_accumulated_input == original_accumulation,
		name + " resets pending draw schedule and restores input accumulation")
	var edit: DrawingEditSession = oracle.begin_edit(reference_layer, oracle.revision).value
	check(edit.paint_path(path, INK, WIDTH, erase, mask).ok and edit.commit().ok,
		name + " independent unsliced oracle publishes")
	var committed: PackedByteArray = render_bytes(doc)
	check(committed == render_bytes(oracle),
		name + " preserves every signed/masked/hole RGBA8 source byte")
	check(doc.undo().ok and oracle.undo().ok and render_bytes(doc) == render_bytes(oracle),
		name + " single Undo matches unsliced oracle")
	check(doc.redo().ok and oracle.redo().ok and render_bytes(doc) == committed and
		committed == render_bytes(oracle), name + " Redo restores identical RGBA8 bytes")
	print("T099_HELD mode=%s events=%d preview_frames=%d drain_calls=%d held_frames=4 release_to_commit_ms=%.3f" % [
		name, path.size() + 1, int(stats.get("preview_frames", 0)),
		int(stats.get("drain_calls", 0)),
		float(int(stats.get("commit_us", 0)) - int(stats.get("release_us", 0))) / 1000.0])


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires an actual graphical viewport")
		quit(2)
		return
	root.size = Vector2i(1000, 780)
	var doc: DrawingDocument = DrawingDocument.new("t099-pointer-signed-mask")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var oracle: DrawingDocument = DrawingDocument.new("t099-unsliced-oracle")
	var reference_layer: String = String(oracle.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(650.0, 520.0)
	canvas.position = Vector2(20.0, 20.0)
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	await process_frame
	await RenderingServer.frame_post_draw
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-116, -105, 232, 210), true)
	check(mask.combine_rectangle(Rect2i(-9, -9, 18, 18), "Subtract"),
		"signed selection excludes a hole across both axes")
	await run_stroke(canvas, doc, layer, oracle, reference_layer, mask, false)
	await run_stroke(canvas, doc, layer, oracle, reference_layer, mask, true)
	# An unsubmitted changed preview must not leak into the next transaction.
	canvas.tool = "Brush"
	canvas.zoom = 1.0
	canvas.camera = Vector2.ZERO
	var old_revision: int = doc.revision
	var original_accumulation: bool = Input.use_accumulated_input
	input_button(canvas, Vector2(-95.5, 60.5), true)
	input_motion(canvas, Vector2(95.5, 60.5))
	check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.CAPTURING,
		"cancel candidate is captured but unpublished")
	canvas.zoom = 1.25
	check(canvas.session == null and doc.revision == old_revision and
		canvas._pending_preview_drain_calls == 0 and
		canvas._pending_preview_first_us == 0 and
		Input.use_accumulated_input == original_accumulation,
		"held zoom cancellation clears deferred draw and input-ownership state")
	check(render_bytes(doc) == render_bytes(oracle),
		"cancelled pending pixels never reach signed source")
	canvas.queue_free()
	print("T099_PREVIEW_SCHEDULE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
