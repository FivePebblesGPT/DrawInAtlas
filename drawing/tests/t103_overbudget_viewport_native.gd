extends SceneTree
## T-103 software/X11 pressure witness. Pointer events, not hardware latency.
## Repeated 25/50/100% views cross the 144-tile retention boundary.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T103_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]

func memory_kib(name: String) -> int:
	var f: FileAccess = FileAccess.open("/proc/%d/status" % OS.get_process_id(), FileAccess.READ)
	if f == null:
		return -1
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.begins_with(name + ":"):
			return int(line.substr(name.length() + 1).strip_edges().split(" ", false)[0])
	return -1

func frame(canvas: Control) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var row: Dictionary = canvas.last_frame_metrics.duplicate()
	row["frame_delay_ms"] = float(Time.get_ticks_usec() - start) / 1000.0
	row["memory_rss_kib"] = memory_kib("VmRSS")
	row["memory_hwm_kib"] = memory_kib("VmHWM")
	return row

func mouse(canvas: Control, point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = canvas.global_position + point
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func pan(canvas: Control, from: Vector2, offset: Vector2) -> void:
	mouse(canvas, from, MOUSE_BUTTON_MIDDLE, true)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = canvas.global_position + from + offset
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(event, true)
	mouse(canvas, from + offset, MOUSE_BUTTON_MIDDLE, false)

func source_hash(doc: DrawingDocument, area: Rect2i) -> String:
	var pixels: DrawingResult = DrawingRenderer.render(doc, area)
	if not pixels.ok:
		return ""
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((pixels.value as Image).get_data())
	return ctx.finish().hex_encode()

func framebuffer_pixel(canvas: Control, point: Vector2) -> Color:
	var pixels: Image = root.get_texture().get_image()
	var screen: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(point))
	if pixels == null or pixels.is_empty() or screen.x < 0 or screen.y < 0 \
			or screen.x >= pixels.get_width() or screen.y >= pixels.get_height():
		return Color(-1, -1, -1)
	return pixels.get_pixelv(screen)

func fill_chunk(color: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(128 * 128 * 4)
	for index: int in range(128 * 128):
		data.encode_u32(index * 4, color)
	return data

func seed_lazy_layer(doc: DrawingDocument, layer: String, data: PackedByteArray,
		bounds: Rect2i) -> void:
	var digest: String = DrawingRasterTile.digest_rgba8(data, 128)
	var loader: Callable = func(_ref: String) -> PackedByteArray: return data
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var result: DrawingResult = doc.register_lazy_chunk(layer, x, y,
				"test-%d-%d" % [x, y], digest, loader)
			if not result.ok:
				check(false, "register authentic lazy chunk %d,%d: %s" % [x, y, result.code])
	check(doc.tile_keys(layer).size() == bounds.get_area(), "full lazy layer occupancy registered")

func edit_dot(doc: DrawingDocument, layer: String) -> bool:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return false
	var edit: DrawingEditSession = started.value as DrawingEditSession
	var bytes: PackedByteArray = PackedByteArray([33, 220, 12, 255])
	if not edit.apply_region(Rect2i(-1, -1, 1, 1), bytes).ok:
		edit.cancel()
		return false
	return edit.commit().ok

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("T103_NATIVE_FAILED: requires X11 framebuffer")
		quit(1)
		return
	root.size = Vector2i(1230, 920)
	root.content_scale_size = root.size
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(42, 40)
	canvas.size = Vector2(1080, 800)
	canvas.zoom = 0.5
	canvas.tool = "Pan"
	canvas.show_pixel_grid = false
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t103-pressure", 128)
	var base: String = String(doc.create_layer(DrawingLayerNode.RASTER, "base").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "overlay").value)
	seed_lazy_layer(doc, base, fill_chunk(0xffb04c31), Rect2i(-8, -6, 16, 12))
	seed_lazy_layer(doc, top, fill_chunk(0x80aa9b21), Rect2i(-4, -3, 8, 6))
	canvas.document = doc
	canvas.layer_id = base
	var initial_cold: Dictionary = await frame(canvas)
	check(int(initial_cold.get("tiles_composited", 0)) > 0,
		"initial dense committed frame composites visible pixels")
	mouse(canvas, canvas.size * 0.5, MOUSE_BUTTON_WHEEL_UP, true)
	check(is_equal_approx(canvas.zoom, 0.625), "actual pointer wheel zooms toward cursor")
	mouse(canvas, canvas.size * 0.5, MOUSE_BUTTON_WHEEL_DOWN, true)
	check(is_equal_approx(canvas.zoom, 0.5), "inverse wheel restores original zoom")
	var canonical: String = source_hash(doc, Rect2i(-128, -128, 256, 256))
	check(not canonical.is_empty(), "signed layered reference SHA")
	var metrics: Array[Dictionary] = []
	var frame_delays: Array[float] = []
	var frame_cpu: Array[float] = []
	var total_transient: int = 0
	var total_upload_bytes: int = 0
	var planned: int = 0
	var focal_evictions: int = 0
	var evicted_hits: int = 0
	var total_cache_hits: int = 0
	var max_frame_refs: int = 0
	for z: float in [0.25, 0.5, 1.0, 0.5, 0.25, 0.5]:
		canvas.zoom = z
		for step: int in range(3):
			if step == 1 or step == 2:
				var before_camera: Vector2 = canvas.camera
				pan(canvas, canvas.size * 0.5,
					Vector2(18, -12) if step == 1 else Vector2(-18, 12))
				check(canvas.camera.distance_to(before_camera) > 1.0,
					"actual middle-button pan changes source camera at %s #%s" % [z, step])
			var row: Dictionary = await frame(canvas)
			metrics.append({"zoom": z, "step": step, "row": row})
			frame_delays.append(float(row["frame_delay_ms"]))
			frame_cpu.append(float(row.get("draw_cpu_us", 0)) / 1000.0)
			total_transient += int(row.get("textures_transient", 0))
			total_upload_bytes += int(row.get("bytes_uploaded", 0))
			planned += 1 if int(row.get("focal_plan_tiles", 0)) == canvas.MAX_DISPLAY_TILES else 0
			focal_evictions += int(row.get("focal_evictions", 0))
			evicted_hits += int(row.get("focal_reused_evicted", 0))
			total_cache_hits += int(row.get("cache_hits", 0))
			max_frame_refs = maxi(max_frame_refs, int(row.get("frame_reference_bytes_upper_bound", 0)))
			check(int(row.get("cache_tiles", 0)) <= canvas.MAX_DISPLAY_TILES,
				"retained tile bound at %s step %s" % [z, step])
			check(int(row.get("cache_bytes_estimate", 0)) <= int(row.get("cache_limit_bytes", -1)),
				"texture byte bound at %s step %s" % [z, step])
			check(int(row.get("frame_reference_bytes_upper_bound", 0)) <= 500 * 128 * 128 * 4,
				"frame-local references bounded under pressure")
			check(int(row.get("tiles_visible", 0)) > 0 and int(row.get("textures_transient", 0)) >= 0,
				"viewport drew at %s step %s" % [z, step])
			if z == 0.25 or z == 0.5:
				check(int(row.get("cold_tiles_deferred", 0)) == 0,
					"overbudget draws complete without missing transient tiles")
			var pixel: Color = framebuffer_pixel(canvas, Vector2(0.5, 0.5))
			check(pixel.r > 0.15 and pixel.g > 0.15 and pixel.b > 0.1,
				"exact signed center remains filled: %s at %s" % [pixel, z])
	check(source_hash(doc, Rect2i(-128, -128, 256, 256)) == canonical,
		"zoom and pan do not change canonical content")
	check(total_transient > 0, "overbudget cold/warm frames really create transient textures")
	check(planned >= 6, "multiple overbudget frames use focal preselection")
	check(edit_dot(doc, base), "publish signed edit under overbudget canvas")
	var edited: String = source_hash(doc, Rect2i(-128, -128, 256, 256))
	check(edited != canonical and not edited.is_empty(), "signed edit changes source SHA")
	await frame(canvas)
	check(doc.undo().ok, "undo atomic source edit")
	check(source_hash(doc, Rect2i(-128, -128, 256, 256)) == canonical,
		"undo restores source exactly")
	await frame(canvas)
	check(doc.redo().ok and source_hash(doc, Rect2i(-128, -128, 256, 256)) == edited,
		"redo restores edited source exactly")
	await frame(canvas)
	check(doc.set_visibility(top, false).ok, "hide dense translucent overlay")
	await frame(canvas)
	check(doc.set_visibility(top, true).ok, "restore translucent overlay")
	await frame(canvas)
	check(source_hash(doc, Rect2i(-128, -128, 256, 256)) == edited,
		"visibility does not mutate source")
	# A mask must be honored without invalidating unrelated densely cached pixels.
	var outside_before: int = int(doc.read_pixel(base, 1, 1).value)
	var inside_before: int = int(doc.read_pixel(base, -2, -2).value)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-2, -2, 1, 1), true)
	var mask_begin: DrawingResult = doc.begin_edit(base, doc.revision)
	check(mask_begin.ok, "begin masked signed edit")
	if mask_begin.ok:
		var masked: DrawingEditSession = mask_begin.value as DrawingEditSession
		var path_points: PackedVector2Array = PackedVector2Array([
			Vector2(-1.5, -1.5), Vector2(1.5, 1.5)])
		check(masked.paint_path(path_points, 0xff13de30, 1.0, false, mask).ok
			and masked.commit().ok, "publish one masked Brush history step")
	check(int(doc.read_pixel(base, -2, -2).value) != inside_before,
		"mask allows signed target pixel")
	check(int(doc.read_pixel(base, 1, 1).value) == outside_before,
		"mask denies outside pixel")
	var masked_hash: String = source_hash(doc, Rect2i(-128, -128, 256, 256))
	check(masked_hash != edited, "masked edit updates canonical source")
	await frame(canvas)
	check(doc.undo().ok and source_hash(doc, Rect2i(-128, -128, 256, 256)) == edited,
		"masked Undo preserves preceding edit")
	await frame(canvas)
	check(doc.redo().ok and source_hash(doc, Rect2i(-128, -128, 256, 256)) == masked_hash,
		"masked Redo restores byte-exact history")
	# Straight-alpha storage must preserve hidden RGB without painting it.
	var hidden_start: DrawingResult = doc.begin_edit(top, doc.revision)
	check(hidden_start.ok, "begin hidden-RGB transparency edit")
	if hidden_start.ok:
		var hidden_edit: DrawingEditSession = hidden_start.value as DrawingEditSession
		check(hidden_edit.apply_region(Rect2i(-3, -3, 1, 1),
			PackedByteArray([0xee, 0x01, 0x5a, 0x00])).ok
			and hidden_edit.commit().ok, "commit transparent nonzero-RGB source")
	check(int(doc.read_pixel(top, -3, -3).value) == 0x005a01ee,
		"hidden RGB survives as canonical source bytes")
	await frame(canvas)
	var hidden_color: Color = framebuffer_pixel(canvas, Vector2(-2.5, -2.5))
	check(hidden_color.r > 0.12 and hidden_color.b > 0.55,
		"transparent top pixel does not blacken framebuffer")
	var final_hash: String = source_hash(doc, Rect2i(-128, -128, 256, 256))
	var path: String = ProjectSettings.globalize_path("user://t103-pressure.drawing")
	check(DrawingFileIO.save(doc, path).ok, "save all dense RGBA8 chunks to standalone file")
	check(FileAccess.file_exists(path), "standalone save is materialized")
	var exported: DrawingResult = DrawingFileIO.open(path)
	check(exported.ok, "saved dense document reopens")
	if exported.ok:
		check(source_hash(exported.value as DrawingDocument,
			Rect2i(-128, -128, 256, 256)) == final_hash, "saved pixels remain byte-exact")
		check(int((exported.value as DrawingDocument).read_pixel(top, -3, -3).value) == 0x005a01ee,
			"standalone save preserves hidden RGB bytes")
	DirAccess.remove_absolute(path)
	var report: Dictionary = {"engine": Engine.get_version_info().get("string", ""),
		"display": DisplayServer.get_name(), "samples": metrics.size(),
		"initial_cold_frame_delay_ms": initial_cold.get("frame_delay_ms", -1),
		"initial_cold_draw_cpu_ms": float(initial_cold.get("draw_cpu_us", 0)) / 1000.0,
		"initial_cold_upload_bytes": int(initial_cold.get("bytes_uploaded", 0)),
		"frame_delay_p50_ms": percentile(frame_delays, 0.5),
		"frame_delay_p95_ms": percentile(frame_delays, 0.95),
		"frame_delay_max_ms": frame_delays.max(),
		"draw_cpu_p50_ms": percentile(frame_cpu, 0.5),
		"draw_cpu_p95_ms": percentile(frame_cpu, 0.95),
		"draw_cpu_max_ms": frame_cpu.max(),
		"retained_tiles": canvas._display_tiles.size(),
		"retained_limit_tiles": canvas.MAX_DISPLAY_TILES,
		"texture_bytes_uploaded": total_upload_bytes,
		"transient_textures": total_transient, "planned_frames": planned,
		"focal_evictions": focal_evictions, "reused_evicted_tiles": evicted_hits,
		"total_cache_hits": total_cache_hits, "max_frame_reference_bytes": max_frame_refs,
		"rss_kib": memory_kib("VmRSS"), "hwm_kib": memory_kib("VmHWM"),
		"original_sha256": canonical, "edited_sha256": edited}
	print("T103_NATIVE_JSON " + JSON.stringify(report))
	print("T103_NATIVE: %d checks; %d failed" % [checks, failures])
	print("T103_NATIVE_PASSED" if failures == 0 else "T103_NATIVE_FAILED")
	quit(0 if failures == 0 else 1)
