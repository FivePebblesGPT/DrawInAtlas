extends SceneTree

# Isolated T-068 GDExtension contract: no main application classes are loaded.
var checks: int = 0
var failed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("T068_BRIDGE_FAIL: ", label)

static func _pixel(data: PackedByteArray, index: int) -> int:
	var offset: int = index * 4
	return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)

static func _put(data: PackedByteArray, index: int, rgba: int) -> void:
	var offset: int = index * 4
	for channel: int in range(4):
		data[offset + channel] = (rgba >> (channel * 8)) & 255

static func _over(source: int, destination: int) -> int:
	var sa: float = float((source >> 24) & 255) / 255.0
	if sa <= 0.0:
		return destination
	var da: float = float((destination >> 24) & 255) / 255.0
	var alpha: float = sa + da * (1.0 - sa)
	var result: int = clampi(roundi(alpha * 255.0), 0, 255) << 24
	for channel: int in range(3):
		var shift: int = channel * 8
		var src: float = float((source >> shift) & 255)
		var dst: float = float((destination >> shift) & 255)
		var blended: int = clampi(roundi((src * sa + dst * da * (1.0 - sa)) / alpha), 0, 255)
		result |= blended << shift
	return result

static func _reference(source: PackedByteArray, points: PackedInt32Array,
		mask: PackedByteArray, width: int, rgba: int, operation: int) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	var seen: Dictionary = {}
	for i: int in range(0, points.size(), 2):
		var index: int = points[i + 1] * width + points[i]
		if seen.has(index) or (not mask.is_empty() and mask[index] == 0):
			continue
		seen[index] = true
		var before: int = _pixel(result, index)
		var after: int = (0 if operation == 1 else rgba if operation == 2 else _over(rgba, before))
		_put(result, index, after)
	return result

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in extension load")
	rng.seed = 68004802
	_check(ClassDB.class_exists("T068RasterBench"), "registered test-only GDExtension")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	if bridge == null:
		printerr("T068_BRIDGE_FAILED: failed to instantiate class")
		quit(1)
		return
	for iteration: int in range(160):
		var width: int = rng.randi_range(2, 16)
		var height: int = rng.randi_range(2, 16)
		var source: PackedByteArray = PackedByteArray()
		source.resize(width * height * 4)
		for byte: int in range(source.size()):
			source[byte] = rng.randi_range(0, 255)
		var original: PackedByteArray = source.duplicate()
		var points: PackedInt32Array = PackedInt32Array()
		for i: int in range(rng.randi_range(0, width * height * 2)):
			points.append(rng.randi_range(0, width - 1))
			points.append(rng.randi_range(0, height - 1))
		var mask: PackedByteArray = PackedByteArray()
		if iteration % 3 != 0:
			mask.resize(width * height)
			for i: int in range(mask.size()):
				mask[i] = 0 if i % 7 == 0 else 1
		var rgba: int = rng.randi() if iteration % 5 != 0 else (0x00996633 if iteration % 2 == 0 else 0xFF000000)
		var operation: int = iteration % 3
		var actual: PackedByteArray = bridge.apply_checked(source, points, mask, width, height, rgba, operation)
		var expected: PackedByteArray = _reference(source, points, mask, width, rgba, operation)
		_check(actual == expected, "RGBA8 parity case %d" % iteration)
		_check(source == original, "immutable source case %d" % iteration)
		if iteration % 16 == 0:
			# Callable uses Godot's generic Variant-call path rather than typed ptrcall.
			var generic: PackedByteArray = Callable(bridge, "apply_checked").callv(
				[source, points, mask, width, height, rgba, operation])
			_check(generic == expected, "generic Variant call %d" % iteration)
	var valid: PackedByteArray = PackedByteArray([1, 2, 3, 4] )
	var empty_mask: PackedByteArray = PackedByteArray()
	var empty_points: PackedInt32Array = PackedInt32Array()
	_check(bridge.apply_checked(valid, empty_points, empty_mask, 1, 1, 0, 1) == valid,
		"empty gesture retains pixels")
	_check(bridge.apply_checked(PackedByteArray([1, 2, 3]), empty_points, empty_mask, 1, 1, 0, 1).is_empty(),
		"short source refuses")
	_check(bridge.apply_checked(valid, PackedInt32Array([0]), empty_mask, 1, 1, 0, 1).is_empty(),
		"odd point array refuses")
	_check(bridge.apply_checked(valid, PackedInt32Array([1, 0]), empty_mask, 1, 1, 0, 1).is_empty(),
		"out-of-range point refuses")
	_check(bridge.apply_checked(valid, empty_points, PackedByteArray([1, 0]), 1, 1, 0, 1).is_empty(),
		"incorrect mask length refuses")
	_check(bridge.apply_checked(valid, empty_points, empty_mask, 1, 1, 0, 3).is_empty(),
		"invalid operation refuses")
	_check(bridge.apply_checked(valid, empty_points, empty_mask, 0, 1, 0, 1).is_empty(),
		"invalid shape refuses")
	_check(bridge.apply_checked(valid, empty_points, empty_mask, 1, 1, -1, 1).is_empty(),
		"negative color refuses")
	_check(bridge.apply_checked(valid, empty_points, empty_mask, 1, 1, 0x100000000, 1).is_empty(),
		"overflow color refuses")

	var latency: Dictionary = {}
	for side: int in [32, 64, 128]:
		var sample_source: PackedByteArray = PackedByteArray()
		sample_source.resize(side * side * 4)
		var sample_points: PackedInt32Array = PackedInt32Array()
		for i: int in range(2048):
			sample_points.append(i % side)
			sample_points.append((i / side) as int % side)
		var timings: Array[int] = []
		for trial: int in range(34):
			var started: int = Time.get_ticks_usec()
			var outcome: PackedByteArray = bridge.apply_checked(sample_source,
				sample_points, PackedByteArray(), side, side, 0x9F2367A5, 2)
			var elapsed: int = Time.get_ticks_usec() - started
			_check(outcome.size() == sample_source.size(),
				"bounded native output on %d-pixel region" % (side * side))
			if trial >= 3:
				timings.append(elapsed)
		timings.sort()
		latency[str(side)] = {"trials": timings.size(),
			"median_us": timings[timings.size() / 2],
			"p95_us": timings[ceili(float(timings.size()) * 0.95) - 1]}
	print("T068_BRIDGE_TIMING: ", JSON.stringify(latency))
	bridge.free()
	print("T068_BRIDGE_PASSED: ", checks, " checks") if failed == 0 else print("T068_BRIDGE_FAILED: ", failed, "/", checks)
	quit(0 if failed == 0 else 1)
