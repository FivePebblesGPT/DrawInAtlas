extends SceneTree
## Opt-in owner-device trace: no source bytes, pixel positions or names in JSONL.

const ENV: String = "DRAWING_T095_TRACE_JSONL"
const TRACE_PATH: String = "user://t095-owner-trace-regression.jsonl"
const INK: int = 0x9b44b7dd
const AREA: Rect2i = Rect2i(-40, -40, 80, 80)
var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_OWNER_TRACE_FAILED: " + message)


func canvas_instance() -> Control:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(520, 400)
	return canvas


func source_bytes(doc: DrawingDocument) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, AREA, 0, 0,
		AREA.size.x * AREA.size.y)
	return (result.value as Image).get_data() if result.ok else PackedByteArray()


func stroke(canvas: Control, start: Vector2, end: Vector2) -> void:
	canvas.start_gesture(canvas.pixel_to_position(start))
	canvas.paint_to(Vector2i(floori(end.x), floori(end.y)))
	canvas.finish_gesture(canvas.pixel_to_position(end))
	var guard: int = 0
	while canvas.session != null and guard < 300:
		canvas._drain_segments(256)
		guard += 1
	check(canvas.session == null, "gesture completes within bounded drain")


func trace_length() -> int:
	var file: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.READ)
	return file.get_length() if file != null else -1


func records() -> Array:
	if not FileAccess.file_exists(TRACE_PATH):
		return []
	var lines: PackedStringArray = FileAccess.get_file_as_string(TRACE_PATH).split("\n", false)
	var result: Array = []
	for line: String in lines:
		var parsed: Variant = JSON.parse_string(line)
		result.append(parsed)
	return result


func run() -> void:
	var original_env: String = OS.get_environment(ENV)
	OS.set_environment(ENV, "")
	if FileAccess.file_exists(TRACE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_PATH))
	var doc := DrawingDocument.new("private-document-name", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
		"private-layer-name", "root").value)
	var canvas: Control = canvas_instance()
	canvas.document = doc
	canvas.layer_id = layer
	canvas.zoom = 7.86
	canvas.brush_width = 60.0
	canvas.color_rgba = INK
	root.add_child(canvas)
	await process_frame
	stroke(canvas, Vector2(-12.5, -12.5), Vector2(7.5, 7.5))
	check(not FileAccess.file_exists(TRACE_PATH),
		"default stroke does not write any diagnostic file")
	var first_bytes: PackedByteArray = source_bytes(doc)
	OS.set_environment(ENV, TRACE_PATH)
	stroke(canvas, Vector2(12.5, -10.5), Vector2(24.5, 15.5))
	stroke(canvas, Vector2(-25.5, 16.5), Vector2(-11.5, 23.5))
	var rows: Array = records()
	check(rows.size() == 2, "opt-in trace appends exactly one record per completed gesture")
	if rows.size() == 2 and rows[0] is Dictionary and rows[1] is Dictionary:
		var first: Dictionary = rows[0] as Dictionary
		var second: Dictionary = rows[1] as Dictionary
		check(int(first.get("schema", 0)) == 1 and
			String(first.get("capture_kind", "")) == "engine_timing_only",
			"versioned schema distinguishes CPU/callback timing from device latency")
		check(int(first.get("brush_width_px", 0)) == 60 and
			is_equal_approx(float(first.get("zoom", 0)), 7.86),
			"reproduction includes Brush width and actual zoom")
		check(first.get("frame_phases_us", null) is Array and
			first.get("sample_to_stage_us", null) is Array and
			first.get("stage_batches_us", null) is Array,
			"diagnostic retains bounded frame, receipt and stage histories")
		check(int(first.get("samples_received", 0)) > 0 and
			int(second.get("commit_us", 0)) >= int(second.get("down_us", 0)),
			"records retain input count and monotonic timing")
		var content: String = FileAccess.get_file_as_string(TRACE_PATH)
		check(not content.contains("private-document-name") and
			not content.contains("private-layer-name") and
			not content.contains("9b44b7dd") and
			not content.contains("source_position") and
			not content.contains("tile_key"),
			"trace does not expose document identity, pixel contents or coordinates")
	check(doc.undo().ok and doc.redo().ok and source_bytes(doc) != first_bytes,
		"trace preserves one-step document Undo/Redo and resulting Brush pixels")
	var before_cancel: String = FileAccess.get_file_as_string(TRACE_PATH)
	var revision_before_cancel: int = doc.revision
	canvas.start_gesture(canvas.pixel_to_position(Vector2(1.5, -30.5)))
	canvas.cancel_gesture()
	check(FileAccess.get_file_as_string(TRACE_PATH) == before_cancel and
		doc.revision == revision_before_cancel,
		"cancelled gesture never records a completed trace or publishes pixels")
	OS.set_environment(ENV, "user://../t095-owner-trace-regression.jsonl")
	stroke(canvas, Vector2(-5.5, -5.5), Vector2(-3.5, -3.5))
	check(FileAccess.get_file_as_string(TRACE_PATH) == before_cancel,
		"traversal-style path is not an authorized trace destination")
	OS.set_environment(ENV, TRACE_PATH)

	# A refusal to append must not change any committed document or overwrite
	# the existing valid lines. A bounded file cannot grow without limit.
	var before: String = FileAccess.get_file_as_string(TRACE_PATH)
	var filler: FileAccess = FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if filler != null:
		filler.seek_end()
		filler.store_string("x".repeat(int(canvas.MAX_T095_TRACE_BYTES)))
		filler.close()
	var full_size: int = trace_length()
	stroke(canvas, Vector2(-20.5, -23.5), Vector2(-15.5, -18.5))
	check(trace_length() == full_size,
		"full trace refuses append without unbounded growth")
	check(FileAccess.get_file_as_string(TRACE_PATH).begins_with(before),
		"trace size cap preserves existing records")
	OS.set_environment(ENV, original_env)
	canvas.queue_free()
	await process_frame
	if FileAccess.file_exists(TRACE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_PATH))
	print("T095_OWNER_TRACE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_OWNER_TRACE_PASSED %d/%d" % [checks, checks])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
