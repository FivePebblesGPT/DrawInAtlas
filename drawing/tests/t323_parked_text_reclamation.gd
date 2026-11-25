extends SceneTree
## Abandoned conversion history must not pin native glyph sources.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T323_FAILED: " + label)

func paint(doc: DrawingDocument, layer: String, x: int, y: int) -> int:
	var key: String = "%d,%d" % [x, y]
	if not doc._publish_edit(layer, doc.revision, {key: 0}, {key: 0x00123456}).ok:
		return 0
	return (doc._events.back()["delta"] as DrawingDelta).native_history_token

func fixture() -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t323", 64)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Other", "root", "other").ok, "other layer")
	check(paint(doc, "other", 1, 1) > 0, "native other paint")
	var text: DrawingTextElement = DrawingTextElement.new()
	text.content = "Glyph"
	text.position = Vector2i(-40, -30)
	text.font_size = 22
	check(doc.commit_text("", text, doc.revision, "root", "glyph").ok, "text creation")
	check(doc.rasterize_text("glyph", doc.revision).ok, "text conversion")
	return doc

func branch(mode: String) -> void:
	var doc: DrawingDocument = fixture()
	var store: Object = doc._native_raster_store
	var other_token: int = (doc._events[0]["delta"] as DrawingDelta).native_history_token
	check(doc.undo().ok, "park conversion")
	check(bool(store.call("is_layer_parked", "glyph")), "glyph parked")
	check(doc.redo().ok, "retained conversion remains replayable")
	var token: int = paint(doc, "glyph", -129, 0)
	check(token > 0, "native glyph paint")
	check(doc.undo().ok and doc.undo().ok, "undo paint and conversion")
	var rev: int = doc.revision
	var bytes_before: int = int(store.call("stats")["bytes_used"])
	if mode == "selection":
		doc.record_selection_history = true
		var before: DrawingHistoryContext = DrawingHistoryContext.new()
		var after: DrawingHistoryContext = DrawingHistoryContext.new()
		after.selected_layer_ids.append("other")
		var active: Dictionary = store.call("begin_edit", "other", rev, false)
		check(bool(active.get("ok", false)), "unrelated native edit")
		check(doc.record_selection_change(before, after), "selection branch")
		check(doc.revision == rev and bool(store.call("discard_edit", int(active.get("transaction", 0)))), "preserve revision and reservation")
	elif mode == "remove":
		check(doc.remove_subtree("glyph", true).ok and not doc.has_node("glyph"), "remove semantic text branch")
	else:
		check(doc.rename_layer("other", "Changed", true).ok and doc.revision == rev + 1, "metadata branch")
	check(not doc.can_redo() and not bool(store.call("is_layer_parked", "glyph")), "release abandoned glyph reservation")
	check(not bool(store.call("has_retained_history_token", token)) and bool(store.call("has_retained_history_token", other_token)), "release only glyph paint token")
	var remaining: int = 0
	for identity: String in doc._native_source_identities:
		if identity.begins_with("glyph:"):
			remaining += 1
	check(remaining == 0, "remove glyph projection identities")
	check(int(store.call("stats")["bytes_used"]) < bytes_before, "native resident memory reclaimed")
	check(not bool(store.call("has_source", "glyph", -3, 0, doc.revision)), "release blank paint authorization")
	if mode == "remove":
		check(doc.undo().ok and doc.has_node("glyph"), "Undo removal restores semantic text only")
	check(doc.inspect_node("glyph").kind == DrawingLayerNode.TEXT and doc.snapshot_for_save().ok, "live semantic text preserved")
	check(doc.rasterize_text("glyph", doc.revision).ok and not bool(store.call("is_layer_parked", "glyph")), "fresh conversion after branch")
	check(doc.undo().ok, "new conversion Undo")
	check(doc.redo().ok, "new conversion Redo")

func rejection_cases() -> void:
	var doc: DrawingDocument = fixture()
	var store: Object = doc._native_raster_store
	var count: int = doc.tile_keys("glyph").size()
	check(not bool(store.call("discard_parked_source", doc.revision, "glyph", count)), "live source cannot be reclaimed")
	var token: int = paint(doc, "glyph", -129, 0)
	check(token > 0 and doc.undo().ok and doc.undo().ok, "park with retained paint Redo")
	var rev: int = doc.revision
	var size: int = int(store.call("stats")["bytes_used"])
	check(not bool(store.call("discard_parked_source", rev, "glyph", count + 1)), "retained paint token prevents reclamation")
	check(not bool(store.call("discard_parked_source", rev - 1, "glyph", count + 1)), "stale revision rejects")
	check(int(store.call("stats")["bytes_used"]) == size, "failed reclamations preserve memory")
	check(doc.redo().ok and doc.redo().ok, "rejected cleanup preserves exact Redo")
	check(int(doc.read_pixel("glyph", -129, 0).value) == 0x00123456, "hidden RGB retained")
	check(doc.undo().ok and doc.undo().ok, "rewind again")
	var snapshot: DrawingLayerNode = doc._events[doc.history_position()]["after"]
	var key: String = snapshot.tiles.keys()[0]
	var tile: DrawingRasterTile = snapshot.tiles[key]
	tile.set_rgba(0, 0, tile.get_rgba(0, 0) ^ 0x00010203)
	doc.record_selection_history = true
	var before: DrawingHistoryContext = DrawingHistoryContext.new()
	var after: DrawingHistoryContext = DrawingHistoryContext.new()
	after.selected_layer_ids.append("other")
	check(doc.record_selection_change(before, after), "branch with tampered retained snapshot")
	check(bool(store.call("is_layer_parked", "glyph")), "corrupt snapshot fails closed, not reclaimed")
	check(not bool(store.call("discard_parked_source", doc.revision, "glyph", count)), "incomplete source cardinality rejects")
	check(doc.snapshot_for_save().ok, "semantic save unaffected")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension")
	branch("metadata")
	branch("selection")
	branch("remove")
	rejection_cases()
	print("T323 checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T323_PARKED_TEXT_RECLAMATION_PASSED")
	quit(1 if failures else 0)
