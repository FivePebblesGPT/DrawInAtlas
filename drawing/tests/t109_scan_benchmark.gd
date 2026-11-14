extends SceneTree
## T-109 optional paired baseline/candidate benchmark over the *same* 512 files.
## T109_SCAN_ROOT must be an existing absolute portable Objects directory.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")


func _initialize() -> void:
	call_deferred("run")


func percentile(numbers: Array[int], fraction: float) -> int:
	var sorted: Array[int] = numbers.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func run() -> void:
	var path: String = OS.get_environment("T109_SCAN_ROOT")
	if path.is_empty() or not path.is_absolute_path() or not DirAccess.dir_exists_absolute(path):
		printerr("T109_SCAN_BENCH_FAILED: Set T109_SCAN_ROOT to a real Objects/ directory")
		quit(1)
		return
	var index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	var durations: Array[int] = []
	var memory: Array[int] = []
	for trial: int in range(9):
		var start: int = Time.get_ticks_usec()
		var result: DrawingResult = index.scan(path)
		durations.append(Time.get_ticks_usec() - start)
		memory.append(OS.get_static_memory_usage())
		if not result.ok or index.entries.size() != 512 or not index.warnings.is_empty() or \
				index.filtered("asset-0500").size() != 1:
			printerr("T109_SCAN_BENCH_FAILED: Missing, duplicate or rejected source in trial " + str(trial))
			quit(1)
			return
	print("T109_SCAN_PROFILE: ", JSON.stringify({
		"scan_us": durations, "scan_p50_us": percentile(durations, 0.5),
		"scan_p95_us": percentile(durations, 0.95),
		"memory_bytes": memory, "memory_p50_bytes": percentile(memory, 0.5),
		"memory_p95_bytes": percentile(memory, 0.95),
		"memory_kind": "engine-tracked allocations, not RSS or GPU VRAM",
		"count": 512, "trials": durations.size()}))
	print("T109_SCAN_BENCH_PASSED")
	quit(0)
