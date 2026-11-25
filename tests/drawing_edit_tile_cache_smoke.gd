extends SceneTree
## T-068: session-local source-tile cache must preserve read failures, exact
## straight-RGBA8, rollback and stale-revision semantics.

var checks: int = 0
var failures: int = 0
var _lazy_bytes: PackedByteArray = PackedByteArray()
var _lazy_available: bool = false
var _lazy_corrupt: bool = false
var _lazy_calls: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T068_TILE_CACHE_FAILED: " + label)


func _read_pixels(document: DrawingDocument, layer: String,
		bounds: Rect2i) -> Dictionary[Vector2i, int]:
	var pixels: Dictionary[Vector2i, int] = {}
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel: DrawingResult = document.read_pixel(layer, x, y)
			if not pixel.ok:
				return {}
			pixels[Vector2i(x, y)] = int(pixel.value)
	return pixels


func _lazy_fetch(_ref: String) -> Variant:
	_lazy_calls += 1
	if not _lazy_available:
		return null
	if _lazy_corrupt:
		return PackedByteArray([1, 2, 3, 4])
	return _lazy_bytes


func _run() -> void:
	var document: DrawingDocument = DrawingDocument.new("cache-seams", 16)
	var layer_result: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	_check(layer_result.ok, "create raster source")
	var layer: String = String(layer_result.value)
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision).value
	var source_bytes: PackedByteArray = PackedByteArray()
	source_bytes.resize(4 * 4 * 4)
	for index: int in range(16):
		source_bytes[index * 4] = 20 + index
		source_bytes[index * 4 + 1] = index * 4
		source_bytes[index * 4 + 2] = 60
		source_bytes[index * 4 + 3] = 0 if index % 3 == 0 else 100
	_check(seed.apply_region(Rect2i(-2, -2, 4, 4), source_bytes).ok and seed.commit().ok,
		"seed exact source pixels across four signed tiles")
	var original: int = int(document.read_pixel(layer, -1, -1).value)
	var source_revision: int = document.revision
	var sampled_bounds: Rect2i = Rect2i(-8, -8, 16, 16)
	var source_pixels: Dictionary[Vector2i, int] = _read_pixels(document, layer, sampled_bounds)
	_check(source_pixels.size() == sampled_bounds.get_area(),
		"snapshot source pixels across the native tile boundary")
	var edit: DrawingEditSession = document.begin_edit(layer, source_revision).value
	var stroke: PackedVector2Array = PackedVector2Array([Vector2(-0.5, -0.5),
		Vector2(-0.5, -0.5)])
	_check(edit.paint_path(stroke, 0x80808042, 8.0).ok, "stage overlapping 8px dab")
	_check(edit._source_tiles.size() == 4, "resolve four source tiles once per transaction")
	var count: int = edit.change_count()
	_check(count > 0 and edit.paint_path(stroke, 0x80808042, 8.0).ok \
		and edit.change_count() == count, "repeat stroke retains once-per-pixel semantics")
	_check(document.revision == source_revision and
		_read_pixels(document, layer, sampled_bounds) == source_pixels,
		"staging leaves all source pixels and the revision unchanged")
	var changed: DrawingResult = edit.commit()
	_check(changed.ok and document.revision == source_revision + 1,
		"native commit publishes exactly one source revision")
	var published_pixels: Dictionary[Vector2i, int] = _read_pixels(document, layer, sampled_bounds)
	var changed_pixels: int = 0
	for point: Vector2i in source_pixels:
		if source_pixels[point] != published_pixels.get(point, -1):
			changed_pixels += 1
	_check(published_pixels.size() == source_pixels.size() and changed_pixels == count,
		"native committed pixels match the exact staged touched-pixel count")
	_check(edit._source_tiles.is_empty(), "commit clears source cache references")
	_check(int(document.read_pixel(layer, -1, -1).value) == \
		DrawingEditSession._blend(0x80808042, original), "straight-alpha blend exact")
	_check(document.undo().ok and _read_pixels(document, layer, sampled_bounds) == source_pixels,
		"undo restores all pre-cache source pixels including hidden RGB")
	_check(document.redo().ok and _read_pixels(document, layer, sampled_bounds) == published_pixels,
		"redo reapplies exact committed RGBA8 over all cached tiles")

	var blank: DrawingDocument = DrawingDocument.new("null-source", 16)
	var blank_layer: String = String(blank.create_layer(DrawingLayerNode.RASTER, "Blank").value)
	var blank_revision: int = blank.revision
	var no_op: DrawingEditSession = blank.begin_edit(blank_layer, blank_revision).value
	_check(no_op.fill_rect(Rect2i(0, 0, 5, 5), 0).ok,
		"fill of absent transparent tile is harmless")
	_check(no_op._source_tiles.size() == 1 and no_op._source_tiles.values()[0] == null,
		"cache successful absence of tile without fabricating pixels")
	_check(not no_op.commit().ok and blank.revision == blank_revision and
		no_op._source_tiles.is_empty(), "no-op commit leaves source unchanged and releases cache")

	var lazy: DrawingDocument = DrawingDocument.new("lazy-source", 16)
	var lazy_layer: String = String(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	_lazy_bytes.resize(16 * 16 * 4)
	_lazy_bytes[0] = 33
	_lazy_bytes[1] = 44
	_lazy_bytes[2] = 55
	_lazy_bytes[3] = 66
	var digest: String = DrawingRasterTile.digest_rgba8(_lazy_bytes, 16)
	_check(lazy.register_lazy_chunk(lazy_layer, 0, 0, "tile-source", digest,
		Callable(self, "_lazy_fetch")).ok, "register digest-protected lazy tile")
	var lazy_revision: int = lazy.revision
	var lazy_edit: DrawingEditSession = lazy.begin_edit(lazy_layer, lazy_revision).value
	var sample: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.5)])
	_check(not lazy_edit.paint_path(sample, 0xff554433, 1.0).ok and
		lazy_edit.change_count() == 0 and lazy_edit._source_tiles.is_empty(),
		"missing referenced tile is not silently treated as transparent")
	_lazy_available = true
	_lazy_corrupt = true
	_check(not lazy_edit.paint_path(sample, 0xff554433, 1.0).ok and
		lazy_edit._source_tiles.is_empty(), "invalid lazy bytes are never cached")
	_lazy_corrupt = false
	_check(lazy_edit.paint_path(sample, 0xff554433, 1.0).ok and
		lazy_edit.change_count() == 1, "repaired source can be loaded and edited")
	var calls_after_load: int = _lazy_calls
	_check(lazy_edit.paint_path(sample, 0xff554433, 1.0).ok and
		_lazy_calls == calls_after_load, "successful lazy resolve is reused")
	_check(lazy_edit.commit().ok and lazy.read_pixel(lazy_layer, 0, 0).ok,
		"lazy source commit succeeds only after verified load")

	# Failed brush staging may have touched valid tiles before discovering a
	# missing source tile; the whole gesture must rollback and remain retryable.
	var broken: DrawingDocument = DrawingDocument.new("partial-failure", 16)
	var broken_layer: String = String(broken.create_layer(DrawingLayerNode.RASTER, "Broken").value)
	_lazy_available = false
	_lazy_calls = 0
	_check(broken.register_lazy_chunk(broken_layer, 1, 0, "tile-source", digest,
		Callable(self, "_lazy_fetch")).ok, "register second lazy tile")
	var broken_revision: int = broken.revision
	var partial: DrawingEditSession = broken.begin_edit(broken_layer, broken_revision).value
	var crossing: PackedVector2Array = PackedVector2Array([Vector2(14.5, 0.5), Vector2(17.5, 0.5)])
	_check(not partial.paint_path(crossing, 0xff123456, 1.0).ok and
		partial.change_count() == 0 and broken.revision == broken_revision,
		"mid-gesture source failure rolls back staged pixels")
	_lazy_available = true
	_check(partial.paint_path(crossing, 0xff123456, 1.0).ok and
		partial.commit().ok and broken.revision == broken_revision + 1,
		"same gesture can retry after loading source")
	_check(int(broken.read_pixel(broken_layer, 14, 0).value) == 0xff123456 and
		int(broken.read_pixel(broken_layer, 17, 0).value) == 0xff123456,
		"retry spans both tile boundaries without holes")

	var stale: DrawingDocument = DrawingDocument.new("stale-session", 16)
	var stale_layer: String = String(stale.create_layer(DrawingLayerNode.RASTER, "Stale").value)
	var first: DrawingEditSession = stale.begin_edit(stale_layer, stale.revision).value
	var other: DrawingEditSession = stale.begin_edit(stale_layer, stale.revision).value
	_check(first.paint_path(sample, 0xff102030, 2.0).ok and
		other.paint_path(sample, 0xff405060, 2.0).ok, "start two competing transactions")
	_check(other.commit().ok and not first.commit().ok and first._source_tiles.is_empty(),
		"revision conflict rejects old cache and releases references")
	_check(int(stale.read_pixel(stale_layer, 0, 0).value) == 0xff405060,
		"conflict retains only winning transaction")

	var cancelled_revision: int = stale.revision
	var cancelled: DrawingEditSession = stale.begin_edit(stale_layer, cancelled_revision).value
	_check(cancelled.paint_path(PackedVector2Array([Vector2(7.5, 7.5)]),
		0xaa987654, 3.0).ok and not cancelled._source_tiles.is_empty(),
		"cancelled gesture may read a cached source")
	cancelled.cancel()
	_check(cancelled._source_tiles.is_empty() and not cancelled.commit().ok
		and stale.revision == cancelled_revision and
		int(stale.read_pixel(stale_layer, 7, 7).value) == 0,
		"cancel releases references without modifying document or history")

	var far: DrawingDocument = DrawingDocument.new("signed-anchor", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var unsafe_anchor: int = 9007199254740993
	var far_revision: int = far.revision
	var unsafe_start: DrawingResult = far.begin_edit(far_layer, far_revision,
		Transform2D.IDENTITY, unsafe_anchor, -unsafe_anchor)
	_check(unsafe_start.ok, "public gesture retains legacy wide signed anchor scope")
	if unsafe_start.ok:
		var unsafe_edit: DrawingEditSession = unsafe_start.value as DrawingEditSession
		var unsafe_stage: DrawingResult = unsafe_edit.paint_path(
			PackedVector2Array([Vector2(-0.5, -0.5)]), 0xaa112233, 3.0)
		var unsafe_commit: DrawingResult = unsafe_edit.commit() if unsafe_stage.ok else unsafe_stage
		_check(not unsafe_commit.ok and far.revision == far_revision and
			int(far.read_pixel(far_layer, unsafe_anchor - 1, -unsafe_anchor - 1).value) == 0,
			"out-of-projection native publication rejects without source mutation")
		unsafe_edit.cancel()
	var anchor: int = 1125899906842625
	var far_start: DrawingResult = far.begin_edit(far_layer, far_revision,
		Transform2D.IDENTITY, anchor, -anchor)
	_check(far_start.ok, "legal large signed anchor opens a native edit")
	if far_start.ok:
		var far_edit: DrawingEditSession = far_start.value as DrawingEditSession
		_check(far_edit.paint_path(PackedVector2Array([Vector2(-0.5, -0.5)]),
			0xaa112233, 3.0).ok and far_edit.commit().ok and far.revision == far_revision + 1,
			"legal signed anchor publishes exact RGBA8 through native tiles")
		_check(int(far.read_pixel(far_layer, anchor - 1, -anchor - 1).value) == 0xaa112233,
			"far signed pixel remains exact")
		_check(far.undo().ok and int(far.read_pixel(far_layer,
			anchor - 1, -anchor - 1).value) == 0,
			"far signed undo restores original transparent pixel")
		_check(far.redo().ok and int(far.read_pixel(far_layer,
			anchor - 1, -anchor - 1).value) == 0xaa112233,
			"far signed redo restores the exact committed pixel")

	print("T068_TILE_CACHE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
