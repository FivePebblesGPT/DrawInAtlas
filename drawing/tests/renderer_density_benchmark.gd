extends SceneTree
## T-086 on-demand CPU compositor comparison at the former sparse cutoff.
## Rendered image hashes are checked per case; this is not a GPU/frame benchmark.

const COUNTS: Array[int] = [8, 12, 13, 24, 48, 64, 96, 256]
const SAMPLES: int = 9


func _initialize() -> void:
	call_deferred("run")


func make_doc(count: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("density-%d" % count, 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return null
	var edit: DrawingEditSession = started.value as DrawingEditSession
	for i: int in range(count):
		var x: int = i % 128
		var y: int = (i * 11 + int(i / 128) * 37) % 128
		var a: int = 0 if i % 11 == 0 else (127 if i % 3 == 0 else 255)
		var rgba: PackedByteArray = PackedByteArray([i % 256, (i * 17) % 256, (i * 61) % 256, a])
		if not edit.apply_region(Rect2i(x, y, 1, 1), rgba).ok:
			return null
	if not edit.commit().ok:
		return null
	return doc


func run() -> void:
	for count: int in COUNTS:
		var doc: DrawingDocument = make_doc(count)
		if doc == null:
			printerr("T086_DENSITY_BENCH_FAILED: seed")
			quit(1)
			return
		var timings: Array[int] = []
		var signature: String = ""
		for iteration: int in range(SAMPLES + 1):
			var plan: Dictionary = DrawingRenderer.prepare_visible_layers(doc)
			var start: int = Time.get_ticks_usec()
			var output: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 128, 128),
				0, 0, 1048576, null, plan)
			var elapsed: int = Time.get_ticks_usec() - start
			if not output.ok:
				printerr("T086_DENSITY_BENCH_FAILED: render")
				quit(1)
				return
			var hash_context: HashingContext = HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update((output.value as Image).get_data())
			var digest: String = hash_context.finish().hex_encode()
			if signature.is_empty():
				signature = digest
			elif signature != digest:
				printerr("T086_DENSITY_BENCH_FAILED: pixel mismatch")
				quit(1)
				return
			if iteration > 0:
				timings.append(elapsed)
		timings.sort()
		print("T086_DENSITY_BENCH_JSON " + JSON.stringify({
			"count": count, "median_us": timings[4], "p95_us": timings[8],
			"sha256": signature, "samples": SAMPLES}))
	print("T086_DENSITY_BENCH_PASSED")
	quit(0)
