extends SceneTree
## T-293: native-authoritative fill must fence global signed projection before
## invoking a lazy provider, even when its view-relative seed is legal.

const LIMIT: int = 4503599627370496
const SOURCE: int = 0x00223344
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
		push_error("T293_PROJECTION_FAILED: " + label)


func _fetch(key: String) -> Variant:
	fetches += 1
	return blobs.get(key)


func _source_bytes(seed_local: Vector2i, invalid_local: Vector2i) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	for point: Vector2i in [seed_local, invalid_local]:
		if point.x < 0 or point.y < 0:
			continue
		var offset: int = (point.y * 16 + point.x) * 4
		bytes[offset] = 0x44
		bytes[offset + 1] = 0x33
		bytes[offset + 2] = 0x22
	return bytes


func _case(label: String, axis_x: bool, sign_value: int) -> void:
	fetches = 0
	blobs.clear()
	var document: DrawingDocument = DrawingDocument.new("projection-" + label, 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var last_allowed: int = sign_value * LIMIT
	var anchor: int = sign_value * (LIMIT + 1)
	var tile: int = DrawingDocument.TILES.floor_div(last_allowed, 16)
	var local: int = posmod(last_allowed, 16)
	var source_local: Vector2i = Vector2i(local, 0) if axis_x else Vector2i(0, local)
	var invalid_local: Vector2i = Vector2i(local + 1, 0) if axis_x else Vector2i(0, local + 1)
	if sign_value < 0:
		invalid_local = Vector2i(-1, -1)
	blobs["source"] = _source_bytes(source_local, invalid_local)
	var registered: DrawingResult = document.register_lazy_chunk(
		layer, tile if axis_x else 0, 0 if axis_x else tile,
		"source", DrawingRasterTile.digest_rgba8(blobs["source"], 16),
		Callable(self, "_fetch"))
	_check(registered.ok, label + " registered legal boundary source")
	var revision: int = document.revision
	var started: DrawingResult = document.begin_edit(layer, revision,
		Transform2D.IDENTITY, anchor if axis_x else 0, 0 if axis_x else anchor)
	_check(started.ok, label + " begin legal large-anchor edit")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value as DrawingEditSession
	var rejected: DrawingResult = session.flood_fill(Vector2i.ZERO, PAINT, null, 12)
	_check(not rejected.ok and rejected.code == "COORD_RANGE",
		label + " rejects global projection overflow before lazy source")
	_check(fetches == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0 and document.revision == revision,
		label + " invalid seed has zero lazy or gesture side effects")
	var valid_seed: Vector2i = Vector2i(-sign_value, 0) if axis_x else Vector2i(0, -sign_value)
	var filled: DrawingResult = session.flood_fill(valid_seed, PAINT, null, 12)
	_check(filled.ok, label + " valid edge seed ignores unpublishable neighbor")
	_check(fetches == 1 and session.change_count() == 1,
		label + " valid edge resolves only one source and stages one pixel")
	if not filled.ok:
		session.cancel()
		return
	_check(session.commit().ok and document.revision == revision + 1,
		label + " commits legal edge edit")
	var source_x: int = last_allowed if axis_x else 0
	var source_y: int = 0 if axis_x else last_allowed
	_check(int(document.read_pixel(layer, source_x, source_y).value) == PAINT,
		label + " exact committed RGBA8")
	_check(document.undo().ok and
		int(document.read_pixel(layer, source_x, source_y).value) == SOURCE,
		label + " Undo preserves hidden RGB")
	_check(document.redo().ok and
		int(document.read_pixel(layer, source_x, source_y).value) == PAINT,
		label + " Redo restores native RGBA8")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "native extension is loaded")
	_case("positive-x", true, 1)
	_case("negative-x", true, -1)
	_case("positive-y", false, 1)
	_case("negative-y", false, -1)
	print("T293_PROJECTION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
