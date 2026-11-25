extends SceneTree
## T-291: a seed denied by selection cannot enter lazy-source callbacks or
## flatten an otherwise accepted deferred Brush transaction.

const SOURCE: int = 0x00223344
const PAINT: int = 0xffaabbcc
const BRUSH: int = 0xff443322

var checks: int = 0
var failures: int = 0
var fetches: int = 0
var unavailable: bool = false
var blobs: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T291_MASKED_FILL_FAILED: " + label)


func _blob() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 0x44
	bytes[1] = 0x33
	bytes[2] = 0x22
	return bytes


func _fetch(name: String) -> Variant:
	fetches += 1
	if unavailable:
		return null
	return blobs.get(name)


func _run() -> void:
	var document: DrawingDocument = DrawingDocument.new("masked-fill-seed", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	blobs["seed"] = _blob()
	_check(document.register_lazy_chunk(layer, 0, 0, "seed",
		DrawingRasterTile.digest_rgba8(blobs["seed"], 16),
		Callable(self, "_fetch")).ok, "register nonresident seed source")
	var revision: int = document.revision
	var started: DrawingResult = document.begin_edit(layer, revision)
	_check(started.ok, "begin detached edit")
	if not started.ok:
		quit(1)
		return
	var session: DrawingEditSession = started.value as DrawingEditSession
	var path: PackedVector2Array = PackedVector2Array([Vector2(20.5, 2.5)])
	_check(session.paint_path(path, BRUSH, 1.0).ok and session._brush_deferred,
		"accept a deferred Brush in a different tile")
	var count_before: int = session.change_count()
	var before_size: int = session._before.size()
	var after_size: int = session._after.size()
	var source_count: int = session._source_tiles.size()
	_check(count_before > 0 and fetches == 0 and
		not session._source_tiles.has("0,0"),
		"Brush does not resolve the unrelated seed tile")

	var outside: DrawingSelection = DrawingSelection.new(Rect2i(4, 4, 1, 1), true)
	var empty: DrawingSelection = DrawingSelection.new(Rect2i(), true)
	var hole: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 2, 1), true)
	var hole_mask: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	hole.set_mask(hole_mask)
	var inverted: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 1, 1), true)
	inverted.inverted = true
	# Even an unavailable source must not fail a fill that cannot touch it.
	unavailable = true
	var masked_cases: Array[DrawingSelection] = [outside, empty, hole, inverted]
	for index: int in range(masked_cases.size()):
		var mask: DrawingSelection = masked_cases[index]
		_check(not mask.allows(Vector2i.ZERO),
			"mask %d genuinely excludes seed" % index)
		var ignored: DrawingResult = session.flood_fill(Vector2i.ZERO, PAINT, mask, 16)
		_check(ignored.ok, "masked-out fill %d remains a successful no-op" % index)
		_check(fetches == 0 and not session._source_tiles.has("0,0") and
			session._source_tiles.size() == source_count,
			"masked-out fill %d does not call lazy source provider" % index)
		_check(session._brush_deferred and session.change_count() == count_before and
			session._before.size() == before_size and session._after.size() == after_size,
			"masked-out fill %d preserves detached Brush" % index)
		_check(document.revision == revision and
			not document.has_stored_pixel(layer, 0, 0),
			"masked-out fill %d leaves source and revision alone" % index)

	var invalid_color: DrawingResult = session.flood_fill(Vector2i.ZERO, -1, outside)
	_check(not invalid_color.ok and invalid_color.code == "RGBA",
		"invalid color remains rejected even under a rejecting mask")
	var invalid_seed: DrawingResult = session.flood_fill(Vector2i(1073741824, 0),
		PAINT, outside)
	_check(not invalid_seed.ok and invalid_seed.code == "COORD_RANGE",
		"invalid seed remains rejected before selection shortcuts")
	_check(fetches == 0 and session._brush_deferred and
		session.change_count() == count_before,
		"invalid inputs leave lazy source and detached Brush untouched")
	unavailable = false
	var allowed: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 1, 1), true)
	var filled: DrawingResult = session.flood_fill(Vector2i.ZERO, PAINT, allowed, 16)
	_check(filled.ok and fetches == 1 and session._source_tiles.has("0,0"),
		"valid retry resolves the source exactly once")
	_check(document.revision == revision and session.change_count() > count_before,
		"valid fill stages with Brush without publishing early")
	_check(session.commit().ok and document.revision == revision + 1,
		"mixed Brush and fill publish in one native revision")
	_check(int(document.read_pixel(layer, 0, 0).value) == PAINT and
		int(document.read_pixel(layer, 20, 2).value) == BRUSH,
		"mixed transaction commits canonical fill and Brush RGBA8")
	_check(document.undo().ok and
		int(document.read_pixel(layer, 0, 0).value) == SOURCE and
		int(document.read_pixel(layer, 20, 2).value) == 0,
		"native Undo restores hidden RGB and clears Brush")
	_check(document.redo().ok and
		int(document.read_pixel(layer, 0, 0).value) == PAINT and
		int(document.read_pixel(layer, 20, 2).value) == BRUSH,
		"native Redo restores both operations exactly")

	print("T291_MASKED_FILL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
