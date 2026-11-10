extends SceneTree
## T-086 optional cold sparse-source CPU benchmark (not a framebuffer or GPU test).

const SAMPLES: int = 9


func _initialize() -> void:
	call_deferred("run")


func seed_source(doc: DrawingDocument, layer: String, position: Vector2i, rgba: PackedByteArray) -> bool:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return false
	var edit: DrawingEditSession = started.value as DrawingEditSession
	return edit.apply_region(Rect2i(position, Vector2i.ONE), rgba).ok and edit.commit().ok


func sha256(bytes: PackedByteArray) -> String:
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t086-sparse-pixel", 256)
	var bottom: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Bottom").value)
	var top: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	for point: Vector2i in [Vector2i(-101, -107), Vector2i(12, -21),
			Vector2i(-4, 11), Vector2i(97, 85)]:
		if not seed_source(doc, bottom, point, PackedByteArray([31, 111, 204, 255])):
			printerr("T086_SPARSE_PIXEL_BENCH_FAILED: seed bottom")
			quit(1)
			return
		if not seed_source(doc, top, point + Vector2i(1, 0), PackedByteArray([210, 47, 5, 117])):
			printerr("T086_SPARSE_PIXEL_BENCH_FAILED: seed top")
			quit(1)
			return
	var view: Rect2i = Rect2i(-128, -128, 256, 256)
	var times: Array[float] = []
	var expected_hash: String = ""
	for i: int in range(SAMPLES + 1):
		var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
		var start: int = Time.get_ticks_usec()
		var rendered: DrawingResult = DrawingRenderer.render(doc, view, 0, 0, 1048576, null, plan)
		var ms: float = (Time.get_ticks_usec() - start) / 1000.0
		if not rendered.ok:
			printerr("T086_SPARSE_PIXEL_BENCH_FAILED: render")
			quit(1)
			return
		var digest: String = sha256((rendered.value as Image).get_data())
		if expected_hash.is_empty():
			expected_hash = digest
		elif digest != expected_hash:
			printerr("T086_SPARSE_PIXEL_BENCH_FAILED: byte mismatch")
			quit(1)
			return
		if i != 0:
			times.append(ms)
	times.sort()
	print("T086_SPARSE_PIXEL_BENCH_JSON " + JSON.stringify({
		"engine": Engine.get_version_info().get("string", "unknown"),
		"view": [256, 256], "stride": 256, "layers": 2,
		"source_pixels": 8, "samples": SAMPLES,
		"median_ms": times[4], "p95_ms": times[8], "sha256": expected_hash}))
	print("T086_SPARSE_PIXEL_BENCH_PASSED")
	quit(0)
