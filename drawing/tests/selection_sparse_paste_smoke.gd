extends SceneTree
## T-088: independent dense oracle for sparse transparent clipboard paste.
## Benchmarks stage-only CPU time, not capture, frame time, or hardware latency.

var checks: int = 0
var failures: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T088_SPARSE_PASTE_FAILED: " + message)


func oracle_paste(clip: DrawingClipboard, edit: DrawingEditSession,
		target: Vector2i, mask: DrawingSelection = null,
		transparent: bool = true) -> DrawingResult:
	# Deliberately independent row-major scan; no iteration over clip._pixels.
	for y: int in range(clip.height):
		for x: int in range(clip.width):
			var local: Vector2i = Vector2i(x, y)
			if clip.source_selection != null and not clip.source_selection.allows(clip.source_position + local):
				continue
			var rgba: int = clip._pixels.get(local, 0)
			if rgba == 0 and transparent:
				continue
			var result: DrawingResult = edit._stage(target.x + x, target.y + y, rgba, mask)
			if not result.ok:
				return result
	return DrawingResult.success(edit.change_count())


func median(values: Array[int]) -> int:
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t088-sparse-paste", 128)
	var source: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Source").value)
	var reference: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Reference").value)
	var actual: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Actual").value)
	var source_edit: DrawingEditSession = doc.begin_edit(source, doc.revision).value as DrawingEditSession
	var area: Rect2i = Rect2i(-260, -135, 512, 512)
	var selected: DrawingSelection = DrawingSelection.new(area, true)
	selected.combine_rectangle(Rect2i(-5, 100, 8, 8), "Subtract")
	var samples: Dictionary[Vector2i, int] = {
		Vector2i(-260, -135): 0xff012345,
		Vector2i(-133, 0): 0x00eeddcc,
		Vector2i(-5, 102): 0xffdeadbe, # excluded by the selection hole
		Vector2i(-4, 103): 0x00997755, # excluded hidden RGB
		Vector2i(0, 0): 0xffaabbcc,
		Vector2i(128, 128): 0xff113355,
		Vector2i(251, 376): 0x00774422,
		Vector2i(249, 375): 0xff887766,
	}
	for point: Vector2i in samples:
		check(source_edit._stage(point.x, point.y, samples[point]).ok,
			"seed sparse source %s" % point)
	check(source_edit.commit().ok, "commit sparse source")
	var captured: DrawingResult = DrawingClipboard.capture(doc, source, area, selected)
	check(captured.ok, "capture 512x512 selection across signed tile boundaries")
	var clip: DrawingClipboard = captured.value as DrawingClipboard
	check(clip._pixels.size() == samples.size() - 2 and
		clip._pixels.get(Vector2i(127, 135), 0) == 0x00eeddcc and
		clip._pixels.get(Vector2i(388, 263), 0) == 0xff113355,
		"captured sparse bytes include hidden RGB and exclude hole")

	var target: Vector2i = Vector2i(300, -410)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(target, area.size), true)
	mask.combine_rectangle(Rect2i(target + Vector2i(388, 263), Vector2i.ONE), "Subtract")
	var expected: DrawingEditSession = doc.begin_edit(reference, doc.revision).value as DrawingEditSession
	var pasted: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
	check(oracle_paste(clip, expected, target, mask).ok, "independent dense oracle stages")
	check(clip.paste(pasted, target, mask).ok, "transparent sparse paste stages")
	check(pasted._after == expected._after and pasted._before == expected._before and
		pasted.change_count() == samples.size() - 3,
		"sparse paste matches dense oracle with mask hole, including hidden RGB")
	expected.cancel()
	check(pasted.commit().ok, "commit actual sparse paste")
	for point: Vector2i in samples:
		var local: Vector2i = point - area.position
		var actual_read: DrawingResult = doc.read_pixel(actual, target.x + local.x, target.y + local.y)
		var expected_value: int = samples[point] if selected.allows(point) and mask.allows(target + local) else 0
		check(actual_read.ok and int(actual_read.value) == expected_value,
			"published bytes match at %s" % point)
	var at_revision: int = doc.revision
	check(doc.undo().ok and doc.revision == at_revision + 1 and
		int(doc.read_pixel(actual, target.x, target.y).value) == 0,
		"one Undo removes only pasted destination bytes")
	check(doc.redo().ok and int(doc.read_pixel(actual, target.x, target.y).value) == 0xff012345,
		"Redo restores exact pasted pixels")

	# Non-transparent paste must still visit missing/zero payload cells and clear
	# them, including a destination chosen from inside an originally empty mask.
	var opaque: DrawingClipboard = DrawingClipboard.new()
	opaque.width = 4
	opaque.height = 2
	opaque._pixels[Vector2i(1, 0)] = 0x00445566
	opaque._pixels[Vector2i(7, 1)] = 0xffeeeeee # Outside clipboard bounds; never pasted.
	opaque._pixels[Vector2i(0, 0)] = 0 # Transparent zero is a no-op in default mode.
	var opaque_destination: Vector2i = Vector2i(-400, 600)
	var seed_targets: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
	check(seed_targets.fill_rect(Rect2i(opaque_destination, Vector2i(4, 2)), 0xffabcdef).ok
		and seed_targets.commit().ok, "seed opaque destination")
	var transparent_edit: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
	check(opaque.paste(transparent_edit, opaque_destination).ok and
		transparent_edit.change_count() == 1 and
		transparent_edit._after.get("-399,600", 0) == 0x00445566,
		"transparent default skips zeros and out-of-range payload entries")
	transparent_edit.cancel()
	var opaque_edit: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
	var opaque_oracle: DrawingEditSession = doc.begin_edit(reference, doc.revision).value as DrawingEditSession
	check(opaque.paste(opaque_edit, opaque_destination, null, false).ok and
		oracle_paste(opaque, opaque_oracle, opaque_destination, null, false).ok,
		"explicit nontransparent mode processes absent payload pixels")
	check(opaque_edit.change_count() == 8 and
		int(opaque_edit._after.get("-400,600", -1)) == 0 and
		int(opaque_edit._after.get("-399,600", -1)) == 0x00445566,
		"nontransparent mode clears empty cells and preserves hidden RGB")
	opaque_edit.cancel()
	opaque_oracle.cancel()

	# Differentially exercise sparse and dense paths against the independent
	# row-major oracle, including zero/nonzero hidden RGB and source/destination
	# masks. A manually supplied clipboard may contain out-of-bounds entries.
	var populations: Array[int] = [0, 1, 9, 80, 300, 520, 1080, 1680]
	var differential_checks: int = 0
	for population: int in populations:
		var comparison: DrawingClipboard = DrawingClipboard.new()
		comparison.width = 48
		comparison.height = 35
		comparison.source_position = Vector2i(-115, 79)
		if population % 2 == 0:
			comparison.source_selection = DrawingSelection.new(
				Rect2i(comparison.source_position, Vector2i(48, 35)), true)
			comparison.source_selection.combine_rectangle(Rect2i(-97, 85, 6, 9), "Subtract")
		for ordinal: int in range(population):
			var cell: int = (ordinal * 457) % (48 * 35)
			var local: Vector2i = Vector2i(cell % 48, cell / 48)
			comparison._pixels[local] = 0x00443322 if ordinal % 5 == 0 else 0xff224466
		comparison._pixels[Vector2i(60, 2)] = 0xff778899
		for transparent_mode: bool in [true, false]:
			var destination: DrawingSelection = DrawingSelection.new(
				Rect2i(-58, 144, 48, 35), true)
			destination.combine_rectangle(Rect2i(-35, 160, 3, 5), "Subtract")
			var dense_session: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
			var sparse_session: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
			var result_reference: DrawingResult = oracle_paste(comparison, dense_session,
				Vector2i(-58, 144), destination, transparent_mode)
			var result_actual: DrawingResult = comparison.paste(sparse_session,
				Vector2i(-58, 144), destination, transparent_mode)
			check(result_actual.ok and result_reference.ok and
				sparse_session._before == dense_session._before and
				sparse_session._after == dense_session._after and
				sparse_session.change_count() == dense_session.change_count(),
				"dense oracle parity population %d, transparent %s" % [population, transparent_mode])
			differential_checks += 1
			dense_session.cancel()
			sparse_session.cancel()
	check(differential_checks == 16, "all 16 dense/sparse differential cases exercised")

	# A failed sparse write must roll back an already staged caller edit and its
	# preview exactly; failure cannot publish a partial delta or clear history.
	var prior: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
	check(prior._stage(100, 100, 0xffcafebe).ok, "seed existing destination draft")
	var before: Dictionary[String, int] = prior._before.duplicate()
	var after: Dictionary[String, int] = prior._after.duplicate()
	var failure: DrawingResult = clip.paste(prior, Vector2i(1073741823, 0))
	check(not failure.ok and failure.code == "COORD_RANGE", "out-of-range sparse paste is rejected")
	check(prior._before == before and prior._after == after and prior.change_count() == 1,
		"failed sparse paste leaves previous draft and history untouched")
	prior.cancel()

	# Compare CPU staging medians only. This is not capture, texture upload,
	# native frame time, or end-to-end user interaction latency.
	var stage_times_us: Array[int] = []
	for trial: int in range(7):
		var perf: DrawingEditSession = doc.begin_edit(actual, doc.revision).value as DrawingEditSession
		var start: int = Time.get_ticks_usec()
		var result: DrawingResult = clip.paste(perf, Vector2i(1000, 1000))
		stage_times_us.append(Time.get_ticks_usec() - start)
		check(result.ok and perf.change_count() == samples.size() - 2,
			"benchmark paste staged correct pixel count on trial %d" % trial)
		perf.cancel()
	print("T088_SPARSE_PASTE_BENCH: 512x512, %d nonzero, 7 trials, CPU stage median %d us, samples=%s" % [
		clip._pixels.size(), median(stage_times_us), str(stage_times_us)])
	print("T088_SPARSE_PASTE: %d checks; %d failed" % [checks, failures])
	if failures == 0 and checks >= 56:
		print("T088_SPARSE_PASTE_PASSED (%d checks; 0 failed)" % checks)
	else:
		failures += 1
	quit(1 if failures else 0)
