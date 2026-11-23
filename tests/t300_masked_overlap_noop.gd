extends SceneTree
## A masked bulk area with conservative-bounds overlap can still be an exact no-op.

const HIDDEN: int = 0x00223344
const BRUSH: int = 0xff667788
const PAINT: int = 0xffaabbcc
const AREA: Rect2i = Rect2i(0, 0, 2, 2)

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
		push_error("T300_MASK_OVERLAP_FAILED: " + label)


func _fetch(_key: String) -> Variant:
	fetches += 1
	return null if unavailable else source_bytes


func _new_document(name: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var registered: DrawingResult = document.register_lazy_chunk(layer, 0, 0, "source",
		DrawingRasterTile.digest_rgba8(source_bytes, 16), Callable(self, "_fetch"))
	_check(registered.ok, name + " registered lazy source")
	var started: DrawingResult = document.begin_edit(layer, document.revision)
	_check(started.ok, name + " began edit")
	return {"document": document, "layer": layer, "session": started.value if started.ok else null}


func _invoke(session: DrawingEditSession, kind: int, selection: DrawingSelection) -> DrawingResult:
	match kind:
		0:
			return session.fill_rect(AREA, PAINT, selection, 8)
		1:
			return session.apply_region(AREA, PackedByteArray([
				0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff,
				0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff]), selection, 8)
		2:
			return session.paint_polygon(PackedVector2Array([
				Vector2.ZERO, Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)]), PAINT,
				selection, 8)
		_:
			return session.clear_rect(AREA, selection, 8)


func _masked_hole_noop() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_document("masked-overlap-noop")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	_check(session.paint_path(PackedVector2Array([Vector2(20.5, 2.5)]), BRUSH, 1.0).ok,
		"accepted native Brush in another tile")
	_check(session._brush_deferred and session._after.is_empty() and fetches == 0,
		"Brush is initially deferred and lazy source unavailable")
	var epoch: int = session._preview_epoch
	var initial_sources: int = session._source_tiles.size()
	var revision: int = document.revision
	var sparse: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 8, 8), true)
	var bits: Dictionary[Vector2i, bool] = {Vector2i(6, 6): true}
	sparse.set_mask(bits)
	var subtracted: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 8, 8), true)
	_check(subtracted.combine_rectangle(AREA, "Subtract"), "subtraction is valid")
	var intersected: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 8, 8), true)
	_check(intersected.combine_rectangle(AREA, "Subtract"),
		"intersected selection subtraction is valid")
	_check(intersected.combine_rectangle(AREA, "Intersect"),
		"intersection retains bounds but removes eligible interior")
	for selection: DrawingSelection in [sparse, subtracted, intersected]:
		_check(selection.bounds.intersects(AREA) and not selection.allows(Vector2i(0, 0))
			and not selection.allows(Vector2i(1, 1)),
			"selection bounds overlap area, but interior is excluded")
		for kind: int in range(4):
			var result: DrawingResult = _invoke(session, kind, selection)
			_check(result.ok and session.change_count() == 1,
				"masked-out command %d returns a successful no-op" % kind)
			_check(session._brush_deferred and session._after.is_empty()
				and session._before.is_empty() and session._preview_epoch == epoch,
				"masked-out command %d preserves deferred Brush and preview" % kind)
			_check(fetches == 0 and session._source_tiles.size() == initial_sources
				and document.revision == revision,
				"masked-out command %d does not invoke lazy loader or mutate document" % kind)
	unavailable = false
	_check(session.commit().ok and document.revision == revision + 1,
		"Brush commits after excluded commands")
	_check(int(document.read_pixel(layer, 20, 2).value) == BRUSH
		and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"Brush and source pixels remain byte-exact")
	_check(document.undo().ok and int(document.read_pixel(layer, 20, 2).value) == 0
		and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"Undo restores bytes without masked-out edits")
	_check(document.redo().ok and int(document.read_pixel(layer, 20, 2).value) == BRUSH,
		"Redo restores accepted Brush only")


func _allowed_control() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_document("masked-overlap-control")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	var sparse: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 8, 8), true)
	var bits: Dictionary[Vector2i, bool] = {Vector2i(1, 1): true}
	sparse.set_mask(bits)
	var rejected: DrawingResult = session.fill_rect(AREA, PAINT, sparse, 8)
	_check(not rejected.ok and fetches == 1, "actual overlap reaches unavailable lazy source")
	unavailable = false
	var accepted: DrawingResult = session.fill_rect(AREA, PAINT, sparse, 8)
	_check(accepted.ok and fetches == 2, "allowed source retries successfully")
	_check(session.commit().ok and int(document.read_pixel(layer, 1, 1).value) == PAINT
		and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"only allowed pixel changed; hidden RGB preserved")
	_check(document.undo().ok and int(document.read_pixel(layer, 1, 1).value) == 0,
		"allowed pixel Undo restores source")
	_check(document.redo().ok and int(document.read_pixel(layer, 1, 1).value) == PAINT,
		"allowed pixel Redo restores RGBA8")


func _budget_and_inversion() -> void:
	var sparse: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 100, 100), true)
	var bits: Dictionary[Vector2i, bool] = {Vector2i(99, 99): true}
	sparse.set_mask(bits)
	if not sparse.has_method("allows_any_in_area"):
		_check(false, "selection must expose a bounded exact overlap probe")
		return
	_check(sparse.allows_any_in_area(AREA) == false,
		"small mask hole is provably excluded")
	_check(sparse.allows_any_in_area(Rect2i(0, 0, 90, 90)),
		"large uncertain region falls back conservatively, no large pixel scan")
	sparse.inverted = true
	_check(sparse.allows_any_in_area(AREA),
		"inverted selection never falsely skips allowed outside pixels")
	var additive: DrawingSelection = DrawingSelection.new(Rect2i(8, 8, 1, 1), true)
	_check(additive.combine_rectangle(AREA, "Add") and additive.allows_any_in_area(AREA),
		"added disjoint rectangle is still considered eligible")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "native Rust extension loaded")
	source_bytes.resize(16 * 16 * 4)
	source_bytes[0] = 0x44
	source_bytes[1] = 0x33
	source_bytes[2] = 0x22
	_masked_hole_noop()
	_allowed_control()
	_budget_and_inversion()
	print("T300_MASK_OVERLAP_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
