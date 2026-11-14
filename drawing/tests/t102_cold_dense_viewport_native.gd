extends SceneTree
## T-102: real X11 cold dense first-population and revision-safe settling witness.
## Software frame_post_draw is not physical scan-out or input-to-photon time.

var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T102_NATIVE_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func frames(count: int = 1) -> void:
	for i: int in range(count):
		await process_frame


func paint(doc: DrawingDocument, layer: String, area: Rect2i, rgba: int) -> bool:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(area.size.x * area.size.y * 4)
	for i: int in range(area.size.x * area.size.y):
		bytes.encode_u32(i * 4, rgba)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return false
	var edit: DrawingEditSession = started.value as DrawingEditSession
	return edit.apply_region(area, bytes).ok and edit.commit().ok


func memory_kib(name: String) -> int:
	var stream: FileAccess = FileAccess.open("/proc/%d/status" % OS.get_process_id(), FileAccess.READ)
	if stream == null:
		return -1
	while not stream.eof_reached():
		var line: String = stream.get_line()
		if line.begins_with(name + ":"):
			return int(line.substr(name.length() + 1).strip_edges().split(" ", false)[0])
	return -1


func source_sha(doc: DrawingDocument, area: Rect2i) -> String:
	var rendered: DrawingResult = DrawingRenderer.render(doc, area)
	if not rendered.ok:
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update((rendered.value as Image).get_data())
	return context.finish().hex_encode()


func sample(canvas: Control, source: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var where: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(source))
	if image == null or image.is_empty() or where.x < 0 or where.y < 0 \
			or where.x >= image.get_width() or where.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(where)


func percentile(values: Array[float], fraction: float) -> float:
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(float(ordered.size()) * fraction) - 1, 0, ordered.size() - 1)]


func cold_settle(canvas: Control, at_zoom: float) -> Dictionary:
	canvas.zoom = at_zoom
	canvas._display_tiles.clear()
	canvas.queue_redraw()
	var durations: Array[float] = []
	var first_us: int = Time.get_ticks_usec()
	var first_frame_us: int = 0
	var first_deferred: int = -1
	var frames_used: int = 0
	var compositions: int = 0
	var bytes_uploaded: int = 0
	var total_texture_us: int = 0
	var max_frame_cpu_us: int = 0
	for i: int in range(40):
		await RenderingServer.frame_post_draw
		var row: Dictionary = canvas.last_frame_metrics.duplicate()
		var cpu: int = int(row.get("draw_cpu_us", 0))
		if cpu <= 0:
			continue
		frames_used += 1
		if first_frame_us == 0:
			first_frame_us = Time.get_ticks_usec() - first_us
			first_deferred = int(row.get("cold_tiles_deferred", 0))
		compositions += int(row.get("tiles_composited", 0))
		bytes_uploaded += int(row.get("bytes_uploaded", 0))
		total_texture_us += int(row.get("texture_cpu_us", 0))
		max_frame_cpu_us = maxi(cpu, max_frame_cpu_us)
		durations.append(float(cpu) / 1000.0)
		if int(row.get("cold_tiles_deferred", 0)) == 0:
			break
	var last: Dictionary = canvas.last_frame_metrics
	return {"zoom": at_zoom, "first_ms": float(first_frame_us) / 1000.0,
		"settled_ms": float(Time.get_ticks_usec() - first_us) / 1000.0,
		"frames": frames_used, "first_deferred": first_deferred,
		"last_deferred": int(last.get("cold_tiles_deferred", -1)),
		"compositions": compositions, "bytes_uploaded": bytes_uploaded,
		"texture_cpu_ms": float(total_texture_us) / 1000.0,
		"frame_cpu_p50_ms": percentile(durations, 0.5),
		"frame_cpu_p95_ms": percentile(durations, 0.95),
		"frame_cpu_max_ms": float(max_frame_cpu_us) / 1000.0,
		"cache_tiles": canvas._display_tiles.size(),
		"hwm_kib": memory_kib("VmHWM")}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("T102_NATIVE_FAILED: X11 framebuffer required")
		quit(1)
		return
	root.size = Vector2i(1024, 800)
	root.content_scale_size = root.size
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(80, 50)
	canvas.size = Vector2(800, 680)
	canvas.tool = "Pan"
	canvas.show_pixel_grid = false
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t102-dense-signed", 256)
	var low: String = String(doc.create_layer(DrawingLayerNode.RASTER, "bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "top").value)
	var area: Rect2i = Rect2i(-256, -256, 512, 512)
	check(paint(doc, low, area, 0xff1c38e0), "seed 512x512 signed opaque bottom")
	check(paint(doc, top, area, 0x8035ce24), "seed 512x512 signed alpha top")
	check(paint(doc, top, Rect2i(-128, -128, 32, 32), 0x00bb77dd),
		"seed hidden RGB under transparent top alpha")
	canvas.document = doc
	canvas.layer_id = low
	await frames(3)
	var canonical: String = source_sha(doc, area)
	check(not canonical.is_empty(), "canonical complete 512x512 source hash")
	var report: Array[Dictionary] = []
	for z: float in [0.25, 0.5, 1.0]:
		var cold_trials: Array[Dictionary] = []
		var warm_cpu: Array[float] = []
		for trial: int in range(3):
			var row: Dictionary = await cold_settle(canvas, z)
			cold_trials.append(row)
			check(int(row["first_deferred"]) > 0 and int(row["frames"]) > 1,
				"cold viewport uses separate draw frames at %s #%s: %s" % [z, trial, row])
			check(int(row["last_deferred"]) == 0 and int(row["cache_tiles"]) >= 16,
				"all signed display tiles settle at %s #%s: %s" % [z, trial, row])
			for point: Vector2 in [Vector2(-192.5, -192.5), Vector2(-0.5, -0.5),
					Vector2(0.5, 0.5), Vector2(192.5, 192.5)]:
				var color: Color = sample(canvas, point)
				check(color.r > 0.15 and color.b > 0.1 and color.g > 0.1,
					"signed framebuffer filled at %s %s: %s" % [z, point, color])
			var hidden: Color = sample(canvas, Vector2(-115.5, -115.5))
			check(hidden.r > 0.75 and hidden.b < 0.2,
				"hidden RGB with zero alpha does not leak at %s: %s" % [z, hidden])
			for warm_trial: int in range(3):
				canvas.queue_redraw()
				await RenderingServer.frame_post_draw
				var warm: Dictionary = canvas.last_frame_metrics
				warm_cpu.append(float(warm.get("draw_cpu_us", 0)) / 1000.0)
				check(int(warm.get("tiles_composited", 0)) == 0 \
					and int(warm.get("textures_created", 0)) == 0,
					"warm viewport reuses complete textures at %s #%s" % [z, warm_trial])
		var first_ms: Array[float] = []
		var settle_ms: Array[float] = []
		var max_cpu_ms: Array[float] = []
		for trial: Dictionary in cold_trials:
			first_ms.append(float(trial["first_ms"]))
			settle_ms.append(float(trial["settled_ms"]))
			max_cpu_ms.append(float(trial["frame_cpu_max_ms"]))
		report.append({"zoom": z, "cold": cold_trials,
			"first_p50_ms": percentile(first_ms, 0.5),
			"first_p95_ms": percentile(first_ms, 0.95),
			"settle_p50_ms": percentile(settle_ms, 0.5),
			"settle_p95_ms": percentile(settle_ms, 0.95),
			"max_frame_cpu_p50_ms": percentile(max_cpu_ms, 0.5),
			"max_frame_cpu_p95_ms": percentile(max_cpu_ms, 0.95),
			"warm_p50_ms": percentile(warm_cpu, 0.5),
			"warm_p95_ms": percentile(warm_cpu, 0.95)})
	canvas.camera = Vector2(28, -12)
	canvas.queue_redraw()
	await frames(5)
	check(sample(canvas, Vector2(0.5, 0.5)).b > 0.1, "pan preserves visible signed content")
	check(doc.set_visibility(top, false).ok, "hide top")
	canvas.queue_redraw()
	await frames(25)
	check(sample(canvas, Vector2(0.5, 0.5)).r > 0.6, "visibility invalidates cold tiles")
	check(doc.set_visibility(top, true).ok, "show top")
	canvas.queue_redraw()
	await frames(25)
	check(sample(canvas, Vector2(0.5, 0.5)).b > 0.1, "show restores composed pixels")
	var rev: int = doc.revision
	check(paint(doc, low, Rect2i(-1, -1, 2, 2), 0xff00ee00), "edit across signed zero seam")
	check(doc.revision == rev + 1, "edit publishes one atomic revision")
	var modified: String = source_sha(doc, area)
	check(modified != canonical and not modified.is_empty(), "source changes after edit")
	canvas.queue_redraw()
	await frames(25)
	check(doc.undo().ok, "undo atomic edit")
	check(source_sha(doc, area) == canonical, "Undo restores byte-exact full source")
	canvas.queue_redraw()
	await frames(25)
	check(doc.redo().ok, "redo atomic edit")
	check(source_sha(doc, area) == modified, "Redo restores exact changed source")
	canvas.queue_redraw()
	await frames(25)
	check(canvas._display_tiles.size() <= canvas.MAX_DISPLAY_TILES,
		"retained texture count remains within budget")
	# An over-cap dense viewport cannot be incrementally presented using
	# transient-only tiles; preserve the original full-frame conservative path.
	var synthetic: Dictionary[String, bool] = canvas._occupied_display_tiles.duplicate()
	var previous_cache: Dictionary[String, Dictionary] = canvas._display_tiles.duplicate()
	canvas._occupied_display_tiles.clear()
	for y: int in range(13):
		for x: int in range(12):
			canvas._occupied_display_tiles["%d,%d" % [x, y]] = true
	check(canvas.has_method("_cold_population_targets") and \
		canvas._cold_population_targets(Rect2i(0, 0, 12, 13), Vector2(6, 6)).is_empty(),
		"156-tile over-budget viewport keeps the complete transient path")
	canvas._occupied_display_tiles = synthetic
	canvas._display_tiles = previous_cache
	var started: DrawingResult = doc.begin_edit(low, doc.revision)
	check(started.ok, "begin detached preview")
	if started.ok:
		canvas._move_preview = started.value as DrawingEditSession
		check(canvas.has_method("_cold_population_targets") and \
			canvas._cold_population_targets(Rect2i(-2, -2, 4, 4), Vector2.ZERO).is_empty(),
			"detached preview bypasses cold throttling")
		canvas._move_preview.cancel()
		canvas._move_preview = null
	print("T102_NATIVE_JSON " + JSON.stringify({"engine": Engine.get_version_info().get("string"),
		"display": DisplayServer.get_name(), "results": report,
		"peak_kib": memory_kib("VmHWM"), "source_sha256": canonical,
		"edited_sha256": modified}))
	print("T102_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T102_NATIVE_PASSED" if failures == 0 else "T102_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
