extends SceneTree
## Optional, non-gating CPU witness: 60px stationary dabs delivered in
## separate paint_path calls. Run alternating fast and full-raster controls;
## the real held-pointer/GPU path must be profiled separately.

const BATCHES: int = 120
const RUNS: int = 6

func run_case(use_cache: bool, run_index: int) -> int:
	var doc := DrawingDocument.new("stationary-%s-%d" % [use_cache, run_index], 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var point := PackedVector2Array([Vector2(0.5, -0.5)])
	var start: int = Time.get_ticks_usec()
	for i: int in range(BATCHES):
		if not use_cache:
			edit._stationary_dab_valid = false
		if not edit.paint_path(point, 0x9c3e76af, 60.0).ok:
			printerr("T095_CROSS_BATCH_BENCH_FAILED: brush rejected")
			return -1
	var elapsed: int = Time.get_ticks_usec() - start
	if edit.change_count() == 0 or edit._cross_batch_dabs_skipped != (BATCHES - 1 if use_cache else 0):
		printerr("T095_CROSS_BATCH_BENCH_FAILED: unexpected coverage or skip count")
		return -1
	edit.cancel()
	return elapsed

func run() -> void:
	var control: Array[int] = []
	var optimized: Array[int] = []
	for i: int in range(RUNS):
		# Alternate execution order so cold-start and clock drift are visible.
		if i % 2 == 0:
			optimized.append(run_case(true, i))
			control.append(run_case(false, i))
		else:
			control.append(run_case(false, i))
			optimized.append(run_case(true, i))
	if optimized.min() < 0 or control.min() < 0:
		quit(1)
		return
	optimized.sort()
	control.sort()
	print("T095_CROSS_BATCH_BENCH_RESULT batches=%d trials=%d control_median_us=%d optimized_median_us=%d control_us=%s optimized_us=%s" % [
		BATCHES, RUNS, (control[2] + control[3]) / 2,
		(optimized[2] + optimized[3]) / 2, str(control), str(optimized)])
	print("T095_CROSS_BATCH_BENCH_PASSED")
	quit(0)

func _initialize() -> void:
	call_deferred("run")
