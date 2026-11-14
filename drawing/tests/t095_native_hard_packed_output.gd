extends SceneTree
## Real-extension oracle for the packed NativeHard output transfer. Compare the
## whole ordered buffer against a separate full-rectangle f32 capsule raster,
## not against the native scanline bounds or another native brush instance.

const CLIP = Rect2i(-192, -192, 384, 384)
const WIDTH: float = 60.0
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_NATIVE_HARD_PACKED_OUTPUT_FAILED: " + label)


func reference(batch: PackedVector2Array, previous: Variant,
		covered: Dictionary) -> PackedInt32Array:
	var emitted: PackedInt32Array = PackedInt32Array()
	var last: Variant = previous
	for finish: Vector2 in batch:
		var start: Vector2 = last if last != null else finish
		var radius: float = WIDTH * 0.5
		var left: int = maxi(CLIP.position.x, floori(minf(start.x, finish.x) - radius - 0.5))
		var right: int = mini(CLIP.end.x, ceili(maxf(start.x, finish.x) + radius + 0.5))
		var top: int = maxi(CLIP.position.y, floori(minf(start.y, finish.y) - radius - 0.5))
		var bottom: int = mini(CLIP.end.y, ceili(maxf(start.y, finish.y) + radius + 0.5))
		var delta: Vector2 = finish - start
		var squared: float = delta.length_squared()
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				var key: Vector2i = Vector2i(x, y)
				if covered.has(key):
					continue
				var center: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
				var fraction: float = clampf((center - start).dot(delta) / squared, 0.0, 1.0) if squared > 0.0 else 0.0
				var distance: Vector2 = center - (start + delta * fraction)
				if distance.length_squared() <= radius * radius:
					covered[key] = true
					emitted.push_back(x)
					emitted.push_back(y)
		last = finish
	return emitted


func output(brush: Object, batch: PackedVector2Array, label: String) -> PackedInt32Array:
	var received: Dictionary = brush.call("hard_segments", batch, WIDTH, CLIP)
	check(bool(received.get("ok", false)), label + " accepted")
	var result: PackedInt32Array = received.get("points", PackedInt32Array())
	check(result.size() % 2 == 0, label + " complete coordinate pairs")
	return result


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "native extension required")
	if not ClassDB.class_exists("DrawingNativeBrush"):
		quit(1)
		return
	var first: PackedVector2Array = PackedVector2Array([Vector2(-164.25, -146.5), Vector2(166.75, 145.625)])
	var second: PackedVector2Array = PackedVector2Array([Vector2(-160.25, 142.125), Vector2(158.375, -144.5)])
	var first_covered: Dictionary = {}
	var expected_first: PackedInt32Array = reference(first, null, first_covered)
	check(expected_first.size() > 50000, "stress oracle contains tens of thousands of ordered pixels")
	var expected_second: PackedInt32Array = reference(second, first[1], first_covered)

	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	brush.call("reset_hard")
	check(bool(brush.call("begin_hard_batch")), "start first transaction")
	var got_first: PackedInt32Array = output(brush, first, "initial 60px sweep")
	check(got_first == expected_first, "initial ordered full-rectangle parity")
	brush.call("rollback_hard_batch")
	check(bool(brush.call("begin_hard_batch")), "restart after rollback")
	check(output(brush, first, "retry 60px sweep") == expected_first,
		"rollback restores full output, cursor and once-only coverage")
	brush.call("commit_hard_batch")
	check(bool(brush.call("begin_hard_batch")), "start overlapping transaction")
	check(output(brush, second, "crossing 60px sweep") == expected_second,
		"crossing path emits only new coordinates in y/x order")
	brush.call("commit_hard_batch")
	check(output(brush, PackedVector2Array([second[1]]), "repeat final dab").is_empty(),
		"identical final dab produces empty packed array")
	var return_batch: PackedVector2Array = PackedVector2Array([first[0]])
	var expected_return: PackedInt32Array = reference(return_batch, second[1], first_covered)
	check(output(brush, return_batch, "return sweep") == expected_return,
		"return sweep preserves ordered once-only coverage across batches")

	print("T095_NATIVE_HARD_PACKED_OUTPUT_RESULT checks=%d failures=%d first_pixels=%d crossing_pixels=%d" % [
		checks, failures, got_first.size() / 2, expected_second.size() / 2])
	if failures == 0:
		print("T095_NATIVE_HARD_PACKED_OUTPUT_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
