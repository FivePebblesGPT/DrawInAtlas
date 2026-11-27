extends SceneTree
## An older bounded-out raster event must not destroy newer retained tokens.

const STRIDE: int = 64
const COUNT: int = 65
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T328_FAILED: " + message)


func context(doc: DrawingDocument) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.document_id = doc.id
	ctx.map_id = "world"
	ctx.selected_layer_ids.append("ink")
	return ctx


func step(doc: DrawingDocument, timeline: AtlasEditHistory, undo_action: bool) -> bool:
	if timeline != null:
		return timeline.undo() if undo_action else timeline.redo()
	return (doc.undo() if undo_action else doc.redo()).ok


func paint(doc: DrawingDocument, timeline: AtlasEditHistory, value: int) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit("ink", doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value
	var staged: DrawingResult = session.fill_rect(Rect2i(-1, 2, 1, 1), value)
	if not staged.ok:
		session.cancel()
		return staged
	var ctx: DrawingHistoryContext = context(doc)
	return timeline.commit_drawing(session, ctx, ctx) if timeline != null else session.commit()


func retained(store: Object, token: int) -> bool:
	return bool(store.call("has_retained_history_token", token))


func color(index: int) -> int:
	return (0x00335500 | index) if index > 0 else 0


func verify_pixel(doc: DrawingDocument, index: int) -> bool:
	var current: DrawingResult = doc.read_pixel("ink", -1, 2)
	var native: Dictionary = doc._native_raster_store.call("read_tile", "ink", -1, 0, false)
	var bytes: PackedByteArray = native.get("bytes", PackedByteArray())
	return current.ok and int(current.value) == color(index) and bool(native.get("ok", false)) and \
		bytes.size() == STRIDE * STRIDE * 4 and bytes.decode_u32((2 * STRIDE + STRIDE - 1) * 4) == color(index)


func test_eviction(external: bool) -> void:
	var doc: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), STRIDE)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok, "create raster")
	var timeline: AtlasEditHistory = null
	if external:
		check(doc.set_external_history(true).ok, "select host owner")
		timeline = AtlasEditHistory.new(AtlasCampaign.sample())
		timeline.active_map_id = "world"
	var tokens: Array[int] = []
	for index: int in range(1, COUNT + 1):
		var committed: DrawingResult = paint(doc, timeline, color(index))
		check(committed.ok and committed.delta != null and committed.delta.native_history_token > 0,
			"native history event %d" % index)
		if not committed.ok or committed.delta == null:
			return
		tokens.append(committed.delta.native_history_token)
	var store: Object = doc._native_raster_store
	check(not retained(store, tokens[0]) and retained(store, tokens[1]) and retained(store, tokens[-1]),
		"real 64-entry eviction, no synthetic token replacement")
	for index: int in range(COUNT - 1, 0, -1):
		check(step(doc, timeline, true) and verify_pixel(doc, index), "unwind retained event %d" % index)
	var revision: int = doc.revision
	check(int(store.call("stats").get("redo", -1)) == 64, "all newer tokens held on native Redo stack")
	var oldest: DrawingDelta = (timeline.get_undo_command() as AtlasDrawingEdit).delta if external else doc._events[0]["delta"]
	var good: Array[Dictionary] = [{"tile_x": -1, "tile_y": 0,
		"expected": oldest.after_tiles["-1,0"], "replacement": oldest.before_tiles["-1,0"]}]
	var bad: Array[Dictionary] = [{"tile_x": -1, "tile_y": 0,
		"expected": PackedByteArray([42]), "replacement": oldest.before_tiles["-1,0"]}]
	for attempt: Dictionary in [
		{"revision": revision, "token": tokens[1], "tiles": good},
		{"revision": revision - 1, "token": tokens[0], "tiles": good},
		{"revision": revision, "token": -1, "tiles": good},
		{"revision": revision, "token": tokens[0], "tiles": bad}]:
		var rejected: Dictionary = store.call("replay_ordered_detached_history", "ink",
			attempt.revision, attempt.token, attempt.tiles)
		check(not bool(rejected.get("ok", false)) and doc.revision == revision and
			int(store.call("stats").get("revision", -1)) == revision and verify_pixel(doc, 1) and
			int(store.call("stats").get("redo", -1)) == 64, "invalid ordered native replay leaves bytes and stacks intact")
	var held: Dictionary = store.call("begin_edit", "ink", revision, false)
	check(bool(held.get("ok", false)), "hold native edit")
	check(not step(doc, timeline, true) and verify_pixel(doc, 1) and doc.revision == revision and
		int(store.call("stats").get("redo", -1)) == 64, "busy replay preserves cursor and all tokens")
	check(bool(store.call("discard_edit", int(held.get("transaction", 0)))), "release native edit")
	check(step(doc, timeline, true) and verify_pixel(doc, 0) and doc.revision == revision + 1,
		"oldest evicted Undo replays exact blank bytes")
	check(int(store.call("stats").get("redo", -1)) == 64 and retained(store, tokens[1]) and retained(store, tokens[-1]),
		"ordered detached Undo preserves every newer native Redo")
	check(step(doc, timeline, false) and verify_pixel(doc, 1), "evicted Redo restores hidden RGB")
	check(bool(store.call("has_history_token", tokens[1], doc.revision, false)),
		"next chronological Redo remains a real native token")
	for index: int in range(2, COUNT + 1):
		check(step(doc, timeline, false) and verify_pixel(doc, index), "replay retained event %d" % index)
	check(int(store.call("stats").get("undo", -1)) == 64 and retained(store, tokens[-1]),
		"64 original tokens restored to native Undo stack")
	check(doc._native_raster_store == store and int(store.call("stats").get("revision", -1)) == doc.revision,
		"one canonical store and monotonic revision throughout")
	# Go through the same eviction boundary again and abandon the entire future.
	for index: int in range(COUNT - 1, -1, -1):
		check(step(doc, timeline, true) and verify_pixel(doc, index), "second unwind %d" % index)
	check(int(store.call("stats").get("redo", -1)) == 64, "repeat detached Undo retains tokens")
	var branch: DrawingResult = paint(doc, timeline, color(COUNT + 1))
	check(branch.ok and verify_pixel(doc, COUNT + 1) and
		int(store.call("stats").get("undo", -1)) == 1 and int(store.call("stats").get("redo", -1)) == 0 and
		not retained(store, tokens[1]) and not retained(store, tokens[-1]), "new branch discards genuinely abandoned tokens")
	check(not step(doc, timeline, false), "abandoned branch cannot Redo")
	check(step(doc, timeline, true) and verify_pixel(doc, 0) and step(doc, timeline, false) and
		verify_pixel(doc, COUNT + 1), "new branch remains byte-exact")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "compiled extension available")
	test_eviction(false)
	test_eviction(true)
	if failures == 0:
		print("T328_ORDERED_DETACHED_HISTORY_PASSED checks=%d failures=0" % checks)
	else:
		print("T328_ORDERED_DETACHED_HISTORY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
