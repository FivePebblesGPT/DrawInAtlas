extends SceneTree
## T-195: same-binary bounded second release drain versus ordinary per-frame drain.
## Signed tiles, hidden RGB, selection subtraction, Brush/Eraser, history,
## framebuffer display and cancellation must not depend on grouping strategy.

const AREA: Rect2i = Rect2i(-256, -256, 512, 512)

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T195_CATCHUP_FAILED: " + label)


func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func path(offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var samples: PackedVector2Array = PackedVector2Array()
	# Revisit signed storage-tile runs and the same pixel on different passes.
	for row in range(6):
		var y: float = -155.0 + row * 53.0
		for column in range(14):
			var step: int = column if row % 2 == 0 else 13 - column
			samples.append(Vector2(-195.5 + 310.0 * step / 13.0, y) + offset)
	return samples


func stroke(canvas: Control, samples: PackedVector2Array) -> Dictionary:
	canvas.start_gesture(canvas.pixel_to_position(samples[0]))
	check(canvas.session != null and canvas._native_brush != null and
		canvas._active_brush_backend == "Hokusai", "required native Hokusai transaction")
	for index: int in range(1, samples.size()):
		canvas.update_gesture(canvas.pixel_to_position(samples[index]))
	await process_frame
	check(canvas.session != null and not canvas._finish_requested and
		int(canvas._metrics.get("post_release_catchup_calls", -1)) == 0,
		"captured pointer input never uses release-only catch-up")
	canvas.finish_gesture(canvas.pixel_to_position(samples[samples.size() - 1]))
	var frames: int = 0
	while canvas.session != null and frames < 240:
		await process_frame
		frames += 1
	check(canvas.session == null, "all queued segments commit within 240 frames")
	await RenderingServer.frame_post_draw
	var metrics: Dictionary = canvas.last_gesture_metrics
	check(int(metrics.get("segments_staged", 0)) > samples.size(),
		"native interpolation preserves all long-segment samples")
	check(int(metrics.get("native_ffi_stats", {}).get("batches", 0)) > 0,
		"native stages rather than synthetic painting")
	return metrics


func bytes_for(doc: DrawingDocument) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(doc, AREA)
	check(rendered.ok, "whole signed source renders")
	return (rendered.value as Image).get_data() if rendered.ok else PackedByteArray()


func trial(reference: bool) -> Dictionary:
	if reference:
		OS.set_environment("DRAWING_T195_RELEASE_CATCHUP_COUNTERFACTUAL", "1")
	else:
		OS.unset_environment("DRAWING_T195_RELEASE_CATCHUP_COUNTERFACTUAL")
	var doc: DrawingDocument = DrawingDocument.new("t195-release-catchup", 256)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Native").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var source: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.25, 0.5, 0.35, 0.5))
	check(seed.apply_region(Rect2i(-256, -256, 256, 256), source.get_data()).ok,
		"seed partial-alpha source for native batch cadence parity")
	check(seed.apply_region(Rect2i(-240, -200, 1, 1),
		PackedByteArray([18, 86, 142, 0])).ok and seed.commit().ok,
		"hidden RGB override committed at signed source location")
	var seeded: PackedByteArray = bytes_for(doc)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(12, 12)
	canvas.size = Vector2(860, 700)
	canvas.camera = Vector2(-40, -10)
	canvas.zoom = 1.0
	canvas.brush_width = 42.0
	canvas.color_rgba = 0xff4433e0
	canvas.brush_preset = "hard"
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	for i in range(5):
		await frame()
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-220, -180, 380, 350), true)
	check(selection.combine_rectangle(Rect2i(-25, -10, 30, 30), "Subtract"),
		"subtracted selection hole is configured")
	canvas.set_selection_mask(selection)
	var hole_before: int = int(doc.read_pixel(layer, -10, -5).value)
	var brush_metrics: Dictionary = await stroke(canvas, path())
	check(int(brush_metrics.get("native_ffi_stats", {}).get("tile_source_lookups", 0)) > 0,
		"native staging is instrumented for both branches")
	var painted: PackedByteArray = bytes_for(doc)
	check(int(doc.read_pixel(layer, -10, -5).value) == hole_before,
		"subtracted selection hole retains original partial-alpha source")
	check(painted != seeded, "Brush changes signed source")
	check(doc.history_length() == 2 and doc.history_position() == 2,
		"seed plus native Brush are one history event each")
	check(int(doc.read_pixel(layer, -240, -200).value) == 0x008e5612,
		"hidden source RGB remains unchanged at alpha zero")
	check(doc.undo().ok and bytes_for(doc) == seeded,
		"Brush Undo restores exact signed RGBA8 including hidden RGB")
	check(doc.redo().ok and bytes_for(doc) == painted,
		"Brush Redo restores exact signed RGBA8")
	canvas.tool = "Eraser"
	canvas.brush_width = 42.0
	var eraser_metrics: Dictionary = await stroke(canvas, path(Vector2(0, 0)))
	var erased: PackedByteArray = bytes_for(doc)
	check(erased != painted, "Eraser really updates painted source")
	check(doc.history_length() == 3 and doc.history_position() == 3,
		"Eraser is a single native history event")
	check(doc.undo().ok and bytes_for(doc) == painted,
		"Eraser Undo restores Brush RGBA8")
	check(doc.redo().ok and bytes_for(doc) == erased,
		"Eraser Redo restores exact RGBA8")
	# The actual portable file must reopen with signed, masked native pixels,
	# not just survive an in-memory encode/decode operation.
	var file_path: String = ProjectSettings.globalize_path(
		"user://t195-release-catchup-%s.drawing" % ("reference" if reference else "optimized"))
	check(DrawingFileIO.save(doc, file_path).ok and FileAccess.file_exists(file_path),
		"real standalone Save accepts native Brush/Eraser source")
	var opened: DrawingResult = DrawingFileIO.open(file_path)
	check(opened.ok and bytes_for(opened.value as DrawingDocument) == erased,
		"standalone Open restores exact signed/masked/partial-alpha native pixels")
	DirAccess.remove_absolute(file_path)
	canvas.tool = "Brush"
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-180, -110)))
	canvas.update_gesture(canvas.pixel_to_position(Vector2(-170, -100)))
	canvas.cancel_gesture()
	check(doc.history_length() == 3 and bytes_for(doc) == erased,
		"cancelled native stroke never edits source or history")
	canvas.queue_free()
	await process_frame
	return {"brush": painted, "eraser": erased, "brush_stats": brush_metrics,
		"erase_stats": eraser_metrics}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "real graphical X11 renderer required")
		quit(1)
		return
	var previous_profile: String = OS.get_environment("DRAWING_T185_PROFILE")
	OS.set_environment("DRAWING_T185_PROFILE", "1")
	root.size = Vector2i(920, 780)
	root.content_scale_size = root.size
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "native classes registered")
	var optimized: Dictionary = await trial(false)
	var reference: Dictionary = await trial(true)
	OS.unset_environment("DRAWING_T195_RELEASE_CATCHUP_COUNTERFACTUAL")
	# The native rasterizer receives the same source-space samples and frozen
	# preset; only the released-stroke drain cadence differs; capturing remains unchanged.
	check(optimized["brush"] == reference["brush"],
		"identical signed/masked/hidden-RGB Brush source with extra release drains")
	check(optimized["eraser"] == reference["eraser"],
		"identical signed/masked/hidden-RGB Eraser source with extra release drains")
	for label in ["brush_stats", "erase_stats"]:
		var fast: Dictionary = optimized[label]
		var prior: Dictionary = reference[label]
		check(int(fast.get("samples_received", 0)) == int(prior.get("samples_received", -1)),
			label + " retains every input event")
		check(int(fast.get("segments_staged", 0)) == int(prior.get("segments_staged", -1)),
			label + " stages every interpolated segment")
		check(int(fast.get("native_ffi_stats", {}).get("batches", 0)) ==
			int(prior.get("native_ffi_stats", {}).get("batches", 0)),
			label + " retains identical native transaction grouping")
		check(int(fast.get("post_release_catchup_calls", 0)) > 0 and
			int(prior.get("post_release_catchup_calls", -1)) == 0,
			label + " performs bounded extra release drains only in optimized mode")
		check(int(fast.get("max_drain_cpu_us", 0)) > 0 and
			int(prior.get("max_drain_cpu_us", 0)) > 0,
			label + " records the unchanged bounded drain timing")
	if previous_profile.is_empty():
		OS.unset_environment("DRAWING_T185_PROFILE")
	else:
		OS.set_environment("DRAWING_T185_PROFILE", previous_profile)
	print("T195_CATCHUP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T195_CATCHUP_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
