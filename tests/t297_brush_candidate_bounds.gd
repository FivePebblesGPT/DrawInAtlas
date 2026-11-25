extends SceneTree
## Oversized but finite Brush widths must never overflow candidate integer bounds.

const COLOR: int = 0xff3366aa
const SOURCE: int = 0x00112233

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T297_BRUSH_BOUNDS_FAILED: " + label)


func _session(label: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision, Transform2D.IDENTITY, 0, 0)
	_check(begun.ok, label + " creates native session")
	return {"doc": doc, "layer": layer, "session": begun.value if begun.ok else null}


func _unclipped(width: float) -> void:
	var ctx: Dictionary = _session("huge-width-%s" % width)
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var doc: DrawingDocument = ctx.doc as DrawingDocument
	var revision: int = doc.revision
	var invalid: DrawingResult = session.paint_path(
		PackedVector2Array([Vector2(0.5, 0.5)]), COLOR, width)
	_check(not invalid.ok and invalid.code == "BRUSH_LIMIT",
		"unclipped finite huge width %s rejects rather than reporting success" % width)
	_check(session.change_count() == 0 and not session._has_last and
		session._preview_tiles.is_empty() and doc.revision == revision,
		"rejected width leaves preview, prior pointer and revision untouched")
	var retry: DrawingResult = session.paint_path(
		PackedVector2Array([Vector2(0.5, 0.5)]), COLOR, 1.0)
	_check(retry.ok and session.change_count() == 1,
		"same-session normal Brush retry succeeds")
	_check(session.commit().ok, "retry publishes canonical native bytes")
	_check(int(doc.read_pixel(String(ctx.layer), 0, 0).value) == COLOR,
		"retry has exact RGBA8")
	_check(doc.undo().ok and int(doc.read_pixel(String(ctx.layer), 0, 0).value) == 0,
		"Undo restores blank pixel")
	_check(doc.redo().ok and int(doc.read_pixel(String(ctx.layer), 0, 0).value) == COLOR,
		"Redo restores Brush pixel")


func _clipped(label: String, path: PackedVector2Array) -> void:
	var ctx: Dictionary = _session("huge-width-clipped-" + label)
	var session: DrawingEditSession = ctx.session as DrawingEditSession
	if session == null:
		return
	var doc: DrawingDocument = ctx.doc as DrawingDocument
	# Transparent hidden RGB is canonical content, not empty. A clipped Brush
	# must preserve it in the native before-image and restore it on Undo.
	_check(session._stage(1, 1, SOURCE).ok and session.commit().ok,
		label + " seed hidden-RGB source pixel")
	var begun: DrawingResult = doc.begin_edit(String(ctx.layer), doc.revision,
		Transform2D.IDENTITY, 0, 0)
	_check(begun.ok, label + " begin Brush after seeding source")
	if not begun.ok:
		return
	session = begun.value as DrawingEditSession
	var result: DrawingResult = session.paint_path(
		path, COLOR, 1.0e30,
		false, null, 16, Rect2i(0, 0, 2, 2))
	_check(result.ok and session.change_count() == 4,
		label + " very wide Brush clipped to 2x2 stages precisely four candidates")
	_check(session.commit().ok, "clipped Brush publishes")
	var layer: String = String(ctx.layer)
	for y: int in range(3):
		for x: int in range(3):
			var expected: int = COLOR if x < 2 and y < 2 else 0
			_check(int(doc.read_pixel(layer, x, y).value) == expected,
				"clipped pixel (%d,%d) is exact" % [x, y])
	_check(doc.undo().ok, "clipped Brush Undo")
	for y: int in range(2):
		for x: int in range(2):
			var original: int = SOURCE if x == 1 and y == 1 else 0
			_check(int(doc.read_pixel(layer, x, y).value) == original,
				"Undo restores exact source/hidden RGB (%d,%d)" % [x, y])
	_check(doc.redo().ok, "clipped Brush Redo")
	for y: int in range(2):
		for x: int in range(2):
			_check(int(doc.read_pixel(layer, x, y).value) == COLOR,
				"Redo restores exact RGBA8 (%d,%d)" % [x, y])


func _run() -> void:
	_check(ClassDB.class_exists("DrawingNativeTiles"), "Rust extension loaded")
	_unclipped(1.0e30)
	_unclipped(1.0e100)
	_clipped("dab", PackedVector2Array([Vector2(0.5, 0.5)]))
	_clipped("horizontal", PackedVector2Array([Vector2(0.5, 0.5), Vector2(1.5, 0.5)]))
	_clipped("vertical", PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 1.5)]))
	_clipped("oblique", PackedVector2Array([Vector2(0.5, 0.5), Vector2(1.5, 1.5)]))
	print("T297_BRUSH_BOUNDS_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
