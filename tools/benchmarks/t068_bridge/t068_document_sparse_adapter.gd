extends RefCounted

# T-068 isolated native sparse-delta experiment. One checked batch, one
# canonical DrawingDocument commit. The production editor does not load this.
const MAX_TILES: int = 16
const MAX_PIXELS: int = 1048576
const VIEW_LIMIT: int = 1073741823


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "changed": 0, "dirty_tiles": []}


## The native response is little-endian [count:u32, (index, before, after):u32 * N].
## Validate *completeness*, not just each returned record. A native return with
## fewer valid records (including a forged zero-change header) must not silently
## omit requested edits. Recompute the expected changed set from the canonical
## source and eligible unique points before accepting a transaction.
static func _checked_deltas(bytes: PackedByteArray, source: PackedByteArray,
		points: PackedInt32Array, mask: PackedByteArray, stride: int,
		rgba: int, operation: int) -> Dictionary:
	if stride <= 0 or source.size() != stride * stride * 4 or \
			points.size() % 2 != 0 or \
			(not mask.is_empty() and mask.size() != stride * stride) or \
			operation < 0 or operation > 2 or bytes.size() < 4 or \
			(bytes.size() - 4) % 12 != 0:
		return _failure("NATIVE_DELTA")
	var count: int = bytes.decode_u32(0)
	if count > mini(points.size() / 2, stride * stride) or bytes.size() != 4 + count * 12:
		return _failure("NATIVE_DELTA")
	var expected: Dictionary[int, int] = {}
	var checked: Dictionary[int, bool] = {}
	for pair: int in range(points.size() / 2):
		var x: int = points[pair * 2]
		var y: int = points[pair * 2 + 1]
		if x < 0 or x >= stride or y < 0 or y >= stride:
			return _failure("NATIVE_DELTA")
		var index: int = y * stride + x
		if checked.has(index):
			continue
		checked[index] = true
		if not mask.is_empty() and mask[index] == 0:
			continue
		var before: int = source.decode_u32(index * 4)
		var after: int = 0 if operation == 1 else rgba if operation == 2 else \
			DrawingEditSession._blend(rgba, before)
		if before != after:
			expected[index] = after
	# The checked native kernel is permitted to return records in any order,
	# but it must return precisely the canonical set of changed coordinates.
	if count != expected.size():
		return _failure("NATIVE_DELTA")
	var seen: Dictionary[int, bool] = {}
	var deltas: Array[Dictionary] = []
	for i: int in range(count):
		var offset: int = 4 + 12 * i
		var index: int = bytes.decode_u32(offset)
		var before: int = bytes.decode_u32(offset + 4)
		var after: int = bytes.decode_u32(offset + 8)
		if not expected.has(index) or seen.has(index) or \
			before != source.decode_u32(index * 4) or after != expected[index]:
			return _failure("NATIVE_DELTA")
		seen[index] = true
		deltas.append({"x": index % stride, "y": index / stride,
			"before": before, "after": after})
	return {"ok": true, "deltas": deltas}

## Request shape matches t068_document_batch_adapter.gd. The extension sees
## immutable full source bytes, but returns only changed records rather than
## copying entire output tiles back through Godot's PackedByteArray boundary.
static func apply(bridge: Object, document: DrawingDocument, layer_id: String,
		expected_revision: int, requests: Array[Dictionary],
		before_commit: Callable = Callable()) -> Dictionary:
	if bridge == null or not bridge.has_method("apply_sparse_checked") or document == null:
		return _failure("BRIDGE")
	if document.revision != expected_revision:
		return _failure("STALE_REVISION")
	if requests.is_empty() or requests.size() > MAX_TILES:
		return _failure("BATCH_LIMIT")
	var stride: int = document.tile_stride
	if stride <= 0 or stride > 1024 or stride * stride > MAX_PIXELS / requests.size():
		return _failure("BATCH_LIMIT")
	var max_tile: int = 1152921504606846976 / stride - 1
	var anchor_x: int = 0
	var anchor_y: int = 0
	var seen_tiles: Dictionary[String, bool] = {}
	var proposed: Array[Dictionary] = []
	var positions: Array[Dictionary] = []
	var transferred: int = 0
	for i: int in range(requests.size()):
		var request: Dictionary = requests[i]
		if not request.get("cx") is int or not request.get("cy") is int or \
				not request.get("points") is PackedInt32Array or \
				not request.get("mask") is PackedByteArray or \
				not request.get("rgba") is int or not request.get("operation") is int:
			return _failure("BATCH_FORMAT")
		var cx: int = request["cx"]
		var cy: int = request["cy"]
		if cx < -max_tile or cx > max_tile or cy < -max_tile or cy > max_tile:
			return _failure("COORD_RANGE")
		var key: String = "%d,%d" % [cx, cy]
		if seen_tiles.has(key):
			return _failure("DUPLICATE_TILE")
		seen_tiles[key] = true
		if i == 0:
			anchor_x = cx
			anchor_y = cy
		var dx: int = cx - anchor_x
		var dy: int = cy - anchor_y
		var bound: int = (VIEW_LIMIT - stride) / stride
		if dx < -bound or dx > bound or dy < -bound or dy > bound:
			return _failure("VIEW_RANGE")
		var points: PackedInt32Array = request["points"]
		var mask: PackedByteArray = request["mask"]
		var rgba: int = request["rgba"]
		var operation: int = request["operation"]
		if points.size() % 2 != 0 or points.size() > 2097152 or \
				(not mask.is_empty() and mask.size() != stride * stride) or \
				rgba < 0 or rgba > 0xffffffff or operation < 0 or operation > 2:
			return _failure("BATCH_FORMAT")
		var resolved: DrawingResult = document.request_chunk_at(layer_id, cx, cy)
		if not resolved.ok:
			return _failure(resolved.code)
		if document.revision != expected_revision:
			return _failure("STALE_REVISION")
		var chunk: DrawingRasterTile = resolved.value as DrawingRasterTile
		var source: PackedByteArray = chunk.to_rgba8() if chunk != null else PackedByteArray()
		if chunk == null:
			source.resize(stride * stride * 4)
		var payload: PackedByteArray = bridge.apply_sparse_checked(source, points,
			mask, stride, stride, rgba, operation)
		var parsed: Dictionary = _checked_deltas(payload, source, points, mask,
			stride, rgba, operation)
		if not parsed.ok:
			return parsed
		transferred += payload.size()
		positions.append({"cx": cx, "cy": cy, "origin_x": cx * stride,
			"origin_y": cy * stride})
		if not parsed.deltas.is_empty():
			proposed.append({"dx": dx, "dy": dy, "deltas": parsed.deltas})
	if proposed.is_empty():
		return {"ok": true, "code": "NO_CHANGE", "changed": 0,
			"revision": expected_revision, "dirty_tiles": [],
			"native_return_bytes": transferred,
			"full_return_bytes": requests.size() * stride * stride * 4}
	var begun: DrawingResult = document.begin_edit(layer_id, expected_revision,
		Transform2D.IDENTITY, anchor_x * stride, anchor_y * stride)
	if not begun.ok:
		return _failure(begun.code)
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	for tile: Dictionary in proposed:
		for delta: Dictionary in tile.deltas:
			var staged: DrawingResult = edit._stage(tile.dx * stride + delta.x,
				tile.dy * stride + delta.y, delta.after, null, false, false, delta.before)
			if not staged.ok:
				edit.cancel()
				return _failure(staged.code)
	if before_commit.is_valid():
		before_commit.call()
	var saved: DrawingResult = edit.commit()
	if not saved.ok:
		return _failure(saved.code)
	var dirty: Array[Dictionary] = []
	for region: DrawingDirtyRegion in saved.regions:
		for position: Dictionary in positions:
			var ox: int = position.origin_x
			var oy: int = position.origin_y
			if region.x >= ox and region.x < ox + stride and \
					region.y >= oy and region.y < oy + stride:
				dirty.append({"cx": position.cx, "cy": position.cy,
					"rect": Rect2i(region.x - ox, region.y - oy,
						region.width, region.height)})
				break
	return {"ok": true, "code": "", "changed": saved.delta.after.size(),
		"revision": saved.revision, "dirty_tiles": dirty, "result": saved,
		"native_return_bytes": transferred,
		"full_return_bytes": requests.size() * stride * stride * 4}
