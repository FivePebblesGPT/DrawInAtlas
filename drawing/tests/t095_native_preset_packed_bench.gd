extends SceneTree
## Opt-in T-095 native-call CPU witness; not an input-to-photon benchmark.
## Recreate the native stroke each trial; time preset_segments only, excluding
## configure_preset and source creation. Compare old/new binaries on one host.

const PRESETS: Dictionary = {
    "hard": "hard_round", "soft": "soft", "ink": "ink", "airbrush": "airbrush"
}
const TRIALS: int = 8

func percentile(sorted: Array[int], ratio: float) -> float:
    return float(sorted[clampi(ceili(ratio * sorted.size()) - 1, 0, sorted.size() - 1)]) / 1000.0

func run() -> void:
    if not ClassDB.class_exists("DrawingNativeBrush"):
        printerr("T095_NATIVE_PRESET_PACKED_BENCH_FAILED: native extension not registered")
        quit(1)
        return
    var paths: Array[PackedVector2Array] = []
    for batch: int in range(12):
        var path: PackedVector2Array = PackedVector2Array()
        for sample: int in range(8):
            var t: float = float(batch * 8 + sample) / 95.0
            path.append(Vector2(-70.5 + 141.0 * t,
                -38.5 + 33.0 * sin(t * TAU * 4.0)))
        paths.append(path)
    for name: String in ["hard", "soft", "ink", "airbrush"]:
        var settings: String = FileAccess.get_file_as_string(
            "res://addons/drawing/brushes/%s.myb" % PRESETS[name])
        var times: Array[int] = []
        var old_pixels: int = -1
        for trial: int in range(TRIALS):
            var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
            if not brush.call("configure_preset", settings, 60.0, 0xff53a071):
                printerr("T095_NATIVE_PRESET_PACKED_BENCH_FAILED: configure ", name)
                quit(1)
                return
            var elapsed: int = 0
            var pixels: int = 0
            for batch: int in range(paths.size()):
                var started: int = Time.get_ticks_usec()
                var result: PackedInt32Array = brush.call("preset_segments", paths[batch],
                    0.7 if batch % 3 == 0 else 1.0)
                elapsed += Time.get_ticks_usec() - started
                pixels += result.size() / 3
            if old_pixels != -1 and old_pixels != pixels:
                printerr("T095_NATIVE_PRESET_PACKED_BENCH_FAILED: inconsistent output")
                quit(1)
                return
            old_pixels = pixels
            times.append(elapsed)
        times.sort()
        print("T095_NATIVE_PRESET_PACKED_BENCH preset=%s pixels=%d median_ms=%.3f p95_ms=%.3f" % [
            name, old_pixels, (float(times[3]) + float(times[4])) / 2000.0,
            percentile(times, 0.95)])
    print("T095_NATIVE_PRESET_PACKED_BENCH_PASSED")
    quit(0)

func _initialize() -> void:
    call_deferred("run")
