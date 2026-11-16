extends SceneTree
## A lazy chunk resolver must not publish a source after its provider changes
## document revision, pending source identity, or recursively loads that key.

const STRIDE: int = 64
const INK: int = 0xff3456ab
var checks: int = 0
var failures: int = 0
var document: DrawingDocument
var lazy_layer: String = ""
var mode: String = ""
var calls: int = 0
var nested_result: DrawingResult
var original: PackedByteArray = PackedByteArray()
var replacement: PackedByteArray = PackedByteArray()
var swap_key: String = ""


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T157_LAZY_GUARD_FAILED: " + label)


func fetch_lazy(reference: String) -> PackedByteArray:
	calls += 1
	if mode == "lock":
		mode = "plain"
		check(document.set_locked(lazy_layer, true).ok,
			"provider changes the target layer's revision")
	elif mode == "swap":
		mode = "plain"
		document._pending_tiles[swap_key] = {
			"ref": "replacement", "sha256": DrawingRasterTile.digest_rgba8(replacement, STRIDE),
			"fetch": Callable(self, "fetch_lazy")}
	elif mode == "recurse":
		mode = "plain"
		nested_result = document.request_chunk(lazy_layer, "1,0")
	return replacement.duplicate() if reference == "replacement" else original.duplicate()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "native tile engine is loaded")
	document = DrawingDocument.new("t157-lazy", STRIDE)
	var ink_layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = document.begin_edit(ink_layer, document.revision)
	check(opened.ok, "open native ink session")
	if not opened.ok:
		quit(1)
		return
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(-64, -64, 128, 128), true).ok,
		"begin Hokusai stroke")
	check(session.paint_path_native(PackedVector2Array([Vector2(-19, 8),
		Vector2(-8, 8)]), INK, false, null).ok, "paint real ink")
	var committed: DrawingResult = session.commit()
	check(committed.ok and committed.delta != null and
		committed.delta.native_history_token > 0, "commit native history token")
	if not committed.ok:
		quit(1)
		return
	var store: Object = document._native_raster_store
	var ink_bytes: PackedByteArray = (document.request_chunk(ink_layer, "-1,0").value as DrawingRasterTile).to_rgba8()
	var token: int = committed.delta.native_history_token
	lazy_layer = str(document.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	original.resize(STRIDE * STRIDE * 4)
	original.encode_u32(0, 0x00335577) # alpha-zero hidden RGB
	replacement = original.duplicate()
	replacement.encode_u32(0, 0xff112233)
	var digest: String = DrawingRasterTile.digest_rgba8(original, STRIDE)
	check(document.register_lazy_chunk(lazy_layer, -1, 0, "original", digest,
		Callable(self, "fetch_lazy")).ok, "register signed lazy chunk")
	var initial_revision: int = document.revision
	mode = "lock"
	var stale: DrawingResult = document.request_chunk(lazy_layer, "-1,0")
	check(not stale.ok and stale.code == "STALE_REVISION",
		"reentrant revision invalidates lazy materialization")
	check(document.revision == initial_revision + 1 and
		int(store.call("stats").get("revision", -1)) == document.revision,
		"reentrant metadata change advances both timelines")
	check(document._pending_tiles.has(lazy_layer + ":-1,0") and
		not document._nodes[lazy_layer].tiles.has("-1,0"),
		"failed load retains pending source without installing bytes")
	check(document.set_locked(lazy_layer, false).ok, "restore editability")
	check(document.request_chunk(lazy_layer, "-1,0").ok and
		int(document.read_pixel(lazy_layer, -64, 0).value) == 0x00335577,
		"retry reads exact source including hidden RGB")
	check(document.register_lazy_chunk(lazy_layer, 0, 0, "original", digest,
		Callable(self, "fetch_lazy")).ok, "register second pending source")
	swap_key = lazy_layer + ":0,0"
	mode = "swap"
	var swap_revision: int = document.revision
	var swapped: DrawingResult = document.request_chunk(lazy_layer, "0,0")
	check(not swapped.ok and swapped.code == "STALE_SOURCE",
		"changed pending reference rejects old provider response")
	check(document.revision == swap_revision and
		document._pending_tiles.has(swap_key) and
		str(document._pending_tiles[swap_key].get("ref", "")) == "replacement" and
		not document._nodes[lazy_layer].tiles.has("0,0"),
		"provider's new pending source remains available for retry")
	check(document.request_chunk(lazy_layer, "0,0").ok and
		int(document.read_pixel(lazy_layer, 0, 0).value) == 0xff112233,
		"retry resolves new source, not stale earlier RGBA8")
	check(document.register_lazy_chunk(lazy_layer, 1, 0, "original", digest,
		Callable(self, "fetch_lazy")).ok, "register recursive source")
	mode = "recurse"
	var outer: DrawingResult = document.request_chunk(lazy_layer, "1,0")
	check(nested_result != null and not nested_result.ok and
		nested_result.code == "SOURCE_BUSY",
		"same-key recursive fetch fails explicitly without stack recursion")
	check(outer.ok and int(document.read_pixel(lazy_layer, 64, 0).value) == 0x00335577,
		"outer fetch can complete after rejecting nested fetch")
	check(document._pending_tiles.is_empty() and calls == 5,
		"all materializations complete with no duplicate recursive callback")
	check(document._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == document.revision and
		store.call("has_history_token", token, document.revision, true),
		"no lazy callback silently invalidates native history authority")
	check((document.request_chunk(ink_layer, "-1,0").value as DrawingRasterTile).to_rgba8() == ink_bytes,
		"unrelated ink canonical pixels remain unchanged")
	check(document.undo().ok and document.redo().ok and
		(document.request_chunk(ink_layer, "-1,0").value as DrawingRasterTile).to_rgba8() == ink_bytes,
		"native Undo/Redo remains functional after lazy callback retries")
	if failures == 0:
		print("T157_LAZY_GUARD_PASSED checks=%d failures=0" % checks)
	else:
		print("T157_LAZY_GUARD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
