extends SceneTree
## T-100: independent tile-local publication/history oracle, plus a diagnostic
## full-512 RGBA8 commit. Opt-in CPU threshold is for paired red controls only.

const RED: int = 0xff0000ff
const HIDDEN: int = 0x00ab37c9
const RED_SHA: String = "b8b9b478324141d9331328a2150e74ec5feb266a743a51cab73d903247247ea4"
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T100_SPARSE_PUBLICATION_FAILED: " + label)


func make_doc(label: String, stride: int) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	return {"doc": doc, "layer": layer}


func key_at(point: Vector2i, stride: int) -> String:
	return DrawingDocument.TILES.tile_key64(point.x, point.y, stride)


func offset_at(point: Vector2i, stride: int) -> int:
	var local: Vector2i = DrawingDocument.TILES.local_offset64(point.x, point.y, stride)
	return local.y * stride + local.x


func read_pixel(doc: DrawingDocument, layer: String, point: Vector2i) -> int:
	var key: String = key_at(point, doc.tile_stride)
	var tile: DrawingRasterTile = doc._nodes[layer].tiles.get(key)
	var local: Vector2i = DrawingDocument.TILES.local_offset64(point.x, point.y, doc.tile_stride)
	return tile.get_rgba(local.x, local.y) if tile != null else 0


func seed_source(doc: DrawingDocument, layer: String) -> void:
	var pixels: Dictionary[String, int] = {
		"-1,-1": HIDDEN, "0,0": RED, "1,0": 0x6734ac11,
		"-30,1": 0x90801062, "30,30": 0x80ffff00,
	}
	var old: Dictionary[String, int] = {}
	for coordinate: String in pixels:
		old[coordinate] = 0
	check(doc._publish_edit(layer, doc.revision, old, pixels).ok,
		"seed canonical hidden-RGB and opaque source")


func signed_parity(stride: int) -> void:
	var fast: Dictionary = make_doc("tile-signed-%d" % stride, stride)
	var reference: Dictionary = make_doc("pixel-signed-%d" % stride, stride)
	var doc: DrawingDocument = fast["doc"]
	var ref: DrawingDocument = reference["doc"]
	var layer: String = fast["layer"]
	seed_source(doc, layer)
	seed_source(ref, reference["layer"])
	var points: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(-31, 1), Vector2i(-30, 1), Vector2i(30, 30),
		Vector2i(31, 30), Vector2i(60, -1),
	]
	var colors: Array[int] = [0, HIDDEN, 0x00f0bd7c, 0x909a7162, 0,
		0xb0ff0000, 0x0f377aaa, 0x77eebb42]
	var before: Dictionary[String, int] = {}
	var after: Dictionary[String, int] = {}
	var patches: Dictionary[String, Dictionary] = {}
	var sources: Dictionary[String, Variant] = {}
	var protected: Dictionary[String, DrawingRasterTile] = {}
	for index: int in range(points.size()):
		var point: Vector2i = points[index]
		var global_key: String = "%d,%d" % [point.x, point.y]
		var tile_key: String = key_at(point, stride)
		if not sources.has(tile_key):
			sources[tile_key] = doc._nodes[layer].tiles.get(tile_key)
			if sources[tile_key] != null:
				protected[tile_key] = sources[tile_key]
		var old: int = read_pixel(doc, layer, point)
		check(old != colors[index], "signed case changes rather than repeats source")
		before[global_key] = old
		after[global_key] = colors[index]
		if not patches.has(tile_key):
			patches[tile_key] = {}
		patches[tile_key][offset_at(point, stride)] = colors[index]
	var expected: DrawingResult = ref._publish_edit(reference["layer"], ref.revision,
		before, after)
	var result: DrawingResult = doc._publish_tile_edit(layer, doc.revision, patches, sources)
	check(result.ok and expected.ok, "signed and hidden-RGB tile + pixel publishers accept")
	if not result.ok or not expected.ok:
		return
	check(result.delta.before == expected.delta.before and result.delta.after == expected.delta.after,
		"canonical deltas match pixel-space oracle")
	check(result.regions.size() == expected.regions.size(), "same source dirty-region count")
	for point: Vector2i in points:
		check(read_pixel(doc, layer, point) == read_pixel(ref, reference["layer"], point),
			"source RGBA8 agrees at %s" % point)
	for tile_key: String in protected:
		check(doc._nodes[layer].tiles.get(tile_key) != protected[tile_key],
			"changed tile detached from published ancestor")
		var original_tile: DrawingRasterTile = protected[tile_key]
		var matching_old: DrawingRasterTile = sources[tile_key]
		check(original_tile == matching_old,
			"source object is immutable through publication")
	check(read_pixel(doc, layer, Vector2i(0, 0)) == HIDDEN,
		"nonzero hidden RGB survives alpha-zero replacement")
	check(read_pixel(doc, layer, Vector2i(-1, -1)) == 0,
		"zero RGBA8 erasure removes prior hidden RGB")
	# Caller-owned patch must never become an installed live tile.
	var first_key: String = key_at(points[0], stride)
	patches[first_key][offset_at(points[0], stride)] = RED
	check(read_pixel(doc, layer, points[0]) == 0,
		"post-publication patch mutation cannot change owned pixels")
	check(doc.history_length() == 2 and doc.revision == 3,
		"seed and patch each publish exactly one undo history step")
	check(doc.undo().ok and ref.undo().ok, "signed Undo accepted")
	for point: Vector2i in points:
		check(read_pixel(doc, layer, point) == read_pixel(ref, reference["layer"], point),
			"signed Undo exactly matches reference")
	check(doc.redo().ok and ref.redo().ok, "signed Redo accepted")
	for point: Vector2i in points:
		check(read_pixel(doc, layer, point) == read_pixel(ref, reference["layer"], point),
			"signed Redo exactly matches reference")


func failure_atomicity() -> void:
	var target: Dictionary = make_doc("atomic", 16)
	var doc: DrawingDocument = target["doc"]
	var layer: String = target["layer"]
	var other: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Unchanged").value)
	var unrelated: DrawingEditSession = doc.begin_edit(other, doc.revision,
		Transform2D.IDENTITY, 0, 0).value
	check(unrelated.fill_rect(Rect2i(0, 0, 3, 3), HIDDEN).ok and
		unrelated.commit().ok, "independent layer seeded with alpha-zero hidden RGB")
	var unrelated_tile: DrawingRasterTile = doc._nodes[other].tiles["0,0"]
	var patches: Dictionary[String, Dictionary] = {
		"-1,-1": {0: RED}, "1,0": {0: HIDDEN},
	}
	var sources: Dictionary[String, Variant] = {"-1,-1": null, "1,0": null}
	var revision_before: int = doc.revision
	var history_before: int = doc.history_length()
	patches["1,0"][-1] = RED
	var failed: DrawingResult = doc._publish_tile_edit(layer, doc.revision, patches, sources)
	check(not failed.ok and failed.code == "COORD", "bad late tile offset rejects")
	check(doc.revision == revision_before and doc.history_length() == history_before and
		doc.tile_keys(layer).is_empty(), "late failure installs no earlier prepared tile")
	patches["1,0"].erase(-1)
	failed = doc._publish_tile_edit(layer, doc.revision - 1, patches, sources)
	check(not failed.ok and failed.code == "STALE_REVISION", "stale expected revision fails")
	failed = doc._publish_tile_edit(layer, doc.revision, {"3,0": {0: RED}}, sources)
	check(not failed.ok and failed.code == "STALE_PIXEL", "unverified source fails")
	patches["1,0"][0] = 0x100000000
	failed = doc._publish_tile_edit(layer, doc.revision, patches, sources)
	check(not failed.ok and failed.code == "RGBA", "invalid late RGBA8 rejects")
	check(doc.tile_keys(layer).is_empty() and doc.history_length() == history_before,
		"all rejected attempts remain atomic")
	check(doc._nodes[other].tiles["0,0"] == unrelated_tile and
		read_pixel(doc, other, Vector2i(0, 0)) == HIDDEN,
		"late failure leaves independent layer byte/identity unchanged")
	patches["1,0"][0] = HIDDEN
	var accepted: DrawingResult = doc._publish_tile_edit(layer, doc.revision, patches, sources)
	check(accepted.ok and accepted.delta.after.size() == 2,
		"valid retry after failure commits both source tiles")
	check(doc.history_length() == history_before + 1 and doc.undo().ok and
		read_pixel(doc, layer, Vector2i(-16, -16)) == 0 and doc.redo().ok and
		read_pixel(doc, layer, Vector2i(-16, -16)) == RED,
		"retry preserves one reversible atomic edit")
	check(doc._nodes[other].tiles["0,0"] == unrelated_tile and
		read_pixel(doc, other, Vector2i(0, 0)) == HIDDEN,
		"retry and Undo/Redo leave unrelated layer unchanged")
	var old_tile: DrawingRasterTile = doc._nodes[layer].tiles["-1,-1"]
	var same_bytes_new_identity: DrawingRasterTile = old_tile.detached_copy()
	doc._nodes[layer].tiles["-1,-1"] = same_bytes_new_identity
	failed = doc._publish_tile_edit(layer, doc.revision,
		{"-1,-1": {0: HIDDEN}}, {"-1,-1": old_tile})
	check(not failed.ok and failed.code == "STALE_PIXEL" and
		doc._nodes[layer].tiles["-1,-1"] == same_bytes_new_identity,
		"same-byte source identity replacement fails without overwriting")


func signed_mask_brush_and_cancellation() -> void:
	var origin: Vector2i = Vector2i(2147483663, -2147483711)
	var area: Rect2i = Rect2i(-64, -64, 128, 128)
	var mask: DrawingSelection = DrawingSelection.new(area, true)
	check(mask.combine_rectangle(Rect2i(-5, -5, 10, 10), "Subtract"),
		"signed mask removes a centered hole")
	for erase: bool in [false, true]:
		var fast: Dictionary = make_doc("signed-mask-tile-%s" % erase, 30)
		var reference: Dictionary = make_doc("signed-mask-pixel-%s" % erase, 30)
		var doc: DrawingDocument = fast["doc"]
		var ref: DrawingDocument = reference["doc"]
		var layer: String = fast["layer"]
		var path: PackedVector2Array = PackedVector2Array([
			Vector2(-42.5, -35.5), Vector2(-8.5, 12.5), Vector2(36.5, 43.5)])
		if erase:
			var seed_fast: DrawingEditSession = doc.begin_edit(layer, doc.revision,
				Transform2D.IDENTITY, origin.x, origin.y).value
			var seed_slow: DrawingEditSession = ref.begin_edit(reference["layer"], ref.revision,
				Transform2D.IDENTITY, origin.x, origin.y).value
			seed_slow._brush_tile_publish = false
			check(seed_fast.paint_path(path, RED, 30.0, false, mask, 1048576, area).ok
				and seed_slow.paint_path(path, RED, 30.0, false, mask, 1048576, area).ok,
				"opaque pre-paint prepares erasable source")
			check(seed_fast.commit().ok and seed_slow.commit().ok,
				"opaque masked pre-paint committed on both paths")
		var fast_edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, origin.x, origin.y).value
		var slow_edit: DrawingEditSession = ref.begin_edit(reference["layer"], ref.revision,
			Transform2D.IDENTITY, origin.x, origin.y).value
		slow_edit._brush_tile_publish = false
		check(fast_edit.paint_path(path, 0xffa2314b, 30.0, erase, mask,
			1048576, area).ok and slow_edit.paint_path(path, 0xffa2314b, 30.0,
			erase, mask, 1048576, area).ok,
			"signed masked Brush/Eraser stages on both paths")
		var fast_preview: DrawingResult = DrawingRenderer.render(doc, area,
			origin.x, origin.y, 128 * 128, fast_edit)
		var slow_preview: DrawingResult = DrawingRenderer.render(ref, area,
			origin.x, origin.y, 128 * 128, slow_edit)
		check(fast_preview.ok and slow_preview.ok and
			fast_preview.value.get_data() == slow_preview.value.get_data(),
			"signed masked preview matches independent pixel publisher")
		var fast_result: DrawingResult = fast_edit.commit()
		var slow_result: DrawingResult = slow_edit.commit()
		check(fast_result.ok and slow_result.ok and
			fast_result.delta.before == slow_result.delta.before and
			fast_result.delta.after == slow_result.delta.after,
			"signed masked Brush/Eraser exact canonical history")
		var fast_source: DrawingResult = DrawingRenderer.render(doc, area,
			origin.x, origin.y, 128 * 128)
		var slow_source: DrawingResult = DrawingRenderer.render(ref, area,
			origin.x, origin.y, 128 * 128)
		check(fast_source.ok and slow_source.ok and
			fast_source.value.get_data() == slow_source.value.get_data() and
			fast_source.value.get_data() == fast_preview.value.get_data(),
			"source RGBA8 matches masked staged preview after commit")
		check(doc.undo().ok and ref.undo().ok, "masked Undo succeeds")
		check(doc.redo().ok and ref.redo().ok, "masked Redo succeeds")
		var cancelled: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, origin.x, origin.y).value
		var prior_revision: int = doc.revision
		var prior_history: int = doc.history_length()
		check(cancelled.paint_path(PackedVector2Array([Vector2(-20.5, -15.5)]),
			0xff23cc77, 18.0).ok, "cancel test stages further held preview")
		cancelled.cancel()
		check(doc.revision == prior_revision and doc.history_length() == prior_history,
			"cancel publishes no source tile or history")
		check(DrawingRenderer.render(doc, area, origin.x, origin.y,
			128 * 128).value.get_data() == fast_source.value.get_data(),
			"cancel restores source and leaves prior Undo/Redo intact")


func public_delta_defensive_copy() -> void:
	var originals: Dictionary[String, int] = {"-1,0": HIDDEN}
	var replacements: Dictionary[String, int] = {"-1,0": RED}
	var delta: DrawingDelta = DrawingDelta.new("ink", originals, replacements)
	originals["-1,0"] = RED
	replacements.clear()
	check(delta.before["-1,0"] == HIDDEN and delta.after["-1,0"] == RED,
		"public DrawingDelta construction still copies caller-owned dictionaries")


func dense_full_red() -> void:
	var target: Dictionary = make_doc("dense-red", 256)
	var doc: DrawingDocument = target["doc"]
	var layer: String = target["layer"]
	var patches: Dictionary[String, Dictionary] = {}
	var sources: Dictionary[String, Variant] = {}
	for cy: int in range(2):
		for cx: int in range(2):
			var tile_key: String = "%d,%d" % [cx, cy]
			var patch: Dictionary = {}
			for offset: int in range(256 * 256):
				patch[offset] = RED
			patches[tile_key] = patch
			sources[tile_key] = null
	var begin_static: int = OS.get_static_memory_usage()
	var begin_peak: int = OS.get_static_memory_peak_usage()
	var before_us: int = Time.get_ticks_usec()
	var result: DrawingResult = doc._publish_tile_edit(layer, doc.revision, patches, sources)
	var commit_ms: float = float(Time.get_ticks_usec() - before_us) / 1000.0
	var after_static: int = OS.get_static_memory_usage()
	var after_peak: int = OS.get_static_memory_peak_usage()
	check(result.ok and result.delta.after.size() == 262144 and
		result.delta.before.size() == 262144, "all 262144 red pixels have canonical history")
	check(doc.revision == 2 and doc.history_length() == 1,
		"full-512 publication commits atomically once")
	for cy: int in range(2):
		for cx: int in range(2):
			var tile: DrawingRasterTile = doc._nodes[layer].tiles["%d,%d" % [cx, cy]]
			var digest: HashingContext = HashingContext.new()
			check(digest.start(HashingContext.HASH_SHA256) == OK,
				"SHA-256 starts for source tile")
			digest.update(tile.to_rgba8())
			check(tile.pixel_count() == 65536 and digest.finish().hex_encode() == RED_SHA,
				"independent complete 256px source-tile RGBA8 digest %d,%d" % [cx, cy])
	check(doc.undo().ok and doc.tile_keys(layer).is_empty(),
		"full red Undo restores sparse empty source")
	check(doc.redo().ok and doc.tile_keys(layer).size() == 4,
		"full red Redo restores four source chunks")
	print("T100_SPARSE_PUBLICATION_RUN commit_cpu_ms=%.3f pixels=262144 " % commit_ms +
		"canonical_delta_entries=524288 source_clone_rgba8_bytes=0 " +
		"static_before=%d static_after=%d peak_before=%d peak_after=%d" % [
		begin_static, after_static, begin_peak, after_peak])
	var threshold: String = OS.get_environment("T100_MAX_COMMIT_MS")
	if not threshold.is_empty():
		check(threshold.is_valid_float() and float(threshold) > 0.0 and
			commit_ms <= float(threshold),
			"opt-in diagnostic publication threshold of %s ms, got %.3f ms" % [
				threshold, commit_ms])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	public_delta_defensive_copy()
	for stride: int in [16, 30, 256]:
		signed_parity(stride)
	failure_atomicity()
	signed_mask_brush_and_cancellation()
	dense_full_red()
	if failures == 0:
		print("T100_SPARSE_PUBLICATION_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T100_SPARSE_PUBLICATION_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
