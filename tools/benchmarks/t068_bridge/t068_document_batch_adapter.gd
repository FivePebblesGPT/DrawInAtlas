extends RefCounted

# Experimental T-068: multiple independently computed native tiles, exactly one
# canonical DrawingDocument transaction. Not loaded by production Drawing/Atlas.
const MAX_TILES: int = 16
const MAX_PIXELS: int = 1048576
const VIEW_LIMIT: int = 1073741823


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "changed": 0, "dirty_tiles": []}


## Each request is {"cx": int, "cy": int, "points": PackedInt32Array,
## "mask": PackedByteArray, "rgba": int, "operation": int}. One operation per
## tile; intentionally refuse duplicate tile targets rather than read a stale
## snapshot twice. The small set must fit one view-relative coordinate window.
static func apply(bridge: Object, document: DrawingDocument, layer_id: String,
		expected_revision: int, requests: Array[Dictionary],
		before_commit: Callable = Callable()) -> Dictionary:
	if bridge == null or not bridge.has_method("apply_checked") or document == null:
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
	var seen: Dictionary[String, bool] = {}
	var proposed_tiles: Array[Dictionary] = []
	var positions: Array[Dictionary] = []
	for index: int in range(requests.size()):
		var request: Dictionary = requests[index]
		if not request.get("cx") is int or not request.get("cy") is int \
				or not request.get("points") is PackedInt32Array \
				or not request.get("mask") is PackedByteArray \
				or not request.get("rgba") is int or not request.get("operation") is int:
			return _failure("BATCH_FORMAT")
		var cx: int = request["cx"]
		var cy: int = request["cy"]
		if cx < -max_tile or cx > max_tile or cy < -max_tile or cy > max_tile:
			return _failure("COORD_RANGE")
		var key: String = "%d,%d" % [cx, cy]
		if seen.has(key):
			return _failure("DUPLICATE_TILE")
		seen[key] = true
		if index == 0:
			anchor_x = cx
			anchor_y = cy
		var dx: int = cx - anchor_x
		var dy: int = cy - anchor_y
		var bound: int = (VIEW_LIMIT - stride) / stride
		if dx < -bound or dx > bound or dy < -bound or dy > bound:
			return _failure("VIEW_RANGE")
		var source_result: DrawingResult = document.request_chunk_at(layer_id, cx, cy)
		if not source_result.ok:
			return _failure(source_result.code)
		if document.revision != expected_revision:
			return _failure("STALE_REVISION")
		var chunk: DrawingRasterTile = source_result.value as DrawingRasterTile
		var source: PackedByteArray = chunk.to_rgba8() if chunk != null else PackedByteArray()
		if chunk == null:
			source.resize(stride * stride * 4)
		var candidate: PackedByteArray = bridge.apply_checked(source,
			request["points"], request["mask"], stride, stride,
			request["rgba"], request["operation"])
		if candidate.size() != source.size():
			return _failure("NATIVE")
		positions.append({"cx": cx, "cy": cy, "origin_x": cx * stride,
			"origin_y": cy * stride})
		if candidate != source:
			proposed_tiles.append({"offset_x": dx * stride,
				"offset_y": dy * stride, "rgba8": candidate})
	if proposed_tiles.is_empty():
		return {"ok": true, "code": "NO_CHANGE", "changed": 0,
			"revision": expected_revision, "dirty_tiles": []}
	# Stage every region in one session; none is published until all succeed.
	var begun: DrawingResult = document.begin_edit(layer_id, expected_revision,
		Transform2D.IDENTITY, anchor_x * stride, anchor_y * stride)
	if not begun.ok:
		return _failure(begun.code)
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	for proposed: Dictionary in proposed_tiles:
		var rectangle: Rect2i = Rect2i(proposed["offset_x"],
			proposed["offset_y"], stride, stride)
		var staged: DrawingResult = edit.apply_region(rectangle, proposed["rgba8"])
		if not staged.ok:
			edit.cancel()
			return _failure(staged.code)
	if before_commit.is_valid():
		before_commit.call()
	var saved: DrawingResult = edit.commit()
	if not saved.ok:
		return _failure(saved.code)
	# DirtyRegion coordinates are signed 64-bit; never convert them to Vector2i
	# or floating-point world coordinates. Return local bounds for each tile.
	var dirty_tiles: Array[Dictionary] = []
	for region: DrawingDirtyRegion in saved.regions:
		for position: Dictionary in positions:
			var ox: int = position["origin_x"]
			var oy: int = position["origin_y"]
			if region.x >= ox and region.x < ox + stride \
					and region.y >= oy and region.y < oy + stride:
				dirty_tiles.append({"cx": position["cx"], "cy": position["cy"],
					"rect": Rect2i(region.x - ox, region.y - oy,
						region.width, region.height)})
				break
	return {"ok": true, "code": "", "changed": saved.delta.after.size(),
		"revision": saved.revision, "dirty_tiles": dirty_tiles, "result": saved}
