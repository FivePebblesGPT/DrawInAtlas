extends SceneTree
## T-153: one MyPaint rasterizer, signed RGBA deltas, revision binding and rollback.

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

func begin(brush: Object, width: float = 14.0) -> Dictionary:
	return brush.call("begin_stroke", "ink", FileAccess.get_file_as_string(PRESET),
		width, INK, 7, CLIP)

func batch(brush: Object, handle: int, coords: PackedFloat32Array) -> Dictionary:
	var accepted: Dictionary = brush.call("append_samples", handle, 7, coords)
	if not accepted.get("ok", false):
		return accepted
	return brush.call("preview_changes", handle, 7)

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "required native extension registered")
	if failures:
		quit(1)
		return
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(int(brush.call("stroke_abi_version")) == 1, "ABI v1 is available")
	var invalid: Dictionary = brush.call("begin_stroke", "ink", "not a preset",
		10.0, INK, 7, CLIP)
	check(not invalid.get("ok", true), "invalid preset fails closed")
	var started: Dictionary = begin(brush)
	var handle: int = int(started.get("handle", 0))
	check(started.get("ok", false) and handle > 0, "bundled hard round opens a stroke")
	check(not begin(brush).get("ok", true), "one live stroke per instance")
	var samples: PackedFloat32Array = PackedFloat32Array([
		-8.5, -9.5, 0.5, 0.01, 7.5, 5.5, 1.0, 0.01])
	var first: Dictionary = batch(brush, handle, samples)
	var changes: PackedInt32Array = first.get("changes", PackedInt32Array())
	check(first.get("ok", false) and first.get("format", "") == "xy_rgba"
		and changes.size() >= 3 and changes.size() % 3 == 0,
		"Hokusai emits signed coordinate/RGBA triples")
	var signed: bool = false
	var alpha: bool = false
	for index: int in range(0, changes.size(), 3):
		signed = signed or changes[index] < 0 or changes[index + 1] < 0
		alpha = alpha or ((changes[index + 2] >> 24) & 255) > 0
	check(signed and alpha, "negative coordinates and nonzero alpha represented")
	check(not brush.call("append_samples", handle, 8, samples).get("ok", true),
		"stale revision rejected")
	check(not brush.call("commit_stroke", handle, 7), "commit blocked with pending batch")
	check(not brush.call("acknowledge_batch", handle + 1, 7, true),
		"wrong handle cannot acknowledge")
	check(brush.call("acknowledge_batch", handle, 7, false), "reject restores batch")
	var retry: Dictionary = batch(brush, handle, samples)
	check(retry.get("changes", PackedInt32Array()) == changes,
		"rejected Hokusai sample batch replays bit-exact")
	check(brush.call("acknowledge_batch", handle, 7, true), "accept successful")
	var bad: Dictionary = batch(brush, handle, PackedFloat32Array([
		-2.5, 2.5, 0.6, 0.01, NAN, 2.5, 1.0, 0.01]))
	check(not bad.get("ok", true), "invalid position rejects entire batch")
	check(not batch(brush, handle, PackedFloat32Array([1, 2, 1.1, 0.01])).get("ok", true),
		"out-of-range pressure rejected")
	var stats: Dictionary = brush.call("stroke_stats", handle, 7)
	check(stats.get("ok", false) and stats.get("format", "") == "xy_rgba"
		and int(stats.get("batches", 0)) == 1,
		"one accepted pigment batch counted")
	check(brush.call("commit_stroke", handle, 7), "stroke commits")
	check(not brush.call("abort_stroke", handle), "committed handle cannot abort")
	var restarted: Dictionary = begin(brush, 7.0)
	check(restarted.get("ok", false) and int(restarted.get("handle", 0)) != handle,
		"new transaction has a distinct handle")
	check(brush.call("abort_stroke", int(restarted.get("handle", 0))),
		"whole-stroke cancellation succeeds")
	print("T147_NATIVE_CONTRACT_PASSED checks=%d errors=%d ints=%s" % [
		checks, failures, stats.get("exported_ints", 0)])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
