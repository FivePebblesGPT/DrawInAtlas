extends SceneTree
## T-095: NativeHard must validate the complete batch before changing its
## once-per-stroke coverage/cursor. A failed late sample must be retryable.

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_NATIVE_HARD_ATOMIC_FAILED: " + label)

func brush() -> Object:
	var instance: Object = ClassDB.instantiate("DrawingNativeBrush")
	instance.call("reset_hard")
	return instance

func output(instance: Object, points: PackedVector2Array,
		width: float = 12.0, clip: Rect2i = Rect2i()) -> Dictionary:
	return instance.call("hard_segments", points, width, clip)

func same_points(a: Dictionary, b: Dictionary) -> bool:
	return bool(a.get("ok", false)) and bool(b.get("ok", false)) and \
		(a.get("points", PackedInt32Array()) as PackedInt32Array) == \
		(b.get("points", PackedInt32Array()) as PackedInt32Array)

func test_rejected_late_point(label: String, bad: Vector2, width: float = 12.0) -> void:
	var reference: Object = brush()
	var candidate: Object = brush()
	var seed := PackedVector2Array([Vector2(-7.5, 2.5)])
	var after := PackedVector2Array([Vector2(-3.5, 2.5), Vector2(9.5, 4.5)])
	var baseline: Dictionary = output(reference, seed)
	check(same_points(baseline, output(candidate, seed)), label + " common seed")
	var failed: Dictionary = output(candidate,
		PackedVector2Array([Vector2(-4.5, 2.5), bad]), width)
	check(not bool(failed.get("ok", true)), label + " is rejected")
	check((failed.get("points", PackedInt32Array()) as PackedInt32Array).is_empty(),
		label + " publishes no partial delta")
	check(same_points(output(candidate, after), output(reference, after)),
		label + " leaves cursor and coverage unchanged")

func test_reset_and_clip() -> void:
	var reference: Object = brush()
	var candidate: Object = brush()
	var stroke := PackedVector2Array([Vector2(-10.5, -5.5), Vector2(13.5, 8.5)])
	var first: Dictionary = output(reference, stroke)
	check(bool(first.get("ok", false)) and
		(first.get("points", PackedInt32Array()) as PackedInt32Array).size() > 0,
		"ordinary signed hard round brush produces pixels")
	var clipped: Dictionary = output(candidate, stroke, 12.0,
		Rect2i(-2, -2, 4, 4))
	check(bool(clipped.get("ok", false)) and
		(clipped.get("points", PackedInt32Array()) as PackedInt32Array).size() > 0,
		"small clipping window still paints")
	candidate.call("reset_hard")
	check(same_points(first, output(candidate, stroke)),
		"reset restores complete hard coverage")
	var duplicate: Dictionary = output(reference, stroke)
	check(bool(duplicate.get("ok", false)) and
		(duplicate.get("points", PackedInt32Array()) as PackedInt32Array).is_empty(),
		"repeated path produces no duplicate pixels")

func test_total_candidate_budget() -> void:
	var reference: Object = brush()
	var candidate: Object = brush()
	var initial := PackedVector2Array([Vector2(-2.5, -3.5)])
	check(same_points(output(reference, initial), output(candidate, initial)),
		"cumulative candidate test starts identical")
	var many := PackedVector2Array()
	for i: int in range(96):
		many.push_back(Vector2(900.5 if i % 2 else -900.5, float(i % 3)))
	var failed: Dictionary = output(candidate, many, 12.0)
	check(not bool(failed.get("ok", true)), "cumulative candidate budget rejected")
	var final_stroke := PackedVector2Array([Vector2(4.5, 1.5)])
	check(same_points(output(reference, final_stroke), output(candidate, final_stroke)),
		"candidate budget rejection retains prior state")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "native class is registered")
	if not ClassDB.class_exists("DrawingNativeBrush"):
		quit(1)
		return
	test_rejected_late_point("NaN late sample", Vector2(NAN, 3.5))
	test_rejected_late_point("Infinity late sample", Vector2(INF, 3.5))
	test_rejected_late_point("out-of-range late sample", Vector2(1000000000.0, 3.5))
	test_rejected_late_point("oversized late sweep", Vector2(1000000.0, 3.5))
	test_rejected_late_point("oversized radius", Vector2(0.5, 3.5), 1000000000.0)
	test_total_candidate_budget()
	test_reset_and_clip()
	print("T095_NATIVE_HARD_ATOMIC_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_NATIVE_HARD_ATOMIC_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
