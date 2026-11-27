extends SceneTree
## Rasterization must publish the glyph source itself, not wait for a Brush.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T313_FAILED: " + label)


func source_matches(doc: DrawingDocument, layer: String) -> bool:
	var store: Object = doc._native_raster_store
	if store == null or doc.tile_keys(layer).is_empty():
		return false
	for key: String in doc.tile_keys(layer):
		var parts: PackedStringArray = key.split(",")
		if not bool(store.call("has_source", layer, int(parts[0]), int(parts[1]), doc.revision)):
			return false
		var read: Dictionary = store.call("read_tile", layer, int(parts[0]), int(parts[1]), false)
		var tile: DrawingRasterTile = doc.request_chunk(layer, key).value
		if not bool(read.get("ok", false)) or read.get("bytes") != tile.to_rgba8():
			return false
	return true


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native tile ABI loaded")
	var doc: DrawingDocument = DrawingDocument.new("t313-glyphs", 64)
	var text: DrawingTextElement = DrawingTextElement.new()
	text.content = "Signed glyph"
	text.position = Vector2i(-48, -21)
	text.font_size = 24
	var layer: String = str(doc.commit_text("", text, doc.revision, "root", "glyph").value)
	var area: Rect2i = Rect2i(-80, -60, 240, 140)
	var before: DrawingResult = DrawingRenderer.render(doc, area)
	var start_revision: int = doc.revision
	var start_history: int = doc.history_length()
	check(doc.rasterize_text(layer, doc.revision).ok, "first rasterization succeeds")
	check(doc.revision == start_revision + 1 and doc.history_length() == start_history + 1,
		"one structural revision and one local history event")
	check(source_matches(doc, layer), "first conversion immediately authorizes every glyph tile in Rust")
	var after: DrawingResult = DrawingRenderer.render(doc, area)
	check(before.ok and after.ok and (before.value as Image).get_data() == (after.value as Image).get_data(),
		"semantic and raster image match exactly")
	var store: Object = doc._native_raster_store
	if store == null:
		check(false, "first conversion bootstraps a persistent Rust owner")
		finish()
		return
	check(int(store.call("stats").get("revision")) == doc.revision and int(store.call("stats").get("undo")) == 0,
		"native revision shares structural event without an extra pixel Undo token")
	var glyph_key: String = doc.tile_keys(layer)[0]
	var glyph_tile: DrawingRasterTile = doc._nodes[layer].tiles[glyph_key]
	var glyph_pixel: int = glyph_tile.get_rgba(0, 0)
	glyph_tile.set_rgba(0, 0, glyph_pixel ^ 0x00ffffff)
	var guarded_revision: int = doc.revision
	check(not doc.snapshot_for_save().ok and not doc.undo().ok and doc.revision == guarded_revision,
		"in-place projection mutation rejected even before first Brush")
	glyph_tile.set_rgba(0, 0, glyph_pixel)
	check(doc.undo().ok and bool(store.call("is_layer_parked", layer)), "Undo parks unpainted glyph source")
	check(doc.snapshot_for_save().ok and doc.export_subtree(layer).ok,
		"parked glyphs do not contaminate the live semantic save or copy")
	var semantic_path: String = ProjectSettings.globalize_path("user://t313-semantic-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, semantic_path).ok, "semantic text can save while native raster is parked")
	var semantic_opened: DrawingResult = DrawingFileIO.open(semantic_path)
	check(semantic_opened.ok and (semantic_opened.value as DrawingDocument).inspect_node(layer).kind == DrawingLayerNode.TEXT,
		"semantic Save/Open does not resurrect parked raster")
	DirAccess.remove_absolute(semantic_path)
	var snapshot: DrawingLayerNode = doc._events[doc._cursor]["after"]
	var snapshot_tile: DrawingRasterTile = snapshot.tiles[glyph_key]
	var snapshot_pixel: int = snapshot_tile.get_rgba(0, 0)
	snapshot_tile.set_rgba(0, 0, snapshot_pixel ^ 0x00ffffff)
	guarded_revision = doc.revision
	check(not doc.redo().ok and doc.revision == guarded_revision and bool(store.call("is_layer_parked", layer)),
		"mutated detached raster snapshot rejected without consuming structural Redo")
	snapshot_tile.set_rgba(0, 0, snapshot_pixel)
	check(doc.redo().ok and source_matches(doc, layer), "Redo restores exact canonical glyph source")
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").value)
	var edit: DrawingEditSession = doc.begin_edit(ink, doc.revision).value
	check(edit.fill_rect(Rect2i(-2, -2, 4, 4), 0x00112233).ok and edit.commit().ok,
		"unrelated native edit records hidden RGB")
	var ink_pixel: int = int(doc.read_pixel(ink, -1, -1).value)
	check(ink_pixel == 0x00112233, "hidden RGB retained")
	var second: String = str(doc.commit_text("", text, doc.revision, "root", "second").value)
	check(doc.rasterize_text(second, doc.revision).ok and source_matches(doc, second),
		"existing owner immediately authorizes second conversion")
	check(doc._native_raster_store == store and int(store.call("stats").get("undo")) == 1,
		"unrelated native token retained")
	check(doc.undo().ok and bool(store.call("is_layer_parked", second)), "second conversion parked before any paint")
	var changed: DrawingTextElement = text.detached_copy()
	changed.content = "Changed glyph"
	changed.position = Vector2i(72, 48)
	check(doc.commit_text(second, changed, doc.revision).ok, "semantic edit branches parked glyphs")
	check(doc.rasterize_text(second, doc.revision).ok and source_matches(doc, second),
		"replacement glyph source immediately native")
	check(not bool(store.call("is_layer_parked", second)) and
		not bool(store.call("has_source", second, -1, -1, doc.revision)), "obsolete signed glyph tiles retired")
	check(int(doc.read_pixel(ink, -1, -1).value) == ink_pixel and int(store.call("stats").get("undo")) == 1,
		"replacement preserves unrelated hidden RGB and history")
	# Rejected direct FFI calls must not authorize a prefix of a malformed batch.
	var tile_bytes: PackedByteArray = PackedByteArray()
	tile_bytes.resize(64 * 64 * 4)
	tile_bytes.encode_u32(0, 0x00112233)
	var descriptor: Dictionary = {"tile_x": -3, "tile_y": 4, "bytes": tile_bytes}
	var invalid_descriptors: Array[Dictionary] = [descriptor, {"tile_x": 4, "tile_y": 4, "bytes": PackedByteArray([1])}]
	var duplicates: Array[Dictionary] = [descriptor, descriptor]
	var prior: Dictionary = store.call("stats")
	check(not bool(store.call("publish_structural_source_revision", "invalid", doc.revision, invalid_descriptors)),
		"late malformed source descriptor rejects whole batch")
	check(not bool(store.call("publish_structural_source_revision", "invalid", doc.revision, duplicates)),
		"duplicate structural source tiles rejected")
	var unchanged: Dictionary = store.call("stats")
	check(unchanged.get("revision") == prior.get("revision") and unchanged.get("bytes_used") == prior.get("bytes_used") and
		unchanged.get("bytes_imported") == prior.get("bytes_imported") and not bool(store.call("has_source", "invalid", -3, 4, doc.revision)),
		"malformed structural source batches have no native side effects")
	var pending_text: String = str(doc.commit_text("", text, doc.revision, "root", "pending").value)
	var pending_edit: DrawingEditSession = doc.begin_edit(ink, doc.revision).value
	guarded_revision = doc.revision
	check(not doc.rasterize_text(pending_text, guarded_revision).ok and doc.revision == guarded_revision and
		doc.inspect_node(pending_text).kind == DrawingLayerNode.TEXT,
		"pending script session reserves raster source publication")
	pending_edit.cancel()
	check(doc.rasterize_text(pending_text, doc.revision).ok and source_matches(doc, pending_text),
		"identical conversion succeeds after cancelling pending session")
	var transparent: DrawingTextElement = text.detached_copy()
	transparent.color_rgba = 0x00112233
	var empty: String = str(doc.commit_text("", transparent, doc.revision, "root", "transparent").value)
	check(doc.rasterize_text(empty, doc.revision).ok and doc.tile_keys(empty).is_empty(),
		"fully transparent text conversion has no fabricated native raster source")
	check(doc.undo().ok and not bool(store.call("is_layer_parked", empty)) and doc.redo().ok,
		"empty source structural replay requires no tombstone")
	var path: String = ProjectSettings.globalize_path("user://t313-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "native source saves")
	var loaded: DrawingResult = DrawingFileIO.open(path)
	check(loaded.ok, "native text-derived raster opens")
	if loaded.ok:
		var restored: DrawingDocument = loaded.value
		var a: DrawingResult = DrawingRenderer.render(doc, area)
		var b: DrawingResult = DrawingRenderer.render(restored, area)
		check(a.ok and b.ok and (a.value as Image).get_data() == (b.value as Image).get_data(), "Save/Open exact composite")
	DirAccess.remove_absolute(path)
	finish()


func finish() -> void:
	print("T313_NATIVE_TEXT_SOURCE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
