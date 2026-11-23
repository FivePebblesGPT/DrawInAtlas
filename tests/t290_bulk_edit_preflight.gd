extends SceneTree
## T-290: invalid bulk-edit requests must not touch lazy sources or transform
## an already accepted detached Brush into its global-pixel representation.

const EDGE: int = 1073741823
const HIDDEN: int = 0x00223344
const PAINT: int = 0xffaabbcc

var checks: int = 0
var failures: int = 0
var calls: int = 0
var sources: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T290_BULK_PREFLIGHT_FAILED: " + label)


func _bytes() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 0x44
	bytes[1] = 0x33
	bytes[2] = 0x22
	return bytes


func _fetch(source_name: String) -> Variant:
	calls += 1
	return sources.get(source_name)


func _run() -> void:
	var document: DrawingDocument = DrawingDocument.new("bulk-preflight", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	sources["edge"] = _bytes()
	sources["origin"] = _bytes()
	_check(document.register_lazy_chunk(layer, 67108863, 0, "edge",
		DrawingRasterTile.digest_rgba8(sources["edge"], 16),
		Callable(self, "_fetch")).ok, "register lazy source before invalid right edge")
	_check(document.register_lazy_chunk(layer, 0, 0, "origin",
		DrawingRasterTile.digest_rgba8(sources["origin"], 16),
		Callable(self, "_fetch")).ok, "register valid lazy origin")
	var revision: int = document.revision
	var started: DrawingResult = document.begin_edit(layer, revision)
	_check(started.ok, "begin edit")
	if not started.ok:
		quit(1)
		return
	var session: DrawingEditSession = started.value as DrawingEditSession
	var invalid_area: Rect2i = Rect2i(EDGE, 0, 2, 1)
	var bytes: PackedByteArray = PackedByteArray([0xaa, 0xbb, 0xcc, 0xff,
		0xaa, 0xbb, 0xcc, 0xff])
	var rectangle: DrawingResult = session.fill_rect(invalid_area, PAINT, null, 8)
	_check(not rectangle.ok and rectangle.code == "COORD_RANGE",
		"entire invalid rectangle is rejected before partial staging")
	_check(calls == 0 and session.change_count() == 0 and
		session._source_tiles.is_empty() and document.revision == revision,
		"invalid rectangle cannot resolve an otherwise valid lazy edge pixel")
	var region: DrawingResult = session.apply_region(invalid_area, bytes, null, 8)
	_check(not region.ok and region.code == "COORD_RANGE",
		"invalid byte region is rejected before partial staging")
	_check(calls == 0 and session.change_count() == 0 and
		session._source_tiles.is_empty(),
		"invalid byte region cannot fetch the lazy edge pixel")

	# A separate session isolates the deferred Brush precondition from the
	# earlier rejected rectangles in the fail-first implementation.
	session.cancel()
	var brush_started: DrawingResult = document.begin_edit(layer, revision)
	_check(brush_started.ok, "begin separate deferred Brush session")
	if not brush_started.ok:
		quit(1)
		return
	session = brush_started.value as DrawingEditSession
	# Paint one deferred Brush dab; invalid follow-up edits must not flatten it.
	var path: PackedVector2Array = PackedVector2Array([Vector2(3.5, 3.5)])
	_check(session.paint_path(path, 0xff443322, 1.0).ok and
		session._brush_deferred and session.change_count() > 0,
		"stage deferred native-compatible Brush before invalid mixed edit")
	var changed: int = session.change_count()
	var reads: int = calls
	var before_size: int = session._before.size()
	var after_size: int = session._after.size()
	for invalid: int in [-1, 0x100000000]:
		var failed_rect: DrawingResult = session.fill_rect(Rect2i(0, 0, 1, 1), invalid)
		_check(not failed_rect.ok and failed_rect.code == "RGBA",
			"invalid rectangle color rejected")
		_check(session._brush_deferred and session.change_count() == changed and
			session._before.size() == before_size and session._after.size() == after_size and
			calls == reads,
			"invalid rectangle cannot materialize deferred Brush")
		var failed_poly: DrawingResult = session.paint_polygon(
			PackedVector2Array([Vector2.ZERO, Vector2(3, 0), Vector2(0, 3)]), invalid)
		_check(not failed_poly.ok and failed_poly.code == "RGBA",
			"invalid polygon color rejected")
		_check(session._brush_deferred and session.change_count() == changed and
			session._before.size() == before_size and session._after.size() == after_size and
			calls == reads,
			"invalid polygon cannot materialize deferred Brush")
	var invalid_late: DrawingResult = session.fill_rect(invalid_area, PAINT, null, 8)
	_check(not invalid_late.ok and invalid_late.code == "COORD_RANGE" and
		session._brush_deferred and session.change_count() == changed and calls == reads,
		"invalid late rectangle preserves accepted deferred Brush")
	var invalid_region: DrawingResult = session.apply_region(invalid_area, bytes, null, 8)
	_check(not invalid_region.ok and invalid_region.code == "COORD_RANGE" and
		session._brush_deferred and session.change_count() == changed and calls == reads,
		"invalid late byte region preserves accepted deferred Brush")
	_check(document.revision == revision and not document.has_stored_pixel(layer, EDGE, 0),
		"invalid requests leave lazy edge unmaterialized and document unchanged")
	_check(session.fill_rect(Rect2i(0, 0, 1, 1), PAINT).ok,
		"valid mixed rectangle retries in same session")
	_check(session.apply_region(Rect2i(1, 0, 1, 1),
		PackedByteArray([0x55, 0x66, 0x77, 0x00])).ok,
		"valid exact RGBA8 byte region still stages after invalid requests")
	_check(session.paint_polygon(PackedVector2Array([Vector2(6, 6),
		Vector2(10, 6), Vector2(6, 10)]), 0xff112233).ok,
		"valid filled polygon still stages after invalid requests")
	_check(session.commit().ok and document.revision == revision + 1 and
		int(document.read_pixel(layer, 0, 0).value) == PAINT and
		int(document.read_pixel(layer, 1, 0).value) == 0x00776655 and
		int(document.read_pixel(layer, 7, 7).value) == 0xff112233,
		"mixed edits publish exact rectangle, hidden-RGB region and polygon")
	_check(int(document.read_pixel(layer, 3, 3).value) == 0xff443322,
		"original deferred Brush also publishes in the same transaction")
	_check(document.undo().ok and int(document.read_pixel(layer, 0, 0).value) == HIDDEN and
		int(document.read_pixel(layer, 1, 0).value) == 0 and
		int(document.read_pixel(layer, 7, 7).value) == 0 and
		int(document.read_pixel(layer, 3, 3).value) == 0,
		"Undo restores exact hidden RGB and removes all three bulk edits plus Brush")
	_check(document.redo().ok and int(document.read_pixel(layer, 0, 0).value) == PAINT and
		int(document.read_pixel(layer, 1, 0).value) == 0x00776655 and
		int(document.read_pixel(layer, 7, 7).value) == 0xff112233 and
		int(document.read_pixel(layer, 3, 3).value) == 0xff443322,
		"Redo restores exact mixed-gesture RGBA8 for all producers")
	_check(not session.fill_rect(Rect2i(0, 0, 1, 1), PAINT).ok and
		not session.paint_polygon(PackedVector2Array([Vector2.ZERO,
		Vector2(3, 0), Vector2(0, 3)]), PAINT).ok,
		"closed session rejects new bulk edits")
	print("T290_BULK_PREFLIGHT_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
