extends SceneTree
## T-068: a flood-fill candidate is queued once, and the work budget counts
## unique examined pixels. Independent finite-grid oracle checks exact pixels.

const SOURCE: int = 0x00223344 # Hidden RGB must remain byte-exact on undo.
const WALL: int = 0xff102030
const PAINT: int = 0xff887766

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_FRONTIER_FAILED: " + label)


func _document(points: Dictionary[Vector2i, int]) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("frontier-fixture", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	for point: Vector2i in points:
		var staged: DrawingResult = edit.fill_rect(Rect2i(point, Vector2i.ONE), points[point])
		if not staged.ok:
			return {}
	if not edit.commit().ok:
		return {}
	return {"doc": doc, "layer": layer}


func _oracle(points: Dictionary[Vector2i, int], seed: Vector2i,
		allowed: Rect2i) -> Dictionary[Vector2i, int]:
	var match_color: int = points.get(seed, 0)
	var changed: Dictionary[Vector2i, int] = {}
	if match_color == 0 or not allowed.has_point(seed):
		return changed
	var queue: Array[Vector2i] = [seed]
	var seen: Dictionary[Vector2i, bool] = {seed: true}
	var head: int = 0
	while head < queue.size():
		var point: Vector2i = queue[head]
		head += 1
		if not allowed.has_point(point) or points.get(point, 0) != match_color:
			continue
		changed[point] = PAINT
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT,
				Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = point + step
			if not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return changed


func _run() -> void:
	# The 2x2 blob has exactly 12 unique candidates: four stored pixels and
	# eight adjacent empty boundary pixels. Duplicate queued entries must not
	# waste the work budget or turn an exact-limit successful fill into failure.
	var square: Dictionary[Vector2i, int] = {}
	for y: int in range(2):
		for x: int in range(2):
			square[Vector2i(x, y)] = SOURCE
	var fixture: Dictionary = _document(square)
	_check(not fixture.is_empty(), "create exact-budget fixture")
	if fixture.is_empty():
		quit(1)
		return
	var doc: DrawingDocument = fixture["doc"]
	var layer: String = fixture["layer"]
	var initial: int = doc.revision
	var too_small: DrawingEditSession = doc.begin_edit(layer, initial).value
	var rejected: DrawingResult = too_small.flood_fill(Vector2i.ZERO, PAINT, null, 11)
	_check(not rejected.ok and rejected.code == "FILL_LIMIT", "11 unique candidates are insufficient")
	_check(too_small.change_count() == 0 and doc.revision == initial,
		"budget failure leaves no partial edits or publication")
	var exact: DrawingResult = too_small.flood_fill(Vector2i.ZERO, PAINT, null, 12)
	_check(exact.ok and too_small.change_count() == 4,
		"12 unique candidates exactly cover 2x2 plus boundary")
	_check(too_small.commit().ok and doc.revision == initial + 1,
		"successful retry publishes one transaction")
	_check(int(doc.read_pixel(layer, 0, 0).value) == PAINT and
		int(doc.read_pixel(layer, 2, 0).value) == 0,
		"fill modifies no unallocated boundary pixel")
	_check(doc.undo().ok and int(doc.read_pixel(layer, 0, 0).value) == SOURCE,
		"undo restores transparent hidden RGB")
	_check(doc.redo().ok and int(doc.read_pixel(layer, 1, 1).value) == PAINT,
		"redo restores exact filled bytes")

	# Independent bounded-grid oracle with barriers, nonzero transparent RGB,
	# negative coordinates, partial masks, and disjoint connected components.
	var seeds: Array[Vector2i] = [Vector2i(-4, -2), Vector2i(-2, 0),
		Vector2i(0, 2), Vector2i(2, -1), Vector2i(3, 3)]
	for case_index: int in range(10):
		var points: Dictionary[Vector2i, int] = {}
		for y: int in range(-4, 5):
			for x: int in range(-5, 6):
				if (x * 17 + y * 13 + case_index) % 11 == 0:
					continue
				points[Vector2i(x, y)] = WALL if (x + y + case_index) % 5 == 0 else SOURCE
		var run: Dictionary = _document(points)
		_check(not run.is_empty(), "create oracle fixture %d" % case_index)
		if run.is_empty():
			continue
		var subject: DrawingDocument = run["doc"]
		var subject_layer: String = run["layer"]
		var origin: Vector2i = seeds[case_index % seeds.size()]
		var mask_rect: Rect2i = Rect2i(-4, -3, 8, 7) if case_index % 2 == 0 \
			else Rect2i(-5, -4, 11, 9)
		var expected: Dictionary[Vector2i, int] = _oracle(points, origin, mask_rect)
		var selection: DrawingSelection = DrawingSelection.new(mask_rect, true)
		var session: DrawingEditSession = subject.begin_edit(subject_layer, subject.revision).value
		var result: DrawingResult = session.flood_fill(origin, PAINT, selection, 1024)
		var eligible: bool = points.get(origin, 0) != 0 and mask_rect.has_point(origin)
		_check(result.ok == eligible or (eligible and expected.is_empty()),
			"oracle case %d accepts/rejects correct seed" % case_index)
		if not result.ok:
			session.cancel()
			continue
		_check(session.change_count() == expected.size(),
			"oracle case %d exact changed count" % case_index)
		var committed: DrawingResult = session.commit()
		_check(committed.ok, "oracle case %d commit" % case_index)
		var pixels_match: bool = committed.ok
		for point: Vector2i in points:
			var wanted: int = PAINT if expected.has(point) else points[point]
			pixels_match = pixels_match and int(subject.read_pixel(subject_layer,
				point.x, point.y).value) == wanted
		_check(pixels_match, "oracle case %d byte-exact pixels" % case_index)
		var undone: bool = subject.undo().ok
		for point: Vector2i in points:
			undone = undone and int(subject.read_pixel(subject_layer,
				point.x, point.y).value) == points[point]
		_check(undone, "oracle case %d undo restores source" % case_index)

	print("T068_FRONTIER_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
