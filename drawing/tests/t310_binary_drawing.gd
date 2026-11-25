extends SceneTree
## T-310: exact portable bytes, bounded envelope, failure atomicity, and reproducible disk I/O measurements.

const STRIDE: int = 128
const FRAME: Rect2i = Rect2i(-1024, -1024, 2048, 2048)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, context: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T310_FAILED: " + context)


func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


func _fixture(kind: String) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new("t310-" + kind, STRIDE, 3, 2)
	var group: String = str(doc.create_layer(DrawingLayerNode.GROUP, "Artwork", DrawingDocument.ROOT_ID, "artwork").value)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink", group, "ink").value)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3102026
	var tiles: Dictionary[String, PackedByteArray] = {}
	var count: int = 16 if kind == "layers" else 64
	var loader: Callable = func(ref: String) -> Variant: return tiles.get(ref, null)
	for index: int in range(count):
		var bytes: PackedByteArray = PackedByteArray()
		bytes.resize(STRIDE * STRIDE * 4)
		if kind == "dense":
			for offset: int in range(0, bytes.size(), 4):
				bytes.encode_u32(offset, rng.randi())
		else:
			# Includes invisible nonzero RGB. Unique data avoids an artificially
			# tiny baseline caused by digest deduplication of identical tiles.
			bytes.encode_u32(index * 4, 0x00123400 + index)
			bytes.encode_u32((index + 2) * 4, 0xffabcdef)
		var digest: String = DrawingRasterTile.digest_rgba8(bytes, STRIDE)
		tiles[digest] = bytes
		check(doc.register_lazy_chunk(layer, index % 8 - 4, index / 8 - 4,
			digest, digest, loader).ok, "register canonical signed tile")
	if kind == "layers":
		for index: int in range(96):
			var group_id: String = str(doc.create_layer(DrawingLayerNode.GROUP, "Group %d" % index,
				group, "group-%d" % index).value)
			check(doc.create_layer(DrawingLayerNode.RASTER, "Blank paint", group_id,
				"paint-%d" % index).ok, "layer-heavy raster record")
			var semantic: String = str(doc.create_layer(DrawingLayerNode.OBJECTS, "Symbols", group_id,
				"symbols-%d" % index).value)
			check(doc.add_object(semantic, {"position": Vector2(-3.5, 2.75),
				"tint": Color(0.25, 0.5, 0.75, 0.5), "label": "café"}, "symbol").ok,
				"layer-heavy semantic record")
			if index % 8 == 0:
				var draft: DrawingTextElement = DrawingTextElement.new()
				draft.content = "Layer %d — café" % index
				draft.font_id = "lato-italic-v1"
				draft.position = Vector2i(-80, index * 2)
				draft.angle = 0.12345678901234567
				check(doc.commit_text("", draft, doc.revision, group_id, "text-%d" % index).ok,
					"editable text with portable font")
				check(doc.set_locked("text-%d" % index, true).ok, "locked text state")
			if index % 4 == 0:
				check(doc.set_visibility(group_id, false).ok, "hidden group state")
	return doc


func _exact(before: DrawingDocument, after: DrawingDocument) -> bool:
	if before.id != after.id or before.revision != after.revision:
		return false
	var prior: DrawingResult = before.export_manifest()
	var later: DrawingResult = after.export_manifest()
	if not prior.ok or not later.ok or prior.value != later.value:
		return false
	for record: Dictionary in prior.value["layers"]:
		for chunk: Dictionary in record["chunks"]:
			var coord: Array = chunk["coord"]
			var left: DrawingResult = before.request_chunk_at(record["id"], coord[0], coord[1])
			var right: DrawingResult = after.request_chunk_at(record["id"], coord[0], coord[1])
			if not left.ok or not right.ok or left.value.to_rgba8() != right.value.to_rgba8():
				return false
	return not after.is_dirty()


func _benchmark(kind: String, legacy: bool, path: String) -> void:
	var doc: DrawingDocument = _fixture(kind)
	# Equal warm source projections, independent processes per fixture/codec.
	for record: Dictionary in doc.export_manifest().value["layers"]:
		for chunk: Dictionary in record["chunks"]:
			var coord: Array = chunk["coord"]
			check(doc.request_chunk_at(record["id"], coord[0], coord[1]).ok, "preload source")
	var save_us: Array[int] = []
	var open_us: Array[int] = []
	var length: int = 0
	for trial: int in range(5):
		var start: int = Time.get_ticks_usec()
		var saved: DrawingResult = DrawingFileIO.save(doc, path, {"image_frame": DrawingImageFrame.encode(FRAME)}, legacy)
		save_us.append(Time.get_ticks_usec() - start)
		check(saved.ok, "benchmark save " + saved.message)
		if not saved.ok:
			return
		var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
		length = handle.get_length()
		handle.close()
		start = Time.get_ticks_usec()
		var loaded: DrawingResult = DrawingFileIO.open_with_frame(path)
		open_us.append(Time.get_ticks_usec() - start)
		check(loaded.ok and loaded.value["image_frame"] == FRAME and _exact(doc, loaded.value["document"]), "benchmark exact open")
	save_us.sort()
	open_us.sort()
	print("T310_BENCH %s %s bytes=%d save_median_us=%d open_median_us=%d save_samples=%s open_samples=%s" % [
		kind, "legacy" if legacy else "binary", length, save_us[2], open_us[2], str(save_us), str(open_us)])


func _envelope(raw: PackedByteArray) -> PackedByteArray:
	var bytes: PackedByteArray = "DIADRAW2".to_ascii_buffer()
	bytes.resize(56)
	bytes.encode_u32(8, 1)
	bytes.encode_u32(12, 0)
	bytes.encode_u32(16, raw.size())
	bytes.encode_u32(20, raw.size())
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(raw)
	var digest: PackedByteArray = hash.finish()
	for index: int in range(32):
		bytes[index + 24] = digest[index]
	bytes.append_array(raw)
	return bytes


func _test(path: String) -> void:
	var doc: DrawingDocument = _fixture("layers")
	var saved: DrawingResult = DrawingFileIO.save(doc, path, {"image_frame": DrawingImageFrame.encode(FRAME)})
	check(saved.ok and not doc.is_dirty(), "binary Save publishes clean snapshot")
	if not saved.ok:
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(original.slice(0, 8).get_string_from_ascii() == "DIADRAW2" and original.decode_u32(8) == 1, "versioned binary signature")
	check(original.decode_u32(12) == 1, "sparse payload compressed")
	var opened: DrawingResult = DrawingFileIO.open_with_frame(path)
	check(opened.ok and opened.value["image_frame"] == FRAME and _exact(doc, opened.value["document"]), "exact document tree, IDs, signed tiles, fonts, typed semantic objects and frame")
	if opened.ok:
		var loaded: DrawingDocument = opened.value["document"]
		check(loaded.read_pixel("ink", -512, -512).value == 0x00123400, "alpha-zero hidden RGB remains exact")
		check(loaded.inspect_node("text-0").text_element.angle == 0.12345678901234567, "precise text rotation")
		check(loaded.inspect_node("symbols-0").objects["symbol"]["position"] == Vector2(-3.5, 2.75), "typed vector survives")
		check(loaded.set_locked("text-0", false).ok and loaded.set_visibility("group-0", true).ok and loaded.set_text("text-0", "Edited text").ok, "reopened text remains editable")
	var payload: DrawingResult = DrawingFileIO.parse_payload(original)
	check(payload.ok, "shared captured-byte parser")
	if not payload.ok:
		return
	var raw: PackedByteArray = var_to_bytes(payload.value)
	var uncompressed: DrawingResult = DrawingFileIO.parse_payload(_envelope(raw))
	check(uncompressed.ok and DrawingFileIO.decode(uncompressed.value).ok, "uncompressed envelope fallback readable")
	var concatenated: PackedByteArray = raw.duplicate()
	concatenated.append_array(var_to_bytes("unexpected second value"))
	check(not DrawingFileIO.parse_payload(_envelope(concatenated)).ok, "reject a rehashed envelope containing extra Variant data")
	for offset: int in [8, 12, 16, 20, 24, original.size() - 1]:
		var damaged: PackedByteArray = original.duplicate()
		damaged[offset] = damaged[offset] ^ 0xff
		check(not DrawingFileIO.parse_payload(damaged).ok, "reject corrupt header/body at %d" % offset)
	for length: int in [8, 55, 56, original.size() - 1]:
		check(not DrawingFileIO.parse_payload(original.slice(0, length)).ok, "reject truncated binary at %d" % length)
	var oversized: PackedByteArray = original.duplicate()
	oversized.encode_u32(16, DrawingFileIO.MAX_DECODED_BYTES + 1)
	check(DrawingFileIO.parse_payload(oversized).code == "FILE_LIMIT", "reject expansion bomb before decompression")
	var unsupported: PackedByteArray = original.duplicate()
	unsupported.encode_u32(8, 2)
	check(DrawingFileIO.parse_payload(unsupported).code == "SCHEMA", "reject unsupported version")
	var trailing: PackedByteArray = original.duplicate()
	trailing.append(1)
	check(not DrawingFileIO.parse_payload(trailing).ok, "reject trailing file bytes")
	var invalid: Dictionary = payload.value.duplicate(true)
	invalid["blobs"].clear()
	check(not DrawingFileIO.decode(invalid).ok, "reject missing canonical tile even with valid envelope")
	invalid = payload.value.duplicate(true)
	var ref: String = str(invalid["blobs"].keys()[0])
	invalid["blobs"][ref][0] = invalid["blobs"][ref][0] ^ 1
	check(DrawingFileIO.decode(invalid).code == "CORRUPT_TILE", "reject internally corrupt tile")
	invalid = payload.value.duplicate(true)
	invalid["font_assets"]["lato-italic-v1"]["sha256"] = "0".repeat(64)
	check(DrawingFileIO.decode(invalid).code == "FONT_CORRUPT", "reject altered font digest")
	invalid = payload.value.duplicate(true)
	invalid["font_assets"].clear()
	check(DrawingFileIO.decode(invalid).code == "FONT_MISSING", "reject missing font")
	invalid = payload.value.duplicate(true)
	invalid["document"]["tile_stride"] = 2048
	check(DrawingFileIO.decode(invalid).code == "FILE_LIMIT", "bound expanded referenced tiles")
	var nonportable: Dictionary = payload.value.duplicate(true)
	nonportable["unsupported"] = RefCounted.new()
	check(not DrawingFileIO.pack_binary(nonportable).ok, "reject nonportable object rather than lose data")
	var objects: Array[RefCounted] = []
	nonportable["unsupported"] = objects
	check(not DrawingFileIO.pack_binary(nonportable).ok, "reject even empty typed Object container")
	# A compressed file still consumes memory per materialized reference, even
	# if both descriptors point to the same deduplicated canonical blob.
	var dedup_doc: DrawingDocument = DrawingDocument.new("dedup-source", 16)
	var dedup_layer: String = str(dedup_doc.create_layer(DrawingLayerNode.RASTER, "Repeated").value)
	var dedup_bytes: PackedByteArray = PackedByteArray()
	dedup_bytes.resize(16 * 16 * 4)
	dedup_bytes.encode_u32(0, 0x00332211)
	var dedup_hash: String = DrawingRasterTile.digest_rgba8(dedup_bytes, 16)
	var loader: Callable = func(_ref: String) -> Variant: return dedup_bytes
	check(dedup_doc.register_lazy_chunk(dedup_layer, -1, 0, dedup_hash, dedup_hash, loader).ok and dedup_doc.register_lazy_chunk(dedup_layer, 1, 0, dedup_hash, dedup_hash, loader).ok, "prepare duplicate tile references")
	var dedup_payload: DrawingResult = DrawingFileIO.encode(dedup_doc, true)
	check(dedup_payload.ok and dedup_payload.value["blobs"].size() == 1 and DrawingFileIO.expanded_raster_bytes(dedup_payload.value).value == 2048, "deduplicated raw payload still charges both raster copies")
	var dedup_open: DrawingResult = DrawingFileIO.decode(dedup_payload.value)
	check(dedup_open.ok and dedup_open.value.read_pixel(dedup_layer, -16, 0).value == 0x00332211 and dedup_open.value.read_pixel(dedup_layer, 16, 0).value == 0x00332211, "deduplicated source preserves hidden RGB at both positions")
	var large_path: String = path + ".oversize"
	var large: FileAccess = FileAccess.open(large_path, FileAccess.WRITE)
	check(large != null and large.resize(DrawingFileIO.MAX_FILE_BYTES + 1) == OK, "make oversize sparse filesystem fixture")
	if large != null:
		large.close()
		check(DrawingFileIO.read_payload(large_path).code == "FILE_LIMIT", "oversize file rejected before reading bytes")
	DirAccess.remove_absolute(large_path)
	var legacy_path: String = path + ".legacy.drawing"
	check(DrawingFileIO.save(doc, legacy_path, {"image_frame": DrawingImageFrame.encode(FRAME)}, true).ok, "write old JSON format")
	check(FileAccess.get_file_as_bytes(legacy_path)[0] == 123, "legacy format stays JSON")
	var legacy_open: DrawingResult = DrawingFileIO.open_with_frame(legacy_path)
	check(legacy_open.ok and _exact(doc, legacy_open.value["document"]) and legacy_open.value["image_frame"] == FRAME, "legacy exact backward-compatible open")
	if legacy_open.ok:
		check(DrawingFileIO.save(legacy_open.value["document"], legacy_path).ok and FileAccess.get_file_as_bytes(legacy_path).slice(0, 8).get_string_from_ascii() == "DIADRAW2", "existing legacy file converts only on explicit Save")
	check(doc.set_visibility("group-0", true).ok and doc.is_dirty(), "make dirty before failing Save")
	check(not DrawingFileIO.save(doc, path, {"image_frame": {}}).ok and doc.is_dirty() and FileAccess.get_file_as_bytes(path) == original, "invalid metadata leaves previous file and dirty state intact")
	var directory: String = path + ".directory"
	DirAccess.make_dir_recursive_absolute(directory)
	check(not DrawingFileIO.save(doc, directory).ok and doc.is_dirty() and DirAccess.dir_exists_absolute(directory), "failed atomic rename preserves directory and dirty state")
	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	var prefix: String = directory.get_file() + ".pending-"
	var clean: bool = true
	for filename: String in dir.get_files():
		if filename.begins_with(prefix):
			clean = false
	check(clean, "failed rename leaves no pending file")
	check(DrawingFileIO.save(doc, path).ok and not doc.is_dirty(), "subsequent successful save recovers")
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(legacy_path)
	var catalog_path: String = path + ".catalog/Objects"
	DirAccess.make_dir_recursive_absolute(catalog_path)
	var object_path: String = catalog_path.path_join("binary.drawing")
	check(DrawingObjectEditorFile.save(doc, object_path, "Binary source", Vector2i(-5, 7), FRAME, 3).ok, "binary Object source save")
	var inspected: DrawingResult = DrawingObjectEditorFile.inspect_metadata(object_path)
	var object_open: DrawingResult = DrawingObjectEditorFile.open(object_path)
	check(inspected.ok and inspected.value["source_id"] == doc.id and inspected.value["source_revision"] == 3 and inspected.value["origin"] == Vector2i(-5, 7) and inspected.value["bounds"] == FRAME, "inspect source identity and frame")
	check(object_open.ok and _exact(doc, object_open.value["document"]), "binary Object source exact open")
	var index: DrawingAssetBrowserIndex = DrawingAssetBrowserIndex.new()
	check(index.scan(catalog_path).ok and index.entries.size() == 1, "binary source indexes by captured-byte digest")
	if index.entries.size() == 1:
		var object_bytes: PackedByteArray = FileAccess.get_file_as_bytes(object_path)
		var remaining: Dictionary = {"bytes": object_bytes.size()}
		check(DrawingLinkedObjects._open(index, index.entries[0], remaining).code == "LINK_LIMIT" and remaining["bytes"] == object_bytes.size(), "linked graph rejects compressed expansion before materialization without spending budget")
		remaining["bytes"] = DrawingFileIO.MAX_DECODED_BYTES
		var full_budget: DrawingResult = DrawingLinkedObjects._open(index, index.entries[0], remaining)
		check(full_budget.ok and remaining["bytes"] == DrawingFileIO.MAX_DECODED_BYTES - DrawingFileIO.decoded_payload_size(object_bytes), "linked graph charges expanded bytes")
	DirAccess.remove_absolute(object_path)
	DirAccess.remove_absolute(catalog_path)
	DirAccess.remove_absolute(catalog_path.get_base_dir())


func _run() -> void:
	if not ClassDB.class_exists("DrawingNativeTiles"):
		printerr("T310_FAILED: native extension required")
		quit(1)
		return
	var path: String = OS.get_cache_dir().path_join("t310-" + DrawingDocument.new_id() + ".drawing")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] in ["sparse", "dense", "layers"] and args[1] in ["legacy", "binary"]:
		_benchmark(args[0], args[1] == "legacy", path)
	else:
		_test(path)
	DirAccess.remove_absolute(path)
	print("T310_BINARY_%s (%d checks; %d failed)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
