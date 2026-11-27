extends SceneTree
## T-155: changing semantic text after undoing a painted rasterization must
## replace its parked native source without discarding other layers' history.

const STRIDE: int = 64
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T155_RERASTER_FAILED: " + label)


func stroke(doc: DrawingDocument, layer: String, pos: Vector2) -> DrawingResult:
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		return started
	var session: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var preset: String = FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb")
	var began: DrawingResult = session.begin_native_stroke(brush, preset,
		8.0, 0xff5599cc, Rect2i(0, 0, STRIDE, STRIDE), true)
	if not began.ok:
		session.cancel()
		return began
	var drew: DrawingResult = session.paint_path_native(
		PackedVector2Array([pos, pos + Vector2(10, 0)]),
		0xff5599cc, false, null)
	if not drew.ok:
		session.cancel()
		return drew
	return session.commit()


func tile_bytes(doc: DrawingDocument, layer: String) -> PackedByteArray:
	var requested: DrawingResult = doc.request_chunk(layer, "0,0")
	if not requested.ok or requested.value == null:
		return PackedByteArray()
	return (requested.value as DrawingRasterTile).to_rgba8()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native raster store loaded")
	var doc: DrawingDocument = DrawingDocument.new("t155-reraster", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER,
		"Ink", "root", "ink").value)
	check(stroke(doc, ink, Vector2(14, 14)).ok, "native ink token committed")
	var store: Object = doc._native_raster_store
	var ink_bytes: PackedByteArray = tile_bytes(doc, ink)
	var ink_undo: int = int(store.call("stats").get("undo", -1))
	var element: DrawingTextElement = DrawingTextElement.new()
	element.content = "First glyph"
	element.position = Vector2i(2, 3)
	element.font_size = 20
	var created: DrawingResult = doc.commit_text("", element, doc.revision,
		"root", "glyph-reuse")
	check(created.ok, "semantic text layer created")
	if not created.ok:
		quit(1)
		return
	var layer: String = str(created.value)
	check(doc.rasterize_text(layer, doc.revision).ok, "first glyph rasterized")
	var original: PackedByteArray = tile_bytes(doc, layer)
	check(stroke(doc, layer, Vector2(25, 24)).ok, "first glyph painted in native store")
	check(doc.undo().ok and tile_bytes(doc, layer) == original,
		"first glyph stroke undone to canonical source")
	check(doc.undo().ok and doc.inspect_node(layer).kind == DrawingLayerNode.TEXT,
		"old text conversion undone")
	check(bool(store.call("is_layer_parked", layer)) and
		int(store.call("stats").get("undo", -1)) == ink_undo,
		"old glyph is parked; unrelated ink history retained")
	var edited: DrawingTextElement = element.detached_copy()
	edited.content = "Second, distinct glyph"
	check(doc.commit_text(layer, edited, doc.revision).ok,
		"edited semantic text discards obsolete conversion Redo")
	var before: int = doc.revision
	var rerastered: DrawingResult = doc.rasterize_text(layer, before)
	check(rerastered.ok, "edited glyph rasterization committed")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"new conversion shares Rust revision without a history-clearing rebase")
	check(not bool(store.call("is_layer_parked", layer)),
		"stale glyph tombstone retired in the same transaction")
	check(int(store.call("stats").get("undo", -1)) == ink_undo and
		int(store.call("stats").get("redo", -1)) == 0,
		"unrelated ink Undo survives; obsolete glyph Redo is discarded")
	var second: PackedByteArray = tile_bytes(doc, layer)
	check(second != original and not second.is_empty(),
		"new text source differs from previously parked pixels")
	check(doc._native_source_identities.has(layer + ":0,0") and
		is_same(doc._native_source_identities[layer + ":0,0"], doc._nodes[layer].tiles["0,0"]) and
		(store.call("read_tile", layer, 0, 0, false) as Dictionary).get("bytes") == second,
		"old native Godot source identity is replaced with the new glyph projection")
	check(stroke(doc, layer, Vector2(25, 24)).ok,
		"new glyph can be painted without a rebase or stale source import")
	var painted_second: PackedByteArray = tile_bytes(doc, layer)
	check(painted_second != second, "new Hokusai stroke changes new glyph bytes")
	check(doc._native_raster_store == store and
		int(store.call("stats").get("undo", -1)) == ink_undo + 1,
		"both unrelated Ink and replacement glyph tokens remain in one store")
	check(doc.undo().ok and tile_bytes(doc, layer) == second,
		"new glyph native Undo restores exact second source")
	check(doc.redo().ok and tile_bytes(doc, layer) == painted_second,
		"new glyph native Redo restores exact second paint")
	check(tile_bytes(doc, ink) == ink_bytes,
		"unrelated Ink canonical pixels remain exact")
	var save_path: String = ProjectSettings.globalize_path("user://t155-" +
		DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, save_path).ok, "edited glyph saves")
	var reopened: DrawingResult = DrawingFileIO.open(save_path)
	check(reopened.ok and tile_bytes(reopened.value as DrawingDocument, layer) == painted_second and
		tile_bytes(reopened.value as DrawingDocument, ink) == ink_bytes,
		"Save/Open preserves exact replaced glyph and ink RGBA8")
	DirAccess.remove_absolute(save_path)
	check(doc.undo().ok and doc.undo().ok and
		bool(store.call("is_layer_parked", layer)),
		"Undo new paint and conversion parks replacement raster")
	var held: Dictionary = store.call("begin_edit", ink, doc.revision, false)
	check(bool(held.get("ok", false)), "active Ink transaction established")
	var guarded_revision: int = doc.revision
	var rejected_active: DrawingResult = doc.rasterize_text(layer, guarded_revision)
	check(not rejected_active.ok and rejected_active.code == "NATIVE_STRUCTURE" and
		doc.revision == guarded_revision and
		int(store.call("stats").get("revision", -1)) == guarded_revision and
		doc.inspect_node(layer).kind == DrawingLayerNode.TEXT and
		bool(store.call("is_layer_parked", layer)),
		"active native transaction rejects replacement without mutating either store")
	check(store.call("discard_edit", int(held.get("transaction", 0))),
		"active Ink transaction cancelled after refusal")
	check(doc.rasterize_text(layer, doc.revision).ok and
		int(store.call("stats").get("revision", -1)) == doc.revision and
		not bool(store.call("is_layer_parked", layer)),
		"identical conversion retry succeeds after cancellation")
	check(int(store.call("stats").get("undo", -1)) == ink_undo and
		tile_bytes(doc, ink) == ink_bytes,
		"retry preserves unrelated ink token and hidden source bytes")
	var ahead_text: DrawingResult = doc.commit_text("", element, doc.revision,
		"root", "ahead-text")
	check(ahead_text.ok, "set up separate text for native-ahead negative case")
	var host_revision: int = doc.revision
	check(store.call("advance_metadata_revision", host_revision, false),
		"inject native-ahead revision without editing document")
	var ahead_rejected: DrawingResult = doc.rasterize_text("ahead-text", host_revision)
	check(not ahead_rejected.ok and ahead_rejected.code == "STALE_REVISION" and
		doc.revision == host_revision and
		int(store.call("stats").get("revision", -1)) == host_revision + 1 and
		doc.inspect_node("ahead-text").kind == DrawingLayerNode.TEXT,
		"ahead native authority rejects conversion without partial Godot publication")
	print("T155_RERASTER_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
