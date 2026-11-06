extends SceneTree

# Research-only Godot 4.8b2 -> C++ scalar swept-brush sparse boundary.
# The native path has no access to DrawingDocument and cannot publish edits.
var checks: int = 0
var failures: int = 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T068_SCALAR_BRIDGE_FAIL: ", label)

static func _path(samples: PackedVector2Array) -> PackedByteArray:
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(samples.size() * 16)
	for i: int in range(samples.size()):
		raw.encode_double(i * 16, samples[i].x)
		raw.encode_double(i * 16 + 8, samples[i].y)
	return raw

static func _document(title: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(title, 16)
	var made: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	return {"doc": doc, "layer": String(made.value)}

static func _tile(doc: DrawingDocument, layer: String) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk_at(layer, 0, 0)
	var tile: DrawingRasterTile = result.value as DrawingRasterTile if result.ok else null
	if tile == null:
		var blank: PackedByteArray = PackedByteArray()
		blank.resize(16 * 16 * 4)
		return blank
	return tile.to_rgba8()

static func _seed(doc: DrawingDocument, layer: String) -> bool:
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begun.ok:
		return false
	var edit: DrawingEditSession = begun.value
	var filled: DrawingResult = edit.fill_rect(Rect2i(2, 3, 1, 1), 0x00223344)
	return filled.ok and edit.commit().ok

static func _source_after(source: PackedByteArray, records: PackedByteArray) -> Dictionary:
	if records.size() < 4 or (records.size() - 4) % 12 != 0:
		return {"ok": false}
	var count: int = records.decode_u32(0)
	if count != (records.size() - 4) / 12:
		return {"ok": false}
	var bytes: PackedByteArray = source.duplicate()
	var changed: Array[Dictionary] = []
	var previous: int = -1
	for i: int in range(count):
		var offset: int = 4 + i * 12
		var pixel: int = records.decode_u32(offset)
		if pixel <= previous or pixel >= 256:
			return {"ok": false}
		previous = pixel
		var before: int = records.decode_u32(offset + 4)
		var after: int = records.decode_u32(offset + 8)
		if bytes.decode_u32(pixel * 4) != before or before == after:
			return {"ok": false}
		bytes.encode_u32(pixel * 4, after)
		changed.append({"x": pixel % 16, "y": pixel / 16,
			"before": before, "after": after})
	return {"ok": true, "bytes": bytes, "deltas": changed}

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "load opt-in extension")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_scalar_brush_sparse"),
		"register isolated scalar brush entrypoint")
	if bridge == null:
		quit(1)
		return
	var expected: Dictionary = _document("scalar-oracle")
	var actual: Dictionary = _document("scalar-bridge")
	_check(_seed(expected.doc, expected.layer) and _seed(actual.doc, actual.layer),
		"seed independent documents, including transparent hidden RGB")
	var source: PackedByteArray = _tile(actual.doc, actual.layer)
	_check(source.decode_u32((3 * 16 + 2) * 4) == 0x00223344,
		"native source includes alpha-zero hidden RGB")
	var selection: PackedByteArray = PackedByteArray()
	selection.resize(256)
	selection.fill(1)
	var samples: PackedVector2Array = PackedVector2Array([
		Vector2(2.5, 3.5), Vector2(12.5, 11.5), Vector2(2.5, 3.5)])
	var points: PackedByteArray = _path(samples)
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])
	var source_copy: PackedByteArray = source.duplicate()
	var expected_edit: DrawingEditSession = expected.doc.begin_edit(
		expected.layer, expected.doc.revision).value
	_check(expected_edit.paint_path(samples, 0x8044aacc, 4.0).ok and
		expected_edit.commit().ok, "actual Godot paint_path oracle committed")
	var output: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, selection, points, 16, 4.0, paint, 0, 256)
	var parsed: Dictionary = _source_after(source, output)
	_check(parsed.ok, "checked sparse wire is sorted, complete, and has exact before bytes")
	if not parsed.ok:
		quit(1)
		return
	_check(output.size() == 4 + 12 * parsed.deltas.size(), "wire is bounded to changed pixels")
	_check(parsed.deltas.size() > 5, "diagonal crossing exercises many pixels")
	_check(parsed.bytes == _tile(expected.doc, expected.layer),
		"native reconstructed pixels match actual Godot brush after hidden-RGB seed")
	_check(source == source_copy, "input PackedByteArray is immutable")
	# Publish only *after* independently validating the complete native output.
	var revision: int = actual.doc.revision
	var begun: DrawingResult = actual.doc.begin_edit(actual.layer, revision)
	_check(begun.ok, "begin revision-checked native-result transaction")
	var staging: DrawingEditSession = begun.value
	var staged: bool = true
	for delta: Dictionary in parsed.deltas:
		var result: DrawingResult = staging._stage(delta.x, delta.y,
			delta.after, null, false, false, delta.before)
		if not result.ok:
			staged = false
			break
	_check(staged, "all native sparse records stage with original-pixel preconditions")
	var committed: DrawingResult = staging.commit() if staged else DrawingResult.failure("STAGE", "Scalar stage failed")
	_check(committed.ok and actual.doc.revision == revision + 1,
		"one atomic document revision for native stroke")
	_check(_tile(actual.doc, actual.layer) == _tile(expected.doc, expected.layer),
		"native document publication equals canonical Godot paint_path")
	_check(actual.doc.undo().ok and _tile(actual.doc, actual.layer) == source,
		"undo restores hidden RGB and all original pixels")
	_check(actual.doc.redo().ok and _tile(actual.doc, actual.layer) == parsed.bytes,
		"redo restores exactly one gesture")

	# Reject malformed native requests without returning a misleading no-op.
	_check(bridge.apply_scalar_brush_sparse(source.slice(0, 8), selection,
		points, 16, 4.0, paint, 0, 256).is_empty(), "short source rejected")
	_check(bridge.apply_scalar_brush_sparse(source, PackedByteArray([1]),
		points, 16, 4.0, paint, 0, 256).is_empty(), "short selection rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, PackedByteArray([1]),
		16, 4.0, paint, 0, 256).is_empty(), "unaligned path rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, 16,
		4.0, PackedByteArray([1]), 0, 256).is_empty(), "short paint rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, 16,
		4.0, paint, 3, 256).is_empty(), "unknown operation rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, 16,
		4.0, paint, 0, 0).is_empty(), "insufficient output capacity rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, 16,
		4.0, paint, 0, 65537).is_empty(), "oversized allocation request rejected")
	var bad_mask: PackedByteArray = selection.duplicate()
	bad_mask[0] = 2
	_check(bridge.apply_scalar_brush_sparse(source, bad_mask, points, 16,
		4.0, paint, 0, 256).is_empty(), "non-binary selection rejected")
	var bad_points: PackedByteArray = points.duplicate()
	bad_points.encode_double(0, NAN)
	_check(bridge.apply_scalar_brush_sparse(source, selection, bad_points, 16,
		4.0, paint, 0, 256).is_empty(), "nonfinite sample rejected")
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, 16,
		-1.0, paint, 0, 256).is_empty(), "negative width rejected")
	_check(source == source_copy, "all rejection paths preserve source")

	# A selection suppresses any changed record outside its binary mask.
	var isolated: PackedByteArray = selection.duplicate()
	isolated.fill(0)
	isolated[3 * 16 + 2] = 1
	var narrow: PackedByteArray = bridge.apply_scalar_brush_sparse(source,
		isolated, points, 16, 4.0, paint, 0, 1)
	var narrow_checked: Dictionary = _source_after(source, narrow)
	_check(narrow_checked.ok and narrow_checked.deltas.size() == 1 and
		narrow_checked.deltas[0].x == 2 and narrow_checked.deltas[0].y == 3,
		"masked stroke touches only authorized hidden-RGB pixel")
	var no_op: PackedByteArray = bridge.apply_scalar_brush_sparse(source,
		selection, points, 16, 4.0, PackedByteArray([2, 3, 4, 0]), 0, 0)
	_check(no_op.size() == 4 and no_op.decode_u32(0) == 0,
		"alpha-zero source-over returns valid four-byte no-op")
	# Erase should zero all channels, not retain hidden RGB.
	var erase: PackedByteArray = bridge.apply_scalar_brush_sparse(source,
		isolated, points, 16, 4.0, paint, 1, 1)
	var erase_checked: Dictionary = _source_after(source, erase)
	_check(erase_checked.ok and erase_checked.deltas.size() == 1 and
		erase_checked.bytes.decode_u32((3 * 16 + 2) * 4) == 0,
		"eraser zeroes alpha and all hidden RGB channels")
	_check(actual.doc.revision == revision + 3, "rejected/no-op calls did not publish")

	if failures == 0:
		print("T068_SCALAR_BRIDGE_EVIDENCE: " + JSON.stringify({
			"source_bytes": source.size(), "path_bytes": points.size(),
			"sparse_bytes": output.size(), "changed": parsed.deltas.size(),
			"masked_sparse_bytes": narrow.size(), "no_op_bytes": no_op.size(),
			"erase_sparse_bytes": erase.size(), "checks": checks}))
	bridge.free()
	if failures == 0:
		print("T068_SCALAR_BRIDGE_PASSED: %d checks" % checks)
	else:
		printerr("T068_SCALAR_BRIDGE_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 else 1)
