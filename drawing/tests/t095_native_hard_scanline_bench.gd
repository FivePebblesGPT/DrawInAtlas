extends SceneTree
## Opt-in T-095 native-only profiling witness. Time only the NativeHard
## candidate/coverage/delta call, not pixels staged, GPU frames, or input.

const CLIP := Rect2i(-192, -192, 384, 384)

func run() -> void:
	if not ClassDB.class_exists("DrawingNativeBrush"):
		printerr("T095_NATIVE_HARD_SCANLINE_BENCH_FAILED: extension absent")
		quit(1)
		return
	var path := PackedVector2Array([Vector2(-164.25, -146.5), Vector2(166.75, 145.625)])
	var timings: Array[float] = []
	var expected: int = -1
	for trial: int in range(11):
		var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
		brush.call("reset_hard")
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = brush.call("hard_segments", path, 60.0, CLIP)
		var duration: int = Time.get_ticks_usec() - started
		if not result.get("ok", false):
			printerr("T095_NATIVE_HARD_SCANLINE_BENCH_FAILED: rejected candidate window")
			quit(1)
			return
		var emitted: PackedInt32Array = result.get("points", PackedInt32Array())
		if expected == -1:
			expected = emitted.size()
		elif expected != emitted.size():
			printerr("T095_NATIVE_HARD_SCANLINE_BENCH_FAILED: inconsistent output")
			quit(1)
			return
		if trial > 0:
			timings.append(float(duration) / 1000.0)
	timings.sort()
	print("T095_NATIVE_HARD_SCANLINE_BENCH pixels=%d trials=%d median_ms=%.3f p95_ms=%.3f" % [
		expected / 2, timings.size(), timings[4] * 0.5 + timings[5] * 0.5, timings[9]])
	print("T095_NATIVE_HARD_SCANLINE_BENCH_PASSED")
	quit(0)

func _initialize() -> void:
	call_deferred("run")
