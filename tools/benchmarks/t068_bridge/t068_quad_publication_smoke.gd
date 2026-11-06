extends "res://scalar_test.gd"

# Opt-in integration witness: native Atlas four-corner scope -> native sparse
# hard brush -> validated, revision-checked canonical DrawingDocument commit.
# Nothing is loaded by the normal Atlas or Drawing application.

static func _pack_doubles(values: Array) -> PackedByteArray:
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(values.size() * 8)
	for i: int in range(values.size()):
		raw.encode_double(i * 8, float(values[i]))
	return raw

static func _pack_pairs(values: Array) -> PackedByteArray:
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(values.size() * 16)
	for i: int in range(values.size()):
		raw.encode_double(i * 16, float(values[i][0]))
		raw.encode_double(i * 16 + 8, float(values[i][1]))
	return raw

static func _hash(raw: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return context.finish().hex_encode()

static func _tile64(doc: DrawingDocument, layer: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk_at(layer, 0, 0)
	var tile: DrawingRasterTile = result.value as DrawingRasterTile if result.ok else null
	if tile == null:
		var empty: PackedByteArray = PackedByteArray()
		empty.resize(64 * 64 * 4)
		return empty
	return tile.to_rgba8()

static func _decode(source: PackedByteArray, mask: PackedByteArray,
		wire: PackedByteArray) -> Dictionary:
	if wire.size() < 4 or (wire.size() - 4) % 12 != 0:
		return {"ok": false}
	var count: int = wire.decode_u32(0)
	if count != (wire.size() - 4) / 12:
		return {"ok": false}
	var output: PackedByteArray = source.duplicate()
	var records: Array[Dictionary] = []
	var prior: int = -1
	for i: int in range(count):
		var offset: int = 4 + 12 * i
		var pixel: int = wire.decode_u32(offset)
		if pixel <= prior or pixel >= 4096 or mask[pixel] != 1:
			return {"ok": false}
		prior = pixel
		var before: int = wire.decode_u32(offset + 4)
		var after: int = wire.decode_u32(offset + 8)
		if before != output.decode_u32(pixel * 4) or before == after:
			return {"ok": false}
		output.encode_u32(pixel * 4, after)
		records.append({"x": pixel % 64, "y": pixel / 64,
			"before": before, "after": after})
	return {"ok": true, "bytes": output, "deltas": records}

func _case(bridge: Object, spec: Dictionary) -> Dictionary:
	var label: String = String(spec["id"])
	var document: DrawingDocument = DrawingDocument.new("native-quad-" + label, 64)
	var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	_check(created.ok, label + ": create raster layer")
	if not created.ok:
		return {}
	var layer: String = String(created.value)
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision).value
	_check(seed.fill_rect(Rect2i(22, 22, 1, 1), 0x00223344).ok and seed.commit().ok,
		label + ": seed hidden RGB")
	var source: PackedByteArray = _tile64(document, layer)
	var source_hash: String = _hash(source)
	var revision: int = document.revision
	var history: int = document.history_length()
	var transform: PackedByteArray = _pack_doubles(spec["transform"])
	var polygon: PackedByteArray = _pack_pairs(spec["polygon"])
	var mask: PackedByteArray = bridge.build_quad_selection(transform,
		float(spec["density"]), polygon, 64, int(spec["enabled"]))
	var oracle_mask: PackedByteArray = Marshalls.base64_to_raw(String(spec["mask_base64"]))
	_check(mask.size() == 4096 and mask == oracle_mask and mask.count(1) == int(spec["allowed"]),
		label + ": native four-corner mask equals Godot oracle")
	if mask.size() != 4096 or mask != oracle_mask:
		return {}
	var path: PackedByteArray = _pack_pairs([[8.5, 8.5], [55.5, 55.5]])
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])
	var payload: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, mask, path, 64, 4.0, paint, 0, 4096)
	var checked: Dictionary = _decode(source, mask, payload)
	_check(checked.get("ok", false) and source_hash == _hash(_tile64(document, layer)),
		label + ": exact sparse before bytes, scope, ordering and detached source")
	if not checked.get("ok", false):
		return {}
	var edit_result: DrawingResult = document.begin_edit(layer, revision)
	_check(edit_result.ok, label + ": revision-checked begin")
	if not edit_result.ok:
		return {}
	var edit: DrawingEditSession = edit_result.value
	var staged: bool = true
	for delta: Dictionary in checked["deltas"]:
		if not edit._stage(delta["x"], delta["y"], delta["after"],
				null, false, false, delta["before"]).ok:
			staged = false
			break
	_check(staged and edit.change_count() == checked["deltas"].size(),
		label + ": bounded native changes staged as one transaction")
	if not staged:
		return {}
	var committed: DrawingResult = edit.commit()
	var changed: int = checked["deltas"].size()
	var expected_advance: int = 1 if changed > 0 else 0
	_check((committed.ok if changed > 0 else (not committed.ok and committed.code == "NO_CHANGE")) and
		document.revision == revision + expected_advance and
		document.history_length() == history + expected_advance and
		_tile64(document, layer) == checked["bytes"],
		label + ": atomic canonical publication or clean no-op")
	var undo_hash: String = source_hash
	var redo_hash: String = _hash(checked["bytes"])
	if changed > 0:
		var undid: DrawingResult = document.undo()
		_check(undid.ok and _tile64(document, layer) == source,
			label + ": undo restores exact hidden RGB and source")
		undo_hash = _hash(_tile64(document, layer))
		var redid: DrawingResult = document.redo()
		_check(redid.ok and _tile64(document, layer) == checked["bytes"],
			label + ": redo restores exact native stroke")
		redo_hash = _hash(_tile64(document, layer))
	else:
		_check(_tile64(document, layer) == source and document.history_length() == history,
			label + ": zero-record gesture changes no history")
		_check(document.revision == revision, label + ": no-op leaves revision alone")
	_check(_hash(source) == source_hash, label + ": native caller source unchanged")
	return {"id": label, "allowed": mask.count(1), "mask_sha256": _hash(mask),
		"changed": changed, "sparse_bytes": payload.size(),
		"pixels_sha256": _hash(checked["bytes"]), "source_sha256": source_hash,
		"undo_sha256": undo_hash, "redo_sha256": redo_hash,
		"history_delta": expected_advance, "revision_delta": expected_advance,
		"checks_after": checks}

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit native bridge load")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("build_quad_selection") and
		bridge.has_method("apply_scalar_brush_sparse"), "native quad and brush APIs")
	if bridge == null:
		quit(1)
		return
	var oracle: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://quad_oracle.json"))
	_check(oracle is Dictionary and oracle.get("schema", 0) == 1 and
		oracle.get("side", 0) == 64, "pinned 64x64 Godot scope oracle")
	if not oracle is Dictionary:
		quit(1)
		return
	var evidence: Array[Dictionary] = []
	for spec: Dictionary in oracle["cases"]:
		var result: Dictionary = _case(bridge, spec)
		if result.is_empty():
			break
		evidence.append(result)
	bridge.free()
	if failures == 0 and evidence.size() == 15:
		print("T068_QUAD_PUBLICATION_EVIDENCE: " + JSON.stringify(evidence))
		print("T068_QUAD_PUBLICATION_PASSED: %d checks" % checks)
	else:
		printerr("T068_QUAD_PUBLICATION_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and evidence.size() == 15 else 1)
