extends SceneTree
## Per-pixel Brush and mixed edits must reject unpublishable global pixels
## before touching lazy sources or flattening an accepted deferred stroke.

const BOUND: int = 4503599627370496
const SOURCE: int = 0x00223344
const PAINT: int = 0xffaabbcc
const BRUSH: int = 0xff556677

var checks: int = 0
var failures: int = 0
var reads: int = 0
var blobs: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T295_BRUSH_PROJECTION_FAILED: " + label)


func _fetch(key: String) -> Variant:
	reads += 1
	return blobs.get(key)


func _source() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 0x44
	bytes[1] = 0x33
	bytes[2] = 0x22
	return bytes


func _begin(label: String, axis_x: bool, sign_value: int) -> Dictionary:
	reads = 0
	blobs.clear()
	var doc: DrawingDocument = DrawingDocument.new("brush-projection-" + label, 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var boundary: int = sign_value * BOUND
	var tile: int = DrawingDocument.TILES.floor_div(boundary, 16)
	blobs[label] = _source()
	var registered: DrawingResult = doc.register_lazy_chunk(layer,
		tile if axis_x else 0, 0 if axis_x else tile, label,
		DrawingRasterTile.digest_rgba8(blobs[label], 16), Callable(self, "_fetch"))
	_check(registered.ok, label + " lazy source registered")
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, boundary if axis_x else 0, 0 if axis_x else boundary)
	_check(begun.ok, label + " session began")
	return {"doc": doc, "layer": layer, "session": begun.value if begun.ok else null,
		"x": boundary if axis_x else 0, "y": boundary if not axis_x else 0}


func _case(axis_x: bool, sign_value: int) -> void:
	var label: String = ("x" if axis_x else "y") + ("+" if sign_value > 0 else "-")
	var context: Dictionary = _begin(label, axis_x, sign_value)
	var session: DrawingEditSession = context.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = context.doc as DrawingDocument
	var layer: String = String(context.layer)
	var revision: int = document.revision
	var invalid: Vector2i = Vector2i(sign_value, 0) if axis_x else Vector2i(0, sign_value)
	var invalid_point: Vector2 = Vector2(invalid.x + 0.5, invalid.y + 0.5)
	var rejected: DrawingResult = session.paint_path(
		PackedVector2Array([invalid_point]), PAINT, 1.0)
	_check(not rejected.ok and rejected.code == "COORD_RANGE",
		label + " rejects unpublishable Brush dab")
	_check(reads == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0 and document.revision == revision,
		label + " invalid Brush cannot access lazy source or stage preview")
	_check(session._preview_tiles.is_empty() and session._covered_rows.is_empty(),
		label + " invalid Brush cannot mark coverage")
	var valid: DrawingResult = session.paint_path(
		PackedVector2Array([Vector2(0.5, 0.5)]), PAINT, 1.0)
	_check(valid.ok and session.change_count() == 1 and reads == 1,
		label + " legal edge retry stages one pixel from one source")
	_check(session.commit().ok and document.revision == revision + 1,
		label + " legal Brush commits")
	var px: int = int(context.x)
	var py: int = int(context.y)
	_check(int(document.read_pixel(layer, px, py).value) == PAINT,
		label + " exact committed RGBA8")
	_check(document.undo().ok and int(document.read_pixel(layer, px, py).value) == SOURCE,
		label + " Undo restores transparent hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, px, py).value) == PAINT,
		label + " Redo restores exact Brush pixel")


func _mixed_deferred() -> void:
	var context: Dictionary = _begin("mixed", true, 1)
	var session: DrawingEditSession = context.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = context.doc as DrawingDocument
	var layer: String = String(context.layer)
	_check(session.paint_path(PackedVector2Array([Vector2(0.5, 1.5)]), BRUSH, 1.0).ok
		and session._brush_deferred and session.change_count() == 1,
		"valid Brush remains tile-local deferred")
	var prior_reads: int = reads
	var revision: int = document.revision
	var rejected: DrawingResult = session._stage(1, 0, PAINT)
	_check(not rejected.ok and rejected.code == "COORD_RANGE",
		"mixed per-pixel stage rejects native-unpublishable coordinate")
	_check(session._brush_deferred and session._before.is_empty() and
		session._after.is_empty() and session.change_count() == 1 and
		reads == prior_reads and document.revision == revision,
		"rejected mixed pixel leaves accepted Brush deferred and source untouched")
	_check(session.commit().ok and document.revision == revision + 1,
		"accepted Brush commits after invalid mixed pixel")
	_check(int(document.read_pixel(layer, BOUND, 1).value) == BRUSH and
		int(document.read_pixel(layer, BOUND, 0).value) == SOURCE,
		"only accepted Brush pixel appears in document")
	_check(document.undo().ok and int(document.read_pixel(layer, BOUND, 1).value) == 0
		and int(document.read_pixel(layer, BOUND, 0).value) == SOURCE,
		"Undo removes only accepted Brush pixel")
	_check(document.redo().ok and int(document.read_pixel(layer, BOUND, 1).value) == BRUSH,
		"Redo restores accepted Brush pixel")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "Rust tile extension loaded")
	for axis_x: bool in [true, false]:
		for sign_value: int in [1, -1]:
			_case(axis_x, sign_value)
	_mixed_deferred()
	print("T295_BRUSH_PROJECTION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
