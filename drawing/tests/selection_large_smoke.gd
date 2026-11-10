extends SceneTree
## T-096: independently enumerate source-pixel boundaries and compare the
## viewport-clipped contour API; exact masked moves use immutable payloads.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T096_MODEL_FAILED: " + description)


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var swap: Vector2i = a
		a = b
		b = swap
	return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]


func _actual_edges(selection: DrawingSelection, view: Rect2i) -> Dictionary:
	var result: Dictionary = {}
	for y: int in range(view.position.y - 1, view.end.y + 1):
		for x: int in range(view.position.x - 1, view.end.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not selection.allows(cell):
				continue
			var candidates: Array[Vector2i] = [Vector2i(x, y), Vector2i(x + 1, y),
				Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]
			var neighbors: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN,
				Vector2i.LEFT, Vector2i.RIGHT]
			for direction: Vector2i in neighbors:
				if selection.allows(cell + direction):
					continue
				var a: Vector2i
				var b: Vector2i
				match direction:
					Vector2i.UP:
						a = candidates[0]
						b = candidates[1]
					Vector2i.DOWN:
						a = candidates[2]
						b = candidates[3]
					Vector2i.LEFT:
						a = candidates[0]
						b = candidates[2]
					Vector2i.RIGHT:
						a = candidates[1]
						b = candidates[3]
				if a.x < view.position.x or a.y < view.position.y or \
					b.x > view.end.x or b.y > view.end.y:
					continue
				result[_edge_key(a, b)] = true
	return result


func _segments_to_edges(lines: PackedVector2Array) -> Dictionary:
	var result: Dictionary = {}
	check(lines.size() % 2 == 0, "contour always returns paired segment endpoints")
	for i: int in range(0, lines.size(), 2):
		var a: Vector2i = Vector2i(lines[i])
		var b: Vector2i = Vector2i(lines[i + 1])
		check(a.x == b.x or a.y == b.y, "axis-aligned boundary")
		var direction: Vector2i = Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		while a != b:
			var next: Vector2i = a + direction
			result[_edge_key(a, next)] = true
			a = next
	return result


func _assert_contour(selection: DrawingSelection, view: Rect2i, label: String) -> void:
	var expected: Dictionary = _actual_edges(selection, view)
	var got: Dictionary = _segments_to_edges(selection.contour_segments(view))
	check(got == expected, "%s: exact viewport edges (%d expected, %d got)" %
		[label, expected.size(), got.size()])


func percentile(values: Array[float], fraction: float) -> float:
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]


func _pixel(doc: DrawingDocument, layer: String, location: Vector2i) -> int:
	var read: DrawingResult = doc.read_pixel(layer, location.x, location.y)
	return int(read.value) if read.ok else -1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(-85, -48, 112, 96), true)
	check(selection.combine_rectangle(Rect2i(-54, -22, 32, 28), "Subtract") and
		selection.combine_rectangle(Rect2i(43, -18, 34, 40), "Add") and
		selection.combine_rectangle(Rect2i(-32, 12, 18, 10), "Subtract"),
		"complex mask has two holes and a detached island over 4096 pixels")
	_assert_contour(selection, Rect2i(-93, -53, 183, 110), "whole large disjoint mask")
	_assert_contour(selection, Rect2i(-53, -24, 39, 36), "subtracted hole, clipped on all sides")
	_assert_contour(selection, Rect2i(35, -23, 53, 53), "island, nonzero positive chunks")
	_assert_contour(selection, Rect2i(-79, 2, 28, 40), "left-hand viewport clip")
	var left: Rect2i = Rect2i(-93, -53, 91, 110)
	var right: Rect2i = Rect2i(-2, -53, 92, 110)
	var stitched: Dictionary = _segments_to_edges(selection.contour_segments(left))
	for key: String in _segments_to_edges(selection.contour_segments(right)):
		stitched[key] = true
	check(stitched == _actual_edges(selection, Rect2i(-93, -53, 183, 110)),
		"two adjacent viewport tiles reconstruct identical contour without fake seam")
	var intersected: DrawingSelection = selection.detached_copy()
	check(intersected.combine_rectangle(Rect2i(-71, -36, 105, 66), "Intersect"),
		"intersection operation accepted")
	_assert_contour(intersected, Rect2i(-85, -49, 144, 94), "intersect respects holes and islands")
	var gigantic: DrawingSelection = DrawingSelection.new(
		Rect2i(-100000, -100000, 200000, 200000), true)
	gigantic.combine_rectangle(Rect2i(-12, -9, 20, 18), "Subtract")
	var tick: int = Time.get_ticks_usec()
	_assert_contour(gigantic, Rect2i(-25, -25, 52, 52), "200k-wide selection is viewport-bounded")
	check(Time.get_ticks_usec() - tick < 5000000,
		"giant document area does not trigger a full-area contour scan")
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-36, -24, 85, 78), true)
	var explicit: Dictionary[Vector2i, bool] = {}
	for y: int in range(-24, 54):
		for x: int in range(-36, 49):
			if (x * 7 + y * 13) % 11 < 4:
				explicit[Vector2i(x, y)] = true
	mask.set_mask(explicit)
	mask.combine_rectangle(Rect2i(-19, -8, 12, 20), "Subtract")
	mask.combine_rectangle(Rect2i(60, 2, 8, 9), "Add")
	_assert_contour(mask, Rect2i(-42, -29, 119, 93), "explicit pixel mask plus operations")
	_assert_contour(mask, Rect2i(-20, 8, 44, 40), "explicit pixel mask clipped tile")
	var tile_union: Dictionary = {}
	for tile_y: int in range(-1, 2):
		for tile_x: int in range(-1, 2):
			for key: String in _segments_to_edges(mask.contour_segments(
				Rect2i(tile_x * 64, tile_y * 64, 64, 64))):
				tile_union[key] = true
	check(tile_union == _actual_edges(mask, Rect2i(-64, -64, 192, 192)),
		"irregular mask contour tiles are seamless and exact")

	var doc: DrawingDocument = DrawingDocument.new("t096-move", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "subject").value)
	var under: String = String(doc.create_layer(DrawingLayerNode.RASTER, "under").value)
	var underneath: DrawingEditSession = doc.begin_edit(under, doc.revision).value as DrawingEditSession
	check(underneath._stage(-18, 0, 0xff707070).ok and underneath.commit().ok,
		"seed lower layer for compositing preservation")
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	var originals: Dictionary[Vector2i, int] = {}
	for y: int in range(-18, 65):
		for x: int in range(-45, 57):
			if (x + y * 2) % 5 == 0:
				var rgba: int = 0x00556677 if (x + y) % 7 == 0 else 0xff5588aa
				var at: Vector2i = Vector2i(x, y)
				originals[at] = rgba
				seed._stage(x, y, rgba)
	check(seed.commit().ok, "seed 8k+ source area with sparse and hidden-RGB pixels")
	var region: Rect2i = Rect2i(-45, -18, 102, 83)
	var chosen: DrawingSelection = DrawingSelection.new(region, true)
	chosen.combine_rectangle(Rect2i(-20, 0, 25, 30), "Subtract")
	var copy_result: DrawingResult = DrawingClipboard.capture(doc, layer, region, chosen)
	check(copy_result.ok, "capture immutable 8466px selected region")
	var clipboard: DrawingClipboard = copy_result.value as DrawingClipboard
	var rev: int = doc.revision
	var hist: int = doc.history_length()
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(9, -6), Vector2i(-7, 4), Vector2i(16, 10)]:
		var preview: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
		var staged: DrawingResult = DrawingClipboard.move_captured(preview, clipboard, offset)
		check(staged.ok, "cached selected pixels stage at offset %s" % offset)
		for point: Vector2i in [Vector2i(-45, -18), Vector2i(-18, 4), Vector2i(8, 8), Vector2i(55, 64)]:
			var original: int = int(originals.get(point, 0))
			var source_local: Vector2i = point - region.position - offset
			var target_rgba: int = int(clipboard._pixels.get(source_local, 0))
			var predicted: int = target_rgba if target_rgba != 0 else (0 if chosen.allows(point) else original)
			# Independent oracle compares staged visible composite, including
			# overlap, holes, transparent sources and signed storage seams.
			var staged_rgba: int = int(preview._after.get("%d,%d" % [point.x, point.y], original))
			check(staged_rgba == predicted, "sparse overlap oracle at %s offset %s" % [point, offset])
		check(doc.revision == rev and doc.history_length() == hist,
			"each preview remains detached and history-free")
		preview.cancel()
	# Controlled same-document before/after profile. The old implementation
	# recaptured, scanned each selected cell to clear, and scanned the entire
	# payload rectangle to paste on EACH movement. Preview dictionaries and
	# every changed source/destination byte must match the optimized staging.
	var old_capture_ms: Array[float] = []
	var old_clear_ms: Array[float] = []
	var old_paste_ms: Array[float] = []
	var optimized_ms: Array[float] = []
	for i: int in range(8):
		var offset: Vector2i = Vector2i(2 + i * 2, -4 + i % 3)
		var old_edit: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
		var stage_tick: int = Time.get_ticks_usec()
		var old_capture: DrawingResult = DrawingClipboard.capture(doc, layer, region, chosen)
		old_capture_ms.append(float(Time.get_ticks_usec() - stage_tick) / 1000.0)
		check(old_capture.ok, "legacy per-drag capture succeeds")
		stage_tick = Time.get_ticks_usec()
		var old_clear: DrawingResult = old_edit.clear_rect(region, chosen)
		old_clear_ms.append(float(Time.get_ticks_usec() - stage_tick) / 1000.0)
		check(old_clear.ok, "legacy per-drag full-rectangle clear succeeds")
		stage_tick = Time.get_ticks_usec()
		var old_paste: DrawingResult = (old_capture.value as DrawingClipboard).paste(
			old_edit, region.position + offset)
		old_paste_ms.append(float(Time.get_ticks_usec() - stage_tick) / 1000.0)
		check(old_paste.ok, "legacy per-drag full-rectangle paste succeeds")
		var optimized: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
		stage_tick = Time.get_ticks_usec()
		check(DrawingClipboard.move_captured(optimized, clipboard, offset).ok,
			"optimized per-drag staging succeeds")
		optimized_ms.append(float(Time.get_ticks_usec() - stage_tick) / 1000.0)
		check(old_edit._after == optimized._after and old_edit._before == optimized._before,
			"all detached preview bytes and undo originals equal legacy at %s" % offset)
		old_edit.cancel()
		optimized.cancel()
	print("T096_PROFILE: legacy_capture_p50/p95_ms=%.3f/%.3f legacy_clear_p50/p95_ms=%.3f/%.3f legacy_paste_p50/p95_ms=%.3f/%.3f optimized_stage_p50/p95_ms=%.3f/%.3f" % [
		percentile(old_capture_ms, 0.5), percentile(old_capture_ms, 0.95),
		percentile(old_clear_ms, 0.5), percentile(old_clear_ms, 0.95),
		percentile(old_paste_ms, 0.5), percentile(old_paste_ms, 0.95),
		percentile(optimized_ms, 0.5), percentile(optimized_ms, 0.95)])
	var pre_staged: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
	var unfilled: Vector2i = Vector2i(-43, -18)
	check(not originals.has(unfilled) and chosen.allows(unfilled),
		"pre-staged transparent source-cell fixture is really absent")
	check(pre_staged._stage(unfilled.x, unfilled.y, 0xff314159).ok and
		DrawingClipboard.move_selection(pre_staged, region, Vector2i(3, 0), chosen).ok and
		not pre_staged._after.has("%d,%d" % [unfilled.x, unfilled.y]),
		"public Move still erases caller's prior draft inside transparent selection")
	pre_staged.cancel()
	var retained_on_failure: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
	check(retained_on_failure._stage(150, 150, 0xff415263).ok and
		not DrawingClipboard.move_captured(retained_on_failure, clipboard,
			Vector2i(1073741823, 0)).ok and
		int(retained_on_failure._after.get("150,150", 0)) == 0xff415263,
		"invalid destination rolls back move without removing previous staged work")
	retained_on_failure.cancel()
	var invalid: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
	check(not DrawingClipboard.move_captured(invalid, clipboard, Vector2i(1073741823, 0)).ok and
		invalid.change_count() == 0, "invalid move restores empty edit atomically")
	invalid.cancel()
	var final: DrawingEditSession = doc.begin_edit(layer, rev).value as DrawingEditSession
	check(DrawingClipboard.move_captured(final, clipboard, Vector2i(9, -6)).ok and
		final.commit().ok and doc.history_length() == hist + 1,
		"drop publishes exactly one move edit")
	check(_pixel(doc, layer, Vector2i(-45, -18)) == 0 and
		_pixel(doc, layer, Vector2i(-36, -24)) == int(originals.get(Vector2i(-45, -18), 0)),
		"committed payload copies source to target, clears source")
	check(doc.undo().ok and _pixel(doc, layer, Vector2i(-45, -18)) ==
		int(originals.get(Vector2i(-45, -18), 0)), "Undo restores original")
	check(doc.redo().ok and _pixel(doc, layer, Vector2i(-45, -18)) == 0,
		"Redo restores moved source")
	print("T096_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T096_MODEL_PASSED")
	quit(0 if failures == 0 else 1)
