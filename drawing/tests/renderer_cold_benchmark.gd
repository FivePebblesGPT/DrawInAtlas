extends SceneTree
## T-086: source compositor only. No physical GPU, frame presentation, or
## input-to-photon timing is inferred from these CPU measurements.

const SAMPLES: int = 9
var records: Dictionary[String, Variant] = {}


func _initialize() -> void:
	call_deferred("run")


func put_pixels(doc: DrawingDocument, layer: String, alpha: int, seed: int) -> bool:
	var area: Rect2i = Rect2i(-64, -64, 128, 128)
	var rgba8: PackedByteArray = PackedByteArray()
	rgba8.resize(area.size.x * area.size.y * 4)
	for y: int in range(area.size.y):
		for x: int in range(area.size.x):
			var index: int = (y * area.size.x + x) * 4
			rgba8[index] = (x * 17 + seed) % 256
			rgba8[index + 1] = (y * 13 + seed) % 256
			rgba8[index + 2] = (x + y + seed) % 256
			rgba8[index + 3] = alpha
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return false
	var edit: DrawingEditSession = started.value as DrawingEditSession
	return edit.apply_region(area, rgba8).ok and edit.commit().ok


func digest(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func percent(values: Array[float], fraction: float) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]


func sample_case(label: String, bottom_alpha: int, top_alpha: int) -> bool:
	var doc: DrawingDocument = DrawingDocument.new("t086-cold-" + label, 128)
	var low: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var high: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	if not put_pixels(doc, low, bottom_alpha, 19) or not put_pixels(doc, high, top_alpha, 101):
		printerr("T086_COLD_BENCH_FAILED: seed " + label)
		return false
	var view: Rect2i = Rect2i(-128, -128, 256, 256)
	var duration: Array[float] = []
	var digest: String = ""
	for i: int in range(SAMPLES + 1):
		var start_us: int = Time.get_ticks_usec()
		var rendered: DrawingResult = DrawingRenderer.render(doc, view)
		var elapsed: float = float(Time.get_ticks_usec() - start_us) / 1000.0
		if not rendered.ok:
			printerr("T086_COLD_BENCH_FAILED: render " + label + " " + rendered.code)
			return false
		var hash_value: String = digest((rendered.value as Image).get_data())
		if digest.is_empty():
			digest = hash_value
		elif digest != hash_value:
			printerr("T086_COLD_BENCH_FAILED: output changed between identical renders " + label)
			return false
		if i > 0:
			duration.append(elapsed)
	records[label] = {"median_ms": percent(duration, 0.5),
		"p95_ms": percent(duration, 0.95), "sha256": digest}
	return true


func run() -> void:
	# The render bounding box corresponds to four 128px source display tiles,
	# an illustrative cold 50% region. The two layers overlap 128x128 pixels.
	if not sample_case("opaque", 255, 255) \
			or not sample_case("alpha", 255, 127) \
			or not sample_case("empty_alpha", 0, 0):
		quit(1)
		return
	var report: Dictionary = {"engine": Engine.get_version_info().get("string", "unknown"),
		"samples_per_case": SAMPLES, "viewport_source": [256, 256],
		"storage_stride": 128, "layer_count": 2, "cases": records}
	print("T086_COLD_BENCH_JSON " + JSON.stringify(report))
	print("T086_COLD_BENCH_PASSED")
	quit(0)
