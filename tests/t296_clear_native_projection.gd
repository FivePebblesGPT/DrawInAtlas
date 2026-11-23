extends SceneTree
## Reject unsafe signed Delete regions before lazy source resolution or Brush materialization.

const BOUND: int = 4503599627370496
const SOURCE: int = 0x00223344
const BRUSH: int = 0xff556677

var checks: int = 0
var failures: int = 0
var reads: int = 0
var blobs: Dictionary[String, PackedByteArray] = {}


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T296_CLEAR_PROJECTION_FAILED: " + description)


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
	var document: DrawingDocument = DrawingDocument.new("clear-native-" + label, 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var anchor: int = sign_value * BOUND
	var tile: int = DrawingDocument.TILES.floor_div(anchor, 16)
	blobs[label] = _source()
	var registered: DrawingResult = document.register_lazy_chunk(layer,
		tile if axis_x else 0, 0 if axis_x else tile, label,
		DrawingRasterTile.digest_rgba8(blobs[label], 16), Callable(self, "_fetch"))
	_check(registered.ok, label + " registered lazy source")
	var started: DrawingResult = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, anchor if axis_x else 0, 0 if axis_x else anchor)
	_check(started.ok, label + " began native edit")
	return {"document": document, "layer": layer,
		"session": started.value if started.ok else null,
		"x": anchor if axis_x else 0, "y": anchor if not axis_x else 0}


func _invalid_area(axis_x: bool, sign_value: int) -> Rect2i:
	var start: int = 0 if sign_value > 0 else -1
	return Rect2i(start, 0, 2, 1) if axis_x else Rect2i(0, start, 1, 2)


func _edge_case(axis_x: bool, sign_value: int) -> void:
	var label: String = ("x" if axis_x else "y") + ("+" if sign_value > 0 else "-")
	var ctx: Dictionary = _begin(label, axis_x, sign_value)
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = String(ctx.layer)
	var revision: int = document.revision
	var rejected: DrawingResult = session.clear_rect(_invalid_area(axis_x, sign_value))
	_check(not rejected.ok and rejected.code == "COORD_RANGE",
		label + " rejects a Delete region crossing native projection")
	_check(reads == 0 and session._source_tiles.is_empty() and
		session.change_count() == 0 and document.revision == revision,
		label + " invalid Delete makes no lazy fetch or staged change")
	_check(session._preview_tiles.is_empty() and not session._clear_deferred,
		label + " invalid Delete cannot create dense preview")
	var valid: DrawingResult = session.clear_rect(Rect2i(0, 0, 1, 1))
	_check(valid.ok and session.change_count() == 1 and reads == 1,
		label + " valid boundary retry clears one source pixel")
	_check(session.commit().ok and document.revision == revision + 1,
		label + " valid Delete commits")
	var px: int = int(ctx.x)
	var py: int = int(ctx.y)
	_check(int(document.read_pixel(layer, px, py).value) == 0,
		label + " committed Delete clears hidden RGB")
	_check(document.undo().ok and int(document.read_pixel(layer, px, py).value) == SOURCE,
		label + " Undo restores exact hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, px, py).value) == 0,
		label + " Redo clears exact pixel")


func _deferred_brush_case() -> void:
	var ctx: Dictionary = _begin("brush", true, 1)
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = String(ctx.layer)
	var accepted: DrawingResult = session.paint_path(
		PackedVector2Array([Vector2(0.5, 1.5)]), BRUSH, 1.0)
	_check(accepted.ok and session._brush_deferred and session.change_count() == 1,
		"accepted Brush remains deferred")
	var prior_reads: int = reads
	var revision: int = document.revision
	var rejected: DrawingResult = session.clear_rect(Rect2i(0, 0, 2, 1))
	_check(not rejected.ok and rejected.code == "COORD_RANGE",
		"out-of-range Delete rejects after deferred Brush")
	_check(session._brush_deferred and session._before.is_empty() and
		session._after.is_empty() and session.change_count() == 1 and
		reads == prior_reads and document.revision == revision,
		"invalid Delete leaves deferred Brush and lazy source untouched")
	_check(session.commit().ok, "accepted Brush commits after rejected Delete")
	_check(int(document.read_pixel(layer, BOUND, 1).value) == BRUSH and
		int(document.read_pixel(layer, BOUND, 0).value) == SOURCE,
		"rejected Delete cannot erase accepted Brush or source")
	_check(document.undo().ok and int(document.read_pixel(layer, BOUND, 1).value) == 0 and
		int(document.read_pixel(layer, BOUND, 0).value) == SOURCE,
		"Undo restores original source and Brush pixel")
	_check(document.redo().ok and int(document.read_pixel(layer, BOUND, 1).value) == BRUSH,
		"Redo reproduces accepted Brush without rejected Delete")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "Rust native extension loaded")
	for axis_x: bool in [true, false]:
		for sign_value: int in [1, -1]:
			_edge_case(axis_x, sign_value)
	_deferred_brush_case()
	print("T296_CLEAR_PROJECTION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
