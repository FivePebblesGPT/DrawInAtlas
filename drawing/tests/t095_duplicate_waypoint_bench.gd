extends SceneTree
## Optional CPU witness only. Measures a real 60px Legacy paint_path batch
## of repeated stationary waypoints; never substitutes a rectangle fill.

const POINTS: int = 360
const REPEATS: int = 7

func run() -> void:
	var timings: Array[int] = []
	for repeat: int in range(REPEATS):
		var doc: DrawingDocument = DrawingDocument.new("duplicate-cpu-%d" % repeat, 64)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
		var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
		var path: PackedVector2Array = PackedVector2Array()
		for index: int in range(POINTS):
			path.append(Vector2(0.5, 0.5))
		var started: int = Time.get_ticks_usec()
		var result: DrawingResult = edit.paint_path(path, 0x9c3e76af, 60.0)
		var elapsed: int = Time.get_ticks_usec() - started
		if not result.ok or edit.change_count() == 0:
			printerr("T095_DUPLICATE_BENCH_FAILED run=%d" % repeat)
			quit(1)
			return
		timings.append(elapsed)
		edit.cancel()
	var sorted: Array[int] = timings.duplicate()
	sorted.sort()
	print("T095_DUPLICATE_BENCH_TIMING waypoints=%d repeats=%d median_us=%d raw_us=%s" % [
		POINTS, REPEATS, sorted[REPEATS / 2], str(timings)])
	print("T095_DUPLICATE_BENCH_PASSED")
	quit(0)

func _initialize() -> void:
	call_deferred("run")
