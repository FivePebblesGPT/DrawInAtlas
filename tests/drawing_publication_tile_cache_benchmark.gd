extends SceneTree
## Targeted T-068 publish-only microbenchmark. Not an event-to-visible test.
## Every run creates a new document, excludes fixture construction from timing.

const STRIDES: Array[int] = [512, 1024, 2048]
const WIDTHS: Array[int] = [64, 128]
const ROUNDS: int = 3
var measurements: Array[Dictionary] = []
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _median(samples: Array[float]) -> float:
	samples.sort()
	return snappedf(samples[samples.size() / 2], 0.001)


func _run() -> void:
	var output_path: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output_path = args[index + 1]
	for stride: int in STRIDES:
		for width: int in WIDTHS:
			var durations: Array[float] = []
			for trial: int in range(ROUNDS):
				var document: DrawingDocument = DrawingDocument.new("publish-benchmark", stride)
				var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
				var layer_id: String = String(created.value)
				var before: Dictionary[String, int] = {}
				var after: Dictionary[String, int] = {}
				for y: int in range(width):
					for x: int in range(width):
						var key: String = "%d,%d" % [x, y]
						before[key] = 0
						after[key] = 0x80554433
				var start_us: int = Time.get_ticks_usec()
				var committed: DrawingResult = document._publish_edit(
					layer_id, document.revision, before, after)
				durations.append(float(Time.get_ticks_usec() - start_us) / 1000.0)
				if not committed.ok or committed.delta.after.size() != width * width or \
					int(document.read_pixel(layer_id, width - 1, width - 1).value) != 0x80554433:
					failures += 1
			measurements.append({"stride": stride, "width": width,
				"changed_pixels": width * width, "median_ms": _median(durations),
				"samples_ms": durations})
	var response: Dictionary = {"engine": Engine.get_version_info().get("string", ""),
		"description": "Headless, new empty document per sample; per-commit CPU wall time, not input latency",
		"results": measurements, "failures": failures}
	if not output_path.is_empty():
		var handle: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if handle == null:
			failures += 1
		else:
			handle.store_string(JSON.stringify(response, "\t") + "\n")
			handle.close()
	print("T068_PUBLICATION_BENCH_%s cases=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", measurements.size(), failures])
	quit(0 if failures == 0 else 1)
