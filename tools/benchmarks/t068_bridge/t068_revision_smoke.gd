extends SceneTree

# T-068 experimental bridge publication contract, independent of Atlas/Drawing runtime.
const ADAPTER = preload("res://adapter.gd")
var checks: int = 0
var failed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("T068_REVISION_FAIL: ", description)

static func _source(width: int, height: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(width * height * 4)
	for i: int in range(bytes.size()):
		bytes[i] = (i * 17 + 13) % 256
	return bytes

static func _put(bytes: PackedByteArray, index: int, rgba: int) -> void:
	for channel: int in range(4):
		bytes[index * 4 + channel] = (rgba >> (channel * 8)) & 255

static func _reference(source: PackedByteArray, coords: PackedInt32Array,
		mask: PackedByteArray, width: int, rgba: int, operation: int) -> PackedByteArray:
	var bytes: PackedByteArray = source.duplicate()
	var seen: Dictionary = {}
	for i: int in range(0, coords.size(), 2):
		var index: int = coords[i + 1] * width + coords[i]
		if seen.has(index) or (not mask.is_empty() and mask[index] == 0):
			continue
		seen[index] = true
		_put(bytes, index, 0 if operation == 1 else rgba)
	return bytes

static func _dirty(before: PackedByteArray, after: PackedByteArray, width: int) -> Dictionary:
	var min_x: int = width
	var min_y: int = before.size() / (4 * width)
	var max_x: int = -1
	var max_y: int = -1
	var count: int = 0
	for i: int in range(before.size() / 4):
		if before.slice(i * 4, i * 4 + 4) == after.slice(i * 4, i * 4 + 4):
			continue
		count += 1
		var x: int = i % width
		var y: int = i / width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
	return {"count": count, "rect": Rect2i() if count == 0 else \
		Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)}

func _texture_matches(adapter: RefCounted) -> bool:
	return adapter.texture.get_image().get_data() == adapter.snapshot()

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in native load")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null, "native bridge class available")
	if bridge == null:
		quit(1)
		return

	var original: PackedByteArray = _source(4, 4)
	var state: RefCounted = ADAPTER.new(4, 4, original)
	_check(state.snapshot() == original, "initial bytes detached")
	_check(_texture_matches(state), "initial texture mirrors source")
	var pixels: PackedInt32Array = PackedInt32Array([1, 1, 2, 1, 1, 2, 1, 1])
	var output: Dictionary = state.apply(bridge, 1, pixels, PackedByteArray(), 0x77332211, 2)
	_check(output.ok and output.changed == 3 and output.revision == 2,
		"one atomic revision for duplicate-coordinate edit")
	_check(output.dirty_rect == Rect2i(1, 1, 2, 2), "bounded dirty region")
	_check(_texture_matches(state), "texture updated after successful commit")
	_check(original == _source(4, 4), "external caller source unchanged")
	var committed: PackedByteArray = state.snapshot()
	output = state.apply(bridge, 1, pixels, PackedByteArray(), 0, 1)
	_check(not output.ok and output.error == "STALE", "stale revision rejected")
	_check(state.snapshot() == committed and _texture_matches(state), "stale write has no effect")
	output = state.apply(bridge, 2, PackedInt32Array(), PackedByteArray(), 0, 1)
	_check(output.ok and output.changed == 0 and state.revision == 2, "empty edit is no-op")
	output = state.apply(bridge, 2, PackedInt32Array([9, 0]), PackedByteArray(), 0, 1)
	_check(not output.ok and output.error == "NATIVE", "invalid coordinate rejected")
	_check(state.snapshot() == committed and state.revision == 2, "invalid edit leaves source unchanged")
	output = state.apply(bridge, 2, pixels, PackedByteArray([0]), 0, 1)
	_check(not output.ok and output.error == "NATIVE", "short mask rejected")
	_check(state.snapshot() == committed and _texture_matches(state), "short mask leaves texture unchanged")

	var masked: PackedByteArray = PackedByteArray()
	masked.resize(16)
	masked[0] = 1
	masked[15] = 1
	output = state.apply(bridge, 2, PackedInt32Array([0, 0, 1, 0, 3, 3]), masked,
		0x00CCBBAA, 2)
	_check(output.ok and output.changed == 2 and output.dirty_rect == Rect2i(0, 0, 4, 4),
		"sparse mask produces bounded dirty rect")
	_check(_texture_matches(state), "masked transparent RGB appears in updated texture")
	var pre_conflict: PackedByteArray = state.snapshot()
	var concurrent: PackedByteArray = pre_conflict.duplicate()
	_put(concurrent, 1, 0xAA221144)
	state.before_publish = func() -> void:
		state.replace_source(state.revision, concurrent)
	output = state.apply(bridge, state.revision, pixels, PackedByteArray(), 0xFFABCD12, 2)
	_check(not output.ok and output.error == "STALE", "concurrent replace rejects computed result")
	_check(state.snapshot() == concurrent and _texture_matches(state),
		"concurrent owner wins and image stays synchronized")
	state.before_publish = Callable()
	_check(not state.replace_source(1, original), "external stale replacement refused")

	rng.seed = 68006811
	for iteration: int in range(70):
		var w: int = rng.randi_range(2, 12)
		var h: int = rng.randi_range(2, 12)
		var source: PackedByteArray = _source(w, h)
		var draft: RefCounted = ADAPTER.new(w, h, source)
		var coords: PackedInt32Array = PackedInt32Array()
		for n: int in range(rng.randi_range(1, w * h * 2)):
			coords.append(rng.randi_range(0, w - 1))
			coords.append(rng.randi_range(0, h - 1))
		var mask: PackedByteArray = PackedByteArray()
		if iteration % 3 == 0:
			mask.resize(w * h)
			for index: int in range(mask.size()):
				mask[index] = 0 if index % 5 == 0 else 1
		var operation: int = 1 if iteration % 2 == 0 else 2
		var rgba: int = rng.randi() if operation == 2 else 0
		var expected: PackedByteArray = _reference(source, coords, mask, w, rgba, operation)
		var expected_bounds: Dictionary = _dirty(source, expected, w)
		var result: Dictionary = draft.apply(bridge, 1, coords, mask, rgba, operation)
		_check(result.ok and draft.snapshot() == expected, "oracle pixel parity %d" % iteration)
		_check(result.changed == expected_bounds.count and result.dirty_rect == expected_bounds.rect,
			"oracle dirty region %d" % iteration)
		_check(draft.revision == (2 if result.changed > 0 else 1),
			"monotonic revision %d" % iteration)
		_check(_texture_matches(draft), "whole-texture update %d" % iteration)
		_check(source == _source(w, h), "caller buffer unchanged %d" % iteration)

	bridge.free()
	print("T068_REVISION_PASSED: ", checks, " checks") if failed == 0 else \
		print("T068_REVISION_FAILED: ", failed, "/", checks)
	quit(0 if failed == 0 else 1)
