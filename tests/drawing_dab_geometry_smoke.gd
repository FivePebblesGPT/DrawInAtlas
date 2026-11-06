extends SceneTree
## T-068: independent Geometry2D oracle for the optimized stationary-dab path.
## Tests signed 64-bit anchors, fractional centers, tile seams and byte parity.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_DAB_FAILED: " + label)


func _run() -> void:
	var anchor: int = 9007199254740993
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
			var committed: DrawingResult = edit.commit()
			_check(committed.ok, "commit stationary brush")
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
			_check(committed.delta != null and committed.delta.after.size() == expected_count,
				"original once-covered pixel count")
			var sample_x: int = floori(point.x)
			var sample_y: int = floori(point.y)
			var before_undo: int = int(doc.read_pixel(layer, anchor + sample_x,
				-anchor + sample_y).value)
			var undone: DrawingResult = doc.undo()
			_check(undone.ok, "undo round dab")
			var redone: DrawingResult = doc.redo()
			_check(redone.ok, "redo round dab")
			_check(int(doc.read_pixel(layer, anchor + sample_x, -anchor + sample_y).value)
				== before_undo, "redo restores original sample exactly")
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
