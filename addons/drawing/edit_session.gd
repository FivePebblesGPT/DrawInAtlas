class_name DrawingEditSession
extends RefCounted
## Detached gesture transaction. No tile is changed before commit; cancel is free.
## View coordinates are camera-relative floats, anchor offsets are signed 64-bit.

var document: DrawingDocument
var layer_id: String = ""
var expected_revision: int = -1
var view_transform: Transform2D = Transform2D.IDENTITY
var anchor_x: int = 0
var anchor_y: int = 0
var _before: Dictionary[String, int] = {}
var _after: Dictionary[String, int] = {}
## Native pigment batches write only tile-local preview offsets while capturing.
## Global pixel string keys are materialized once, at commit or when a different
## edit API is mixed into the same session; they must not be rebuilt every dab.
var _hokusai_deferred: bool = false
var _hokusai_change_count: int = 0
# The hard Brush/Eraser blends each pixel only once per gesture. Keep covered
# coordinates in integer-keyed scanlines so repeated overlapping 60px sweeps
# can be rejected *before* their costly geometry and pixel-string allocation.
# Rows are global (anchor-relative edits must never collide).
var _covered_rows: Dictionary[int, Dictionary] = {}
# An edit sees one immutable source revision; avoid re-resolving its tile for
# each covered pixel. Cache successful absent tiles (null), never failed loads.
var _source_tiles: Dictionary[String, Variant] = {}
## Detached preview indexed by storage tile + pixel offset; never stored on the document.
var _preview_tiles: Dictionary[String, Dictionary] = {}
## Per-storage-tile monotonic content versions. A display tile only needs
## recomposition when a storage tile touching its source footprint changes.
var _preview_epoch: int = 0
var _preview_tile_versions: Dictionary[String, int] = {}
## Only touched pixels need rollback. A full triple-dictionary duplicate per motion
## event grew quadratically over long strokes.
var _paint_journal: Dictionary[String, Array] = {}
var _journaling: bool = false
var _closed: bool = false
var hokusai_perf: Dictionary = {"native_us": 0, "stage_us": 0, "pixels": 0}
var _has_last: bool = false
var _last: Vector2 = Vector2.ZERO


func _init(target: DrawingDocument, layer: String, source_revision: int,
		transform: Transform2D, origin_x: int, origin_y: int) -> void:
	document = target
	layer_id = layer
	expected_revision = source_revision
	view_transform = transform
	anchor_x = origin_x
	anchor_y = origin_y


func change_count() -> int:
	return _after.size() + _hokusai_change_count


## Publish uses canonical global string-keyed _before/_after; retain that
## contract without paying its allocation cost during every native dab.
func _materialize_hokusai_preview() -> void:
	if not _hokusai_deferred:
		return
	var stride: int = document.tile_stride
	for tile_key: String in _preview_tiles:
		var coordinates: PackedStringArray = tile_key.split(",")
		var tile_x: int = int(coordinates[0])
		var tile_y: int = int(coordinates[1])
		var source: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		var source_pixels: Dictionary[int, int] = {}
		if source != null:
			source_pixels = source._pixels
		var patch: Dictionary = _preview_tiles[tile_key]
		for local_index: int in patch:
			var local_x: int = local_index % stride
			var local_y: int = local_index / stride
			var pixel_key: String = "%d,%d" % [tile_x * stride + local_x,
				tile_y * stride + local_y]
			_before[pixel_key] = int(source_pixels.get(local_index, 0))
			_after[pixel_key] = int(patch[local_index])
	_hokusai_change_count = 0
	_hokusai_deferred = false


## Renderer reads only this session's detached patch; a closed/stale session is blank.
func preview_tile(tile_key: String) -> Dictionary:
	if _closed or document.revision != expected_revision:
		return {}
	return _preview_tiles.get(tile_key, {})


func preview_stamp_for_area(area: Rect2i) -> int:
	if _closed or _preview_tile_versions.is_empty() or document.revision != expected_revision:
		return 0
	var stride: int = document.tile_stride
	var start_x: int = DrawingDocument.TILES.floor_div(area.position.x, stride)
	var start_y: int = DrawingDocument.TILES.floor_div(area.position.y, stride)
	var end_x: int = DrawingDocument.TILES.floor_div(area.end.x - 1, stride)
	var end_y: int = DrawingDocument.TILES.floor_div(area.end.y - 1, stride)
	var stamp: int = 0
	# Tiny storage strides must not turn a 128px display lookup into a
	# quadratic scan of thousands of absent storage tiles.
	var span: int = (end_x - start_x + 1) * (end_y - start_y + 1)
	if _preview_tile_versions.size() < span:
		for key: String in _preview_tile_versions:
			var parts: PackedStringArray = key.split(",")
			var tile_x: int = int(parts[0])
			var tile_y: int = int(parts[1])
			if tile_x >= start_x and tile_x <= end_x and tile_y >= start_y and tile_y <= end_y:
				stamp = maxi(stamp, _preview_tile_versions[key])
	else:
		for y: int in range(start_y, end_y + 1):
			for x: int in range(start_x, end_x + 1):
				stamp = maxi(stamp, int(_preview_tile_versions.get("%d,%d" % [x, y], 0)))
	return stamp


## Snapshot the changed storage-tile generations into the *visible* display
## tile grid once per draw. Without this, a zoomed-out view asks every display
## tile to scan every changed storage key (especially with small strides).
## The index includes superseded/cleared preview versions: those still need to
## invalidate a texture which previously held a draft. A capped fallback keeps
## pathologically large strides or change sets from allocating unbounded maps.
func preview_stamps_for_display_tiles(visible_tiles: Rect2i, display_stride: int,
		max_entries: int = 40000) -> Dictionary:
	var index: Dictionary[String, int] = {}
	if _closed or document.revision != expected_revision or _preview_tile_versions.is_empty():
		return {"indexed": true, "stamps": index}
	if display_stride <= 0 or max_entries <= 0 or not visible_tiles.has_area():
		return {"indexed": false, "stamps": index}
	var stride: int = document.tile_stride
	# Coordinates may be signed 64-bit anchors. Do not overflow while deriving
	# the world-space footprint: the original per-area lookup remains exact.
	var safe_tile_limit: int = 1152921504606846976 / maxi(stride, 1)
	var attempted_entries: int = 0
	for key: String in _preview_tile_versions:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return {"indexed": false, "stamps": {}}
		var storage_x: int = int(parts[0])
		var storage_y: int = int(parts[1])
		if storage_x < -safe_tile_limit or storage_x > safe_tile_limit \
				or storage_y < -safe_tile_limit or storage_y > safe_tile_limit:
			return {"indexed": false, "stamps": {}}
		var world_x: int = storage_x * stride
		var world_y: int = storage_y * stride
		var first_x: int = maxi(visible_tiles.position.x,
			DrawingDocument.TILES.floor_div(world_x, display_stride))
		var first_y: int = maxi(visible_tiles.position.y,
			DrawingDocument.TILES.floor_div(world_y, display_stride))
		var last_x: int = mini(visible_tiles.end.x - 1,
			DrawingDocument.TILES.floor_div(world_x + stride - 1, display_stride))
		var last_y: int = mini(visible_tiles.end.y - 1,
			DrawingDocument.TILES.floor_div(world_y + stride - 1, display_stride))
		if last_x < first_x or last_y < first_y:
			continue
		# Bound attempted insertions as well as distinct keys; many overlapping
		# storage footprints must not turn an otherwise small index into a loop.
		var span_x: int = last_x - first_x + 1
		var span_y: int = last_y - first_y + 1
		if span_x > max_entries or span_y > max_entries / span_x \
				or attempted_entries + span_x * span_y > max_entries:
			return {"indexed": false, "stamps": {}}
		attempted_entries += span_x * span_y
		var version: int = _preview_tile_versions[key]
		for y: int in range(first_y, last_y + 1):
			for x: int in range(first_x, last_x + 1):
				var display_key: String = "%d,%d" % [x, y]
				index[display_key] = maxi(int(index.get(display_key, 0)), version)
	return {"indexed": true, "stamps": index}


func _sync_preview_pixel(tile_key: String, local_index: int, pixel_key: String) -> void:
	_preview_epoch += 1
	_preview_tile_versions[tile_key] = _preview_epoch
	var tile_patch: Dictionary = _preview_tiles.get(tile_key, {})
	if _after.has(pixel_key):
		tile_patch[local_index] = _after[pixel_key]
		_preview_tiles[tile_key] = tile_patch
	else:
		tile_patch.erase(local_index)
		if tile_patch.is_empty():
			_preview_tiles.erase(tile_key)


## Rare failure path for the other edit APIs which still use full snapshots.
## Their preview index must never outlive a rolled-back staging dictionary.
func _rebuild_preview_tiles() -> void:
	_preview_tiles.clear()
	for key: String in _after:
		var parts: PackedStringArray = key.split(",")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		var stride: int = document.tile_stride
		_sync_preview_pixel(DrawingDocument.TILES.tile_key64(x, y, stride),
			posmod(y, stride) * stride + posmod(x, stride), key)


func _rollback_paint() -> void:
	for key: String in _paint_journal:
		var snapshot: Array = _paint_journal[key]
		if snapshot[0]:
			_before[key] = snapshot[1]
		else:
			_before.erase(key)
		if snapshot[2]:
			_after[key] = snapshot[3]
		else:
			_after.erase(key)
		if not snapshot[4]:
			var parts: PackedStringArray = key.split(",")
			var row_y: int = int(parts[1])
			var row: Dictionary = _covered_rows.get(row_y, {})
			row.erase(int(parts[0]))
			if row.is_empty():
				_covered_rows.erase(row_y)
		_sync_preview_pixel(String(snapshot[5]), int(snapshot[6]), key)
	_paint_journal.clear()
	_journaling = false


func cancel() -> void:
	_before.clear()
	_after.clear()
	_hokusai_deferred = false
	_hokusai_change_count = 0
	_covered_rows.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_preview_tile_versions.clear()
	_paint_journal.clear()
	_journaling = false
	_closed = true


func commit() -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	# Ordinary Hokusai-only strokes already have verified tile-local preview
	# patches. Publish those directly rather than generating tens of thousands
	# of global keys only for DrawingDocument to split them back into tiles.
	# Other edit APIs materialize canonical keys before mixing, so their
	# existing publication path stays unchanged.
	var result: DrawingResult
	if _hokusai_deferred and _after.is_empty():
		result = document._publish_tile_edit(layer_id, expected_revision,
			_preview_tiles, _source_tiles)
	else:
		_materialize_hokusai_preview()
		result = document._publish_edit(layer_id, expected_revision, _before, _after)
	_closed = true
	_hokusai_deferred = false
	_hokusai_change_count = 0
	_before.clear()
	_after.clear()
	_covered_rows.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_preview_tile_versions.clear()
	_paint_journal.clear()
	return result


func _stage(x: int, y: int, rgba: int, selection: DrawingSelection = null,
		once: bool = false, blend: bool = false, verified_source: int = -1) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	# Ordinary GDScript Brush strokes must not pay an extra function call per
	# covered pixel; only a session with native deferred edits needs a flush.
	if _hokusai_deferred:
		_materialize_hokusai_preview()
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	if x <= -1073741824 or x >= 1073741824 or y <= -1073741824 or y >= 1073741824:
		return DrawingResult.failure("COORD_RANGE", "Gesture view-relative pixel exceeds safe bounds")
	if selection != null and not selection.allows(Vector2i(x, y)):
		return DrawingResult.success()
	var global_x: int = anchor_x + x
	var global_y: int = anchor_y + y
	var covered_row: Dictionary = {}
	if once:
		covered_row = _covered_rows.get(global_y, {})
		if covered_row.has(global_x):
			return DrawingResult.success()
	var key: String = "%d,%d" % [global_x, global_y]
	# Flood fill has already read this exact pixel through the verified source
	# snapshot. Re-resolving its tile here needlessly allocates a tile key and
	# repeats the pixel lookup. -1 means all other callers read it normally.
	var old: int = verified_source
	if old == -1:
		var stride: int = document.tile_stride
		var tile_key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride)
		if not _source_tiles.has(tile_key):
			var resolved: DrawingResult = document._resolve_chunk(layer_id, tile_key)
			if not resolved.ok:
				return resolved
			_source_tiles[tile_key] = resolved.value
		var tile: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		old = tile.get_rgba(posmod(global_x, stride), posmod(global_y, stride)) \
			if tile != null else 0
	var replacement: int = _blend(rgba, old) if blend else rgba
	var stride_local: int = document.tile_stride
	var preview_tile_key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride_local)
	var local_index: int = posmod(global_y, stride_local) * stride_local + posmod(global_x, stride_local)
	if _journaling and not _paint_journal.has(key):
		_paint_journal[key] = [_before.has(key), _before.get(key, 0),
			_after.has(key), _after.get(key, 0), covered_row.has(global_x),
			preview_tile_key, local_index]
	if once:
		covered_row[global_x] = true
		_covered_rows[global_y] = covered_row
	if not _before.has(key):
		_before[key] = old
	if replacement == _before[key]:
		_after.erase(key)
		_before.erase(key)
	else:
		_after[key] = replacement
	_sync_preview_pixel(preview_tile_key, local_index, key)
	return DrawingResult.success()


## Exact canonical bytes, optionally including nonzero RGB when alpha is zero.
## A region is always view-relative, and bounded before allocating/staging changes.
func apply_region(area: Rect2i, rgba8: PackedByteArray,
		selection: DrawingSelection = null, max_pixels: int = 1048576) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("REGION_LIMIT", "Region is empty or over pixel budget")
	if rgba8.size() != area.size.x * area.size.y * 4:
		return DrawingResult.failure("RGBA", "Region bytes must be tightly packed RGBA8")
	_materialize_hokusai_preview()
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for row: int in range(area.size.y):
		for column: int in range(area.size.x):
			var position: int = (row * area.size.x + column) * 4
			var rgba: int = int(rgba8[position]) | (int(rgba8[position + 1]) << 8) | (int(rgba8[position + 2]) << 16) | (int(rgba8[position + 3]) << 24)
			var result: DrawingResult = _stage(area.position.x + column, area.position.y + row, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


func fill_rect(area: Rect2i, rgba: int, selection: DrawingSelection = null,
		max_pixels: int = 1048576) -> DrawingResult:
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("REGION_LIMIT", "Rectangle is empty or over pixel budget")
	_materialize_hokusai_preview()
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var result: DrawingResult = _stage(x, y, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


func clear_rect(area: Rect2i, selection: DrawingSelection = null,
		max_pixels: int = 1048576) -> DrawingResult:
	return fill_rect(area, 0, selection, max_pixels)


## Native batched coverage avoids revisiting every 60px candidate in
## GDScript. Only newly hit pixels cross the ABI; the document's _stage()
## still owns straight-alpha compositing, selection, previews and history.
## Native output differences must be regression-tested before enabling Auto.
func paint_path_native_hard(path: PackedVector2Array, rgba: int, width: float,
		erase: bool, selection: DrawingSelection, native: Object,
		clip_bounds: Rect2i = Rect2i()) -> DrawingResult:
	if _closed or path.is_empty() or width <= 0.0 or not is_finite(width) or native == null:
		return DrawingResult.failure("NATIVE_BRUSH", "Invalid native hard-brush stroke")
	var inverse: Transform2D = view_transform.affine_inverse()
	var relative: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in path:
		relative.append(inverse * point)
	var result: Dictionary = native.call("hard_segments", relative, width, clip_bounds)
	if not result.get("ok", false):
		return DrawingResult.failure("NATIVE_BRUSH", str(result.get("error", "Native coverage failed")))
	var coordinates: PackedInt32Array = result.get("points", PackedInt32Array())
	if coordinates.size() % 2 != 0:
		return DrawingResult.failure("NATIVE_BRUSH", "Native coverage returned invalid coordinates")
	_journaling = true
	_paint_journal.clear()
	for index: int in range(0, coordinates.size(), 2):
		var staged: DrawingResult = _stage(coordinates[index], coordinates[index + 1],
			0 if erase else rgba, selection, true, not erase)
		if not staged.ok:
			_rollback_paint()
			return staged
	_paint_journal.clear()
	_journaling = false
	return DrawingResult.success(_after.size())


## Hokusai samples paint a native pigment surface rather than the prior
## detached preview. Apply exported deltas against the original layer snapshot;
## never stack opacity against the previous preview of the same stroke.
## Preflight ALL coordinates and source tiles before any write so a failed
## source read cannot leave a partially published preview batch.
func paint_path_hokusai(path: PackedVector2Array, rgba: int,
		selection: DrawingSelection, native: Object,
		clip_bounds: Rect2i = Rect2i(), pressure: float = 1.0) -> DrawingResult:
	if _closed or path.is_empty() or native == null:
		return DrawingResult.failure("HOKUSAI", "Invalid Hokusai brush stroke")
	var inverse: Transform2D = view_transform.affine_inverse()
	var relative: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in path:
		relative.append(inverse * point)
	var native_start_us: int = Time.get_ticks_usec()
	var changed: PackedInt32Array = native.call("preset_segments", relative, pressure)
	hokusai_perf["native_us"] = int(hokusai_perf["native_us"]) + Time.get_ticks_usec() - native_start_us
	hokusai_perf["pixels"] = int(hokusai_perf["pixels"]) + changed.size() / 3
	if changed.size() % 3 != 0 or changed.size() > 1048576 * 3:
		return DrawingResult.failure("HOKUSAI_LIMIT", "Invalid or excessive native pixel delta")
	var stage_start_us: int = Time.get_ticks_usec()
	var opacity: int = (rgba >> 24) & 255
	var stride: int = document.tile_stride
	# Group each accepted delta by its storage tile during preflight, then
	# stage using integer offsets. Native quantized pixels may revisit the same
	# source pixel across batches; never repeatedly construct global keys.
	# Packed arrays retrieved from a Dictionary can detach on mutation; keep
	# the current tile run local and write it back only at the next tile switch.
	# Spatial clustering usually keeps hundreds of deltas in one run.
	var tile_deltas: Dictionary[String, PackedInt32Array] = {}
	var clipping: bool = clip_bounds.has_area()
	var clip_left: int = clip_bounds.position.x
	var clip_top: int = clip_bounds.position.y
	var clip_right: int = clip_bounds.end.x
	var clip_bottom: int = clip_bounds.end.y
	# Hokusai emits changed pixels in spatially clustered 64px tile runs.
	# A Drawing storage tile usually covers many consecutive deltas, so
	# resolve its signed-64-bit key once per run, not once per changed pixel.
	var cached_tile_x: int = 0
	var cached_tile_y: int = 0
	var cached_tile_key: String = ""
	var has_cached_tile: bool = false
	var cached_pixels: PackedInt32Array = PackedInt32Array()
	for index: int in range(0, changed.size(), 3):
		var x: int = changed[index]
		var y: int = changed[index + 1]
		if x <= -1073741824 or x >= 1073741824 or y <= -1073741824 or y >= 1073741824:
			return DrawingResult.failure("COORD_RANGE", "Hokusai pixel exceeds safe edit coordinates")
		if clipping and (x < clip_left or y < clip_top or x >= clip_right or y >= clip_bottom):
			continue
		if selection != null and not selection.allows(Vector2i(x, y)):
			continue
		var global_x: int = anchor_x + x
		var global_y: int = anchor_y + y
		var storage_x: int = DrawingDocument.TILES.floor_div(global_x, stride)
		var storage_y: int = DrawingDocument.TILES.floor_div(global_y, stride)
		if not has_cached_tile or storage_x != cached_tile_x or storage_y != cached_tile_y:
			cached_tile_x = storage_x
			cached_tile_y = storage_y
			if has_cached_tile:
				tile_deltas[cached_tile_key] = cached_pixels
			cached_tile_key = "%d,%d" % [storage_x, storage_y]
			cached_pixels = tile_deltas.get(cached_tile_key, PackedInt32Array())
			has_cached_tile = true
		# floor_div (not 32-bit Vector2i conversion) keeps negative and >2^31
		# world positions in their original storage tile and local offset.
		var local_index: int = (global_y - storage_y * stride) * stride + global_x - storage_x * stride
		var pigment: int = int(changed[index + 2]) & 0xffffffff
		var alpha: int = (((pigment >> 24) & 255) * opacity + 127) / 255
		cached_pixels.push_back(local_index)
		cached_pixels.push_back((pigment & 0xffffff) | (alpha << 24))
	if has_cached_tile:
		tile_deltas[cached_tile_key] = cached_pixels
	# Any source failure aborts the entire batch BEFORE touching previews.
	for source_key: String in tile_deltas:
		if not _source_tiles.has(source_key):
			var resolved: DrawingResult = document._resolve_chunk(layer_id, source_key)
			if not resolved.ok:
				return resolved
			_source_tiles[source_key] = resolved.value
	# Sessions using another edit API already have canonical global keys; the
	# uncommon mixed case preserves _stage's existing semantics. Ordinary
	# native sessions defer that materialization until a single commit.
	var defer_keys: bool = _after.is_empty()
	if defer_keys and not tile_deltas.is_empty():
		_hokusai_deferred = true
	for tile_key: String in tile_deltas:
		var tile: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		# Local indices are prevalidated modulo the storage stride. Reading the
		# resident map once per tile avoids a GDScript getter for every native dab.
		var source_pixels: Dictionary[int, int] = {}
		if tile != null:
			source_pixels = tile._pixels
		var pixels: PackedInt32Array = tile_deltas[tile_key]
		var patch: Dictionary = _preview_tiles.get(tile_key, {})
		var touched: bool = false
		var tile_coordinates: PackedStringArray = PackedStringArray()
		if not defer_keys:
			tile_coordinates = tile_key.split(",")
		for index: int in range(0, pixels.size(), 2):
			var local_index: int = pixels[index]
			var local_x: int = local_index % stride
			var local_y: int = local_index / stride
			var old: int = int(source_pixels.get(local_index, 0))
			var replacement: int = _blend(pixels[index + 1], old)
			var previous: int = int(patch.get(local_index, old))
			if replacement == previous:
				continue
			touched = true
			if defer_keys:
				if replacement == old:
					patch.erase(local_index)
					_hokusai_change_count -= 1
				else:
					if not patch.has(local_index):
						_hokusai_change_count += 1
					patch[local_index] = replacement
			else:
				var global_x: int = int(tile_coordinates[0]) * stride + local_x
				var global_y: int = int(tile_coordinates[1]) * stride + local_y
				var pixel_key: String = "%d,%d" % [global_x, global_y]
				if replacement == old:
					_before.erase(pixel_key)
					_after.erase(pixel_key)
					patch.erase(local_index)
				else:
					if not _before.has(pixel_key):
						_before[pixel_key] = old
					_after[pixel_key] = replacement
					patch[local_index] = replacement
		if not touched:
			continue
		_preview_epoch += 1
		_preview_tile_versions[tile_key] = _preview_epoch
		if patch.is_empty():
			_preview_tiles.erase(tile_key)
		else:
			_preview_tiles[tile_key] = patch

	hokusai_perf["stage_us"] = int(hokusai_perf["stage_us"]) + Time.get_ticks_usec() - stage_start_us
	return DrawingResult.success(change_count())


## Swept hard brush; one alpha blend per covered pixel for the entire gesture.
## Pointer path is in view coordinates; transform freezes the raster-space mapping.
func paint_path(path: PackedVector2Array, rgba: int, width: float = 1.0,
		erase: bool = false, selection: DrawingSelection = null,
		max_candidates: int = 1048576, clip_bounds: Rect2i = Rect2i()) -> DrawingResult:
	if _closed or path.is_empty() or width <= 0.0 or not is_finite(width) or max_candidates <= 0:
		return DrawingResult.failure("BRUSH", "Invalid brush session, radius or pointer path")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "Invalid straight RGBA8 color")
	var inverse: Transform2D = view_transform.affine_inverse()
	_journaling = true
	_paint_journal.clear()
	var previous: Vector2 = _last
	for index: int in range(path.size()):
		var position: Vector2 = inverse * path[index]
		if not position.is_finite() or absf(position.x) > 1000000000.0 or absf(position.y) > 1000000000.0:
			_rollback_paint()
			return DrawingResult.failure("COORD_RANGE", "Brush point is outside the view-relative range")
		var start: Vector2 = previous if index > 0 or _has_last else position
		var touched: DrawingResult = _paint_segment(start, position, width * 0.5, rgba,
			erase, selection, max_candidates, clip_bounds)
		if not touched.ok:
			_rollback_paint()
			return touched
		previous = position
	_has_last = true
	_last = previous
	_paint_journal.clear()
	_journaling = false
	return DrawingResult.success(_after.size())


func _paint_segment(start: Vector2, finish: Vector2, radius: float, rgba: int,
		erase: bool, selection: DrawingSelection, max_candidates: int,
		clip_bounds: Rect2i = Rect2i(), depth: int = 0) -> DrawingResult:
	var left: int = floori(minf(start.x, finish.x) - radius - 0.5)
	var top: int = floori(minf(start.y, finish.y) - radius - 0.5)
	var right: int = ceili(maxf(start.x, finish.x) + radius + 0.5)
	var bottom: int = ceili(maxf(start.y, finish.y) + radius + 0.5)
	# Restrict only this stroke's candidate window, never sparse document data.
	# Clipping before the candidate limit also avoids processing off-frame runs.
	if clip_bounds.has_area():
		left = maxi(left, clip_bounds.position.x)
		top = maxi(top, clip_bounds.position.y)
		right = mini(right, clip_bounds.end.x)
		bottom = mini(bottom, clip_bounds.end.y)
	var columns: int = right - left
	var rows: int = bottom - top
	if columns <= 0 or rows <= 0:
		return DrawingResult.success()
	if columns > max_candidates or rows > max_candidates / columns:
		if depth >= 32 or start == finish:
			return DrawingResult.failure("BRUSH_LIMIT", "Brush candidate window exceeds pixel limit")
		var middle: Vector2 = (start + finish) * 0.5
		var first: DrawingResult = _paint_segment(start, middle, radius, rgba, erase,
			selection, max_candidates, clip_bounds, depth + 1)
		if not first.ok:
			return first
		return _paint_segment(middle, finish, radius, rgba, erase,
			selection, max_candidates, clip_bounds, depth + 1)
	# A stationary dab has no segment projection. Axis-aligned segments can
	# compute squared distance without a Geometry2D call per candidate. Keep
	# the original native geometry oracle for all oblique sweeps.
	if start != finish and (start.x == finish.x or start.y == finish.y):
		return _paint_axis_segment(start, finish, left, top, right, bottom,
			radius * radius, rgba, erase, selection)
	var stationary: bool = start == finish
	var radius_squared: float = radius * radius
	for y: int in range(top, bottom):
		var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
		for x: int in range(left, right):
			if covered_row.has(anchor_x + x):
				continue
			var center: Vector2 = Vector2(x + 0.5, y + 0.5)
			var nearest: Vector2 = start if stationary else Geometry2D.get_closest_point_to_segment(center, start, finish)
			if center.distance_squared_to(nearest) > radius_squared:
				continue
			var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
				selection, true, not erase)
			if not result.ok:
				return result
	return DrawingResult.success()


func _paint_axis_segment(start: Vector2, finish: Vector2, left: int, top: int,
		right: int, bottom: int, radius_squared: float, rgba: int, erase: bool,
		selection: DrawingSelection) -> DrawingResult:
	if start.y == finish.y:
		var min_x: float = minf(start.x, finish.x)
		var max_x: float = maxf(start.x, finish.x)
		for y: int in range(top, bottom):
			var dy: float = (y + 0.5) - start.y
			var dy_squared: float = dy * dy
			if dy_squared > radius_squared:
				continue
			var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
			for x: int in range(left, right):
				if covered_row.has(anchor_x + x):
					continue
				var center_x: float = x + 0.5
				var dx: float = center_x - clampf(center_x, min_x, max_x)
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase)
				if not result.ok:
					return result
	else:
		var min_y: float = minf(start.y, finish.y)
		var max_y: float = maxf(start.y, finish.y)
		for y: int in range(top, bottom):
			var center_y: float = y + 0.5
			var dy: float = center_y - clampf(center_y, min_y, max_y)
			var dy_squared: float = dy * dy
			var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
			for x: int in range(left, right):
				if covered_row.has(anchor_x + x):
					continue
				var dx: float = (x + 0.5) - start.x
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase)
				if not result.ok:
					return result
	return DrawingResult.success()


func paint_polygon(polygon: PackedVector2Array, rgba: int,
		selection: DrawingSelection = null, max_pixels: int = 1048576) -> DrawingResult:
	if polygon.size() < 3:
		return DrawingResult.failure("SHAPE", "A filled polygon needs three vertices")
	var inverse: Transform2D = view_transform.affine_inverse()
	var points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in polygon:
		var pixel_point: Vector2 = inverse * point
		if not pixel_point.is_finite() or absf(pixel_point.x) > 1000000000.0 or absf(pixel_point.y) > 1000000000.0:
			return DrawingResult.failure("COORD_RANGE", "Polygon point out of view-relative bounds")
		points.append(pixel_point)
	var min_x: float = points[0].x
	var min_y: float = points[0].y
	var max_x: float = points[0].x
	var max_y: float = points[0].y
	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var area: Rect2i = Rect2i(floori(min_x), floori(min_y),
		ceili(max_x) - floori(min_x), ceili(max_y) - floori(min_y))
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("SHAPE_LIMIT", "Polygon exceeds candidate budget")
	_materialize_hokusai_preview()
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				continue
			var result: DrawingResult = _stage(x, y, rgba, selection)
			if not result.ok:
				_before = old_before
				_after = old_after
				_rebuild_preview_tiles()
				return result
	return DrawingResult.success(_after.size())


## Read one canonical source pixel from the gesture's immutable tile snapshot.
## This also materializes verified lazy tiles: has_stored_pixel() only inspects
## resident tiles, so using it to gate fill would silently reject persisted
## artwork that has not yet been decoded. A zero RGBA8 pixel is still blank;
## nonzero hidden RGB (alpha=0) remains a legitimate stored fill source.
func _fill_source_pixel(point: Vector2i) -> DrawingResult:
	var global_x: int = anchor_x + point.x
	var global_y: int = anchor_y + point.y
	var stride: int = document.tile_stride
	var key: String = DrawingDocument.TILES.tile_key64(global_x, global_y, stride)
	if not _source_tiles.has(key):
		var loaded: DrawingResult = document._resolve_chunk(layer_id, key)
		if not loaded.ok:
			return loaded
		_source_tiles[key] = loaded.value
	var tile: DrawingRasterTile = _source_tiles[key] as DrawingRasterTile
	if tile == null:
		return DrawingResult.success(0)
	return DrawingResult.success(tile.get_rgba(posmod(global_x, stride),
		posmod(global_y, stride)))


## Four-connected fill of existing pixels; never expands into implicit blank space.
func flood_fill(seed: Vector2i, rgba: int, selection: DrawingSelection = null,
		limit: int = 262144) -> DrawingResult:
	if limit <= 0 or _closed:
		return DrawingResult.failure("FILL_LIMIT", "Invalid flood fill budget/session")
	var original: DrawingResult = _fill_source_pixel(seed)
	if not original.ok:
		return original
	if int(original.value) == 0:
		return DrawingResult.failure("BLANK_SEED", "Fill begins in unallocated transparent space")
	if original.value == rgba:
		return DrawingResult.failure("NO_CHANGE", "Target color is already present")
	var frontier: Array[Vector2i] = [seed]
	# Mark a point when queued, rather than when popped. Dense regions would
	# otherwise enqueue the same interior and boundary coordinates repeatedly.
	# The limit still counts unique examined candidates, including boundaries.
	var queued: Dictionary[Vector2i, bool] = {seed: true}
	_materialize_hokusai_preview()
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	var head: int = 0
	while head < frontier.size():
		if head >= limit:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return DrawingResult.failure("FILL_LIMIT", "Fill was cancelled at the pixel budget")
		var point: Vector2i = frontier[head]
		head += 1
		if selection != null and not selection.allows(point):
			continue
		var current: DrawingResult = _fill_source_pixel(point)
		if not current.ok:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return current
		if int(current.value) == 0 or current.value != original.value:
			continue
		var staged: DrawingResult = _stage(point.x, point.y, rgba, selection,
			false, false, int(current.value))
		if not staged.ok:
			_before = old_before
			_after = old_after
			_rebuild_preview_tiles()
			return staged
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + offset
			if not queued.has(next):
				queued[next] = true
				frontier.append(next)
	return DrawingResult.success(_after.size())


## Source-over in unpremultiplied 8-bit color. Unmodified destination bytes stay exact.
static func _blend(source: int, destination: int) -> int:
	var source_alpha: int = (source >> 24) & 255
	if source_alpha == 0:
		return destination
	# Fully opaque source and fully transparent destination both produce the
	# exact source RGBA8 bytes (regardless of hidden destination RGB). Avoid
	# three floating-point divides for the common blank-canvas/solid dab.
	# Mask sign-extended PackedInt32 pigment values to the canonical 32 bits.
	if source_alpha == 255 or ((destination >> 24) & 255) == 0:
		return source & 0xffffffff
	var sa: float = float(source_alpha) / 255.0
	var da: float = float((destination >> 24) & 255) / 255.0
	var out_alpha: float = sa + da * (1.0 - sa)
	var a: int = clampi(roundi(out_alpha * 255.0), 0, 255)
	# Exact original per-channel arithmetic, without allocating a typed Array
	# and appending to it three times for every source-over pixel. Preserve the
	# evaluation order and rounding; the independent T-095 blend oracle guards
	# hidden RGB, both alpha edges, and intermediate-alpha parity.
	var red: int = clampi(roundi((float(source & 255) * sa +
		float(destination & 255) * da * (1.0 - sa)) / out_alpha), 0, 255)
	var green: int = clampi(roundi((float((source >> 8) & 255) * sa +
		float((destination >> 8) & 255) * da * (1.0 - sa)) / out_alpha), 0, 255)
	var blue: int = clampi(roundi((float((source >> 16) & 255) * sa +
		float((destination >> 16) & 255) * da * (1.0 - sa)) / out_alpha), 0, 255)
	return red | (green << 8) | (blue << 16) | (a << 24)
