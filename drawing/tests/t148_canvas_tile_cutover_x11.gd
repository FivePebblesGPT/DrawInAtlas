extends SceneTree
## T-148 production Canvas native tile cutover; graphical software-rendered
## integration, source/preview/Undo and real portable .drawing file witness.

const SIZE: int = 64
const STRIDE: int = 64
const HIDDEN: int = 0x00c79a47
const RED: int = 0xff0000ee


class FailingSourceDocument extends DrawingDocument:
	var reject_source: bool = true
	var lock_during_read: bool = false

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		if reject_source and key == "0,0":
			return DrawingResult.failure("MISSING_TILE", "Injected lazy source failure")
		if lock_during_read and key == "0,0":
			lock_during_read = false
			set_locked(layer_id, true)
		return super._resolve_chunk(layer_id, key)
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_CANVAS_TILES_FAILED: " + label)


func frames(count: int = 1) -> void:
	for i: int in range(count):
		await process_frame


func pixel_bytes(doc: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, SIZE, SIZE))
	check(result.ok, "canonical image render")
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func drain(canvas: Control) -> void:
	for frame: int in range(180):
		if canvas.session == null:
			return
		await process_frame
	check(canvas.session == null, "native Canvas stroke drain did not time out")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires real software-rendered graphical viewport")
		quit(1)
		return
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real native classes installed")
	root.size = Vector2i(640, 640)
	var doc: DrawingDocument = DrawingDocument.new("native-canvas-publish", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Pigment").value)
	var original: PackedByteArray = PackedByteArray()
	original.resize(STRIDE * STRIDE * 4)
	original.encode_u32(0, HIDDEN)
	doc._nodes[layer].tiles["0,0"] = DrawingRasterTile.from_rgba8(STRIDE, original)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(420, 420)
	canvas.camera = Vector2(32, 32)
	canvas.zoom = 5.0
	canvas.document = doc
	canvas.layer_id = layer
	canvas.image_bounds = Rect2i(0, 0, SIZE, SIZE)
	canvas.clip_strokes_to_image_frame = true
	canvas.brush_backend = "NativeHard"
	canvas.brush_width = 18.0
	canvas.color_rgba = RED
	canvas.tool = "Brush"
	root.add_child(canvas)
	await frames(3)
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(8, 8, 48, 48), true)
	check(selected.combine_rectangle(Rect2i(30, 30, 6, 6), "Subtract"),
		"selection with interior hole")
	canvas.set_selection_mask(selected)
	var previous_revision: int = doc.revision
	var start: Vector2 = canvas.pixel_to_position(Vector2(20.5, 20.5))
	var end: Vector2 = canvas.pixel_to_position(Vector2(42.5, 42.5))
	canvas.start_gesture(start)
	check(canvas.session != null and canvas.session._native_tiles != null,
		"production pointer dispatch enters native tile engine")
	if canvas.session == null:
		quit(1)
		return
	canvas.update_gesture(end)
	await frames(4)
	check(doc.revision == previous_revision, "native preview remains detached")
	check(canvas.session != null and canvas.session._preview_tiles.is_empty() \
		and canvas.session._after.is_empty(),
		"no GDScript per-pixel preview/history staging")
	var preview: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, SIZE, SIZE),
		0, 0, SIZE * SIZE, canvas.session)
	check(preview.ok, "renderer consumes actual native tile preview")
	var preview_bytes: PackedByteArray = (preview.value as Image).get_data() if preview.ok \
		else PackedByteArray()
	check(not preview_bytes.is_empty() and preview_bytes.count(0) < preview_bytes.size() - 3,
		"native preview contains visible pigment")
	canvas.finish_gesture(end)
	await drain(canvas)
	check(doc.revision == previous_revision + 1, "single native Canvas revision")
	var metrics: Dictionary = canvas.last_gesture_metrics
	var ffi: Dictionary = metrics.get("native_ffi_stats", {})
	check(int(ffi.get("tile_ffi_calls", 0)) > 0 and
		int(ffi.get("tile_pixel_stream_calls", -1)) == 0,
		"real Canvas tile ABI uses zero per-pixel FFI stream calls")
	check(int(ffi.get("tile_bytes_imported", 0)) > 0 or
		int(ffi.get("tile_bytes_exported", 0)) > 0,
		"actual tile-level transfer is measured")
	check(doc.history_length() == 1 and
		(doc._events[0]["delta"] as DrawingDelta).tile_stride == STRIDE and
		(doc._events[0]["delta"] as DrawingDelta).after.is_empty(),
		"one document history event uses packed tile snapshots")
	var committed: PackedByteArray = pixel_bytes(doc)
	check(preview_bytes == committed, "held NativeHard preview equals committed source bytes")
	check(int(doc.read_pixel(layer, 32, 32).value) == 0,
		"native selection hole excludes pigment")
	check(((int(doc.read_pixel(layer, 25, 25).value) >> 24) & 255) > 0,
		"native mask authorizes pigment inside selection")
	check(int(doc.read_pixel(layer, 0, 0).value) == HIDDEN,
		"native pigment preserves unrelated alpha-zero hidden RGB")
	var source: DrawingRasterTile = doc._nodes[layer].tiles["0,0"]
	check(source.has_packed_rgba8(), "canonical published tile remains packed")
	var saved_path: String = ProjectSettings.globalize_path("user://t148-cutover-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, saved_path).ok, "native Canvas source saves as portable .drawing")
	var opened: DrawingResult = DrawingFileIO.open(saved_path)
	check(opened.ok, "native Canvas .drawing reload succeeds")
	if opened.ok:
		check(pixel_bytes(opened.value as DrawingDocument) == committed,
			"loaded .drawing renders byte-identical committed pigment")
	DirAccess.remove_absolute(saved_path)
	check(doc.undo().ok and doc.revision == previous_revision + 2,
		"native Canvas gesture undo increments document revision once")
	check(int(doc.read_pixel(layer, 0, 0).value) == HIDDEN and
		int(doc.read_pixel(layer, 25, 25).value) == 0,
		"Undo restores prior exact source")
	check(doc.redo().ok and pixel_bytes(doc) == committed,
		"Redo restores the exact native committed framebuffer")
	canvas.set_selection_mask(DrawingSelection.new())
	canvas.tool = "Eraser"
	canvas.start_gesture(start)
	canvas.finish_gesture(end)
	await drain(canvas)
	var erased: PackedByteArray = pixel_bytes(doc)
	check(erased != committed and doc.revision == previous_revision + 4,
		"native eraser publishes one changed tile revision")
	check(doc.undo().ok and pixel_bytes(doc) == committed,
		"native Eraser Undo restores original RGBA8")
	# A cancelled brush must not publish new tile content or history.
	canvas.tool = "Brush"
	var before_cancel: PackedByteArray = pixel_bytes(doc)
	var cancel_revision: int = doc.revision
	canvas.start_gesture(start)
	check(canvas.session != null and canvas.session._native_tiles != null,
		"cancel witness opens native tile transaction")
	canvas.cancel_gesture()
	check(doc.revision == cancel_revision and pixel_bytes(doc) == before_cancel,
		"native cancellation publishes zero pixels or revisions")
	# A production Canvas source failure must reject the whole native draft,
	# preserve history, and permit the next independent gesture to retry.
	var failing_doc: FailingSourceDocument = FailingSourceDocument.new(
		"native-source-failure", STRIDE)
	var failing_layer: String = str(failing_doc.create_layer(
		DrawingLayerNode.RASTER, "Lazy").value)
	var failed_canvas: Control = Control.new()
	failed_canvas.set_script(load("res://addons/drawing/canvas.gd"))
	failed_canvas.position = Vector2(30, 30)
	failed_canvas.size = Vector2(420, 420)
	failed_canvas.camera = Vector2(32, 32)
	failed_canvas.zoom = 5.0
	failed_canvas.document = failing_doc
	failed_canvas.layer_id = failing_layer
	failed_canvas.image_bounds = Rect2i(0, 0, SIZE, SIZE)
	failed_canvas.clip_strokes_to_image_frame = true
	failed_canvas.brush_backend = "NativeHard"
	failed_canvas.brush_width = 18.0
	failed_canvas.color_rgba = RED
	failed_canvas.tool = "Brush"
	root.add_child(failed_canvas)
	await frames(3)
	var fault_start: Vector2 = failed_canvas.pixel_to_position(Vector2(20.5, 20.5))
	var failure_revision: int = failing_doc.revision
	failed_canvas.start_gesture(fault_start)
	failed_canvas.finish_gesture(fault_start)
	await drain(failed_canvas)
	check(failed_canvas.session == null and failing_doc.revision == failure_revision,
		"failed lazy source aborts live native stroke without publication")
	check(failing_doc.history_length() == 0 and not failing_doc._nodes[failing_layer].tiles.has("0,0"),
		"failed lazy source leaves canonical pixels and undo stack unchanged")
	failing_doc.reject_source = false
	failed_canvas.start_gesture(fault_start)
	failed_canvas.finish_gesture(fault_start)
	await drain(failed_canvas)
	check(failing_doc.revision == failure_revision + 1 and
		failing_doc.history_length() == 1,
		"retry on recovered source commits one native history event")
	check(int(failing_doc.read_pixel(failing_layer, 20, 20).value) != 0,
		"retry recovers native brush output at source pixel")
	# Bypass the Canvas setter deliberately: a compromised caller must not
	# replace the frozen mask halfway through a native transaction.
	failed_canvas.set_selection_mask(DrawingSelection.new(
		Rect2i(15, 15, 14, 14), true))
	var selection_revision: int = failing_doc.revision
	failed_canvas.start_gesture(fault_start)
	check(failed_canvas.session != null, "selection witness started native gesture")
	if failed_canvas.session != null:
		failed_canvas._stroke_selection.set_rectangle(Rect2i(40, 40, 8, 8))
		failed_canvas.finish_gesture(fault_start)
		await drain(failed_canvas)
		check(failing_doc.revision == selection_revision and
			failing_doc.history_length() == 1 and failed_canvas.session == null,
			"changed selection cannot publish an earlier authorized draft")
	# An untrusted lazy resolver may reenter the document and lock the layer.
	# The native batch must not publish against that newly stale authority.
	failed_canvas.set_selection_mask(DrawingSelection.new())
	var before_lock: PackedByteArray = pixel_bytes(failing_doc)
	failing_doc.lock_during_read = true
	var before_lock_revision: int = failing_doc.revision
	failed_canvas.start_gesture(fault_start)
	failed_canvas.finish_gesture(fault_start)
	await drain(failed_canvas)
	check(failing_doc.revision == before_lock_revision + 1 and
		failing_doc._nodes[failing_layer].locked and failed_canvas.session == null,
		"reentrant lazy provider invalidates native authority and aborts")
	check(pixel_bytes(failing_doc) == before_lock,
		"reentrant layer lock leaves raster source untouched")
	failed_canvas.queue_free()
	await frames(2)
	print("T148_CANVAS_TILES_RESULT checks=%d failures=%d ffi=%s" % [
		checks, failures, str(ffi)])
	quit(0 if failures == 0 else 1)


func _initialize() -> void:
	call_deferred("run")
