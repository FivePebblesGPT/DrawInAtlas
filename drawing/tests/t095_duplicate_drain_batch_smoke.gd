extends SceneTree
## T-095: identical Legacy source targets can share one bounded paint_path call.
## Input accounting and independent full-raster byte/history parity must survive.

const INK: int = 0xb75382d9
const VIEW: Rect2i = Rect2i(-68, -68, 136, 136)

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_DUPLICATE_DRAIN_FAILED: " + description)


func make_target(title: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(title, 32)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var pixels: PackedByteArray = PackedByteArray()
	for i: int in range(17 * 17):
		pixels.append_array(PackedByteArray([i % 256, (i * 7) % 256,
			(i * 13) % 256, 0 if i % 5 == 0 else 181]))
	check(seed.apply_region(Rect2i(-8, -8, 17, 17), pixels).ok and seed.commit().ok,
		title + " initial RGBA8 source seeded")
	return {"doc": doc, "layer": layer}


func source_bytes(target: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var output: DrawingResult = DrawingRenderer.render(target["doc"], VIEW, 0, 0,
		VIEW.size.x * VIEW.size.y, edit)
	check(output.ok, "render source or detached preview")
	return (output.value as Image).get_data() if output.ok else PackedByteArray()


func drain(canvas: Control) -> void:
	for i: int in range(200):
		if canvas._samples.is_empty() and not canvas._has_segment_target:
			return
		canvas._drain_segments(256)
	check(false, "drain completed without hitting guard")


func run() -> void:
	var fast: Dictionary = make_target("duplicate-drain-fast")
	var reference: Dictionary = make_target("duplicate-drain-reference")
	var doc: DrawingDocument = fast["doc"]
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(980, 700)
	canvas.zoom = 7.86
	canvas.document = doc
	canvas.layer_id = fast["layer"]
	canvas.brush_backend = "Legacy"
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	root.add_child(canvas)
	await process_frame
	await process_frame

	var start: Vector2 = Vector2(-0.5, 0.5)
	var points: PackedVector2Array = PackedVector2Array([start])
	canvas.start_gesture(canvas.pixel_to_position(start))
	check(canvas.session != null, "real Canvas gesture started")
	var edit: DrawingEditSession = canvas.session
	# 80 duplicates, a short movement, then another 80 repeated endpoints.
	# All are queued before staging, as in a backlog of real mouse motions.
	for i: int in range(80):
		var sample: Vector2 = Vector2(-0.5, 0.5)
		points.append(sample)
		canvas.paint_to(Vector2i(-1, 0))
	points.append(Vector2(4.5, -3.5))
	canvas.paint_to(Vector2i(4, -4))
	for i: int in range(80):
		points.append(Vector2(4.5, -3.5))
		canvas.paint_to(Vector2i(4, -4))
	check(int(canvas._metrics.get("samples_received", -1)) == points.size(),
		"all 162 individual source events were received")
	check(int(canvas._metrics.get("segments_staged", 0)) == 1,
		"only pointer-down staged before the queued backlog")
	var revision: int = doc.revision
	drain(canvas)
	check(canvas.session == edit and doc.revision == revision,
		"all queued motions staged without publishing")
	check(int(canvas._metrics.get("segments_staged", -1)) == points.size(),
		"every source sample remains counted as a staged segment")
	check(int(canvas._metrics.get("sample_to_stage_total", -1)) == points.size(),
		"every input timestamp contributes to latency telemetry")
	check((canvas._metrics.get("sample_to_stage_us", []) as Array).size() == points.size(),
		"each sampled input retains a latency observation")
	check(int(canvas._metrics.get("duplicate_drain_batched", 0)) >= 140,
		"duplicate source positions are combined into bounded Legacy batches")
	check(int(canvas._metrics.get("stage_batch_total", 0)) <= 16,
		"162 input segments require at most sixteen atomic Legacy calls")
	check(canvas._samples.is_empty() and not canvas._has_segment_target,
		"no pending input is dropped or stranded")
	print("T095_DUPLICATE_DRAIN_PROFILE stage_cpu_us=%d batches=%d segments=%d merged=%d" % [
		int(canvas._metrics.get("stage_cpu_us", -1)),
		int(canvas._metrics.get("stage_batch_total", -1)),
		int(canvas._metrics.get("segments_staged", -1)),
		int(canvas._metrics.get("duplicate_drain_batched", 0))])
	check(edit._cross_batch_dabs_skipped <= 10,
		"duplicate suppression primarily takes place inside atomic batches")

	var reference_edit: DrawingEditSession = (reference["doc"] as DrawingDocument).begin_edit(
		reference["layer"], (reference["doc"] as DrawingDocument).revision).value
	for point: Vector2 in points:
		# Deliberately bypass the prior cross-batch shortcut; every reference
		# input rasterizes the full once-only candidate footprint.
		reference_edit._stationary_dab_valid = false
		check(reference_edit.paint_path(PackedVector2Array([point]), INK, 60.0).ok,
			"full-rectangle reference accepted point")
	var initial: PackedByteArray = source_bytes(fast)
	check(initial == source_bytes(reference), "sources match before commit")
	var preview: PackedByteArray = source_bytes(fast, edit)
	check(preview == source_bytes(reference, reference_edit),
		"exact RGBA8 preview parity with individual full-raster calls")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(4.5, -3.5)))
	drain(canvas)
	check(canvas.session == null and doc.revision == revision + 1,
		"one released gesture produces one content revision")
	check(reference_edit.paint_path(PackedVector2Array([Vector2(4.5, -3.5)]),
		INK, 60.0).ok and reference_edit.commit().ok,
		"full-raster control commits same released endpoint")
	check(source_bytes(fast) == source_bytes(reference) and source_bytes(fast) == preview,
		"committed pixels match independent source and preview")
	var reference_doc: DrawingDocument = reference["doc"]
	check(doc.undo().ok and reference_doc.undo().ok and
		source_bytes(fast) == source_bytes(reference) and source_bytes(fast) == initial,
		"one-step Undo exact RGBA8 parity")
	check(doc.redo().ok and reference_doc.redo().ok and
		source_bytes(fast) == source_bytes(reference) and source_bytes(fast) == preview,
		"Redo exactly restores source")
	canvas.queue_free()
	await process_frame
	print("T095_DUPLICATE_DRAIN_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_DUPLICATE_DRAIN_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
