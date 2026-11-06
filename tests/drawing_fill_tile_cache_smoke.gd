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
	var published: DrawingResult = edit.commit()
	_check(published.ok and published.delta != null and published.delta.after.size() == 3,
		"exact three-pixel delta committed atomically")
	var exact: bool = true
	for x: int in range(15, 18):
		exact = exact and int(doc.read_pixel(layer, x, 0).value) == NEW
	_check(exact and int(doc.read_pixel(layer, 18, 0).value) == 0,
		"fill does not extend into unallocated clear space")
	_check(doc.undo().ok, "undo exact lazy fill")
	var restored: bool = true
	for x: int in range(15, 18):
		restored = restored and int(doc.read_pixel(layer, x, 0).value) == OLD
	_check(restored, "undo restores hidden RGB and alpha zero across seam")
	_check(doc.redo().ok and int(doc.read_pixel(layer, 17, 0).value) == NEW,
		"redo restores exact published bytes")

	# A selection must constrain the fill without destroying the neighboring
	# linked source pixel; there is no implicit conversion of hidden RGB.
	_check(doc.undo().ok, "restore original bytes before masked fill")
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(15, 0, 2, 1), true)
	var masked: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	_check(masked.flood_fill(Vector2i(15, 0), NEW, mask, 96).ok and
		masked.change_count() == 2, "mask excludes a connected pixel")
	_check(masked.commit().ok, "masked fill commit")
	_check(int(doc.read_pixel(layer, 16, 0).value) == NEW and
		int(doc.read_pixel(layer, 17, 0).value) == OLD,
		"masked fill leaves excluded hidden-RGB source unchanged")

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

	# Tile addressing never converts a signed 64-bit origin through float32.
	var far: DrawingDocument = DrawingDocument.new("far-fill", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var anchor: int = 9007199254740993
	var far_seed: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(far_seed.fill_rect(Rect2i(0, 0, 2, 1), OLD).ok and far_seed.commit().ok,
		"seed far positive/negative signed world coordinates")
	var far_edit: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(far_edit.flood_fill(Vector2i.ZERO, NEW, null, 32).ok and
		far_edit.change_count() == 2 and far_edit.commit().ok,
		"fill crosses a far signed-64-bit tile seam")
	_check(int(far.read_pixel(far_layer, anchor, -anchor).value) == NEW and
		int(far.read_pixel(far_layer, anchor + 1, -anchor).value) == NEW,
		"exact far signed coordinates remain distinct")
	_check(far.undo().ok and int(far.read_pixel(far_layer, anchor, -anchor).value) == OLD,
		"far-world Undo restores original hidden RGB")

	print("T068_FILL_CACHE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
