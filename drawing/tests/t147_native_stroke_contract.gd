extends SceneTree
## Direct real-GDExtension v1 contract tests: handles, signed samples, pressure,
## bounded batches, deterministic rollback and finite packed FFI volume.

const INK: int = 0xff2938a7
const CLIP: Rect2i = Rect2i(-30, -30, 60, 60)
const PRESET: String = "res://addons/drawing/brushes/hard_round.myb"
var checks: int = 0
var failures: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T147_NATIVE_CONTRACT_FAILED: " + message)


func create_brush(mode: String, width: float = 14.0, clip: Rect2i = CLIP) -> Dictionary:
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string(PRESET) if mode == "Hokusai" else ""
	var started: Dictionary = brush.call("begin_stroke", "ink", mode,
		preset, width, INK, 7, clip)
	check(bool(started.get("ok", false)) and int(started.get("handle", 0)) > 0,
		mode + " creates a source-revision-bound stroke")
	return {"native": brush, "handle": int(started.get("handle", 0)), "mode": mode}


func batch(source: Dictionary, coords: PackedFloat32Array) -> Dictionary:
	var native: Object = source["native"]
	var handle: int = source["handle"]
	var accepted: Dictionary = native.call("append_samples", handle, 7, coords)
	if not accepted.get("ok", false):
		return accepted
	return native.call("preview_changes", handle, 7)


func acknowledge(source: Dictionary, accepted: bool) -> bool:
	return bool((source["native"] as Object).call("acknowledge_batch",
		source["handle"], 7, accepted))


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "native extension exists")
	if failures > 0:
		quit(1)
		return
	var bogus: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(int(bogus.call("stroke_abi_version")) == 1, "ABI version is 1")
	var bad_begin: Dictionary = bogus.call("begin_stroke", "ink", "Hokusai",
		"not a preset", 10.0, INK, 7, CLIP)
	check(not bad_begin.get("ok", true), "invalid preset rejected before allocating handle")
	check(not (bogus.call("begin_stroke", "ink", "bad", "", 10.0, INK, 7, CLIP) as Dictionary).get("ok", true),
		"unknown native strategy rejected")
	var hard: Dictionary = create_brush("NativeHard")
	var preset: Dictionary = create_brush("Hokusai")
	check(hard["handle"] != preset["handle"], "handles never alias across instances")
	var repeated_begin: Dictionary = (hard["native"] as Object).call("begin_stroke", "ink", "NativeHard", "", 14.0, INK, 7, CLIP)
	check(not repeated_begin.get("ok", true), "one live stroke per native object")
	var sample_values: PackedFloat32Array = PackedFloat32Array([
		-8.5, -9.5, 0.5, 0.01, 7.5, 5.5, 1.0, 0.01])
	var hard_first: Dictionary = batch(hard, sample_values)
	check(bool(hard_first.get("ok", false)) and hard_first.get("format") == "xy",
		"hard strategy emits signed packed XY coverage")
	var hard_data: PackedInt32Array = hard_first.get("changes", PackedInt32Array())
	check(hard_data.size() >= 2 and hard_data.size() % 2 == 0,
		"hard paint emits paired coordinates")
	var invalid_handle: Dictionary = (hard["native"] as Object).call("preview_changes", preset["handle"], 7)
	check(not invalid_handle.get("ok", true), "foreign instance handle fails closed")
	var stale: Dictionary = (hard["native"] as Object).call("append_samples", hard["handle"], 8, sample_values)
	check(not stale.get("ok", true), "wrong revision fails without consuming current pending batch")
	check(not (hard["native"] as Object).call("commit_stroke", hard["handle"], 7),
		"pending batch prevents premature whole-stroke commit")
	check(not (hard["native"] as Object).call("acknowledge_batch", preset["handle"], 7, true),
		"wrong handle cannot accept batch")
	check(acknowledge(hard, false), "hard cancelled batch acknowledged")
	var hard_retry: Dictionary = batch(hard, sample_values)
	check(hard_retry.get("changes", PackedInt32Array()) == hard_data,
		"hard rollback and retry are bit-exact")
	check(acknowledge(hard, true), "hard batch committed")
	var hard_overlap: Dictionary = batch(hard, sample_values)
	check((hard_overlap.get("changes", PackedInt32Array()) as PackedInt32Array).is_empty(),
		"hard strategy has once-only coverage")
	check(acknowledge(hard, true), "overlap acknowledged without new pixels")
	var bad_points: Dictionary = batch(hard, PackedFloat32Array([
		-3.5, 0.5, 1.0, 0.01, NAN, 3.5, 1.0, 0.01]))
	check(not bad_points.get("ok", true), "late invalid float rejects whole batch")
	var bad_pressure: Dictionary = batch(hard, PackedFloat32Array([1, 2, 1.1, 0.01]))
	check(not bad_pressure.get("ok", true), "pressure out of range rejected")
	var hard_stats: Dictionary = (hard["native"] as Object).call("stroke_stats", hard["handle"], 7)
	check(hard_stats.get("ok", false) and int(hard_stats.get("batches", 0)) == 2,
		"counted accepted hard batches")
	check(int(hard_stats.get("input_floats", 0)) == 24 and
		int(hard_stats.get("exported_ints", 0)) == hard_data.size() * 2,
		"input and output volumes counted once per successful append")
	check(int(hard_stats.get("ffi_calls", 0)) < hard_data.size(),
		"hard native FFI calls stay below pixel count")
	check((hard["native"] as Object).call("commit_stroke", hard["handle"], 7),
		"hard whole-stroke commit succeeds")
	check(not (hard["native"] as Object).call("abort_stroke", hard["handle"]),
		"released handle cannot abort another transaction")
	var preset_first: Dictionary = batch(preset, sample_values)
	check(preset_first.get("ok", false) and preset_first.get("format", "") == "xy_rgba",
		"preset uses same sample ABI and returns signed RGBA8 triples")
	var pigment_data: PackedInt32Array = preset_first.get("changes", PackedInt32Array())
	check(pigment_data.size() > 0 and pigment_data.size() % 3 == 0,
		"preset native emits nonempty pigment changes")
	check(acknowledge(preset, false), "preset rollback acknowledges one batch")
	var preset_retry: Dictionary = batch(preset, sample_values)
	check(preset_retry.get("changes", PackedInt32Array()) == pigment_data,
		"preset rollback restores RNG/tile/published cache exactly")
	check(acknowledge(preset, true), "preset batch committed")
	var preset_stats: Dictionary = (preset["native"] as Object).call("stroke_stats", preset["handle"], 7)
	check(int(preset_stats.get("input_floats", 0)) == 16 and
		int(preset_stats.get("exported_ints", 0)) == pigment_data.size() * 2,
		"same input/output accounting for pigment")
	check((preset["native"] as Object).call("commit_stroke", preset["handle"], 7),
		"preset whole-stroke commit succeeds")
	# Cancel a whole stroke (not just its last batch), then restart on same object.
	var restarted: Dictionary = (preset["native"] as Object).call("begin_stroke",
		"ink", "NativeHard", "", 7.0, INK, 7, CLIP)
	check(restarted.get("ok", false) and restarted.get("handle", 0) != preset["handle"],
		"native instance can retry with a fresh handle")
	check((preset["native"] as Object).call("abort_stroke", restarted["handle"]),
		"new stroke whole-gesture cancellation succeeds")
	print("T147_NATIVE_CONTRACT_PASSED checks=%d errors=%d hard_ffi=%s hard_ints=%s preset_ffi=%s preset_ints=%s" % [
		checks, failures, hard_stats.get("ffi_calls", 0), hard_stats.get("exported_ints", 0),
		preset_stats.get("ffi_calls", 0), preset_stats.get("exported_ints", 0)])
	quit(0 if failures == 0 else 1)


func _initialize() -> void:
	call_deferred("run")
