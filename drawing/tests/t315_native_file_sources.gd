extends SceneTree
## Portable file loading must authorize every validated source before returning.

const STRIDE: int = 64
const HIDDEN: int = 0x00112233
const INK: int = 0xff987654
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T315_FAILED: " + label)


func matches(doc: DrawingDocument, layer: String, key: String, bytes: PackedByteArray) -> bool:
	var store: Object = doc._native_raster_store
	if store == null:
		return false
	var coords: PackedStringArray = key.split(",")
	return bool(store.call("has_source", layer, int(coords[0]), int(coords[1]), doc.revision)) and \
		store.call("read_tile", layer, int(coords[0]), int(coords[1]), false).get("bytes") == bytes and \
		doc._native_source_matches(layer, key, doc._nodes[layer].tiles.get(key))


func exercise(doc: DrawingDocument, saved_revision: int, bytes: PackedByteArray, label: String) -> void:
	check(doc.revision == saved_revision and doc.published_revision == saved_revision and not doc.is_dirty() and doc.history_length() == 0, label + ": load is not an edit")
	check(matches(doc, "ink", "-1,2", bytes) and matches(doc, "hidden", "2,-3", bytes), label + ": all signed sources native before first paint")
	var store: Object = doc._native_raster_store
	check(store != null, label + ": store attached")
	if store == null:
		return
	var stats: Dictionary = store.call("stats")
	check(int(stats["tiles"]) == 2 and int(stats["undo"]) == 0 and int(stats["redo"]) == 0 and int(stats["revision"]) == saved_revision, label + ": exact native initial state")
	check(doc._pending_tiles.is_empty() and doc._dirty_tiles.is_empty() and doc._known_refs.size() == 2, label + ": no dirty tiles or stale lazy refs")
	check(not doc._editable("hidden"), label + ": locked/hidden metadata intact")
	var projected: DrawingRasterTile = doc._nodes["ink"].tiles["-1,2"]
	projected.set_rgba(1, 2, 0x00445566)
	check(not DrawingFileIO.encode(doc).ok and not doc.export_subtree("ink").ok, label + ": unauthorized hidden RGB rejected before paint")
	projected.set_rgba(1, 2, HIDDEN)
	check(DrawingFileIO.encode(doc).ok and doc.export_subtree("ink").ok, label + ": exact correction retries")
	var edit: DrawingEditSession = doc.begin_edit("ink", doc.revision).value
	check(edit.fill_rect(Rect2i(-STRIDE + 1, 2 * STRIDE + 2, 1, 1), INK).ok and edit.commit().ok, label + ": edit authorized source")
	check(doc._native_raster_store == store and doc.history_length() == 1 and int(doc.read_pixel("ink", -STRIDE + 1, 2 * STRIDE + 2).value) == INK, label + ": edit retains owner")
	check(doc.undo().ok and matches(doc, "ink", "-1,2", bytes) and not doc.is_dirty(), label + ": undo restores published baseline")
	check(doc.redo().ok and doc.undo().ok, label + ": redo/undo exact")
	check(doc.remove_subtree("ink", true).ok and bool(store.call("is_layer_parked", "ink")), label + ": loaded source parks")
	check(doc.undo().ok and matches(doc, "ink", "-1,2", bytes), label + ": structural restore retains loaded bytes")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension loaded")
	var original: DrawingDocument = DrawingDocument.new("portable", STRIDE)
	original.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink")
	original.create_layer(DrawingLayerNode.RASTER, "Hidden", "root", "hidden")
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 2, HIDDEN)
	tile.set_rgba(3, 4, INK)
	var bytes: PackedByteArray = tile.to_rgba8()
	original._nodes["ink"].tiles["-1,2"] = tile
	original._nodes["hidden"].tiles["2,-3"] = tile.detached_copy()
	original.set_visibility("hidden", false)
	original.set_locked("hidden", true)
	var saved_revision: int = original.revision
	var base: String = ProjectSettings.globalize_path("user://t315-" + DrawingDocument.new_id())
	for legacy: bool in [false, true]:
		var label: String = "legacy" if legacy else "binary"
		var path: String = base + "-" + label + ".drawing"
		check(DrawingFileIO.save(original, path, {}, legacy).ok, label + ": file saved")
		var opened: DrawingResult = DrawingFileIO.open(path)
		check(opened.ok, label + ": file opened")
		if opened.ok:
			exercise(opened.value as DrawingDocument, saved_revision, bytes, label)
		DirAccess.remove_absolute(path)
	var object_path: String = base + "-object.drawing"
	check(DrawingObjectEditorFile.save(original, object_path, "Object", Vector2i(-2, 3), Rect2i(-64, 0, 256, 256), 3, true).ok, "legacy registry-compatible Object saved")
	var object_open: DrawingResult = DrawingObjectEditorFile.open(object_path)
	check(object_open.ok, "Object opened")
	if object_open.ok:
		var object_doc: DrawingDocument = object_open.value["document"]
		check(object_open.value["source_revision"] == 3 and object_open.value["origin"] == Vector2i(-2, 3), "Object metadata intact")
		exercise(object_doc, saved_revision, bytes, "Object")
	DirAccess.remove_absolute(object_path)
	var encoded: DrawingResult = DrawingFileIO.encode(original, true)
	check(encoded.ok, "binary payload prepared")
	if encoded.ok:
		var invalid: Dictionary = (encoded.value as Dictionary).duplicate(true)
		invalid["blobs"].clear()
		check(not DrawingFileIO.decode(invalid).ok, "missing blob rejected, no document returned")
	# Exercise the provisional initialization boundary directly. The first
	# descriptor is valid; the later malformed source must not leak ownership.
	var manifest: Dictionary = original.export_manifest().value
	var loader: Callable = func(_ref: String) -> PackedByteArray:
		return bytes
	# export_manifest may have empty refs for never-published resident tiles.
	for record: Dictionary in manifest["layers"]:
		for chunk: Dictionary in record["chunks"]:
			chunk["ref"] = chunk["sha256"]
	var raw: DrawingResult = DrawingDocument.open_manifest(manifest, loader)
	check(raw.ok, "logical manifest stays independently lazy")
	if raw.ok:
		var pending: DrawingDocument = raw.value
		check(pending._native_raster_store == null and pending._pending_tiles.size() == 2, "logical manifest does not eagerly allocate native storage")
		check(not pending._adopt_opened_raster_sources().ok and pending._native_raster_store == null, "unresolved document rejects bootstrap")
		check(pending.request_chunk("ink", "-1,2").ok and pending.request_chunk("hidden", "2,-3").ok, "both manifest sources resolve")
		var bad_tile: DrawingRasterTile = pending._nodes["hidden"].tiles["2,-3"]
		bad_tile._rgba8 = PackedByteArray([1])
		check(not pending._adopt_opened_raster_sources().ok and pending._native_raster_store == null and pending._native_source_identities.is_empty(), "malformed source leaves provisional owner unpublished")
		pending._nodes["hidden"].tiles["2,-3"] = DrawingRasterTile.from_rgba8(STRIDE, bytes)
		check(pending._adopt_opened_raster_sources().ok and matches(pending, "ink", "-1,2", bytes) and matches(pending, "hidden", "2,-3", bytes), "corrected initialization can retry")
		var retained: Object = pending._native_raster_store
		check(not pending._adopt_opened_raster_sources().ok and pending._native_raster_store == retained and pending.revision == saved_revision, "cannot replace live native owner")
	var empty: DrawingDocument = DrawingDocument.new("empty", STRIDE)
	empty.create_layer(DrawingLayerNode.RASTER, "Empty", "root", "empty")
	var empty_open: DrawingResult = DrawingFileIO.decode(DrawingFileIO.encode(empty, true).value)
	check(empty_open.ok and not (empty_open.value as DrawingDocument).is_dirty(), "empty document loads cleanly")
	var small: DrawingDocument = DrawingDocument.new("small", 3)
	small.create_layer(DrawingLayerNode.RASTER, "Small", "root", "small")
	var tiny: DrawingRasterTile = DrawingRasterTile.new(3)
	tiny.set_rgba(1, 1, HIDDEN)
	small._nodes["small"].tiles["-1,0"] = tiny
	var small_open: DrawingResult = DrawingFileIO.decode(DrawingFileIO.encode(small, true).value)
	check(small_open.ok and int((small_open.value as DrawingDocument).read_pixel("small", -2, 1).value) == HIDDEN, "historical unsupported stride remains readable")
	print("T315_NATIVE_FILE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T315_NATIVE_FILE_PASSED")
	quit(1 if failures else 0)
