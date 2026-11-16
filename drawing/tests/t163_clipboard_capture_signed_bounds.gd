extends SceneTree
## T-163: clipboard capture must not wrap signed source origins or local rects.

const LIMIT: int = 1152921504606846976
const MAX_I64: int = 9223372036854775807
const MIN_I64: int = -9223372036854775807 - 1
const MAX_I32: int = 2147483647
const STRIDE: int = 16
const HIDDEN: int = 0x00123456
var checks: int = 0
var failures: int = 0
var loader_calls: int = 0

class CountingDocument:
	extends DrawingDocument
	var resolves: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolves += 1
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T163_CLIPBOARD_FAILED: " + label)


func fetch(_ref: String) -> PackedByteArray:
	loader_calls += 1
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STRIDE * STRIDE * 4)
	bytes.encode_u32(0, HIDDEN)
	return bytes


func rejected(doc: CountingDocument, layer: String, area: Rect2i,
		ox: int, oy: int, label: String) -> void:
	var start_revision: int = doc.revision
	var start_epoch: int = doc.display_source_epoch
	var before_resolves: int = doc.resolves
	var before_loads: int = loader_calls
	var outcome: DrawingResult = DrawingClipboard.capture(doc, layer, area, null, ox, oy)
	check(not outcome.ok and outcome.code == "COORD_RANGE", label + " rejected")
	check(doc.revision == start_revision and doc.display_source_epoch == start_epoch
		and doc.resolves == before_resolves and loader_calls == before_loads,
		label + " leaves loader and source authority untouched")


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not opened.ok:
		return opened
	var edit: DrawingEditSession = opened.value as DrawingEditSession
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var started: DrawingResult = edit.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, 0xff776655, Rect2i(-16, -16, 64, 64), true)
	if not started.ok:
		edit.cancel()
		return started
	var dab: DrawingResult = edit.paint_path_native(
		PackedVector2Array([Vector2(4, 5), Vector2(12, 5)]),
		0xff776655, false, null)
	if not dab.ok:
		edit.cancel()
		return dab
	return edit.commit()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real native extension available")
	var doc: CountingDocument = CountingDocument.new("t163-clipboard", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var bytes: PackedByteArray = fetch("")
	loader_calls = 0
	check(doc.register_lazy_chunk(layer, 0, 0, "opaque-source",
		DrawingRasterTile.digest_rgba8(bytes, STRIDE), Callable(self, "fetch")).ok,
		"register hidden-RGB lazy source")

	# Origin must be validated *before* adding even a one-pixel Rect2i offset.
	rejected(doc, layer, Rect2i(1, 0, 1, 1), MAX_I64, 0, "MAX_I64 + 1")
	rejected(doc, layer, Rect2i(-1, 0, 1, 1), MIN_I64, 0, "MIN_I64 - 1")
	rejected(doc, layer, Rect2i(0, 1, 1, 1), 0, MAX_I64, "MAX_I64 y + 1")
	rejected(doc, layer, Rect2i(0, -1, 1, 1), 0, MIN_I64, "MIN_I64 y - 1")
	# Both the first and last selected source pixel must remain inside the
	# public signed anchor bound. An in-range first pixel alone is insufficient.
	rejected(doc, layer, Rect2i(1, 0, 1, 1), LIMIT, 0, "positive anchor outside public limit")
	rejected(doc, layer, Rect2i(-1, 0, 1, 1), -LIMIT, 0, "negative anchor outside public limit")
	rejected(doc, layer, Rect2i(0, 0, 3, 1), LIMIT - 1, 0, "positive last pixel outside")
	rejected(doc, layer, Rect2i(0, 0, 1, 3), 0, -LIMIT - 1, "negative origin outside")
	# Rect2i uses 32-bit coordinates: never build a clipboard whose selected
	# local positions wrap when they are stored back in Vector2i.
	rejected(doc, layer, Rect2i(MAX_I32, 0, 2, 1), 0, 0, "local x exceeds Vector2i")
	rejected(doc, layer, Rect2i(0, MAX_I32, 1, 2), 0, 0, "local y exceeds Vector2i")

	var valid_edge: DrawingResult = DrawingClipboard.capture(doc, layer,
		Rect2i(1, 0, 2, 1), null, LIMIT - 2, 0)
	check(valid_edge.ok and (valid_edge.value as DrawingClipboard)._pixels.is_empty(),
		"positive inclusive public boundary still works")
	var valid_negative: DrawingResult = DrawingClipboard.capture(doc, layer,
		Rect2i(-1, 0, 2, 1), null, -LIMIT + 1, 0)
	check(valid_negative.ok and (valid_negative.value as DrawingClipboard)._pixels.is_empty(),
		"negative inclusive public boundary still works")
	check(loader_calls == 0, "out-of-footprint valid captures do not materialize lazy data")

	var read: DrawingResult = DrawingClipboard.capture(doc, layer, Rect2i(0, 0, 8, 8))
	check(read.ok and loader_calls == 1 and
		(read.value as DrawingClipboard)._pixels.get(Vector2i.ZERO, -1) == HIDDEN,
		"valid lazy capture fetches once with exact hidden RGB")
	check(doc.revision == 1 and doc.display_source_epoch == 1,
		"lazy capture never writes document revision or epoch")

	# An existing native history token and its canonical tile must survive
	# bad clipboard coordinates. Copy is read-only, never a native rebase.
	var native_doc: CountingDocument = CountingDocument.new("t163-native", 64)
	var native_layer: String = str(native_doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var initial: DrawingResult = paint(native_doc, native_layer)
	check(initial.ok and initial.delta != null and
		initial.delta.native_history_token > 0, "real Hokusai source and history")
	if initial.ok:
		var store: Object = native_doc._native_raster_store
		var token: int = initial.delta.native_history_token
		var rev: int = native_doc.revision
		var canonical: Dictionary = store.call("read_tile", native_layer, 0, 0, false)
		rejected(native_doc, native_layer, Rect2i(0, 0, 2, 1), MAX_I64, 0,
			"native invalid signed capture")
		check(native_doc.revision == rev and
			int(store.call("stats").get("revision", -1)) == rev and
			store.call("has_history_token", token, rev, true),
			"bad capture preserves native revision and Undo token")
		check(store.call("read_tile", native_layer, 0, 0, false).get("bytes") ==
			canonical.get("bytes"), "bad capture preserves canonical Rust RGBA8")
		var normal: DrawingResult = DrawingClipboard.capture(native_doc,
			native_layer, Rect2i(0, 0, 24, 24))
		check(normal.ok and not (normal.value as DrawingClipboard)._pixels.is_empty(),
			"valid native-authored pixels remain copyable")
		check(native_doc.undo().ok and native_doc.redo().ok,
			"native Undo/Redo remains valid after rejected captures")

	print("T163_CLIPBOARD_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 30:
		print("T163_CLIPBOARD_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
