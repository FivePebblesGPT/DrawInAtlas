extends SceneTree
## Retained native history tokens cannot bypass LIFO via detached replay.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const PAINT: int = 0xff336699
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T239_HISTORY_ORDER_FAILED: " + label)


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		return super._resolve_chunk(layer_id, key)


func fixture(label: String) -> Dictionary:
	var doc: CountingDocument = CountingDocument.new(label, STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.set_external_history(true).ok, "host history selected before edits")
	var first: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"0,0": 0}, {"0,0": HIDDEN})
	var second: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"64,0": 0}, {"64,0": PAINT})
	check(first.ok and second.ok and doc._native_raster_store != null,
		"two native-owned disjoint host commands committed")
	check(first.ok and first.delta.tile_stride == STRIDE and
		second.ok and second.delta.tile_stride == STRIDE and
		first.delta.native_history_token > 0 and second.delta.native_history_token > 0 and
		first.delta.native_history_token != second.delta.native_history_token,
		"host retained distinct tokenized tile deltas")
	return {"doc": doc, "layer": layer, "first": first.delta.detached_copy(),
		"second": second.delta.detached_copy()}


func test_undo_order() -> void:
	var f: Dictionary = fixture("t239-undo")
	var doc: DrawingDocument = f.doc
	var store: Object = doc._native_raster_store
	var first: DrawingDelta = f.first
	var second: DrawingDelta = f.second
	var original_revision: int = doc.revision
	check(bool(store.call("has_history_token", second.native_history_token,
		original_revision, true)), "latest token is current native Undo target")
	check(not bool(store.call("has_history_token", first.native_history_token,
		original_revision, true)), "earlier retained token is not current Undo target")
	var reads_before: int = doc.reads
	var invalid: DrawingResult = doc.replay_delta(first, true)
	check(not invalid.ok and invalid.code == "HISTORY_ORDER",
		"out-of-order retained Undo rejects instead of detached fallback")
	check(doc.reads == reads_before, "rejected retained Undo does not invoke a lazy source")
	check(doc.revision == original_revision and doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == original_revision,
		"rejection leaves native revision and store identity intact")
	check(int(doc.read_pixel(f.layer, 0, 0).value) == HIDDEN and
		int(doc.read_pixel(f.layer, 64, 0).value) == PAINT,
		"out-of-order rejection preserves both exact pixels")
	check(bool(store.call("has_history_token", second.native_history_token,
		doc.revision, true)), "rejection does not discard latest native Undo token")
	check(doc.replay_delta(second, true).ok and
		int(doc.read_pixel(f.layer, 64, 0).value) == 0,
		"correct top-of-stack Undo succeeds")
	check(doc.replay_delta(first, true).ok and
		int(doc.read_pixel(f.layer, 0, 0).value) == 0,
		"older Undo succeeds after top Undo")
	check(doc.replay_delta(first, false).ok and
		int(doc.read_pixel(f.layer, 0, 0).value) == HIDDEN,
		"normal Redo of older edit preserves hidden RGB")
	check(doc.replay_delta(second, false).ok and
		int(doc.read_pixel(f.layer, 64, 0).value) == PAINT,
		"normal Redo of newer edit restores host timeline")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"ordered history retains persistent Rust owner")


func test_redo_order() -> void:
	var f: Dictionary = fixture("t239-redo")
	var doc: DrawingDocument = f.doc
	var first: DrawingDelta = f.first
	var second: DrawingDelta = f.second
	check(doc.replay_delta(second, true).ok and doc.replay_delta(first, true).ok,
		"setup unwinds both native events in host order")
	var store: Object = doc._native_raster_store
	var revision_before: int = doc.revision
	check(bool(store.call("has_history_token", first.native_history_token,
		revision_before, false)), "oldest undone token is current Redo target")
	var reads_before: int = (doc as CountingDocument).reads
	var invalid: DrawingResult = doc.replay_delta(second, false)
	check(not invalid.ok and invalid.code == "HISTORY_ORDER",
		"out-of-order retained Redo rejects")
	check((doc as CountingDocument).reads == reads_before,
		"rejected retained Redo does not invoke a lazy source")
	check(doc.revision == revision_before and store == doc._native_raster_store and
		int(store.call("stats").get("revision", -1)) == revision_before,
		"rejected Redo leaves revision and native owner unchanged")
	check(doc.replay_delta(first, false).ok and doc.replay_delta(second, false).ok,
		"both Redo events remain replayable in order")


func test_detached_fallback() -> void:
	var f: Dictionary = fixture("t239-detached")
	var doc: DrawingDocument = f.doc
	var first: DrawingDelta = f.first
	first.native_history_token = 0
	var base: int = doc.revision
	check(doc.replay_delta(first, true).ok,
		"genuinely detached token-free history retains snapshot recovery")
	check(doc.revision == base + 1 and
		int(doc.read_pixel(f.layer, 0, 0).value) == 0 and
		int(doc.read_pixel(f.layer, 64, 0).value) == PAINT,
		"detached fallback still advances native RGBA8 canonically")


func test_evicted_token() -> void:
	var f: Dictionary = fixture("t239-evicted")
	var doc: DrawingDocument = f.doc
	var first: DrawingDelta = f.first
	# Rust retains at most 64 native history entries, while a host may keep
	# older detached snapshots. Subsequent disjoint edits evict the first token.
	for x: int in range(128, 128 + 64 * STRIDE, STRIDE):
		var done: DrawingResult = doc._publish_edit(f.layer, doc.revision,
			{"%d,0" % x: 0}, {"%d,0" % x: PAINT})
		if not done.ok:
			check(false, "eviction fixture records next native tile")
			return
	var store: Object = doc._native_raster_store
	check(not store.call("has_retained_history_token", first.native_history_token),
		"oldest token is absent after bounded native history eviction")
	var before: int = doc.revision
	var recovered: DrawingResult = doc.replay_delta(first, true)
	check(recovered.ok and doc.revision == before + 1 and
		doc._native_raster_store == store,
		"evicted host token can still replay its checked detached snapshot")
	check(int(doc.read_pixel(f.layer, 0, 0).value) == 0 and
		int(doc.read_pixel(f.layer, 64, 0).value) == PAINT,
		"evicted recovery changes only the requested tile")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native tile-store extension available")
	test_undo_order()
	test_redo_order()
	test_detached_fallback()
	test_evicted_token()
	if failures == 0:
		print("T239_HISTORY_ORDER_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T239_HISTORY_ORDER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
