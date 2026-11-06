extends RefCounted

# T-068 isolated experiment: feed an opt-in native *tile* result through the
# real DrawingEditSession transaction, never directly mutate DrawingDocument.
# This is not a shipped renderer/backend and does not manage Atlas history.

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "changed": 0, "dirty_rect": Rect2i()}

static func apply(bridge: Object, document: DrawingDocument, layer_id: String,
		tile_x: int, tile_y: int, expected_revision: int,
		points: PackedInt32Array, mask: PackedByteArray, rgba: int, operation: int,
		before_commit: Callable = Callable()) -> Dictionary:
	if bridge == null or not bridge.has_method("apply_checked") or document == null:
		return _failure("BRIDGE")
	if document.revision != expected_revision:
		return _failure("STALE_REVISION")
	# apply_region() enforces a one-million-pixel transaction budget. Bound the
	# native tile before allocating, and reject origin multiplication overflow.
	var stride: int = document.tile_stride
	if stride <= 0 or stride > 1024 or stride * stride > 1048576:
		return _failure("TILE_LIMIT")
	var max_tile: int = 1152921504606846976 / stride
	if abs(tile_x) > max_tile or abs(tile_y) > max_tile:
		return _failure("COORD_RANGE")
	var origin_x: int = tile_x * stride
	var origin_y: int = tile_y * stride
	var resolved: DrawingResult = document.request_chunk_at(layer_id, tile_x, tile_y)
	if not resolved.ok:
		return _failure(resolved.code)
	if document.revision != expected_revision:
		return _failure("STALE_REVISION")
	var tile: DrawingRasterTile = resolved.value as DrawingRasterTile
	var source: PackedByteArray = tile.to_rgba8() if tile != null else PackedByteArray()
	if tile == null:
		source.resize(stride * stride * 4)
	var proposed: PackedByteArray = bridge.apply_checked(source, points, mask,
		stride, stride, rgba, operation)
	if proposed.size() != source.size():
		return _failure("NATIVE")
	# Reentrant callbacks are test-only; the document remains authoritative.
	if before_commit.is_valid():
		before_commit.call()
	if document.revision != expected_revision:
		return _failure("STALE_REVISION")
	if proposed == source:
		return {"ok": true, "code": "NO_CHANGE", "changed": 0,
			"dirty_rect": Rect2i(), "revision": expected_revision}
	var begun: DrawingResult = document.begin_edit(layer_id, expected_revision,
		Transform2D.IDENTITY, origin_x, origin_y)
	if not begun.ok:
		return _failure(begun.code)
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	var staged: DrawingResult = edit.apply_region(Rect2i(0, 0, stride, stride), proposed)
	if not staged.ok:
		edit.cancel()
		return _failure(staged.code)
	var saved: DrawingResult = edit.commit()
	if not saved.ok:
		return _failure(saved.code)
	var region: DrawingDirtyRegion = saved.regions[0] as DrawingDirtyRegion
	return {"ok": true, "code": "", "changed": saved.delta.after.size(),
		"revision": saved.revision,
		"dirty_rect": Rect2i(region.x - origin_x, region.y - origin_y,
			region.width, region.height), "result": saved}
