extends SceneTree
## T-086 optional software-only benchmark. The *same* workload can run on a
## pre-T-086 canvas with test-only timing probes or the new cached canvas.
## Frame-post-draw measures Godot submission, never physical input-to-photon.

const SAMPLES: int = 12
var results: Dictionary[String, Variant] = {}


func _initialize() -> void:
	call_deferred("run")


func frames(n: int = 3) -> void:
	for i: int in range(n):
		await process_frame


func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return -1.0
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]


func summary(rows: Array[Dictionary]) -> Dictionary:
	var fields: Array[String] = ["frame_ms", "compose_cpu_us", "texture_cpu_us",
		"draw_cpu_us", "tiles_composited", "textures_created", "textures_updated",
		"source_pixels_rendered", "bytes_uploaded", "cache_bytes_estimate"]
	var aggregated: Dictionary = {}
	for field: String in fields:
		var values: Array[float] = []
		for row: Dictionary in rows:
			var scalar: float = float(row.get(field, 0))
			values.append(scalar / 1000.0 if field.ends_with("_us") else scalar)
		aggregated[field] = {"median": percentile(values, 0.5), "p95": percentile(values, 0.95)}
	return aggregated


func memory_kib(name: String) -> int:
	var path: String = "/proc/%d/status" % OS.get_process_id()
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return -1
	for i: int in range(1024):
		if stream.eof_reached():
			break
		var line: String = stream.get_line()
		if line.begins_with(name + ":"):
			var content: String = line.substr(name.length() + 1).strip_edges()
			return int(content.split(" ", false)[0])
	return -1


func render_sample(canvas: Control) -> Dictionary:
	var start_us: int = Time.get_ticks_usec()
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var row: Dictionary = canvas.get("last_frame_metrics").duplicate()
	row["frame_ms"] = float(Time.get_ticks_usec() - start_us) / 1000.0
	return row


func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("T086_BENCH needs a real X11 framebuffer")
		quit(1)
		return
	root.size = Vector2i(640, 460)
	root.content_scale_size = root.size
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(212, 164)
	canvas.tool = "Pan"
	root.add_child(canvas)
	var doc: DrawingDocument = DrawingDocument.new("t086-software-benchmark")
	var bottom: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	for layer: String in [bottom, top]:
		var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
		var area: Rect2i = Rect2i(-12, -12, 64, 64)
		var rgba: PackedByteArray = PackedByteArray()
		for i: int in range(area.size.x * area.size.y):
			rgba.append_array(PackedByteArray([40, 100, 230, 140 if layer == top else 255]))
		if not edit.apply_region(area, rgba).ok or not edit.commit().ok:
			printerr("T086_BENCH seed failed")
			quit(1)
			return
	canvas.document = doc
	canvas.layer_id = bottom
	await frames(6)
	var zooms: Array[float] = [1.0, 0.5, 0.25]
	for zoom_value: float in zooms:
		canvas.zoom = zoom_value
		var cold: Dictionary = await render_sample(canvas)
		var idle: Array[Dictionary] = []
		var edits: Array[Dictionary] = []
		for i: int in range(SAMPLES):
			idle.append(await render_sample(canvas))
		for i: int in range(SAMPLES):
			var edit: DrawingEditSession = doc.begin_edit(bottom, doc.revision).value as DrawingEditSession
			var color: int = 0xff100000 | (i << 8) | (int(zoom_value * 100) << 16) | 0xff
			if not edit.paint_path(PackedVector2Array([Vector2(float(20 + i) + 0.5, 11.5)]), color, 1.0).ok \
					or not edit.commit().ok:
				printerr("T086_BENCH edit failed")
				quit(1)
				return
			edits.append(await render_sample(canvas))
		results[str(zoom_value)] = {"zoom_transition": cold, "idle": summary(idle), "edits": summary(edits)}
	results["environment"] = {"engine": Engine.get_version_info().get("string", "unknown"),
		"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_rendering_device() != null,
		"window": [root.size.x, root.size.y], "canvas": [canvas.size.x, canvas.size.y],
		"samples_per_zoom_and_phase": SAMPLES, "rss_kib": memory_kib("VmRSS"),
		"process_hwm_kib": memory_kib("VmHWM"),
		"godot_tracked_peak_kib": OS.get_static_memory_peak_usage() / 1024}
	print("T086_BENCH_JSON " + JSON.stringify(results))
	print("T086_BENCH_PASSED")
	quit(0)
