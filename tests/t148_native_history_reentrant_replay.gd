extends SceneTree
## T-148: lazy history source cannot reenter and consume the native token
## after changing document authority. Rejected preflight must retain history.

const STRIDE: int = 64
const INK: int = 0xff3456ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0
var source_calls: int = 0
var source_document: DrawingDocument
var source_layer: String = ""
var source_bytes: PackedByteArray = PackedByteArray()
var reenter_lock: bool = false
var lazy_by_reference: Dictionary[String, PackedByteArray] = {}
var tamper_previous: bool = false
var previous_key: String = ""
var tampered_bytes: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T148_HISTORY_REENTRANT_FAILED: " + label)


func packed(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var tile: DrawingResult = document.request_chunk(layer, key)
	if not tile.ok or tile.value == null:
		return PackedByteArray()
	return (tile.value as DrawingRasterTile).to_rgba8()


func fetch_lazy(reference: String) -> PackedByteArray:
	source_calls += 1
	if reenter_lock:
		check(source_document.set_locked(source_layer, true).ok,
			"lazy callback can change layer authority before returning source bytes")
	if tamper_previous and reference == "last":
		source_document._nodes[source_layer].tiles[previous_key] = \
			DrawingRasterTile.from_rgba8(STRIDE, tampered_bytes)
	return lazy_by_reference[reference].duplicate() if lazy_by_reference.has(reference) \
		else source_bytes.duplicate()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real native engine available")
	var doc: DrawingDocument = DrawingDocument.new("t148-reentrant", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "start edit on editable raster layer")
	if not opened.ok:
		quit(1)
		return
	var session: DrawingEditSession = opened.value
	var native: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(native, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"), 8.0, INK,
		CLIP, true).ok, "native tile stroke begins")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-20.5, 10.5), Vector2(-12.5, 10.5)]), INK, false, null).ok,
		"real Brush publishes a signed storage tile")
	var committed: DrawingResult = session.commit()
	check(committed.ok and committed.delta != null and
		committed.delta.native_history_token > 0 and
		committed.delta.tile_stride == STRIDE, "native history event carries whole-tile token")
	if not committed.ok:
		quit(1)
		return
	var key: String = "-1,0"
	var original: PackedByteArray = committed.delta.after_tiles.get(key, PackedByteArray())
	check(original.size() == STRIDE * STRIDE * 4,
		"committed tile has full packed RGBA8 source")
	var store: Object = doc._native_raster_store
	var starting_undo: int = int(store.call("stats").get("undo", -1))
	check(starting_undo == 1 and doc.can_undo(), "Rust and local history retain one edit")
	# A lazy materializer is allowed to modify the document while reentering.
	# It must NOT cause Undo to commit a stale Rust replay or mutate the cursor.
	doc._nodes[layer].tiles.erase(key)
	source_document = doc
	source_layer = layer
	source_bytes = original
	reenter_lock = true
	var registered: DrawingResult = doc.register_lazy_chunk(layer, -1, 0,
		"reentrant-source", DrawingRasterTile.digest_rgba8(original, STRIDE),
		Callable(self, "fetch_lazy"))
	check(registered.ok, "register lazy source for exact native-authored tile")
	var revision_before: int = doc.revision
	var rejected: DrawingResult = doc.undo()
	check(not rejected.ok and rejected.code == "STALE_REVISION",
		"reentrant layer lock rejects Undo before native history replay")
	check(source_calls == 1 and doc.revision == revision_before + 1 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"lazy callback advanced the shared revision exactly once")
	check(doc.can_undo() and not doc.can_redo() and
		int(store.call("stats").get("undo", -1)) == starting_undo and
		int(store.call("stats").get("redo", -1)) == 0,
		"rejected replay preserves local cursor and Rust token")
	check(packed(doc, layer, key) == original,
		"preflight does not replace or erase committed RGBA8 bytes")
	check(doc.set_locked(layer, false).ok,
		"restore layer editability for retry")
	reenter_lock = false
	check(doc.undo().ok and packed(doc, layer, key).is_empty(),
		"same native history token undoes on a later permitted attempt")
	check(doc.redo().ok and packed(doc, layer, key) == original,
		"native Redo restores exactly the same signed RGBA8 tile")
	check(int(store.call("stats").get("revision", -1)) == doc.revision and
		int(store.call("stats").get("undo", -1)) == 1,
		"Rust and document stay synchronized after retry/Redo")
	# Malformed detached input must fail *before* loading another source.
	var bad: DrawingDelta = committed.delta.detached_copy()
	bad.after_tiles["-01,0"] = bad.after_tiles[key].duplicate()
	var calls_before: int = source_calls
	var bad_result: DrawingResult = doc.replay_delta(bad, true)
	check(not bad_result.ok and source_calls == calls_before,
		"noncanonical detached tile key rejects without source callback")
	check(packed(doc, layer, key) == original and doc.revision ==
		int(store.call("stats").get("revision", -1)),
		"malformed replay leaves source and revision intact")
	# A later lazy provider may silently replace an earlier source *without*
	# changing the revision. Recheck the entire source set after all providers.
	var detached_doc: DrawingDocument = DrawingDocument.new("t148-two-lazy", STRIDE)
	var detached_layer: String = str(detached_doc.create_layer(
		DrawingLayerNode.RASTER, "Two lazy tiles").value)
	var left: PackedByteArray = PackedByteArray()
	left.resize(STRIDE * STRIDE * 4)
	left.encode_u32(0, 0x00335577) # transparent hidden RGB
	var right: PackedByteArray = left.duplicate()
	right.encode_u32(0, 0xff112233)
	var target_left: PackedByteArray = left.duplicate()
	target_left.encode_u32(4, 0xff778899)
	var target_right: PackedByteArray = right.duplicate()
	target_right.encode_u32(4, 0xffaabbcc)
	var detached: DrawingDelta = DrawingDelta.from_owned_tile_bytes(detached_layer,
		STRIDE, {"-1,0": target_left, "0,0": target_right},
		{"-1,0": left, "0,0": right})
	var changed_keys: Array[String] = detached.after_tiles.keys()
	var first_key: String = changed_keys[0]
	var last_key: String = changed_keys[1]
	source_document = detached_doc
	source_layer = detached_layer
	reenter_lock = false
	tamper_previous = true
	previous_key = first_key
	tampered_bytes = left.duplicate()
	tampered_bytes.encode_u32(8, 0xff445566)
	lazy_by_reference = {"first": detached.after_tiles[first_key],
		"last": detached.after_tiles[last_key]}
	for index: int in changed_keys.size():
		var tile_key: String = changed_keys[index]
		var coords: PackedStringArray = tile_key.split(",")
		var ref_name: String = "first" if index == 0 else "last"
		var contents: PackedByteArray = lazy_by_reference[ref_name]
		check(detached_doc.register_lazy_chunk(detached_layer,
			int(coords[0]), int(coords[1]), ref_name,
			DrawingRasterTile.digest_rgba8(contents, STRIDE),
			Callable(self, "fetch_lazy")).ok,
			"register detached history source tile " + tile_key)
	var detached_revision: int = detached_doc.revision
	var stale_source: DrawingResult = detached_doc.replay_delta(detached, true)
	check(not stale_source.ok and stale_source.code == "STALE_PIXEL",
		"later lazy callback cannot substitute an earlier history source")
	check(detached_doc.revision == detached_revision and
		packed(detached_doc, detached_layer, first_key) == tampered_bytes and
		packed(detached_doc, detached_layer, last_key) == detached.after_tiles[last_key],
		"rejected detached replay installs no history replacement tiles")
	# Fix the independently tampered source and retry with the same delta.
	detached_doc._nodes[detached_layer].tiles[first_key] = \
		DrawingRasterTile.from_rgba8(STRIDE, detached.after_tiles[first_key])
	tamper_previous = false
	check(detached_doc.replay_delta(detached, true).ok,
		"detached snapshot replays atomically once lazy sources are stable")
	check(packed(detached_doc, detached_layer, "-1,0") == target_left and
		packed(detached_doc, detached_layer, "0,0") == target_right and
		detached_doc.revision == detached_revision + 1,
		"successful detached replay publishes both complete signed RGBA8 tiles")
	if failures == 0:
		print("T148_HISTORY_REENTRANT_PASSED checks=%d failures=0" % checks)
	else:
		print("T148_HISTORY_REENTRANT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
