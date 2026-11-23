extends SceneTree
## Polygon bounds may overlap a selection even when its interior covers no allowed pixel.

const HIDDEN: int = 0x00223344
const BRUSH: int = 0xff667788
const PAINT: int = 0xffaabbcc
var triangle: PackedVector2Array = PackedVector2Array([
	Vector2(0, 0), Vector2(2, 0), Vector2(0, 1.7)])

var checks: int = 0
var failures: int = 0
var fetches: int = 0
var unavailable: bool = true
var source_bytes: PackedByteArray


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T301_POLYGON_SELECTION_FAILED: " + label)


func _fetch(_key: String) -> Variant:
	fetches += 1
	return null if unavailable else source_bytes


func _new_session(label: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(label, 16)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var registered: DrawingResult = document.register_lazy_chunk(layer, 0, 0, "source",
		DrawingRasterTile.digest_rgba8(source_bytes, 16), Callable(self, "_fetch"))
	_check(registered.ok, "lazy source registered")
	var started: DrawingResult = document.begin_edit(layer, document.revision)
	_check(started.ok, "native edit session started")
	return {"document": document, "layer": layer,
		"session": started.value if started.ok else null}


func _noop_geometry() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_session("polygon-geometry-noop")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	_check(session.paint_path(PackedVector2Array([Vector2(20.5, 2.5)]), BRUSH, 1.0).ok,
		"deferred native Brush accepted")
	_check(session._brush_deferred and session._after.is_empty(), "Brush still deferred")
	var epoch: int = session._preview_epoch
	var initial_sources: int = session._source_tiles.size()
	var revision: int = document.revision
	var selections: Array[DrawingSelection] = []
	# Cell (1, 1) lies in the triangle's bounding box, but outside its geometry.
	var rectangular: DrawingSelection = DrawingSelection.new(Rect2i(1, 1, 1, 1), true)
	selections.append(rectangular)
	var masked: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 2, 2), true)
	masked.set_mask({Vector2i(1, 1): true})
	selections.append(masked)
	var subtracted: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 2, 2), true)
	_check(subtracted.combine_rectangle(Rect2i(0, 0, 2, 1), "Subtract"),
		"boolean subtraction selection valid")
	selections.append(subtracted)
	for selection: DrawingSelection in selections:
		_check(selection.allows_any_in_area(Rect2i(0, 0, 2, 2)),
			"selection allows bounding-box pixels")
		_check(not selection.allows(Vector2i(0, 0)) and selection.allows(Vector2i(1, 1)),
			"selection allows only pixels outside the polygon")
		var result: DrawingResult = session.paint_polygon(triangle, PAINT, selection, 16)
		_check(result.ok and session.change_count() == 1,
			"polygon with no allowed interior is a successful no-op")
		_check(session._brush_deferred and session._after.is_empty() and session._before.is_empty()
			and session._preview_epoch == epoch,
			"no-op polygon does not materialize accepted Brush")
		_check(fetches == 0 and session._source_tiles.size() == initial_sources and document.revision == revision,
			"no-op polygon cannot fetch lazy source or publish history")
	unavailable = false
	_check(session.commit().ok, "deferred Brush commits after polygon no-ops")
	_check(int(document.read_pixel(layer, 20, 2).value) == BRUSH
		and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"exact Brush and transparent hidden RGB after commit")
	_check(document.undo().ok and int(document.read_pixel(layer, 20, 2).value) == 0,
		"native Undo reverts only Brush")
	_check(document.redo().ok and int(document.read_pixel(layer, 20, 2).value) == BRUSH,
		"native Redo restores Brush")


func _allowed_control() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_session("polygon-allowed-control")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	var selected: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 2, 2), true)
	selected.set_mask({Vector2i(0, 0): true})
	var blocked: DrawingResult = session.paint_polygon(triangle, PAINT, selected, 16)
	_check(not blocked.ok and fetches == 1, "allowed interior reaches unavailable source")
	unavailable = false
	_check(session.paint_polygon(triangle, PAINT, selected, 16).ok and fetches == 2,
		"allowed interior retries lazy source")
	_check(session.commit().ok and int(document.read_pixel(layer, 0, 0).value) == PAINT
		and int(document.read_pixel(layer, 1, 1).value) == 0,
		"only actual selected triangle interior changes")
	_check(document.undo().ok and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"Undo restores original transparent hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, 0, 0).value) == PAINT,
		"Redo restores selected polygon RGBA8")


func _conservative_fallback() -> void:
	var ctx: Dictionary = _new_session("polygon-conservative-fallback")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 100, 100), true)
	mask.set_mask({Vector2i(99, 99): true})
	_check(not session._polygon_selection_excludes_pixels(Rect2i(0, 0, 65, 65),
		triangle, mask), "large uncertain overlap never skips staging")
	mask.inverted = true
	_check(not session._polygon_selection_excludes_pixels(Rect2i(0, 0, 2, 2),
		triangle, mask), "inverted mask never falsely declares polygon excluded")
	mask.inverted = false
	_check(session._polygon_selection_excludes_pixels(Rect2i(0, 0, 2, 2),
		triangle, mask), "small exact masked geometry proves empty")
	_check(not session._polygon_selection_excludes_pixels(Rect2i(0, 0, 2, 2),
		triangle, null), "unselected polygon retains normal edit path")
	var huge_shape: PackedVector2Array = PackedVector2Array()
	for vertex: int in range(2000):
		huge_shape.append(triangle[vertex % triangle.size()])
	_check(not session._polygon_selection_excludes_pixels(Rect2i(0, 0, 32, 32),
		huge_shape, mask), "high-vertex polygon does not cause unbounded mask work")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "Rust raster extension loaded")
	source_bytes.resize(16 * 16 * 4)
	source_bytes[0] = 0x44
	source_bytes[1] = 0x33
	source_bytes[2] = 0x22
	_noop_geometry()
	_allowed_control()
	_conservative_fallback()
	print("T301_POLYGON_SELECTION_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
