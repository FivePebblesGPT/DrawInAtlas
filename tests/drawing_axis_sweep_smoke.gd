extends SceneTree
## T-068: exact Geometry2D oracle for horizontal/vertical hard-brush sweeps.
## The oracle stays independent of the optimized segment's implementation.
## Native tile history no longer exposes per-pixel DrawingDelta.after.
## Check full committed/Undo/Redo document pixels instead.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_AXIS_SWEEP_FAILED: " + message)


func _oracle(start: Vector2, finish: Vector2, width: float,
		anchor_x: int, anchor_y: int, mask: DrawingSelection) -> Dictionary[String, int]:
	var radius: float = width * 0.5
	var left: int = floori(minf(start.x, finish.x) - radius - 0.5)
	var top: int = floori(minf(start.y, finish.y) - radius - 0.5)
	var right: int = ceili(maxf(start.x, finish.x) + radius + 0.5)
	var bottom: int = ceili(maxf(start.y, finish.y) + radius + 0.5)
	var expected: Dictionary[String, int] = {}
	for y: int in range(top, bottom):
		for x: int in range(left, right):
			var center: Vector2 = Vector2(x + 0.5, y + 0.5)
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(center, start, finish)
			if center.distance_squared_to(nearest) > radius * radius:
				continue
			if mask != null and not mask.allows(Vector2i(x, y)):
				continue
			expected[DrawingDocument.TILES.pixel_key64(anchor_x + x, anchor_y + y)] = 0x80442211
	return expected


func _region_matches(doc: DrawingDocument, layer: String, start: Vector2,
		finish: Vector2, width: float, anchor_x: int, anchor_y: int,
		expected: Dictionary[String, int], undone: bool) -> bool:
	var radius: float = width * 0.5
	var left: int = floori(minf(start.x, finish.x) - radius - 0.5)
	var top: int = floori(minf(start.y, finish.y) - radius - 0.5)
	var right: int = ceili(maxf(start.x, finish.x) + radius + 0.5)
	var bottom: int = ceili(maxf(start.y, finish.y) + radius + 0.5)
	# Include a one-pixel border to prove neither the optimized sweep nor its
	# native commit painted beyond the exact Geometry2D/mask coverage.
	for y: int in range(top - 1, bottom + 1):
		for x: int in range(left - 1, right + 1):
			var key: String = DrawingDocument.TILES.pixel_key64(anchor_x + x, anchor_y + y)
			var expected_pixel: int = 0 if undone else int(expected.get(key, 0))
			var pixel: DrawingResult = doc.read_pixel(layer, anchor_x + x, anchor_y + y)
			if not pixel.ok or int(pixel.value) != expected_pixel:
				return false
	return true


func _case(start: Vector2, finish: Vector2, width: float,
		mask: DrawingSelection = null) -> void:
	var label: String = "%s -> %s width=%s mask=%s" % [start, finish, width, mask != null]
	var doc: DrawingDocument = DrawingDocument.new("axis-sweep", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	# Keep source tile low bits nonzero, but stay within the native ±2^52
	# tile projection. The original >2^53 anchor must fail publication.
	var anchor_x: int = 1125899906842625
	var anchor_y: int = -1125899906842625
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor_x, anchor_y).value as DrawingEditSession
	var path: PackedVector2Array = PackedVector2Array([start, finish])
	var painted: DrawingResult = edit.paint_path(path, 0x80442211, width, false, mask)
	_check(painted.ok, "stage " + label)
	if not painted.ok:
		return
	var expected: Dictionary[String, int] = _oracle(start, finish, width,
		anchor_x, anchor_y, mask)
	_check(edit.change_count() == expected.size(), "expected coverage before commit " + label)
	var count: int = edit.change_count()
	_check(edit.paint_path(path, 0x80442211, width, false, mask).ok and edit.change_count() == count,
		"once-covered repeated path " + label)
	var prior_revision: int = doc.revision
	var committed: DrawingResult = edit.commit()
	_check(committed.ok and doc.revision == prior_revision + 1,
		"native commit advances one revision " + label)
	if not committed.ok:
		return
	_check(_region_matches(doc, layer, start, finish, width, anchor_x, anchor_y,
		expected, false), "exact original Geometry2D pixels and RGBA8 " + label)
	var undone: DrawingResult = doc.undo()
	_check(undone.ok and _region_matches(doc, layer, start, finish, width,
		anchor_x, anchor_y, expected, true), "full blank region after undo " + label)
	var redone: DrawingResult = doc.redo()
	_check(redone.ok and _region_matches(doc, layer, start, finish, width,
		anchor_x, anchor_y, expected, false), "full exact RGBA8 after redo " + label)


func _randomized_geometry_parity() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 680318
	var failures_found: int = 0
	var candidates: int = 0
	for trial: int in range(320):
		var vertical: bool = trial % 2 == 0
		var first: Vector2 = Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
		var second: Vector2 = Vector2(first.x, rng.randf_range(-20.0, 20.0)) if vertical else Vector2(rng.randf_range(-20.0, 20.0), first.y)
		if first == second:
			continue
		var width: float = [1.0, 1.5, 2.0, 2.5, 3.0, 8.0, 16.0][trial % 7]
		var radius: float = width * 0.5
		var left: int = floori(minf(first.x, second.x) - radius - 0.5)
		var top: int = floori(minf(first.y, second.y) - radius - 0.5)
		var right: int = ceili(maxf(first.x, second.x) + radius + 0.5)
		var bottom: int = ceili(maxf(first.y, second.y) + radius + 0.5)
		var minimum: float = minf(first.y, second.y) if vertical else minf(first.x, second.x)
		var maximum: float = maxf(first.y, second.y) if vertical else maxf(first.x, second.x)
		for y: int in range(top, bottom):
			for x: int in range(left, right):
				candidates += 1
				var center: Vector2 = Vector2(x + 0.5, y + 0.5)
				var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(center, first, second)
				var reference: bool = center.distance_squared_to(nearest) <= radius * radius
				var parallel: float = center.y if vertical else center.x
				var fixed: float = center.x - first.x if vertical else center.y - first.y
				var excess: float = parallel - clampf(parallel, minimum, maximum)
				var optimized: bool = fixed * fixed + excess * excess <= radius * radius
				if reference != optimized:
					failures_found += 1
					if failures_found == 1:
						push_warning("First mismatch: axis=%s start=%s end=%s width=%s center=%s" % [
							"vertical" if vertical else "horizontal", first, second, width, center])
	_check(failures_found == 0 and candidates > 20000,
		"randomized independent Geometry2D parity over %d candidates; mismatches=%d" % [
			candidates, failures_found])


func _run() -> void:
	_randomized_geometry_parity()
	var starts: Array[Vector2] = [Vector2(-15.25, 0.5), Vector2(17.5, -16.25),
		Vector2(-0.125, 17.75), Vector2(0.5, -0.5)]
	var ends: Array[Vector2] = [Vector2(24.75, 0.5), Vector2(-9.5, -16.25),
		Vector2(-0.125, -14.25), Vector2(0.5, 21.5)]
	for width: float in [1.0, 2.5, 8.0, 15.0]:
		for index: int in range(starts.size()):
			_case(starts[index], ends[index], width)
			_case(ends[index], starts[index], width)
	# Mask clipping must retain the identical per-pixel approval boundary.
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-3, -2, 8, 6), true)
	_case(Vector2(-15.25, 0.5), Vector2(24.75, 0.5), 8.0, mask)
	_case(Vector2(0.5, -16.25), Vector2(0.5, 21.5), 8.0, mask)
	# The public gesture may be created at >2^53, but the native tile
	# publisher must fail closed with no revision or pixel mutation.
	var unsafe_anchor: int = 9007199254740993
	var unsafe: DrawingDocument = DrawingDocument.new("axis-out-of-projection", 16)
	var unsafe_layer: String = String(unsafe.create_layer(DrawingLayerNode.RASTER, "Unsafe").value)
	var unsafe_revision: int = unsafe.revision
	var unsafe_begin: DrawingResult = unsafe.begin_edit(unsafe_layer, unsafe_revision,
		Transform2D.IDENTITY, unsafe_anchor, -unsafe_anchor)
	_check(unsafe_begin.ok, "out-of-projection gesture remains constructible")
	if unsafe_begin.ok:
		var unsafe_edit: DrawingEditSession = unsafe_begin.value as DrawingEditSession
		var unsafe_stage: DrawingResult = unsafe_edit.paint_path(
			PackedVector2Array([Vector2(0.5, 0.5), Vector2(3.5, 0.5)]),
			0x80442211, 2.5)
		var unsafe_commit: DrawingResult = unsafe_edit.commit() if unsafe_stage.ok else unsafe_stage
		var unsafe_pixel: DrawingResult = unsafe.read_pixel(unsafe_layer, unsafe_anchor, -unsafe_anchor)
		_check(not unsafe_commit.ok and unsafe.revision == unsafe_revision and
			unsafe_pixel.ok and int(unsafe_pixel.value) == 0,
			"out-of-projection sweep cannot publish pixels or history")
		unsafe_edit.cancel()
	print("T068_AXIS_SWEEP_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
