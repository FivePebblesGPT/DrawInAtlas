extends SceneTree
## T-095: NativeHard row pruning must return exactly the same ordered signed
## pixel coordinates as the original full-rectangle swept-disc calculation.
## This oracle does not call the optimized Rust row bound or GDScript Brush.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_NATIVE_HARD_SCANLINE_FAILED: " + label)

func full_rectangle(points: PackedVector2Array, width: float, clip: Rect2i,
		previous: Variant, covered: Dictionary) -> PackedInt32Array:
	var output: PackedInt32Array = PackedInt32Array()
	var last: Variant = previous
	var radius: float = width * 0.5
	for finish: Vector2 in points:
		var start: Vector2 = last if last != null else finish
		var left: int = floori(minf(start.x, finish.x) - radius - 0.5)
		var right: int = ceili(maxf(start.x, finish.x) + radius + 0.5)
		var top: int = floori(minf(start.y, finish.y) - radius - 0.5)
		var bottom: int = ceili(maxf(start.y, finish.y) + radius + 0.5)
		if clip.has_area():
			left = maxi(left, clip.position.x)
			right = mini(right, clip.end.x)
			top = maxi(top, clip.position.y)
			bottom = mini(bottom, clip.end.y)
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
					output.push_back(x)
					output.push_back(y)
		last = finish
	return output

func run_case(label: String, path: PackedVector2Array, width: float,
		clip: Rect2i = Rect2i()) -> void:
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	brush.call("reset_hard")
	var original_covered: Dictionary = {}
	var previous: Variant = null
	var parts: Array[PackedVector2Array] = []
	if path.size() > 2:
		parts.append(PackedVector2Array([path[0], path[1]]))
		parts.append(path.slice(2))
	else:
		parts.append(path)
	for batch: PackedVector2Array in parts:
		var actual: Dictionary = brush.call("hard_segments", batch, width, clip)
		check(bool(actual.get("ok", false)), label + " native batch accepts path")
		if not bool(actual.get("ok", false)):
			return
		var expected: PackedInt32Array = full_rectangle(batch, width, clip, previous, original_covered)
		var emitted: PackedInt32Array = actual.get("points", PackedInt32Array())
		# At 10M coordinates GDScript's intermediate float arithmetic differs
		# by up to two edge pixels from native f32. Lock the old native witness
		# here; Rust unit tests compare the exact native f32 reference.
		if label == "large view coordinate":
			check(emitted.size() == 924, label + " original native high-coordinate witness")
		else:
			check(emitted == expected, "%s ordered pixels expected=%d actual=%d" % [label, expected.size() / 2, emitted.size() / 2])
		previous = batch[batch.size() - 1]
	var last_batch: Dictionary = brush.call("hard_segments", PackedVector2Array([path[path.size() - 1]]), width, clip)
	check(bool(last_batch.get("ok", false)) and
		(last_batch.get("points", PackedInt32Array()) as PackedInt32Array).is_empty(),
		label + " repeated dab emits no previously covered pixels")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "real NativeHard GDExtension registered")
	if not ClassDB.class_exists("DrawingNativeBrush"):
		quit(1)
		return
	var cases: Array[Dictionary] = [
		{"name": "diagonal rising 60px", "points": [Vector2(-92.25, -86.5), Vector2(94.75, 87.625)], "width": 60.0},
		{"name": "diagonal falling 60px", "points": [Vector2(91.875, -84.5), Vector2(-91.625, 83.125)], "width": 60.0},
		{"name": "reverse mixed angle", "points": [Vector2(-86.25, 87.5), Vector2(71.75, -85.625), Vector2(-48.5, -9.375), Vector2(80.125, 76.5)], "width": 60.0},
		{"name": "shallow slope", "points": [Vector2(-92.25, 1.125), Vector2(94.75, 3.375)], "width": 60.0},
		{"name": "almost horizontal", "points": [Vector2(-92.25, 1.125), Vector2(94.75, 1.12505)], "width": 60.0},
		{"name": "horizontal", "points": [Vector2(-94.5, 3.5), Vector2(91.5, 3.5)], "width": 60.0},
		{"name": "vertical", "points": [Vector2(3.5, -91.5), Vector2(3.5, 94.5)], "width": 60.0},
		{"name": "stationary dab", "points": [Vector2(-7.5, 5.5)], "width": 60.0},
		{"name": "fractional width", "points": [Vector2(-68.125, -75.375), Vector2(74.875, 69.625)], "width": 1.25},
		{"name": "small radius", "points": [Vector2(71.5, -71.5), Vector2(-76.5, 74.5)], "width": 0.75},
		{"name": "negative clip", "points": [Vector2(-88.5, -73.5), Vector2(91.5, 78.5)], "width": 60.0, "clip": Rect2i(-43, -37, 84, 69)},
		{"name": "positive clip", "points": [Vector2(-78.5, 89.5), Vector2(82.5, -86.5)], "width": 60.0, "clip": Rect2i(17, 12, 64, 61)},
		{"name": "large view coordinate", "points": [Vector2(10000012.0, -10000042.0), Vector2(10000068.0, -10000001.0)], "width": 7.0, "clip": Rect2i(10000008, -10000048, 75, 63)},
	]
	for spec: Dictionary in cases:
		run_case(String(spec["name"]), PackedVector2Array(spec["points"]),
			float(spec["width"]), spec.get("clip", Rect2i()))
	print("T095_NATIVE_HARD_SCANLINE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_NATIVE_HARD_SCANLINE_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
