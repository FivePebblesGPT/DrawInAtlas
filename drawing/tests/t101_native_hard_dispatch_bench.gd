extends SceneTree
## Opt-in T-101 CPU-only microbenchmark: identical prebuilt NativeHard packed
## coordinates on a fresh 256px sparse tile per trial. Measures GDScript
## staging/transaction only; does not measure Rust rasterization, framebuffer,
## input-to-photon, or authorisation for a hardware performance claim.

const TRIALS: int = 7
const SIDE: int = 256
const INK: int = 0xff0000ff

class NativeStub:
	extends RefCounted
	var points: PackedInt32Array
	func begin_hard_batch() -> bool:
		return true
	func hard_segments(_path: PackedVector2Array, _width: float,
			_clip: Rect2i) -> Dictionary:
		return {"ok": true, "points": points}
	func commit_hard_batch() -> void:
		pass
	func rollback_hard_batch() -> void:
		pass

func percentile(sorted: Array[int], fraction: float) -> float:
	return float(sorted[clampi(ceili(sorted.size() * fraction) - 1,
		0, sorted.size() - 1)]) / 1000.0

func run() -> void:
	var samples: PackedInt32Array = PackedInt32Array()
	samples.resize(SIDE * SIDE * 2)
	var index: int = 0
	for y: int in range(SIDE):
		for x: int in range(SIDE):
			samples[index] = x
			samples[index + 1] = y
			index += 2
	var stub: NativeStub = NativeStub.new()
	stub.points = samples
	var elapsed_us: Array[int] = []
	for trial: int in range(TRIALS):
		var doc: DrawingDocument = DrawingDocument.new("t101-bench-%d" % trial)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER,
			"Paint", "root").value)
		var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, 0, 0).value
		var start_us: int = Time.get_ticks_usec()
		var result: DrawingResult = edit.paint_path_native_hard(
			PackedVector2Array([Vector2(64.5, 64.5)]), INK, 96.0, false,
			null, stub, Rect2i(0, 0, SIDE, SIDE))
		var duration: int = Time.get_ticks_usec() - start_us
		if not result.ok or edit.change_count() != SIDE * SIDE:
			printerr("T101_NATIVE_DISPATCH_BENCH_FAILED: incorrect staged RGBA8 count")
			quit(1)
			return
		elapsed_us.append(duration)
		edit.cancel()
	elapsed_us.sort()
	print("T101_NATIVE_DISPATCH_BENCH pixels=%d trials=%d p50_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [
		SIDE * SIDE, TRIALS, percentile(elapsed_us, 0.5),
		percentile(elapsed_us, 0.95), float(elapsed_us[-1]) / 1000.0])
	print("T101_NATIVE_DISPATCH_BENCH_PASSED")
	quit(0)

func _initialize() -> void:
	call_deferred("run")
