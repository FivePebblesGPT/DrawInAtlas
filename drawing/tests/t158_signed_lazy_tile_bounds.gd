extends SceneTree
## Signed lazy tile IDs must use the same bounded coordinate space as Rust.

const STRIDE: int = 64
const MAX_PIXEL: int = 4503599627370496
const HIDDEN_RGBA: int = 0x00123456
var checks: int = 0
var failures: int = 0
var fetches: int = 0
var bytes: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T158_TILE_BOUNDS_FAILED: " + label)


func fetch(_reference: String) -> PackedByteArray:
	fetches += 1
	return bytes.duplicate()


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "real native Hokusai engine available")
	var doc: DrawingDocument = DrawingDocument.new("t158-coordinates", STRIDE)
	var ink: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var started: DrawingResult = doc.begin_edit(ink, doc.revision)
	check(started.ok, "native ink gesture begins")
	if not started.ok:
		quit(1)
		return
	var session: DrawingEditSession = started.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, 0xff667788, Rect2i(-64, -64, 128, 128), true).ok,
		"Hokusai stroke configured")
	check(session.paint_path_native(PackedVector2Array([
		Vector2(-12, 10), Vector2(5, 10)]), 0xff667788, false, null).ok,
		"real Hokusai pigment staged")
	var painted: DrawingResult = session.commit()
	check(painted.ok and painted.delta != null and
		painted.delta.native_history_token > 0, "native stroke committed with history")
	if not painted.ok:
		quit(1)
		return
	var store: Object = doc._native_raster_store
	var token: int = painted.delta.native_history_token
	var ink_snapshot: PackedByteArray = (doc.request_chunk(ink, "-1,0").value as DrawingRasterTile).to_rgba8()
	var lazy: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	bytes.resize(STRIDE * STRIDE * 4)
	bytes.encode_u32(0, HIDDEN_RGBA)
	var digest: String = DrawingRasterTile.digest_rgba8(bytes, STRIDE)
	var limit: int = MAX_PIXEL / STRIDE
	var key: String = "%d,%d" % [limit, -limit]
	check(doc.register_lazy_chunk(lazy, limit, -limit, "far-valid", digest,
		Callable(self, "fetch")).ok, "maximally signed canonical lazy tile accepted")
	var revision: int = doc.revision
	var epoch: int = doc.display_source_epoch
	var pending: int = doc._pending_tiles.size()
	for invalid: int in [limit + 1, -limit - 1, 9223372036854775807, -9223372036854775807 - 1]:
		var rejected: DrawingResult = doc.register_lazy_chunk(lazy, invalid, 0,
			"far-invalid", digest, Callable(self, "fetch"))
		check(not rejected.ok and rejected.code == "COORD_RANGE",
			"out-of-range positive/negative signed tile ID fails before registration")
	check(doc.revision == revision and doc.display_source_epoch == epoch and
		doc._pending_tiles.size() == pending and doc._known_refs.size() == pending,
		"rejected IDs leave document and persistence metadata unchanged")
	check(fetches == 0 and doc._pending_tiles.has(lazy + ":" + key),
		"validation does not load or replace the valid distant source")
	check(doc._native_raster_store == store and
		store.call("has_history_token", token, revision, true),
		"registration failures leave Rust revision and history token valid")
	# Export a standalone lazy-only manifest: an unsaved Ink layer intentionally
	# has empty chunk refs and must not obscure this coordinate validation.
	var import_doc: DrawingDocument = DrawingDocument.new("t158-import", STRIDE)
	var import_layer: String = str(import_doc.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	check(import_doc.register_lazy_chunk(import_layer, limit, -limit,
		"import-valid", digest, Callable(self, "fetch")).ok,
		"create isolated valid lazy manifest source")
	var manifest_result: DrawingResult = import_doc.export_manifest()
	check(manifest_result.ok, "valid signed coordinate exports")
	if manifest_result.ok:
		var bad: Dictionary = (manifest_result.value as Dictionary).duplicate(true)
		for record: Dictionary in bad["layers"]:
			if record["id"] == import_layer:
				(record["chunks"] as Array)[0]["coord"] = [limit + 1, -limit]
		var bad_open: DrawingResult = DrawingDocument.open_manifest(bad, Callable(self, "fetch"))
		check(not bad_open.ok and bad_open.code == "COORD_RANGE",
			"logical manifest rejects unsafe lazy coordinate before loader")
	check(fetches == 0, "rejected manifest never calls lazy provider")
	var forged_key: String = "%d,0" % [limit + 1]
	var forged: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	forged.set_rgba(0, 0, HIDDEN_RGBA)
	doc._nodes[lazy].tiles[forged_key] = forged
	var forged_export: DrawingResult = doc.export_manifest()
	check(not forged_export.ok and forged_export.code == "COORD_RANGE",
		"manifest export refuses forged out-of-range resident tile")
	doc._nodes[lazy].tiles.erase(forged_key)
	check(doc.request_chunk(lazy, key).ok and fetches == 1 and
		int(doc.read_pixel(lazy, limit * STRIDE, -limit * STRIDE).value) == HIDDEN_RGBA,
		"valid distant signed tile resolves and retains hidden RGB")
	var encoded: DrawingResult = DrawingFileIO.encode(doc)
	check(encoded.ok, "valid large-coordinate standalone file encodes")
	if encoded.ok:
		var corrupt: Dictionary = (encoded.value as Dictionary).duplicate(true)
		for record: Dictionary in (corrupt["document"] as Dictionary)["layers"]:
			if record["id"] == lazy:
				(record["chunks"] as Array)[0]["coord"] = [str(limit + 1), str(-limit)]
		var bad_file: DrawingResult = DrawingFileIO.decode(corrupt)
		check(not bad_file.ok and bad_file.code == "COORD_RANGE",
			"portable .drawing decode rejects unsafe source metadata")
		var decoded: DrawingResult = DrawingFileIO.decode(encoded.value)
		check(decoded.ok and int((decoded.value as DrawingDocument).read_pixel(
			lazy, limit * STRIDE, -limit * STRIDE).value) == HIDDEN_RGBA,
			"valid distant signed source roundtrips exact RGBA8 through .drawing")
	check(doc._native_raster_store == store and doc.revision == revision and
		store.call("has_history_token", token, revision, true) and
		(doc.request_chunk(ink, "-1,0").value as DrawingRasterTile).to_rgba8() == ink_snapshot,
		"invalid persistence attempts never damage previously painted native Ink")
	check(doc.undo().ok and doc.redo().ok and
		(doc.request_chunk(ink, "-1,0").value as DrawingRasterTile).to_rgba8() == ink_snapshot,
		"prior native Undo/Redo remains exact after signed source validation")
	if failures == 0:
		print("T158_TILE_BOUNDS_PASSED checks=%d failures=0" % checks)
	else:
		print("T158_TILE_BOUNDS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
