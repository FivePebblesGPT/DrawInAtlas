extends SceneTree
## T-161: public gesture, viewport and image anchors must not wrap INT64_MIN.

const LIMIT: int = 1152921504606846976
const MIN_I64: int = -9223372036854775807 - 1
const MAX_I64: int = 9223372036854775807
const STRIDE: int = 64
const INK: int = 0xff224466
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T161_SIGNED_ANCHOR_FAILED: " + message)


func tile_bytes(doc: DrawingDocument, layer_id: String, key: String) -> PackedByteArray:
	var source: DrawingResult = doc.request_chunk(layer_id, key)
	if not source.ok or source.value == null:
		return PackedByteArray()
	return (source.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "required Hokusai native classes loaded")
	var doc: DrawingDocument = DrawingDocument.new("t161-public-anchors", STRIDE)
	var layer_id: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var session_result: DrawingResult = doc.begin_edit(layer_id, doc.revision)
	check(session_result.ok, "Hokusai session opens")
	if not session_result.ok:
		quit(1)
		return
	var session: DrawingEditSession = session_result.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(-64, -64, 128, 128), true).ok,
		"Hard Round Hokusai preset configured")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-8, 8), Vector2(8, 8)]), INK, false, null).ok,
		"Hokusai source staged")
	var paint: DrawingResult = session.commit()
	check(paint.ok and paint.delta != null and paint.delta.native_history_token > 0,
		"Hokusai native history token committed")
	if not paint.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var stamp: int = doc.revision
	var token: int = paint.delta.native_history_token
	var left: PackedByteArray = tile_bytes(doc, layer_id, "-1,0")
	var right: PackedByteArray = tile_bytes(doc, layer_id, "0,0")
	var dirty: Dictionary = doc._dirty_tiles.duplicate()
	var events: int = doc.history_length()
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(0.2, 0.4, 0.8, 1.0))
	var unsafe: Array[Dictionary] = [
		{"x": MIN_I64, "y": 0}, {"x": 0, "y": MIN_I64},
		{"x": MAX_I64, "y": 0}, {"x": 0, "y": MAX_I64},
		{"x": -LIMIT - 1, "y": 0}, {"x": 0, "y": -LIMIT - 1},
		{"x": LIMIT + 1, "y": 0}, {"x": 0, "y": LIMIT + 1},
	]
	for case: Dictionary in unsafe:
		var x: int = case["x"]
		var y: int = case["y"]
		var opened: DrawingResult = doc.begin_edit(layer_id, stamp,
			Transform2D.IDENTITY, x, y)
		check(not opened.ok and opened.code == "COORD_RANGE",
			"unsafe gesture anchor rejected before session creation: %d,%d" % [x, y])
		if opened.ok:
			(opened.value as DrawingEditSession).cancel()
		var drawn: DrawingResult = DrawingRenderer.render(doc, Rect2i(0, 0, 1, 1), x, y)
		check(not drawn.ok and drawn.code == "COORD_RANGE",
			"unsafe viewport anchor rejected before compositing: %d,%d" % [x, y])
		var imported: DrawingResult = DrawingRasterImport.import_image(
			doc, layer_id, image, x, y, stamp)
		check(not imported.ok and imported.code == "COORD_RANGE",
			"unsafe image anchor rejected before source mutation: %d,%d" % [x, y])
		check(doc.revision == stamp and doc._dirty_tiles == dirty and
			doc.history_length() == events and
			doc._native_raster_store == store and
			int(store.call("stats").get("revision", -1)) == stamp and
			store.call("has_history_token", token, stamp, true),
			"three rejected anchors leave native source and timeline unchanged: %d,%d" % [x, y])

	# Validate inputs before addition: MAX_I64 + 1 would wrap to INT64_MIN.
	var wrapped: DrawingResult = DrawingRenderer.render(doc,
		Rect2i(1, 0, 1, 1), MAX_I64, 0)
	check(not wrapped.ok and wrapped.code == "COORD_RANGE",
		"viewport origin checked before addition can overflow")
	var beyond: DrawingResult = DrawingRenderer.render(doc,
		Rect2i(1, 0, 1, 1), LIMIT, 0)
	check(not beyond.ok and beyond.code == "COORD_RANGE",
		"in-range origin plus viewport offset may leave bounded range")
	check(tile_bytes(doc, layer_id, "-1,0") == left and
		tile_bytes(doc, layer_id, "0,0") == right,
		"no rejected input changes Hokusai RGBA8 pixels")
	check(doc.undo().ok and doc.redo().ok and
		tile_bytes(doc, layer_id, "-1,0") == left and
		tile_bytes(doc, layer_id, "0,0") == right and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"Hokusai Undo/Redo remains exact after rejected public entrypoints")

	# Inclusive old anchors remain accepted: this guard is an integer safety
	# fix, not early Legacy retirement or a new 2^52-only viewport policy.
	var old: DrawingDocument = DrawingDocument.new("t161-historical", STRIDE)
	var old_layer: String = str(old.create_layer(DrawingLayerNode.RASTER, "Old").value)
	for anchor: int in [-LIMIT, LIMIT]:
		var edge: DrawingResult = old.begin_edit(old_layer, old.revision,
			Transform2D.IDENTITY, anchor, -anchor)
		check(edge.ok, "existing inclusive ±2^60 non-native session anchor accepted")
		if edge.ok:
			(edge.value as DrawingEditSession).cancel()
		var image_edge: DrawingResult = DrawingRenderer.render(old,
			Rect2i(0, 0, 1, 1), anchor, -anchor)
		check(image_edge.ok, "existing inclusive ±2^60 empty viewport accepted")
	check(DrawingRasterImport.import_image(old, old_layer, image, 0, 0, old.revision).ok,
		"ordinary image import remains available")
	check(old.undo().ok and old.redo().ok and
		int(old.read_pixel(old_layer, 0, 0).value) != 0,
		"ordinary raster import preserves exact local Undo/Redo")

	if failures == 0:
		print("T161_SIGNED_ANCHOR_PASSED checks=%d failures=0" % checks)
	else:
		print("T161_SIGNED_ANCHOR_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
