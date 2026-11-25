extends SceneTree
## Non-inverted masks outside bulk areas must not flatten a pending Brush.

const HIDDEN: int = 0x00223344
const BRUSH: int = 0xff667788
const PAINT: int = 0xffaabbcc

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
		push_error("T299_MASKED_BULK_FAILED: " + label)


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


func _polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(2, 0),
		Vector2(2, 2), Vector2(0, 2)])


func _invoke(session: DrawingEditSession, kind: int, selection: DrawingSelection) -> DrawingResult:
	var area: Rect2i = Rect2i(0, 0, 2, 2)
	match kind:
		0:
			return session.fill_rect(area, PAINT, selection, 8)
		1:
			return session.apply_region(area, PackedByteArray([
				0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff,
				0xcc, 0xbb, 0xaa, 0xff, 0xcc, 0xbb, 0xaa, 0xff]), selection, 8)
		2:
			return session.paint_polygon(_polygon(), PAINT, selection, 8)
		_:
			return session.clear_rect(area, selection, 8)


func _masked_noop() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_document("masked-bulk-noop")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	_check(session.paint_path(PackedVector2Array([Vector2(20.5, 2.5)]), BRUSH, 1.0).ok,
		"accepted Brush in an unrelated tile")
	_check(session._brush_deferred and session._after.is_empty() and
		session.change_count() == 1 and fetches == 0,
		"Brush starts tile-local and target lazy tile remains unloaded")
	var initial_epoch: int = session._preview_epoch
	var initial_sources: int = session._source_tiles.size()
	var revision: int = document.revision
	var outside: DrawingSelection = DrawingSelection.new(Rect2i(40, 40, 2, 2), true)
	var empty: DrawingSelection = DrawingSelection.new(Rect2i(), true)
	for mask: DrawingSelection in [outside, empty]:
		for kind: int in range(4):
			var result: DrawingResult = _invoke(session, kind, mask)
			_check(result.ok and session.change_count() == 1,
				"excluded bulk edit %d returns a no-op without losing Brush" % kind)
			_check(session._brush_deferred and session._before.is_empty() and
				session._after.is_empty() and session._preview_epoch == initial_epoch,
				"excluded edit %d preserves deferred Brush and preview" % kind)
			_check(fetches == 0 and session._source_tiles.size() == initial_sources and
				document.revision == revision,
				"excluded edit %d invokes no lazy loader or publication" % kind)
	unavailable = false  # Source is needed only for the committed-document readback.
	_check(session.commit().ok and document.revision == revision + 1,
		"Brush commits after excluded edits")
	_check(int(document.read_pixel(layer, 20, 2).value) == BRUSH and
		int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"excluded edits leave source and accepted Brush pixels exact")
	_check(document.undo().ok and int(document.read_pixel(layer, 20, 2).value) == 0 and
		int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"Undo restores original bytes")
	_check(document.redo().ok and int(document.read_pixel(layer, 20, 2).value) == BRUSH,
		"Redo restores only accepted Brush")


func _inverted_control() -> void:
	fetches = 0
	unavailable = true
	var ctx: Dictionary = _new_document("masked-bulk-inverted")
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var document: DrawingDocument = ctx.document as DrawingDocument
	var layer: String = str(ctx.layer)
	var inverted: DrawingSelection = DrawingSelection.new(Rect2i(40, 40, 2, 2), true)
	inverted.inverted = true
	var rejected: DrawingResult = session.fill_rect(Rect2i(0, 0, 1, 1), PAINT, inverted, 4)
	_check(not rejected.ok and fetches == 1,
		"inverted selection permits the distant area and reaches lazy source")
	unavailable = false
	var accepted: DrawingResult = session.fill_rect(Rect2i(0, 0, 1, 1), PAINT, inverted, 4)
	_check(accepted.ok and fetches == 2 and session.change_count() == 1,
		"inverted selection valid retry stages source pixel")
	_check(session.commit().ok and int(document.read_pixel(layer, 0, 0).value) == PAINT,
		"inverted selection commits")
	_check(document.undo().ok and int(document.read_pixel(layer, 0, 0).value) == HIDDEN,
		"inverted selection Undo preserves hidden RGB")
	_check(document.redo().ok and int(document.read_pixel(layer, 0, 0).value) == PAINT,
		"inverted selection Redo retains RGBA8")


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "native extension loaded")
	source_bytes.resize(16 * 16 * 4)
	source_bytes[0] = 0x44
	source_bytes[1] = 0x33
	source_bytes[2] = 0x22
	_masked_noop()
	_inverted_control()
	print("T299_MASKED_BULK_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
