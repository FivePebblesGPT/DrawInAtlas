extends SceneTree
## T-068 diagnostic: repeated exact four-connected fills; no GPU/input timings.

const TRIALS: int = 5
const SIZES: Array[int] = [32, 64, 96]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output: Array[Dictionary] = []
	for size: int in SIZES:
		var samples: Array[float] = []
		var pixels: PackedByteArray = PackedByteArray()
		pixels.resize(size * size * 4)
		for index: int in range(size * size):
			pixels[index * 4] = 10
			pixels[index * 4 + 1] = 30
			pixels[index * 4 + 2] = 50
			pixels[index * 4 + 3] = 255
		for trial: int in range(TRIALS):
			var document: DrawingDocument = DrawingDocument.new("fill-timing", 128)
			var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
			var seed: DrawingEditSession = document.begin_edit(layer, document.revision).value
			var seeded: DrawingResult = seed.apply_region(Rect2i(-4, -5, size, size), pixels)
			if not seeded.ok or not seed.commit().ok:
				push_error("T068_FILL_BENCH_FAILED: seed")
				quit(1)
				return
			var fill: DrawingEditSession = document.begin_edit(layer, document.revision).value
			var start: int = Time.get_ticks_usec()
			var staged: DrawingResult = fill.flood_fill(Vector2i(-4, -5), 0xff614020, null, size * size * 6)
			var result: DrawingResult = fill.commit() if staged.ok else staged
			samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
			if not result.ok or result.delta == null or result.delta.after.size() != size * size:
				push_error("T068_FILL_BENCH_FAILED: fill coverage")
				quit(1)
				return
		samples.sort()
		output.append({"size": size, "pixels": size * size,
			"median_ms": snappedf(samples[TRIALS / 2], 0.001),
			"samples_ms": samples})
	print("T068_FILL_BENCH_PASSED " + JSON.stringify(output))
	quit(0)
