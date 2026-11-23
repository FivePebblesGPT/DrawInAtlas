extends SceneTree
## T-289: reject invalid flood-fill requests before resolving lazy chunks,
## preview materialization, or changing the edit session's published state.

const OUTSIDE: int = 1073741824
const SOURCE: int = 0x00223344 # Transparent hidden RGB is nonblank.
const PAINT: int = 0xffaabbcc

var checks: int = 0
var failures: int = 0
var fetches: int = 0
var blobs: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T289_FILL_PREFLIGHT_FAILED: " + label)


func _blob() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 0x44
	bytes[1] = 0x33
	bytes[2] = 0x22
	bytes[3] = 0x00
	return bytes


func _fetch(source_name: String) -> Variant:
	fetches += 1
	return blobs.get(source_name)


func _run() -> void:
	var document: DrawingDocument = DrawingDocument.new("fill-preflight", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	blobs["valid"] = _blob()
	blobs["invalid"] = _blob()
	_check(document.register_lazy_chunk(layer, 0, 0, "valid",
		DrawingRasterTile.digest_rgba8(blobs["valid"], 16),
		Callable(self, "_fetch")).ok, "register valid lazy seed")
	# The source at the first invalid positive view-relative pixel is still
	# a valid sparse *global* tile; a rejected gesture must not fetch it.
	_check(document.register_lazy_chunk(layer, 67108864, 0, "invalid",
		DrawingRasterTile.digest_rgba8(blobs["invalid"], 16),
		Callable(self, "_fetch")).ok, "register out-of-gesture-range lazy source")
	var revision: int = document.revision
	var result: DrawingResult = document.begin_edit(layer, revision)
	_check(result.ok, "begin checked raster session")
	if not result.ok:
		quit(1)
		return
	var session: DrawingEditSession = result.value as DrawingEditSession

	for position: Vector2i in [Vector2i(OUTSIDE, 0), Vector2i(-OUTSIDE, 0),
			Vector2i(0, OUTSIDE), Vector2i(0, -OUTSIDE),
			Vector2i(2147483647, 0)]:
		var rejected: DrawingResult = session.flood_fill(position, PAINT)
		_check(not rejected.ok and rejected.code == "COORD_RANGE",
			"invalid view-relative seed is consistently rejected: %s" % position)
		_check(fetches == 0 and session.change_count() == 0 and
				session._source_tiles.is_empty() and document.revision == revision,
			"invalid seed cannot enter the lazy provider or stage pixels: %s" % position)

	for invalid_rgba: int in [-1, 0x100000000]:
		var rejected_color: DrawingResult = session.flood_fill(Vector2i.ZERO, invalid_rgba)
		_check(not rejected_color.ok and rejected_color.code == "RGBA",
			"invalid fill color is rejected before reading source")
		_check(fetches == 0 and session.change_count() == 0 and
				session._source_tiles.is_empty() and document.revision == revision,
			"invalid color cannot fetch a source or affect the session")

	_check(not document.has_stored_pixel(layer, 0, 0) and
		not document.has_stored_pixel(layer, OUTSIDE, 0),
		"rejecting requests does not materialize either lazy source")
	var accepted: DrawingResult = session.flood_fill(Vector2i.ZERO, PAINT, null, 16)
	_check(accepted.ok and session.change_count() == 1 and fetches == 1,
		"valid fill retries in same session, fetching its source once")
	_check(document.revision == revision and
		int(document.read_pixel(layer, 0, 0).value) == SOURCE,
		"valid staged pixel leaves published hidden RGB unchanged")
	_check(session.commit().ok and document.revision == revision + 1 and
		int(document.read_pixel(layer, 0, 0).value) == PAINT,
		"valid fill publishes only the intended source")
	_check(document.undo().ok and
		int(document.read_pixel(layer, 0, 0).value) == SOURCE,
		"native Undo restores exact transparent hidden RGB")
	_check(document.redo().ok and
		int(document.read_pixel(layer, 0, 0).value) == PAINT,
		"native Redo restores the committed fill")

	print("T289_FILL_PREFLIGHT_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
