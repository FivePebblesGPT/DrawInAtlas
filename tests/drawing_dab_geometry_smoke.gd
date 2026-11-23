extends SceneTree
## T-068: independent Geometry2D oracle for the optimized stationary-dab path.
## Tests native-publishable signed anchors, fractional centers, tile seams and exact RGBA8.
## Native tile history does not expose obsolete per-pixel DrawingDelta.after maps.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_DAB_FAILED: " + label)


func _region_matches(doc: DrawingDocument, layer: String, anchor: int,
		point: Vector2, radius: float, left: int, top: int,
		right: int, bottom: int, undone: bool) -> bool:
	for y: int in range(top - 1, bottom + 1):
		for x: int in range(left - 1, right + 1):
			var center: Vector2 = Vector2(x + 0.5, y + 0.5)
			var inside: bool = x >= left and x < right and y >= top and y < bottom
			var expected: int = 0
			if not undone and inside and center.distance_squared_to(
					Geometry2D.get_closest_point_to_segment(center, point, point)) <= radius * radius:
				expected = 0xff562413
			var pixel: DrawingResult = doc.read_pixel(layer, anchor + x, -anchor + y)
			if not pixel.ok or int(pixel.value) != expected:
				return false
	return true


func _run() -> void:
	# Keep the low bits nonzero to exercise signed source-tile seams. The
	# former >2^53 anchor cannot be projected into the native tile store.
	var anchor: int = 1125899906842625
	var sizes: Array[float] = [1.0, 3.0, 8.0, 32.0, 64.0]
	var points: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(-0.3, 15.9),
		Vector2(16.25, -16.75)]
	for width: float in sizes:
		for point: Vector2 in points:
			var doc: DrawingDocument = DrawingDocument.new("t068-dab", 16)
			var created: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Dab")
			_check(created.ok, "create test layer")
			if not created.ok:
				continue
			var layer: String = String(created.value)
			var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
				Transform2D.IDENTITY, anchor, -anchor).value as DrawingEditSession
			var result: DrawingResult = edit.paint_path(PackedVector2Array([point]),
				0xff562413, width)
			_check(result.ok, "stage stationary brush")
			if not result.ok:
				continue
			var staged_count: int = edit.change_count()
			var source_revision: int = doc.revision
			var committed: DrawingResult = edit.commit()
			_check(committed.ok and doc.revision == source_revision + 1,
				"native commit publishes exactly one revision")
			if not committed.ok:
				continue
			var radius: float = width * 0.5
			var left: int = floori(point.x - radius - 0.5)
			var top: int = floori(point.y - radius - 0.5)
			var right: int = ceili(point.x + radius + 0.5)
			var bottom: int = ceili(point.y + radius + 0.5)
			var expected_count: int = 0
			var byte_exact: bool = true
			for y: int in range(top - 1, bottom + 1):
				for x: int in range(left - 1, right + 1):
					var center: Vector2 = Vector2(x + 0.5, y + 0.5)
					var inside: bool = x >= left and x < right and y >= top and y < bottom
					var expected: int = 0
					if inside and center.distance_squared_to(
							Geometry2D.get_closest_point_to_segment(center, point, point)) <= radius * radius:
						expected = 0xff562413
						expected_count += 1
					var pixel: DrawingResult = doc.read_pixel(layer, anchor + x, -anchor + y)
					if not pixel.ok or int(pixel.value) != expected:
						byte_exact = false
			_check(byte_exact, "exact original geometry and RGBA8 at width=%s point=%s" % [width, point])
			_check(staged_count == expected_count,
				"independent Geometry2D once-covered pixel count")
			var undone: DrawingResult = doc.undo()
			_check(undone.ok and _region_matches(doc, layer, anchor, point, radius,
				left, top, right, bottom, true), "undo restores entire blank region")
			var redone: DrawingResult = doc.redo()
			_check(redone.ok and _region_matches(doc, layer, anchor, point, radius,
				left, top, right, bottom, false), "redo restores complete exact dab")
	# Broad public gestures can still be constructed beyond the native tile
	# projection; they must fail publication without creating a history step.
	var unsafe_anchor: int = 9007199254740993
	var unsafe: DrawingDocument = DrawingDocument.new("out-of-projection", 16)
	var unsafe_layer: String = String(unsafe.create_layer(DrawingLayerNode.RASTER, "Unsafe").value)
	var unsafe_revision: int = unsafe.revision
	var unsafe_begin: DrawingResult = unsafe.begin_edit(unsafe_layer, unsafe_revision,
		Transform2D.IDENTITY, unsafe_anchor, -unsafe_anchor)
	_check(unsafe_begin.ok, "out-of-projection gesture is constructible")
	if unsafe_begin.ok:
		var unsafe_edit: DrawingEditSession = unsafe_begin.value as DrawingEditSession
		var unsafe_stage: DrawingResult = unsafe_edit.paint_path(
			PackedVector2Array([Vector2(0.5, 0.5)]), 0xff562413, 3.0)
		var unsafe_commit: DrawingResult = unsafe_edit.commit() if unsafe_stage.ok else unsafe_stage
		_check(not unsafe_commit.ok and unsafe.revision == unsafe_revision and
			int(unsafe.read_pixel(unsafe_layer, unsafe_anchor, -unsafe_anchor).value) == 0,
			"out-of-projection commit never mutates native pixels or revision")
		unsafe_edit.cancel()
	# Transparent RGB must survive a zero-alpha overdraw, regardless of brush width.
	var hidden: DrawingDocument = DrawingDocument.new("t068-hidden", 16)
	var layer_id: String = String(hidden.create_layer(DrawingLayerNode.RASTER, "Hidden").value)
	var seed: DrawingEditSession = hidden.begin_edit(layer_id, hidden.revision).value
	var pixels: PackedByteArray = PackedByteArray([0xa1, 0xb2, 0xc3, 0])
	_check(seed.apply_region(Rect2i(0, 0, 1, 1), pixels).ok and seed.commit().ok,
		"seed hidden RGB")
	var over: DrawingEditSession = hidden.begin_edit(layer_id, hidden.revision).value
	var prior_revision: int = hidden.revision
	_check(over.paint_path(PackedVector2Array([Vector2(0.5, 0.5)]),
		0x00010203, 64.0).ok, "transparent round dab")
	_check(over.change_count() == 0, "transparent source does not stage a change")
	over.cancel()
	_check(hidden.revision == prior_revision, "no-op dab never publishes")
	_check(int(hidden.read_pixel(layer_id, 0, 0).value) == 0x00c3b2a1,
		"unchanged hidden RGB with zero source alpha")
	print("T068_DAB_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
