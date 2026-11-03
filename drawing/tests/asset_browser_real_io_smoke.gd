extends SceneTree
## T-065: disk-backed, nontrivial Object files, decode/metadata consistency,
## corruption rejection and a bounded before/after I/O measurement.
## Timing is diagnostic, not a hardware pass/fail threshold.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, context: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T065_REAL_IO_FAILED: " + context)


func _copy(source: String, destination: String) -> bool:
	return DirAccess.copy_absolute(source, destination) == OK


func _write_json(path: String, payload: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true


func _old_two_read_open(path: String) -> DrawingResult:
	# Exact old I/O shape: full pixel decode from the first JSON read, then
	# reread/parse the same file to inspect Object metadata separately.
	var opened: DrawingResult = DrawingFileIO.open(path)
	if not opened.ok:
		return opened
	var raw: FileAccess = FileAccess.open(path, FileAccess.READ)
	if raw == null:
		return DrawingResult.failure("OPEN", "Cannot read source metadata")
	var parsed: Variant = JSON.parse_string(raw.get_as_text())
	raw.close()
	if not parsed is Dictionary:
		return DrawingResult.failure("FILE", "Cannot parse source metadata")
	return DrawingResult.success(opened.value)


func _run() -> void:
	var root_dir: String = ProjectSettings.globalize_path("user://t065-real-io-" + DrawingDocument.new_id())
	var objects: String = root_dir.path_join("Objects")
	_check(DirAccess.make_dir_recursive_absolute(objects) == OK,
		"create test Objects folder")
	var source: String = objects.path_join("large-source.drawing")
	var document: DrawingDocument = DrawingDocument.new("large-source", 128)
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Real pixels")
	_check(layer.ok, "create raster source")
	var edit_result: DrawingResult = document.begin_edit(layer.value, document.revision)
	_check(edit_result.ok, "start multi-tile edit")
	if edit_result.ok:
		var edit: DrawingEditSession = edit_result.value
		for y: int in range(2):
			for x: int in range(2):
				var rgba: PackedByteArray = PackedByteArray([30 + x * 90, 35 + y * 70, 81, 237])
				_check(edit.apply_region(Rect2i(127 + x, 127 + y, 1, 1), rgba).ok,
					"write real RGBA pixel into tile quadrant %d,%d" % [x, y])
		_check(edit.commit().ok, "commit four nontransparent canonical tiles")
	_check(DrawingObjectEditorFile.save(document, source, "Large disk-backed source",
		Vector2i(5, 9), Rect2i(0, 0, 256, 256), 3).ok,
		"write valid versioned Object payload")
	var handle: FileAccess = FileAccess.open(source, FileAccess.READ)
	var file_size: int = handle.get_length() if handle != null else 0
	if handle != null:
		handle.close()
	_check(file_size > 250000 and file_size < DrawingFileIO.MAX_FILE_BYTES,
		"real Object payload exceeds 250 KB and remains below bounded loader limit")
	var payload: DrawingResult = DrawingFileIO.read_payload(source)
	_check(payload.ok and payload.value is Dictionary, "read canonical JSON once")
	var new_open: DrawingResult = DrawingObjectEditorFile.open(source)
	var older_open: DrawingResult = _old_two_read_open(source)
	_check(new_open.ok and older_open.ok, "new and legacy I/O shapes decode valid pixels")
	if new_open.ok:
		_check(new_open.value["source_id"] == "large-source" and
			new_open.value["source_revision"] == 3 and
			new_open.value["origin"] == Vector2i(5, 9) and
			new_open.value["bounds"] == Rect2i(0, 0, 256, 256),
			"single envelope preserves exact Object metadata")
		var sample: DrawingResult = DrawingRenderer.render(new_open.value["document"],
			Rect2i(125, 125, 8, 8), 0, 0, 256)
		_check(sample.ok and (sample.value as Image).get_pixel(2, 2).r8 == 30 and
			(sample.value as Image).get_pixel(3, 3).r8 == 120,
			"decoded tile seam and bytes agree with original edit")
	# Timings quantify parsing the same immutable 350 KB source in one test
	# environment. Do not fail CI on a speed threshold or claim GPU latency.
	var legacy_us: int = 0
	var single_us: int = 0
	for index: int in range(6):
		# Alternate invocation order so OS cache/warmup cannot always favor
		# the same path. Every pair validates the same immutable disk bytes.
		var prior: DrawingResult
		var current: DrawingResult
		var started: int
		if index % 2 == 0:
			started = Time.get_ticks_usec()
			prior = _old_two_read_open(source)
			legacy_us += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			current = DrawingObjectEditorFile.open(source)
			single_us += Time.get_ticks_usec() - started
		else:
			started = Time.get_ticks_usec()
			current = DrawingObjectEditorFile.open(source)
			single_us += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			prior = _old_two_read_open(source)
			legacy_us += Time.get_ticks_usec() - started
		_check(prior.ok and current.ok, "large source read repetition %d" % index)
	print("T065_REAL_IO_DIAGNOSTIC bytes=%d old_six_opens_us=%d single_six_opens_us=%d" % [
		file_size, legacy_us, single_us])
	var indexer: DrawingAssetBrowserIndex = DrawingAssetBrowserIndex.new()
	_check(indexer.scan(objects).ok and indexer.entries.size() == 1,
		"real large Object is indexed by its embedded source ID")
	var indexed: Dictionary = indexer.entries[0]
	var thumbnails: DrawingAssetBrowserThumbnails = DrawingAssetBrowserThumbnails.new()
	var image: DrawingResult = thumbnails.preview(indexer, indexed)
	_check(image.ok and image.value is Image and thumbnails.count() == 1,
		"bounded thumbnail renders real four-tile source")
	_check(thumbnails.preview(indexer, indexed).ok and thumbnails.renders == 1,
		"repeat validated source reuses a cached thumbnail")
	var corrupt_path: String = objects.path_join("corrupt-source.drawing")
	_check(_copy(source, corrupt_path), "copy immutable source for corruption check")
	if payload.ok:
		var damaged: Dictionary = (payload.value as Dictionary).duplicate(true)
		var blobs: Dictionary = damaged["blobs"]
		var refs: Array = blobs.keys()
		if not refs.is_empty():
			var ref: String = String(refs[0])
			var encoded: String = String(blobs[ref])
			blobs[ref] = encoded.substr(0, 8) + ("B" if encoded[8] == "A" else "A") + encoded.substr(9)
			_check(_write_json(corrupt_path, damaged), "write changed base64 without updating digest")
			_check(not DrawingObjectEditorFile.open(corrupt_path).ok,
				"single-read Object loader rejects corrupted canonical pixel bytes")
			_check(not DrawingFileIO.open(corrupt_path).ok,
				"ordinary Drawing loader still rejects same corrupted source")
		var invalid: Dictionary = (payload.value as Dictionary).duplicate(true)
		(invalid["object_source"] as Dictionary)["name"] = ""
		_check(_write_json(corrupt_path, invalid), "write invalid metadata without corrupting pixels")
		_check(DrawingFileIO.open(corrupt_path).ok and
			not DrawingObjectEditorFile.open(corrupt_path).ok,
			"Drawing remains readable but Object identity contract rejects bad metadata")
	_check(indexer.safe_to_open(indexed) and thumbnails.renders == 1,
		"unmodified published source remains authorized after malicious neighbor")
	_check(not DrawingObjectEditorFile.open(objects.path_join("missing.drawing")).ok and
		not DrawingFileIO.read_payload(objects.path_join("missing.drawing")).ok,
		"missing or deleted sources fail closed before decoding")
	# Keep fixtures outside tracked files; removing the directory needs no game
	# state mutation, and the cache never holds a writable file handle.
	for file_name: String in ["large-source.drawing", "corrupt-source.drawing"]:
		DirAccess.remove_absolute(objects.path_join(file_name))
	DirAccess.remove_absolute(objects)
	DirAccess.remove_absolute(root_dir)
	print("T065_REAL_IO_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
