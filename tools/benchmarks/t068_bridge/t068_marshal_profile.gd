extends SceneTree

# Optional T-068 Godot↔C++ transfer screen. This is NOT a renderer benchmark:
# coverage points are precomputed, native output is detached, and no texture
# upload, document commit, pointer delivery or production integration is timed.
const SIDES: Array[int] = [32, 128, 256]
const DENSITIES: Array[String] = ["single", "sparse", "dense"]
const TRIALS: int = 19
const WARMUP: int = 3
const RGBA: int = 0x804488CC
var checks: int = 0
var failures: int = 0


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T068_MARSHAL_FAIL: ", label)


static func _source(side: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(side * side * 4)
	for index: int in range(side * side):
		# Deliberate transparent pixels with nonzero RGB, not just zeroed tiles.
		var alpha: int = 0 if index % 7 == 0 else (index * 97) & 255
		var rgb: int = ((index * 31 + 7) & 255) | \
			(((index * 67 + 9) & 255) << 8) | (((index * 13 + 23) & 255) << 16)
		data.encode_u32(index * 4, rgb | (alpha << 24))
	return data


static func _points(side: int, density: String) -> PackedInt32Array:
	var points: PackedInt32Array = PackedInt32Array()
	if density == "single":
		points.append_array(PackedInt32Array([side / 2 + 1, side / 2]))
		return points
	var count: int = 128 if density == "sparse" else side * side / 4
	for i: int in range(count):
		var index: int = (i * 151 + 29) % (side * side)
		points.append(index % side)
		points.append(index / side)
		if i % 7 == 0:
			points.append(index % side)
			points.append(index / side)
	return points


static func _mask(side: int) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(side * side)
	for i: int in range(mask.size()):
		mask[i] = 0 if i % 5 == 0 else 1
	return mask


static func _canonical(source: PackedByteArray, points: PackedInt32Array,
		mask: PackedByteArray, side: int) -> Dictionary:
	var expected: PackedByteArray = source.duplicate()
	var visited: Dictionary = {}
	var changes: int = 0
	for k: int in range(0, points.size(), 2):
		var index: int = points[k + 1] * side + points[k]
		if visited.has(index) or mask[index] == 0:
			continue
		visited[index] = true
		var before: int = expected.decode_u32(index * 4)
		var after: int = DrawingEditSession._blend(RGBA, before)
		if after != before:
			changes += 1
			expected.encode_u32(index * 4, after)
	return {"pixels": expected, "changes": changes}


# A separate wire decoder, rather than trusting the return count as proof.
# The oracle comparison below also detects omitted-but-valid-looking deltas.
static func _decode_sparse(source: PackedByteArray, payload: PackedByteArray) -> Dictionary:
	if payload.size() < 4:
		return {"ok": false}
	var count: int = payload.decode_u32(0)
	if count > source.size() / 4 or payload.size() != 4 + count * 12:
		return {"ok": false}
	var reconstructed: PackedByteArray = source.duplicate()
	var seen: Dictionary = {}
	for i: int in range(count):
		var offset: int = 4 + i * 12
		var index: int = payload.decode_u32(offset)
		if index >= source.size() / 4 or seen.has(index):
			return {"ok": false}
		seen[index] = true
		var before: int = payload.decode_u32(offset + 4)
		var after: int = payload.decode_u32(offset + 8)
		if before != source.decode_u32(index * 4) or before == after:
			return {"ok": false}
		reconstructed.encode_u32(index * 4, after)
	return {"ok": true, "pixels": reconstructed, "count": count}


static func _percentile(sorted_values: Array[int], fraction: float) -> int:
	return sorted_values[clampi(ceili(sorted_values.size() * fraction) - 1,
		0, sorted_values.size() - 1)]


func _measure(bridge: Object, source: PackedByteArray,
		points: PackedInt32Array, mask: PackedByteArray, side: int,
		mode: String) -> Dictionary:
	var samples: Array[int] = []
	var expected_size: int = source.size()
	for trial: int in range(TRIALS):
		var started: int = Time.get_ticks_usec()
		var output: PackedByteArray
		match mode:
			"copy":
				output = source.duplicate()
			"full_ptrcall":
				output = bridge.apply_checked(source, points, mask, side, side, RGBA, 0)
			"full_variant":
				output = Callable(bridge, "apply_checked").callv(
					[source, points, mask, side, side, RGBA, 0])
			"sparse_ptrcall":
				output = bridge.apply_sparse_checked(source, points, mask, side, side, RGBA, 0)
		var elapsed: int = Time.get_ticks_usec() - started
		_check(output.size() >= 4 if mode == "sparse_ptrcall" else
			output.size() == expected_size, "%s %d trial %d returns valid size" %
			[mode, side, trial])
		if trial >= WARMUP:
			samples.append(elapsed)
	samples.sort()
	return {"trials": samples.size(), "median_us": _percentile(samples, 0.5),
		"p95_us": _percentile(samples, 0.95), "min_us": samples[0],
		"max_us": samples[samples.size() - 1]}


func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit isolated extension loaded")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null, "checked GDExtension exists")
	if bridge == null:
		quit(1)
		return
	var cases: Array[Dictionary] = []
	for side: int in SIDES:
		for density: String in DENSITIES:
			var source: PackedByteArray = _source(side)
			var original: PackedByteArray = source.duplicate()
			var points: PackedInt32Array = _points(side, density)
			var mask: PackedByteArray = _mask(side)
			var canonical: Dictionary = _canonical(source, points, mask, side)
			var full: PackedByteArray = bridge.apply_checked(source, points,
				mask, side, side, RGBA, 0)
			var sparse: PackedByteArray = bridge.apply_sparse_checked(source,
				points, mask, side, side, RGBA, 0)
			var decoded: Dictionary = _decode_sparse(source, sparse)
			_check(full == canonical.pixels, "full exact pixel oracle %d/%s" % [side, density])
			_check(decoded.ok and decoded.pixels == canonical.pixels and
				decoded.count == canonical.changes,
				"sparse exact changed set %d/%s" % [side, density])
			_check(source == original and original.decode_u32(0) != 0,
				"source and hidden RGB untouched %d/%s" % [side, density])
			_check(sparse.size() == 4 + canonical.changes * 12,
				"wire byte count %d/%s" % [side, density])
			# One tampered record must never be accepted by the fixture decoder.
			if sparse.size() > 4:
				var tampered: PackedByteArray = sparse.duplicate()
				tampered.encode_u32(8, tampered.decode_u32(8) ^ 1)
				_check(not _decode_sparse(source, tampered).ok,
					"tampered before byte rejected %d/%s" % [side, density])
			var timings: Dictionary = {}
			for mode: String in ["copy", "full_ptrcall", "full_variant", "sparse_ptrcall"]:
				timings[mode] = _measure(bridge, source, points, mask, side, mode)
			cases.append({"side": side, "density": density,
				"requested_points": points.size() / 2,
				"unique_changed_pixels": canonical.changes,
				"input_rgba_bytes": source.size(), "input_mask_bytes": mask.size(),
				"input_points_bytes": points.size() * 4,
				"full_output_bytes": full.size(), "sparse_output_bytes": sparse.size(),
				"measurements_us": timings})
	bridge.free()
	print("T068_MARSHAL_TIMING: ", JSON.stringify(cases))
	print("T068_MARSHAL_PASSED: ", checks, " checks") if failures == 0 else \
		print("T068_MARSHAL_FAILED: ", failures, "/", checks)
	quit(0 if failures == 0 else 1)
