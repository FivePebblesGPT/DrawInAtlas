extends SceneTree
## Diagnostic only: synthetic isolated GDScript edit+commit cost, not input-to-visible latency.

const RUNS: int = 7
const CASES: Array[Dictionary] = [
	{"name": "horizontal", "start": Vector2(-100.25, 0.5), "finish": Vector2(100.25, 0.5)},
	{"name": "vertical", "start": Vector2(0.5, -100.25), "finish": Vector2(0.5, 100.25)},
	{"name": "diagonal_control", "start": Vector2(-70.25, -70.25), "finish": Vector2(70.25, 70.25)},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var outputs: Array[Dictionary] = []
	for test_case: Dictionary in CASES:
		var measurements: Array[float] = []
		var first_coverage: int = -1
		for trial: int in range(RUNS):
			var doc: DrawingDocument = DrawingDocument.new("sweep-perf", 256)
			var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
			var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
			var before: int = Time.get_ticks_usec()
			var painted: DrawingResult = edit.paint_path(PackedVector2Array([
				test_case["start"], test_case["finish"]]), 0x80554433, 16.0)
			var result: DrawingResult = edit.commit() if painted.ok else painted
			measurements.append(float(Time.get_ticks_usec() - before) / 1000.0)
			if not result.ok or result.delta == null:
				push_error("T068_AXIS_BENCH_FAILED: " + String(test_case["name"]))
				quit(1)
				return
			if first_coverage < 0:
				first_coverage = result.delta.after.size()
			elif first_coverage != result.delta.after.size():
				push_error("T068_AXIS_BENCH_FAILED: nonrepeatable pixel coverage")
				quit(1)
				return
		measurements.sort()
		outputs.append({"name": test_case["name"], "coverage": first_coverage,
			"median_ms": snappedf(measurements[RUNS / 2], 0.001),
			"p95_ms": snappedf(measurements[ceili(RUNS * 0.95) - 1], 0.001),
			"samples_ms": measurements})
	print("T068_AXIS_BENCH_PASSED " + JSON.stringify(outputs))
	quit(0)
