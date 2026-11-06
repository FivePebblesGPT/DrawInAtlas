extends SceneTree

# T-068: opt-in canonical Godot vs native sparse brush with transformed paths.
# The client constructs a raster-local binary DrawingSelection mask; this is
# NOT a native implementation of Atlas's four-corner polygon scope.
const PAINT: int = 0x8044aacc
const WIDTH: float = 4.0

var checks: int = 0
var failures: int = 0


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T068_SCALAR_TRANSFORM_FAIL: ", message)


static func _cases() -> Array[Dictionary]:
	return [
		{"name": "identity_rect", "side": 32, "transform": Transform2D.IDENTITY,
			"mask": "rect", "erase": false, "points": PackedVector2Array([
				Vector2(5.5, 7.5), Vector2(24.5, 19.5)])},
		{"name": "rotated_inverted", "side": 32,
			"transform": Transform2D(Vector2(0, 1), Vector2(-1, 0), Vector2(33, 3)),
			"mask": "inverted", "erase": false, "points": PackedVector2Array([
				Vector2(4.5, 6.5), Vector2(26.5, 25.5)])},
		{"name": "shear_sparse_erase", "side": 32,
			"transform": Transform2D(Vector2(1, 0.25), Vector2(0.4, 1), Vector2(3, 2)),
			"mask": "sparse", "erase": true, "points": PackedVector2Array([
				Vector2(1.5, 3.5), Vector2(28.5, 26.5), Vector2(2.5, 26.5)])},
		{"name": "mirrored_crossing", "side": 64,
			"transform": Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(65, 0)),
			"mask": "rect", "erase": false, "points": PackedVector2Array([
				Vector2(12.5, 13.5), Vector2(50.5, 49.5),
				Vector2(12.5, 49.5), Vector2(50.5, 13.5)])},
		{"name": "nonuniform_inverted_sparse", "side": 64,
			"transform": Transform2D(Vector2(1.25, 0.1), Vector2(0.2, 0.7), Vector2(4, -3)),
			"mask": "inverted_sparse", "erase": true, "points": PackedVector2Array([
				Vector2(8.5, 8.5), Vector2(56.5, 56.5)])},
		{"name": "zoom_pan_dab", "side": 64,
			"transform": Transform2D(Vector2(2, 0), Vector2(0, 1.5), Vector2(-5, 7)),
			"mask": "all", "erase": false, "points": PackedVector2Array([
				Vector2(30.5, 27.5)])},
	]


static func _new_document(side: int, label: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(label, side)
	var created: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not created.ok:
		return {"ok": false}
	var layer: String = String(created.value)
	var edit_result: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not edit_result.ok:
		return {"ok": false}
	var edit: DrawingEditSession = edit_result.value
	var inset: int = 10 if side == 32 else 20
	var block: int = 12 if side == 32 else 24
	if not edit.fill_rect(Rect2i(2, 3, 1, 1), 0x00223344).ok or not edit.fill_rect(
			Rect2i(inset, inset, block, block), 0x80445566).ok or not edit.commit().ok:
		return {"ok": false}
	return {"ok": true, "doc": doc, "layer": layer}


static func _tile(doc: DrawingDocument, layer: String, side: int) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk_at(layer, 0, 0)
	if result.ok and result.value is DrawingRasterTile:
		return (result.value as DrawingRasterTile).to_rgba8()
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(side * side * 4)
	return empty


static func _selection(side: int, mode: String) -> DrawingSelection:
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(6, 6, side - 12, side - 12), mode != "all")
	selection.inverted = mode == "inverted" or mode == "inverted_sparse"
	if mode == "sparse" or mode == "inverted_sparse":
		var sparse: Dictionary[Vector2i, bool] = {}
		for y: int in range(6, side - 6):
			for x: int in range(6, side - 6):
				if (x * 3 + y * 5) % 11 < 5:
					sparse[Vector2i(x, y)] = true
		selection.set_mask(sparse)
	return selection


static func _binary_mask(side: int, selection: DrawingSelection) -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(side * side)
	for y: int in range(side):
		for x: int in range(side):
			mask[y * side + x] = 1 if selection.allows(Vector2i(x, y)) else 0
	return mask


static func _packed_path(points: PackedVector2Array) -> PackedByteArray:
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(points.size() * 16)
	for index: int in range(points.size()):
		packed.encode_double(16 * index, points[index].x)
		packed.encode_double(16 * index + 8, points[index].y)
	return packed


static func _decode(source: PackedByteArray, payload: PackedByteArray, side: int) -> Dictionary:
	if payload.size() < 4 or (payload.size() - 4) % 12 != 0:
		return {"ok": false}
	var count: int = payload.decode_u32(0)
	if count > side * side or payload.size() != 4 + count * 12:
		return {"ok": false}
	var recovered: PackedByteArray = source.duplicate()
	var deltas: Array[Dictionary] = []
	var previous: int = -1
	for index: int in range(count):
		var offset: int = 4 + index * 12
		var pixel: int = payload.decode_u32(offset)
		if pixel <= previous or pixel >= side * side:
			return {"ok": false}
		previous = pixel
		var before: int = payload.decode_u32(offset + 4)
		var after: int = payload.decode_u32(offset + 8)
		if recovered.decode_u32(pixel * 4) != before or before == after:
			return {"ok": false}
		recovered.encode_u32(pixel * 4, after)
		deltas.append({"x": pixel % side, "y": pixel / side,
			"before": before, "after": after})
	return {"ok": true, "bytes": recovered, "deltas": deltas}


static func _sha256(value: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


func _case(bridge: Object, spec: Dictionary) -> Dictionary:
	var side: int = spec.side
	var name: String = spec.name
	var reference: Dictionary = _new_document(side, name + "-godot")
	var native: Dictionary = _new_document(side, name + "-native")
	_check(reference.get("ok", false) and native.get("ok", false), name + ": documents seeded")
	if not reference.get("ok", false) or not native.get("ok", false):
		return {}
	var source: PackedByteArray = _tile(native.doc, native.layer, side)
	var original_revision: int = native.doc.revision
	_check(source == _tile(reference.doc, reference.layer, side) and
		source.decode_u32((3 * side + 2) * 4) == 0x00223344,
		name + ": identical hidden-RGB source")
	var selection: DrawingSelection = _selection(side, spec.mask)
	var mask: PackedByteArray = _binary_mask(side, selection)
	var selected_count: int = 0
	for item: int in mask:
		selected_count += item
	_check(selected_count > 0 and selected_count < side * side or spec.mask == "all",
		name + ": nontrivial selection")
	var transform: Transform2D = spec.transform
	var local_points: PackedVector2Array = spec.points
	var view_points: PackedVector2Array = PackedVector2Array()
	var recovered_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in local_points:
		view_points.append(transform * point)
		recovered_points.append(transform.affine_inverse() * view_points[-1])
	var expected_begin: DrawingResult = reference.doc.begin_edit(reference.layer,
		reference.doc.revision, transform)
	_check(expected_begin.ok, name + ": begin transformed canonical gesture")
	if not expected_begin.ok:
		return {}
	var expected_edit: DrawingEditSession = expected_begin.value
	var painted: DrawingResult = expected_edit.paint_path(
		view_points, PAINT, WIDTH, spec.erase, selection)
	_check(painted.ok and expected_edit.commit().ok, name + ": actual Godot gesture committed")
	if not painted.ok:
		return {}
	var expected: PackedByteArray = _tile(reference.doc, reference.layer, side)
	var path: PackedByteArray = _packed_path(recovered_points)
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])
	var payload: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, mask, path, side, WIDTH, paint, int(spec.erase), side * side)
	var decoded: Dictionary = _decode(source, payload, side)
	_check(decoded.get("ok", false), name + ": sorted canonical before/after wire")
	if not decoded.get("ok", false):
		return {}
	_check(decoded.bytes == expected, name + ": exact transformed Godot RGBA8 parity")
	if decoded.bytes != expected:
		return {}
	var changed: int = decoded.deltas.size()
	_check(changed > 0, name + ": nonempty changed pixels")
	_check(payload.size() == 4 + 12 * changed and changed <= selected_count,
		name + ": bounded masked sparse output")
	var all_selected: bool = true
	for delta: Dictionary in decoded.deltas:
		if mask[delta.y * side + delta.x] != 1:
			all_selected = false
			break
	_check(all_selected, name + ": every native change is selected")
	_check(_tile(native.doc, native.layer, side) == source and
		native.doc.revision == original_revision,
		name + ": native call has not published")
	# Capacity rejection is distinguishable from a legitimate four-byte no-op.
	var too_small: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, mask, path, side, WIDTH, paint, int(spec.erase), changed - 1)
	_check(too_small.is_empty(), name + ": insufficient capacity rejected")
	var begun: DrawingResult = native.doc.begin_edit(native.layer, original_revision)
	_check(begun.ok, name + ": begin native publication at source revision")
	if not begun.ok:
		return {}
	var native_edit: DrawingEditSession = begun.value
	var stage_ok: bool = true
	for delta: Dictionary in decoded.deltas:
		if not native_edit._stage(delta.x, delta.y, delta.after, null,
				false, false, delta.before).ok:
			stage_ok = false
			break
	_check(stage_ok, name + ": stage exactly verified original pixels")
	if not stage_ok:
		native_edit.cancel()
		return {}
	var published: DrawingResult = native_edit.commit()
	_check(published.ok and native.doc.revision == original_revision + 1,
		name + ": one atomic native publication")
	_check(_tile(native.doc, native.layer, side) == expected,
		name + ": document publication equals Godot oracle")
	_check(native.doc.undo().ok and _tile(native.doc, native.layer, side) == source,
		name + ": exact hidden-RGB undo")
	_check(native.doc.redo().ok and _tile(native.doc, native.layer, side) == expected,
		name + ": exact redo")
	return {"name": name, "side": side, "changed": changed,
		"selected": selected_count, "path_bytes": path.size(),
		"source_bytes": source.size(), "sparse_bytes": payload.size(),
		"canonical_sha256": _sha256(expected)}


func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in extension load")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_scalar_brush_sparse"), "native sparse entrypoint")
	if bridge == null:
		quit(1)
		return
	var records: Array[Dictionary] = []
	for spec: Dictionary in _cases():
		var result: Dictionary = _case(bridge, spec)
		if result.is_empty():
			break
		records.append(result)
	bridge.free()
	if failures == 0 and records.size() == _cases().size():
		print("T068_SCALAR_TRANSFORM_EVIDENCE: " + JSON.stringify(records))
		print("T068_SCALAR_TRANSFORM_PASSED: %d checks" % checks)
	else:
		printerr("T068_SCALAR_TRANSFORM_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and records.size() == _cases().size() else 1)
