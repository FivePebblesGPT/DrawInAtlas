extends SceneTree
## T-068: fill source reads must be verified, cached and exact, including lazy
## transparent-RGB tiles, rollback, masks and signed 64-bit coordinates.

const OLD: int = 0x00665544
const NEW: int = 0xffddccbb

var checks: int = 0
var failures: int = 0
var blobs: Dictionary = {}
var unavailable: Dictionary = {}
var corrupt: Dictionary = {}
var fetches: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_FILL_CACHE_FAILED: " + name)


func _bytes_at(tile_x: int, tiles: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	for x: int in range(tiles):
		var offset: int = (tile_x + x) * 4
		bytes[offset] = 0x44
		bytes[offset + 1] = 0x55
		bytes[offset + 2] = 0x66
		bytes[offset + 3] = 0
	return bytes


func _fetch(name: String) -> Variant:
	fetches[name] = int(fetches.get(name, 0)) + 1
	if bool(unavailable.get(name, false)):
		return null
	if bool(corrupt.get(name, false)):
		return PackedByteArray([1, 2, 3, 4])
	return blobs.get(name, null)


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


func _run() -> void:
	var blank: DrawingDocument = DrawingDocument.new("blank", 16)
	var empty_layer: String = String(blank.create_layer(DrawingLayerNode.RASTER, "Empty").value)
	var empty: DrawingEditSession = blank.begin_edit(empty_layer, blank.revision).value
	var empty_result: DrawingResult = empty.flood_fill(Vector2i.ZERO, NEW)
	_check(not empty_result.ok and empty_result.code == "BLANK_SEED" and
		empty.change_count() == 0, "unallocated transparent seed is unfillable")
	_check(empty._source_tiles.has("0,0") and empty._source_tiles["0,0"] == null,
		"absent tile is cached without inventing stored pixels")
	var blank_revision: int = blank.revision
	empty.cancel()
	_check(blank.revision == blank_revision and empty._source_tiles.is_empty(),
		"blank fill cancellation releases source references")

	# Both tiles exist only as verified saved blobs: resident lookup returns false
	# until loading. They join at the exact x=15/16 signed tile seam.
	var doc: DrawingDocument = DrawingDocument.new("lazy-fill", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	blobs["left"] = _bytes_at(15, 1)
	blobs["right"] = _bytes_at(0, 2)
	_check(doc.register_lazy_chunk(layer, 0, 0, "left",
		DrawingRasterTile.digest_rgba8(blobs["left"], 16), Callable(self, "_fetch")).ok,
		"register first signed tile")
	_check(doc.register_lazy_chunk(layer, 1, 0, "right",
		DrawingRasterTile.digest_rgba8(blobs["right"], 16), Callable(self, "_fetch")).ok,
		"register second signed tile")
	_check(not doc.has_stored_pixel(layer, 15, 0),
		"lazy seed is not resident before fill")
	var saved_revision: int = doc.revision
	var edit: DrawingEditSession = doc.begin_edit(layer, saved_revision).value
	unavailable["right"] = true
	var missing: DrawingResult = edit.flood_fill(Vector2i(15, 0), NEW, null, 96)
	_check(not missing.ok and missing.code == "MISSING_TILE",
		"unavailable adjacent lazy tile fails closed")
	_check(edit.change_count() == 0 and doc.revision == saved_revision,
		"failed lazy read rolls back all staged data")
	_check(int(fetches.get("left", 0)) == 1 and int(fetches.get("right", 0)) == 1,
		"source tile is resolved once and missing tile is not cached")
	unavailable.erase("right")
	corrupt["right"] = true
	var damaged: DrawingResult = edit.flood_fill(Vector2i(15, 0), NEW, null, 96)
	_check(not damaged.ok and damaged.code == "CORRUPT_TILE" and
		edit.change_count() == 0, "hash/size-invalid bytes cannot be filled")
	corrupt.erase("right")
	var retried: DrawingResult = edit.flood_fill(Vector2i(15, 0), NEW, null, 96)
	_check(retried.ok and edit.change_count() == 3,
		"successful retry finds three connected hidden-RGB pixels across lazy seam")
	_check(int(fetches.get("left", 0)) == 1 and int(fetches.get("right", 0)) == 3,
		"valid tile remains cached, failed resolves are retried")
	_check(doc.revision == saved_revision and int(doc.read_pixel(layer, 15, 0).value) == OLD,
		"staging never changes published transparent RGB")
	var bounds: Rect2i = Rect2i(14, -1, 6, 3)
	var source_pixels: Dictionary[Vector2i, int] = _read_pixels(doc, layer, bounds)
	_check(source_pixels.size() == bounds.get_area() and
		source_pixels.get(Vector2i(15, 0), -1) == OLD and
		source_pixels.get(Vector2i(16, 0), -1) == OLD and
		source_pixels.get(Vector2i(17, 0), -1) == OLD and
		source_pixels.get(Vector2i(18, 0), -1) == 0,
		"snapshot exact hidden-RGB seed and adjacent clear border")
	var expected_pixels: Dictionary[Vector2i, int] = source_pixels.duplicate()
	for x: int in range(15, 18):
		expected_pixels[Vector2i(x, 0)] = NEW
	var published: DrawingResult = edit.commit()
	_check(published.ok and doc.revision == saved_revision + 1,
		"three-pixel fill commits one native revision atomically")
	_check(_read_pixels(doc, layer, bounds) == expected_pixels,
		"committed region exactly changes only three pixels across lazy seam")
	_check(doc.undo().ok and _read_pixels(doc, layer, bounds) == source_pixels,
		"undo restores every source pixel and hidden RGB across seam")
	_check(doc.redo().ok and _read_pixels(doc, layer, bounds) == expected_pixels,
		"redo restores exact full-region published bytes")

	# A selection must constrain the fill without destroying the neighboring
	# linked source pixel; there is no implicit conversion of hidden RGB.
	_check(doc.undo().ok, "restore original bytes before masked fill")
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(15, 0, 2, 1), true)
	var masked: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	_check(masked.flood_fill(Vector2i(15, 0), NEW, mask, 96).ok and
		masked.change_count() == 2, "mask excludes a connected pixel")
	var mask_source: Dictionary[Vector2i, int] = _read_pixels(doc, layer, bounds)
	var mask_expected: Dictionary[Vector2i, int] = mask_source.duplicate()
	mask_expected[Vector2i(15, 0)] = NEW
	mask_expected[Vector2i(16, 0)] = NEW
	_check(masked.commit().ok, "masked fill commit")
	_check(_read_pixels(doc, layer, bounds) == mask_expected,
		"mask changes only two connected pixels, retaining excluded hidden RGB")
	_check(doc.undo().ok and _read_pixels(doc, layer, bounds) == mask_source,
		"masked fill Undo restores the entire region")
	_check(doc.redo().ok and _read_pixels(doc, layer, bounds) == mask_expected,
		"masked fill Redo preserves exact mask boundary")

	# Candidate budget rolls back the entire gesture, not just the last batch.
	var budget: DrawingDocument = DrawingDocument.new("fill-budget", 16)
	var budget_layer: String = String(budget.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var seed: DrawingEditSession = budget.begin_edit(budget_layer, budget.revision).value
	_check(seed.fill_rect(Rect2i(1, 1, 8, 8), OLD).ok and seed.commit().ok,
		"seed connected 64-pixel region")
	var budget_revision: int = budget.revision
	var limited: DrawingEditSession = budget.begin_edit(budget_layer, budget_revision).value
	var too_small: DrawingResult = limited.flood_fill(Vector2i(2, 2), NEW, null, 4)
	_check(not too_small.ok and too_small.code == "FILL_LIMIT" and
		limited.change_count() == 0 and budget.revision == budget_revision,
		"fill budget rejects all partial changes")
	_check(limited.flood_fill(Vector2i(2, 2), NEW, null, 512).ok and
		limited.change_count() == 64 and limited.commit().ok,
		"same edit can retry with larger budget")
	_check(budget.undo().ok and int(budget.read_pixel(budget_layer, 2, 2).value) == OLD,
		"retry still uses ordinary Undo history")

	# The public session can stage wider signed anchors than the native tile
	# projection can publish. Rejection must not mutate source or history.
	var far: DrawingDocument = DrawingDocument.new("far-fill", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var unsafe_anchor: int = 9007199254740993
	var far_revision: int = far.revision
	var unsafe: DrawingResult = far.begin_edit(far_layer, far_revision,
		Transform2D.IDENTITY, unsafe_anchor, -unsafe_anchor)
	_check(unsafe.ok, "wide signed anchor remains valid for a public edit")
	if unsafe.ok:
		var unsafe_edit: DrawingEditSession = unsafe.value as DrawingEditSession
		var unsafe_stage: DrawingResult = unsafe_edit.fill_rect(Rect2i(-2, 0, 3, 1), OLD)
		_check(unsafe_stage.ok and unsafe_edit.change_count() == 3,
			"unsafe signed gesture stages three candidate pixels")
		var unsafe_commit: DrawingResult = unsafe_edit.commit() if unsafe_stage.ok else unsafe_stage
		var unchanged_unsafe: bool = true
		for offset: int in range(-2, 1):
			unchanged_unsafe = unchanged_unsafe and int(far.read_pixel(far_layer,
				unsafe_anchor + offset, -unsafe_anchor).value) == 0
		_check(not unsafe_commit.ok and far.revision == far_revision and unchanged_unsafe,
			"unsafe native publication rejects without source or revision mutation")
		unsafe_edit.cancel()

	# The exact large signed anchor has nonzero low bits and crosses the
	# x=tile_size-1 / x=0 source tile seam at the local -2/-1 boundary.
	var anchor: int = 1125899906842625
	var far_seed: DrawingEditSession = far.begin_edit(far_layer, far_revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(far_seed.fill_rect(Rect2i(-2, 0, 3, 1), OLD).ok and far_seed.commit().ok,
		"seed exact hidden RGB across a legal large signed tile seam")
	var signed_seed_revision: int = far.revision
	var far_edit: DrawingEditSession = far.begin_edit(far_layer, signed_seed_revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(far_edit.flood_fill(Vector2i(-2, 0), NEW, null, 32).ok and
		far_edit.change_count() == 3 and far.revision == signed_seed_revision,
		"fill stages exactly three far-signed seam pixels without publication")
	_check(far_edit.commit().ok and far.revision == signed_seed_revision + 1,
		"far signed fill publishes a single native revision")
	var exact_far: bool = true
	for offset: int in range(-3, 2):
		var expected: int = NEW if offset >= -2 and offset <= 0 else 0
		exact_far = exact_far and int(far.read_pixel(far_layer,
			anchor + offset, -anchor).value) == expected
	_check(exact_far, "far signed fill changes only the intended three pixels")
	_check(far.undo().ok, "far-world undo succeeds")
	var restored_far: bool = true
	for offset: int in range(-3, 2):
		var expected: int = OLD if offset >= -2 and offset <= 0 else 0
		restored_far = restored_far and int(far.read_pixel(far_layer,
			anchor + offset, -anchor).value) == expected
	_check(restored_far, "far-world undo restores every hidden-RGB source pixel")
	_check(far.redo().ok, "far-world redo succeeds")
	var redone_far: bool = true
	for offset: int in range(-3, 2):
		var expected: int = NEW if offset >= -2 and offset <= 0 else 0
		redone_far = redone_far and int(far.read_pixel(far_layer,
			anchor + offset, -anchor).value) == expected
	_check(redone_far, "far-world redo restores all three pixels and seam guards")

	print("T068_FILL_CACHE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
