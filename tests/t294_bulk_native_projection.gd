extends SceneTree
## T-294: bulk edits must reject native-unpublishable signed document ranges
## before accessing lazy source tiles or materializing another accepted edit.

const BOUND: int = 4503599627370496
const SOURCE: int = 0x00223344
const PAINT: int = 0xffaabbcc

var checks: int = 0
var failures: int = 0
var reads: int = 0
var sources: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T294_BULK_PROJECTION_FAILED: " + detail)


func _fetch(name: String) -> Variant:
	reads += 1
	return sources.get(name)


func _rectangle(axis_x: bool, sign_value: int) -> Rect2i:
	var start: int = 0 if sign_value > 0 else -1
	return Rect2i(start, 0, 2, 1) if axis_x else Rect2i(0, start, 1, 2)


func _polygon(axis_x: bool, sign_value: int) -> PackedVector2Array:
	var start: float = 0.0 if sign_value > 0 else -1.0
	return PackedVector2Array([
		Vector2(start, 0), Vector2(start + 2, 0),
		Vector2(start + 2, 1), Vector2(start, 1),
	]) if axis_x else PackedVector2Array([
		Vector2(0, start), Vector2(1, start),
		Vector2(1, start + 2), Vector2(0, start + 2),
	])


func _case(axis_x: bool, sign_value: int) -> void:
	var label: String = ("x" if axis_x else "y") + ("+" if sign_value > 0 else "-")
	reads = 0
	sources.clear()
	var document: DrawingDocument = DrawingDocument.new("bulk-projection-" + label, 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Raster").value)
	var global: int = sign_value * BOUND
	var tile: int = DrawingDocument.TILES.floor_div(global, 16)
	var offset: int = posmod(global, 16)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	var pixel_index: int = ((offset if not axis_x else 0) * 16 +
		(offset if axis_x else 0)) * 4
	bytes[pixel_index] = 0x44
	bytes[pixel_index + 1] = 0x33
	bytes[pixel_index + 2] = 0x22
	sources[label] = bytes
	_check(document.register_lazy_chunk(layer, tile if axis_x else 0,
		0 if axis_x else tile, label,
		DrawingRasterTile.digest_rgba8(bytes, 16), Callable(self, "_fetch")).ok,
		label + " registered legal lazy source")
	var revision: int = document.revision
	var started: DrawingResult = document.begin_edit(layer, revision,
		Transform2D.IDENTITY, global if axis_x else 0, 0 if axis_x else global)
	_check(started.ok, label + " began legal anchor edit")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value as DrawingEditSession
	var area: Rect2i = _rectangle(axis_x, sign_value)
	var invalid_fill: DrawingResult = session.fill_rect(area, PAINT, null, 8)
	_check(not invalid_fill.ok and invalid_fill.code == "COORD_RANGE",
		label + " rejects rectangle crossing global native boundary")
	_check(reads == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0 and document.revision == revision,
		label + " invalid rectangle does not resolve lazy source or stage pixels")
	var rgba8: PackedByteArray = PackedByteArray([
		0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff])
	var invalid_region: DrawingResult = session.apply_region(area, rgba8, null, 8)
	_check(not invalid_region.ok and invalid_region.code == "COORD_RANGE",
		label + " rejects byte region crossing native boundary")
	_check(reads == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0,
		label + " invalid byte region does not read or stage")
	var invalid_polygon: DrawingResult = session.paint_polygon(
		_polygon(axis_x, sign_value), PAINT, null, 8)
	_check(not invalid_polygon.ok and invalid_polygon.code == "COORD_RANGE",
		label + " rejects polygon crossing native boundary")
	_check(reads == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0,
		label + " invalid polygon does not read or stage")
	_check(session.fill_rect(Rect2i(0, 0, 1, 1), PAINT).ok,
		label + " legal boundary rectangle succeeds in same session")
	_check(reads == 1 and session.change_count() == 1,
		label + " valid retry loads only its single source tile")
	_check(session.commit().ok and document.revision == revision + 1,
		label + " legal boundary edit commits")
	var px: int = global if axis_x else 0
	var py: int = global if not axis_x else 0
	_check(int(document.read_pixel(layer, px, py).value) == PAINT,
		label + " published exact RGBA8")
	_check(document.undo().ok and int(document.read_pixel(layer, px, py).value) == SOURCE,
		label + " Undo restores transparent hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, px, py).value) == PAINT,
		label + " Redo restores exact pixel")


func _deferred_brush_case() -> void:
	reads = 0
	sources.clear()
	var document: DrawingDocument = DrawingDocument.new("bulk-projection-brush", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Raster").value)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 0x44
	bytes[1] = 0x33
	bytes[2] = 0x22
	sources["brush"] = bytes
	_check(document.register_lazy_chunk(layer, int(BOUND / 16), 0, "brush",
		DrawingRasterTile.digest_rgba8(bytes, 16), Callable(self, "_fetch")).ok,
		"deferred Brush legal boundary source registered")
	var revision: int = document.revision
	var started: DrawingResult = document.begin_edit(layer, revision,
		Transform2D.IDENTITY, BOUND, 0)
	_check(started.ok, "deferred Brush legal boundary edit started")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value as DrawingEditSession
	var brush: DrawingResult = session.paint_path(
		PackedVector2Array([Vector2(0.5, 1.5)]), 0xff445566, 1.0)
	_check(brush.ok and session._brush_deferred and session.change_count() == 1,
		"Brush remains in tile-local deferred mode")
	var prior_reads: int = reads
	var prior_changes: int = session.change_count()
	for operation: int in range(3):
		var result: DrawingResult
		match operation:
			0:
				result = session.fill_rect(Rect2i(0, 0, 2, 1), PAINT, null, 8)
			1:
				result = session.apply_region(Rect2i(0, 0, 2, 1),
					PackedByteArray([0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff]),
					null, 8)
			_:
				result = session.paint_polygon(_polygon(true, 1), PAINT, null, 8)
		_check(not result.ok and result.code == "COORD_RANGE",
			"rejected bulk edit retains accepted Brush (%d)" % operation)
		_check(session._brush_deferred and session._before.is_empty() and
			session._after.is_empty() and session.change_count() == prior_changes and
			reads == prior_reads and document.revision == revision,
			"rejected bulk edit does not flatten Brush or resolve more sources (%d)" % operation)
	_check(session.fill_rect(Rect2i(0, 0, 1, 1), PAINT).ok,
		"legal rectangle can share the existing Brush transaction")
	_check(session.commit().ok and document.revision == revision + 1,
		"accepted Brush and rectangle commit atomically")
	_check(int(document.read_pixel(layer, BOUND, 0).value) == PAINT and
		int(document.read_pixel(layer, BOUND, 1).value) == 0xff445566,
		"committed pixels preserve both Brush and rectangle")
	_check(document.undo().ok and int(document.read_pixel(layer, BOUND, 0).value) == SOURCE and
		int(document.read_pixel(layer, BOUND, 1).value) == 0,
		"Undo restores source and removes the deferred Brush pixel")
	_check(document.redo().ok and int(document.read_pixel(layer, BOUND, 0).value) == PAINT and
		int(document.read_pixel(layer, BOUND, 1).value) == 0xff445566,
		"Redo restores both mixed edits exactly")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "Rust native extension is loaded")
	for axis_x: bool in [true, false]:
		for sign_value: int in [1, -1]:
			_case(axis_x, sign_value)
	_deferred_brush_case()
	print("T294_BULK_PROJECTION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
