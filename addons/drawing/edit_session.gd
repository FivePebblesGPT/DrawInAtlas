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
## Immutable session storage stride. -1 selects the general signed-divide path.
var _stage_tile_shift: int = -1
## Hard Brush pixels arrive in spatial runs. A stable per-session tile-key
## cache avoids allocating the same "x,y" String for every covered pixel.
## Cache the *tile indices*, not the pixel offsets, so signed/irregular
## strides and transitions back to an earlier tile remain exact.
var _brush_cached_tile_x: int = 0
var _brush_cached_tile_y: int = 0
var _brush_cached_tile_key: String = ""
## The current storage tile's immutable source and detached patch can be reused
## across a scanline. A failed lazy read is never cached as a successful null
## tile, and the preview reference is reset after transaction rollback.
var _brush_cached_source: DrawingRasterTile = null
var _brush_cached_source_ready: bool = false
var _brush_cached_patch: Dictionary = {}
## Detached preview indexed by storage tile + pixel offset; never stored on the document.
var _preview_tiles: Dictionary[String, Dictionary] = {}
## Per-storage-tile monotonic content versions. A display tile only needs
## recomposition when a storage tile touching its source footprint changes.
var _preview_epoch: int = 0
var _preview_tile_versions: Dictionary[String, int] = {}
## The renderer's display tiles are 128px, but storage chunks may cover many
## such tiles. Keep a bounded *exact* touched-display index for ordinary
## Brush/Eraser pixel updates. Any path that cannot prove the index complete
## falls back to the existing conservative storage-tile stamps.
const PREVIEW_DISPLAY_STRIDE: int = 128
const MAX_PREVIEW_DISPLAY_KEYS: int = 4096
var _preview_display_versions: Dictionary[String, int] = {}
var _preview_display_exact: bool = true
var _preview_display_last_epoch: int = 0
var _preview_display_cached_x: int = 0
var _preview_display_cached_y: int = 0
var _preview_display_cached_key: String = ""


func _invalidate_exact_preview_display_index() -> void:
	_preview_display_exact = false
	_preview_display_versions.clear()


func _mark_preview_display_pixel(global_x: int, global_y: int) -> void:
	if not _preview_display_exact:
		return
	# Arithmetic shifts are floor division by 128 even for signed world pixels.
	var tile_x: int = global_x >> 7
	var tile_y: int = global_y >> 7
	if (_preview_display_cached_key.is_empty()
			or tile_x != _preview_display_cached_x
			or tile_y != _preview_display_cached_y):
		_preview_display_cached_x = tile_x
		_preview_display_cached_y = tile_y
		_preview_display_cached_key = "%d,%d" % [tile_x, tile_y]
	var key: String = _preview_display_cached_key
	if (not _preview_display_versions.has(key)
			and _preview_display_versions.size() >= MAX_PREVIEW_DISPLAY_KEYS):
		_invalidate_exact_preview_display_index()
		return
	_preview_display_versions[key] = _preview_epoch
	_preview_display_last_epoch = _preview_epoch


## Record only a native batch's changed local rectangle, not its enclosing
## cumulative transaction footprint. Signed storage coordinates remain 64-bit;
## the bounded display map uses string keys instead of Rect2i world positions.
## If any range cannot fit the exact index, fall back to conservative stamps.
func _mark_native_preview_display_rect(tile_x: int, tile_y: int,
		local_dirty: Rect2i) -> void:
	if not _preview_display_exact:
		return
	if not local_dirty.has_area():
		_invalidate_exact_preview_display_index()
		return
	var stride: int = document.tile_stride
	if local_dirty.position.x < 0 or local_dirty.position.y < 0 \
			or local_dirty.end.x > stride or local_dirty.end.y > stride:
		_invalidate_exact_preview_display_index()
		return
	var start_x: int = (tile_x * stride + local_dirty.position.x) >> 7
	var start_y: int = (tile_y * stride + local_dirty.position.y) >> 7
	var end_x: int = (tile_x * stride + local_dirty.end.x - 1) >> 7
	var end_y: int = (tile_y * stride + local_dirty.end.y - 1) >> 7
	var width: int = end_x - start_x + 1
	var height: int = end_y - start_y + 1
	if width > MAX_PREVIEW_DISPLAY_KEYS or height > MAX_PREVIEW_DISPLAY_KEYS / width:
		_invalidate_exact_preview_display_index()
		return
	for y: int in range(start_y, end_y + 1):
		for x: int in range(start_x, end_x + 1):
			var key: String = "%d,%d" % [x, y]
			if not _preview_display_versions.has(key) \
					and _preview_display_versions.size() >= MAX_PREVIEW_DISPLAY_KEYS:
				_invalidate_exact_preview_display_index()
				return
			_preview_display_versions[key] = _preview_epoch
	_preview_display_last_epoch = _preview_epoch


## Canvas-only refinement: pixels in one 256px storage tile should not dirty
## all four 128px display tiles. Preserve the existing public conservative
## stamp API and fail back to it for bulk edits, rollbacks, oversized
## gestures, nonstandard display strides, or synthetic legacy mutation tests.
func preview_display_stamps_for_canvas(visible_tiles: Rect2i, display_stride: int,
		max_entries: int = 40000) -> Dictionary:
	if (not _preview_display_exact
			or _preview_display_last_epoch != _preview_epoch
			or (_preview_display_versions.is_empty() and not _preview_tile_versions.is_empty())
			or display_stride != PREVIEW_DISPLAY_STRIDE):
		return preview_stamps_for_display_tiles(visible_tiles, display_stride, max_entries)
	var stamps: Dictionary[String, int] = {}
	if _closed or document.revision != expected_revision:
		return {"indexed": true, "stamps": stamps}
	if not visible_tiles.has_area() or max_entries <= 0:
		return {"indexed": false, "stamps": stamps}
	for key: String in _preview_display_versions:
		var parts: PackedStringArray = key.split(",")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		if (x >= visible_tiles.position.x and x < visible_tiles.end.x
				and y >= visible_tiles.position.y and y < visible_tiles.end.y):
			if stamps.size() >= max_entries:
				return {"indexed": false, "stamps": {}}
			stamps[key] = _preview_display_versions[key]
	return {"indexed": true, "stamps": stamps}
## Only touched pixels need rollback. A full triple-dictionary duplicate per motion
## event grew quadratically over long strokes.
var _paint_journal: Dictionary[String, Array] = {}
var _journaling: bool = false
## Only the internal swept-Brush loop reuses this immutable success sentinel.
## Public _stage() calls still receive independent result objects.
var _brush_stage_ok: DrawingResult = DrawingResult.success()
## Swept-Brush-only sessions have already built the exact tile-local patch and
## verified source pointers while painting. Publish that patch directly instead
## of parsing all global pixel string keys again on mouse-up. Any mixed public
## edit API returns to the canonical pixel-key publisher.
var _brush_tile_publish: bool = true
## Ordinary swept Brush-only edits also keep their changed pixels tile-local
## until an external edit API needs canonical global keys.
var _brush_deferred: bool = false
var _brush_change_count: int = 0
## T-253: a dense Delete keeps full RGBA8 tiles and tile-local preview offsets,
## not 70k+ global string-keyed pixel deltas. Mixed edit APIs materialize
## the same canonical pixel maps before continuing.
var _clear_deferred: bool = false
var _clear_change_count: int = 0
var _clear_images: Dictionary[String, PackedByteArray] = {}
var _clear_sources: Dictionary[String, Variant] = {}
var _clear_bounds: Dictionary[String, Rect2i] = {}
## Rollback records each first-attempted local offset in the paint batch,
## including source-identical pixels whose once-only coverage was recorded.
## Each entry is [prior_patch_exists, prior_pixel, newly_covered, global_y, global_x].
var _brush_tile_journal: Dictionary[String, Dictionary] = {}
var _brush_change_count_before_batch: int = 0
var _closed: bool = false
var hokusai_perf: Dictionary = {"native_us": 0, "stage_us": 0, "pixels": 0}
## Count stationary waypoints elided by the once-only Legacy hard-brush path.
## Native pigment presets intentionally retain every pressure/dab sample.
var _duplicate_waypoints_skipped: int = 0
## A stationary hard Brush/Eraser dab may repeat in the *next* one-point
## pointer batch. Reuse it only after a successful identical prior dab; a
## different selection, clip, width, color, budget or coordinate mapping must
## revalidate all candidates. Never apply this to accumulating Hokusai pigment.
var _cross_batch_dabs_skipped: int = 0
var _stationary_dab_valid: bool = false
var _stationary_dab_width: float = 0.0
var _stationary_dab_rgba: int = 0
var _stationary_dab_erase: bool = false
var _stationary_dab_clip: Rect2i = Rect2i()
var _stationary_dab_budget: int = 0
var _stationary_dab_transform: Transform2D = Transform2D.IDENTITY
var _stationary_dab_anchor_x: int = 0
var _stationary_dab_anchor_y: int = 0
var _stationary_dab_revision: int = -1
var _stationary_dab_preview_epoch: int = -1
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
	# A script-only gesture must reserve its history owner even when created
	# directly rather than through DrawingDocument.begin_edit(). The document
	# holds only a weak handle and releases closed/abandoned sessions.
	document._register_edit_session(self)
	var size: int = document.tile_stride
	if (size & (size - 1)) == 0:
		_stage_tile_shift = 0
		while size > 1:
			_stage_tile_shift += 1
			size >>= 1


func change_count() -> int:
	return _after.size() + _hokusai_change_count + _brush_change_count + _native_change_count + _clear_change_count


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
			source_pixels = source.sparse_pixels()
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


## Materialize Brush-only tile-local edits on the first mixed edit API. This
## keeps the canonical before/after contract for shape/fill/clipboard callers.
## Maintain the old mixed-session contract if a caller uses a second editing
## API after a deferred Delete. The standalone Delete commit skips this work.
func _materialize_clear_preview() -> void:
	if not _clear_deferred:
		return
	var stride: int = document.tile_stride
	for tile_key: String in _preview_tiles:
		var parts: PackedStringArray = tile_key.split(",")
		var tile_x: int = int(parts[0])
		var tile_y: int = int(parts[1])
		var original: DrawingRasterTile = _clear_sources[tile_key] as DrawingRasterTile
		var pixels: Dictionary[int, int] = original.sparse_pixels()
		for local_index: int in _preview_tiles[tile_key]:
			var x: int = tile_x * stride + local_index % stride
			var y: int = tile_y * stride + local_index / stride
			var key: String = "%d,%d" % [x, y]
			_before[key] = int(pixels[local_index])
			_after[key] = 0
	_clear_deferred = false
	_clear_change_count = 0
	_clear_images.clear()
	_clear_sources.clear()
	_clear_bounds.clear()


func _materialize_brush_preview() -> void:
	if not _brush_deferred:
		return
	var stride: int = document.tile_stride
	for tile_key: String in _preview_tiles:
		var coordinates: PackedStringArray = tile_key.split(",")
		var tile_x: int = int(coordinates[0])
		var tile_y: int = int(coordinates[1])
		var source: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		var source_pixels: Dictionary[int, int] = {}
		if source != null:
			source_pixels = source.sparse_pixels()
		var patch: Dictionary = _preview_tiles[tile_key]
		for local_index: int in patch:
			var x: int = tile_x * stride + local_index % stride
			var y: int = tile_y * stride + local_index / stride
			var key: String = "%d,%d" % [x, y]
			_before[key] = int(source_pixels.get(local_index, 0))
			_after[key] = int(patch[local_index])
	_brush_change_count = 0
	_brush_deferred = false


## Renderer reads only this session's detached patch; a closed/stale session is blank.
func preview_tile(tile_key: String) -> Dictionary:
	if _closed or document.revision != expected_revision:
		return {}
	return _preview_tiles.get(tile_key, {})


## The renderer can consume one native whole-tile byte span, bypassing the
## per-pixel GDScript patch dictionary used by historical stroke fixtures.
func preview_rgba8_tile(tile_key: String) -> PackedByteArray:
	if _closed or _native_tiles == null or not _preview_tile_versions.has(tile_key) \
			or document.revision != expected_revision:
		return PackedByteArray()
	if _native_preview_cache.has(tile_key):
		return _native_preview_cache[tile_key]
	var coordinates: PackedStringArray = tile_key.split(",")
	if coordinates.size() != 2:
		return PackedByteArray()
	var source: Dictionary = _native_tiles.call("read_tile", layer_id,
		int(coordinates[0]), int(coordinates[1]), true)
	if not bool(source.get("ok", false)):
		return PackedByteArray()
	var bytes: PackedByteArray = source.get("bytes", PackedByteArray())
	_native_preview_cache[tile_key] = bytes
	return bytes


## Display-only cropped native bytes. Every region is tile-local and cache entries
## are grouped by storage tile, so a later changed batch invalidates all crops.
## Cap distinct rectangles per tile: third-party render callers may request many
## overlapping offsets in one stroke without owning unbounded detached bytes.
## Commit, history and persistence always read complete canonical native tiles.
func preview_rgba8_region(tile_key: String, local_rect: Rect2i,
		display: bool = false) -> Dictionary:
	const MAX_CACHED_REGIONS_PER_TILE: int = 8
	if _closed or _native_tiles == null or not _preview_tile_versions.has(tile_key) \
			or document.revision != expected_revision:
		return {}
	var stride: int = document.tile_stride
	if local_rect.position.x < 0 or local_rect.position.y < 0 \
			or local_rect.size.x <= 0 or local_rect.size.y <= 0 \
			or local_rect.end.x > stride or local_rect.end.y > stride:
		return {}
	var local_key: String = "%s:%d,%d,%d,%d" % ["display" if display else "source",
		local_rect.position.x, local_rect.position.y, local_rect.size.x, local_rect.size.y]
	var crops: Dictionary = _native_preview_regions.get(tile_key, {})
	if crops.has(local_key):
		return crops[local_key] as Dictionary
	var coordinates: PackedStringArray = tile_key.split(",")
	if coordinates.size() != 2:
		return {}
	var method: String = "read_tile_region_display" if display else "read_tile_region"
	var source: Dictionary = _native_tiles.call(method, layer_id,
		int(coordinates[0]), int(coordinates[1]), true,
		local_rect.position.x, local_rect.position.y, local_rect.size.x, local_rect.size.y)
	if not bool(source.get("ok", false)):
		return {}
	var bytes: PackedByteArray = source.get("bytes", PackedByteArray())
	if bytes.size() != local_rect.get_area() * 4:
		return {}
	var result: Dictionary = {"bytes": bytes, "hidden_rgb": bool(source.get("hidden_rgb", true))}
	if crops.size() < MAX_CACHED_REGIONS_PER_TILE:
		crops[local_key] = result
		_native_preview_regions[tile_key] = crops
	return result


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
	if _preview_display_exact:
		var point: PackedStringArray = pixel_key.split(",")
		_mark_preview_display_pixel(int(point[0]), int(point[1]))
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
	_invalidate_exact_preview_display_index()
	_preview_tiles.clear()
	for key: String in _after:
		var parts: PackedStringArray = key.split(",")
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		var stride: int = document.tile_stride
		_sync_preview_pixel(DrawingDocument.TILES.tile_key64(x, y, stride),
			posmod(y, stride) * stride + posmod(x, stride), key)


func _rollback_paint() -> void:
	_invalidate_exact_preview_display_index()
	_stationary_dab_valid = false
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
	# A failed batch must not lose any pixels staged in previous batches.
	for tile_key: String in _brush_tile_journal:
		var entries: Dictionary = _brush_tile_journal[tile_key]
		var patch: Dictionary = _preview_tiles.get(tile_key, {})
		for local_index: int in entries:
			var snapshot: Array = entries[local_index]
			if snapshot[0]:
				patch[local_index] = snapshot[1]
			else:
				patch.erase(local_index)
			if snapshot[2]:
				var row: Dictionary = _covered_rows.get(int(snapshot[3]), {})
				row.erase(int(snapshot[4]))
				if row.is_empty():
					_covered_rows.erase(int(snapshot[3]))
		_preview_epoch += 1
		_preview_tile_versions[tile_key] = _preview_epoch
		_invalidate_exact_preview_display_index()
		if patch.is_empty():
			_preview_tiles.erase(tile_key)
		else:
			_preview_tiles[tile_key] = patch
	_brush_change_count = _brush_change_count_before_batch
	_brush_tile_journal.clear()
	# Rollback may detach/rebuild the current preview tile's dictionary. Never
	# reuse a reference which no longer corresponds to the published preview.
	_brush_cached_tile_key = ""
	_brush_cached_source_ready = false
	_brush_cached_source = null
	_brush_cached_patch = {}
	_journaling = false


func cancel() -> void:
	if _native_tiles != null:
		_native_tiles.call("discard_edit", _native_transaction)
		_native_tiles = null
		_native_transaction = 0
		_native_change_count = 0
		_native_preview_cache.clear()
		_native_preview_regions.clear()
	_finish_native_stroke(false)
	_stationary_dab_valid = false
	_brush_deferred = false
	_brush_change_count = 0
	_brush_tile_journal.clear()
	_clear_deferred = false
	_clear_change_count = 0
	_clear_images.clear()
	_clear_sources.clear()
	_clear_bounds.clear()
	_before.clear()
	_after.clear()
	_hokusai_deferred = false
	_hokusai_change_count = 0
	_covered_rows.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_preview_tile_versions.clear()
	_preview_display_versions.clear()
	_preview_display_cached_key = ""
	_paint_journal.clear()
	_journaling = false
	_closed = true


func commit() -> DrawingResult:
	_stationary_dab_valid = false
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if document.revision != expected_revision:
		cancel()
		return DrawingResult.failure("STALE_REVISION", "Stroke source revision changed")
	if _native_tiles != null:
		return _commit_native_tile_stroke()
	if not _finish_native_stroke(true):
		cancel()
		return DrawingResult.failure("NATIVE_COMMIT", "Native stroke commit failed")
	# Native Hokusai and ordinary Brush-only sessions already own verified
	# tile-local patches. Publish them without reparsing global pixel keys.
	# Mixed edit APIs retain the original canonical-key publication contract.
	var result: DrawingResult
	var tile_only: bool = (_hokusai_deferred and _after.is_empty()) \
		or (_brush_deferred and _after.is_empty()) \
		or (_brush_tile_publish and not _after.is_empty())
	if _clear_deferred:
		result = document._publish_dense_clear_tiles(layer_id, expected_revision,
			_clear_images, _clear_sources, _clear_bounds)
	elif tile_only:
		result = document._publish_tile_edit(layer_id, expected_revision,
			_preview_tiles, _source_tiles)
	else:
		_materialize_hokusai_preview()
		_materialize_brush_preview()
		result = document._publish_edit(layer_id, expected_revision, _before, _after)
	_closed = true
	_brush_deferred = false
	_brush_change_count = 0
	_brush_tile_journal.clear()
	_clear_deferred = false
	_clear_change_count = 0
	_clear_images.clear()
	_clear_sources.clear()
	_clear_bounds.clear()
	_hokusai_deferred = false
	_hokusai_change_count = 0
	_before.clear()
	_after.clear()
	_covered_rows.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_preview_tile_versions.clear()
	_preview_display_versions.clear()
	_preview_display_cached_key = ""
	_paint_journal.clear()
	return result


func _stage(x: int, y: int, rgba: int, selection: DrawingSelection = null,
		once: bool = false, blend: bool = false, verified_source: int = -1,
		internal_brush: bool = false) -> DrawingResult:
	if not internal_brush:
		_stationary_dab_valid = false
	if _clear_deferred:
		_materialize_clear_preview()
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if internal_brush and _brush_tile_publish and not _hokusai_deferred:
		return _stage_brush_tile(x, y, rgba, selection, once, blend, verified_source)
	if not internal_brush:
		_brush_tile_publish = false
		_materialize_brush_preview()
	# Ordinary GDScript Brush strokes must not pay an extra function call per
	# covered pixel; only a session with native deferred edits needs a flush.
	if _hokusai_deferred:
		_materialize_hokusai_preview()
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	if x <= -1073741824 or x >= 1073741824 or y <= -1073741824 or y >= 1073741824:
		return DrawingResult.failure("COORD_RANGE", "Gesture view-relative pixel exceeds safe bounds")
	if selection != null and not selection.allows(Vector2i(x, y)):
		return _brush_stage_ok if internal_brush else DrawingResult.success()
	var global_x: int = anchor_x + x
	var global_y: int = anchor_y + y
	var covered_row: Dictionary = {}
	if once:
		covered_row = _covered_rows.get(global_y, {})
		if covered_row.has(global_x):
			return _brush_stage_ok if internal_brush else DrawingResult.success()
	var key: String = "%d,%d" % [global_x, global_y]
	# Stage and preview access exactly the same source tile and local offset.
	# Resolve these only once per accepted candidate, rather than recomputing
	# tile keys/modulos and going through a per-pixel tile accessor twice.
	var stride: int = document.tile_stride
	var tile_key: String
	var local_x: int
	var local_y: int
	if _stage_tile_shift >= 0:
		tile_key = "%d,%d" % [global_x >> _stage_tile_shift,
			global_y >> _stage_tile_shift]
		local_x = global_x & (stride - 1)
		local_y = global_y & (stride - 1)
	else:
		tile_key = DrawingDocument.TILES.tile_key64(global_x, global_y, stride)
		local_x = posmod(global_x, stride)
		local_y = posmod(global_y, stride)
	var local_index: int = local_y * stride + local_x
	var old: int = verified_source
	if old == -1:
		if not _source_tiles.has(tile_key):
			var resolved: DrawingResult = document._resolve_chunk(layer_id, tile_key)
			if not resolved.ok:
				return resolved
			_source_tiles[tile_key] = resolved.value
		var tile: DrawingRasterTile = _source_tiles[tile_key] as DrawingRasterTile
		old = int(tile.sparse_pixels().get(local_index, 0)) if tile != null else 0
	var replacement: int = _blend(rgba, old) if blend else rgba
	var preview_tile_key: String = tile_key
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
	return _brush_stage_ok if internal_brush else DrawingResult.success()


## Fast path used only by unmodified swept Brush/Eraser sessions. Resolve and
## blend exactly as _stage() does, but omit redundant global pixel-string keys
## and _before/_after mutations until a mixed edit API actually needs them.
func _stage_brush_tile(x: int, y: int, rgba: int, selection: DrawingSelection,
		once: bool, blend: bool, verified_source: int) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	if x <= -1073741824 or x >= 1073741824 or y <= -1073741824 or y >= 1073741824:
		return DrawingResult.failure("COORD_RANGE", "Gesture view-relative pixel exceeds safe bounds")
	if selection != null and not selection.allows(Vector2i(x, y)):
		return _brush_stage_ok
	var global_x: int = anchor_x + x
	var global_y: int = anchor_y + y
	var covered_row: Dictionary = {}
	if once:
		covered_row = _covered_rows.get(global_y, {})
		if covered_row.has(global_x):
			return _brush_stage_ok
	var stride: int = document.tile_stride
	var local_x: int
	var local_y: int
	var tile_x: int
	var tile_y: int
	if _stage_tile_shift >= 0:
		tile_x = global_x >> _stage_tile_shift
		tile_y = global_y >> _stage_tile_shift
		local_x = global_x & (stride - 1)
		local_y = global_y & (stride - 1)
	else:
		local_x = posmod(global_x, stride)
		local_y = posmod(global_y, stride)
		# Dividing after subtracting the nonnegative local remainder avoids
		# truncation toward zero on negative signed world coordinates.
		tile_x = (global_x - local_x) / stride
		tile_y = (global_y - local_y) / stride
	if _brush_cached_tile_key.is_empty() or tile_x != _brush_cached_tile_x \
			or tile_y != _brush_cached_tile_y:
		_brush_cached_tile_key = "%d,%d" % [tile_x, tile_y]
		_brush_cached_tile_x = tile_x
		_brush_cached_tile_y = tile_y
		_brush_cached_source = null
		_brush_cached_source_ready = false
		_brush_cached_patch = _preview_tiles.get(_brush_cached_tile_key, {})
	var tile_key: String = _brush_cached_tile_key
	var local_index: int = local_y * stride + local_x
	# A preverified old pixel skips its individual source read, but the tile
	# identity must still be captured for fail-closed publication.
	if not _brush_cached_source_ready:
		if not _source_tiles.has(tile_key):
			var resolved: DrawingResult = document._resolve_chunk(layer_id, tile_key)
			if not resolved.ok:
				return resolved
			_source_tiles[tile_key] = resolved.value
		_brush_cached_source = _source_tiles[tile_key] as DrawingRasterTile
		_brush_cached_source_ready = true
	var old: int = verified_source
	if old == -1:
		old = int(_brush_cached_source.sparse_pixels().get(local_index, 0)) \
			if _brush_cached_source != null else 0
	var replacement: int = _blend(rgba, old) if blend else rgba
	var patch: Dictionary = _brush_cached_patch
	var previous: int = int(patch.get(local_index, old))
	if _journaling:
		var entries: Dictionary = _brush_tile_journal.get(tile_key, {})
		if not entries.has(local_index):
			entries[local_index] = [patch.has(local_index), previous,
				once and not covered_row.has(global_x), global_y, global_x]
			_brush_tile_journal[tile_key] = entries
	if once:
		covered_row[global_x] = true
		_covered_rows[global_y] = covered_row
	if replacement != previous:
		if previous == old and replacement != old:
			_brush_change_count += 1
		elif previous != old and replacement == old:
			_brush_change_count -= 1
		if replacement == old:
			patch.erase(local_index)
		else:
			patch[local_index] = replacement
		_preview_epoch += 1
		_preview_tile_versions[tile_key] = _preview_epoch
		_mark_preview_display_pixel(global_x, global_y)
		if patch.is_empty():
			_preview_tiles.erase(tile_key)
		else:
			_preview_tiles[tile_key] = patch
	_brush_deferred = true
	return _brush_stage_ok


## A bulk operation must validate its *entire* candidate rectangle before
## materializing deferred Brush/Erase history or invoking a lazy source loader.
## Size/budget validation belongs to each caller and precedes this check.
func _bulk_area_in_view_range(area: Rect2i) -> bool:
	var last_x: int = int(area.position.x) + int(area.size.x) - 1
	var last_y: int = int(area.position.y) + int(area.size.y) - 1
	return area.position.x > -1073741824 and last_x < 1073741824 \
		and area.position.y > -1073741824 and last_y < 1073741824


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
	if not _bulk_area_in_view_range(area):
		return DrawingResult.failure("COORD_RANGE", "Region exceeds safe view-relative pixel coordinates")
	_materialize_hokusai_preview()
	# A failed mixed edit must restore the already accepted deferred Brush, not
	# an empty pre-materialization snapshot. Materialize before rollback state.
	_materialize_brush_preview()
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
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("REGION_LIMIT", "Rectangle is empty or over pixel budget")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	if not _bulk_area_in_view_range(area):
		return DrawingResult.failure("COORD_RANGE", "Rectangle exceeds safe view-relative pixel coordinates")
	_materialize_hokusai_preview()
	# A failed mixed edit must restore the already accepted deferred Brush, not
	# an empty pre-materialization snapshot. Materialize before rollback state.
	_materialize_brush_preview()
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


## Content deletion visits only occupied source pixels. Selection bounds can
## span millions of empty tiles; the candidate budget protects dense clears,
## not the (potentially enormous) rectangle surrounding sparse content.
## Pending tiles are checked against the mask *before* lazy resolution.
func clear_rect(area: Rect2i, selection: DrawingSelection = null,
		max_pixels: int = 1048576) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if area.size.x <= 0 or area.size.y <= 0 or max_pixels <= 0:
		return DrawingResult.failure("REGION_LIMIT", "Clear region or pixel budget is invalid")
	# _stage() accepts only safe local coordinates, including when the source
	# contains no tiles. Check the whole region before staging anything.
	var last_x: int = int(area.position.x) + int(area.size.x) - 1
	var last_y: int = int(area.position.y) + int(area.size.y) - 1
	if area.position.x <= -1073741824 or last_x >= 1073741824 \
			or area.position.y <= -1073741824 or last_y >= 1073741824 \
			or not DrawingDocument.TILES.document_anchor_in_range(
				anchor_x + int(area.position.x), anchor_y + int(area.position.y)) \
			or not DrawingDocument.TILES.document_anchor_in_range(
				anchor_x + last_x, anchor_y + last_y):
		return DrawingResult.failure("COORD_RANGE", "Clear area exceeds safe pixel coordinates")
	_materialize_hokusai_preview()
	_materialize_brush_preview()
	_materialize_clear_preview()
	if _before.is_empty() and _after.is_empty() and _preview_tiles.is_empty() \
			and _native_tiles == null and ClassDB.class_exists("DrawingNativeTiles") \
			and document.tile_stride >= 16 and document.tile_stride <= 2048:
		return _clear_rect_dense_tiles(area, selection, max_pixels, last_x, last_y)
	var old_before: Dictionary[String, int] = _before.duplicate()
	var old_after: Dictionary[String, int] = _after.duplicate()
	var stride: int = document.tile_stride
	var count: int = 0
	# A mixed session can have newly staged pixels in absent source tiles.
	# Freeze those keys before traversing source tiles; _stage will update them.
	var staged_keys: Array[String] = _after.keys()
	for key: String in document.tile_keys(layer_id):
		var parts: PackedStringArray = key.split(",")
		var tile_x: int = int(parts[0]) * stride - anchor_x
		var tile_y: int = int(parts[1]) * stride - anchor_y
		var left: int = maxi(int(area.position.x), tile_x)
		var top: int = maxi(int(area.position.y), tile_y)
		var right: int = mini(last_x + 1, tile_x + stride)
		var bottom: int = mini(last_y + 1, tile_y + stride)
		if left >= right or top >= bottom:
			continue
		if selection != null and selection.enabled and not selection.inverted \
				and (selection.bounds.position.x >= right or selection.bounds.end.x <= left \
				or selection.bounds.position.y >= bottom or selection.bounds.end.y <= top):
			continue
		# A pending tile with no selected pixels must neither fetch nor fail,
		# even if its lazy provider is corrupt or unavailable.
		if selection != null and selection.enabled \
				and document._pending_tiles.has(layer_id + ":" + key):
			var authorized: bool = false
			for y: int in range(top, bottom):
				for x: int in range(left, right):
					if selection.allows(Vector2i(x, y)):
						authorized = true
						break
				if authorized:
					break
			if not authorized:
				continue
		var resolved: DrawingResult = document._resolve_chunk(layer_id, key)
		if not resolved.ok:
			return _rollback_sparse_clear(old_before, old_after, resolved)
		var tile: DrawingRasterTile = resolved.value as DrawingRasterTile
		if tile == null:
			continue
		# Packed native-projected RGBA8 is decoded once per occupied tile.
		# Zero-alpha pixels with hidden RGB are nonzero and must be cleared.
		var pixels: Dictionary[int, int] = tile.sparse_pixels()
		for index: int in pixels:
			var x: int = tile_x + index % stride
			var y: int = tile_y + index / stride
			if x < left or x >= right or y < top or y >= bottom:
				continue
			if selection != null and not selection.allows(Vector2i(x, y)):
				continue
			count += 1
			if count > max_pixels:
				return _rollback_sparse_clear(old_before, old_after,
					DrawingResult.failure("REGION_LIMIT", "Clear exceeds occupied pixel budget"))
			var staged: DrawingResult = _stage(x, y, 0, selection, false, false,
				int(pixels[index]))
			if not staged.ok:
				return _rollback_sparse_clear(old_before, old_after, staged)
	# Source traversal cannot see pixels introduced by this detached session.
	# It already rewrote source-backed patches to zero above, so only nonzero
	# values left in _after still require a second pass.
	for key: String in staged_keys:
		if not _after.has(key) or int(_after[key]) == 0:
			continue
		var coords: PackedStringArray = key.split(",")
		var x: int = int(coords[0]) - anchor_x
		var y: int = int(coords[1]) - anchor_y
		if x < area.position.x or x > last_x or y < area.position.y or y > last_y \
				or (selection != null and not selection.allows(Vector2i(x, y))):
			continue
		count += 1
		if count > max_pixels:
			return _rollback_sparse_clear(old_before, old_after,
				DrawingResult.failure("REGION_LIMIT", "Clear exceeds occupied pixel budget"))
		var staged: DrawingResult = _stage(x, y, 0, selection)
		if not staged.ok:
			return _rollback_sparse_clear(old_before, old_after, staged)
	return DrawingResult.success(_after.size())


## Fast Delete path: one source scan and one changed RGBA8 snapshot per
## occupied tile. Empty selection space is never traversed; sparse masks and
## transparent pixels with hidden RGB are treated exactly like _stage().
## Nothing reaches Rust or the document until commit() performs a checked
## whole-tile preflight. A failed stage leaves no partially published preview.
func _clear_rect_dense_tiles(area: Rect2i, selection: DrawingSelection,
		max_pixels: int, last_x: int, last_y: int) -> DrawingResult:
	var stride: int = document.tile_stride
	var count: int = 0
	for tile_key: String in document.tile_keys(layer_id):
		var parts: PackedStringArray = tile_key.split(",")
		var tile_x: int = int(parts[0]) * stride - anchor_x
		var tile_y: int = int(parts[1]) * stride - anchor_y
		var left: int = maxi(int(area.position.x), tile_x)
		var top: int = maxi(int(area.position.y), tile_y)
		var right: int = mini(last_x + 1, tile_x + stride)
		var bottom: int = mini(last_y + 1, tile_y + stride)
		if left >= right or top >= bottom:
			continue
		if selection != null and selection.enabled and not selection.inverted \
				and (selection.bounds.position.x >= right or selection.bounds.end.x <= left \
				or selection.bounds.position.y >= bottom or selection.bounds.end.y <= top):
			continue
		# Preserve the lazy-source rule: never fetch a pending tile that has
		# no selected pixels, even when its backing provider is corrupt.
		if selection != null and selection.enabled \
				and document._pending_tiles.has(layer_id + ":" + tile_key):
			var authorized: bool = false
			for y: int in range(top, bottom):
				for x: int in range(left, right):
					if selection.allows(Vector2i(x, y)):
						authorized = true
						break
				if authorized:
					break
			if not authorized:
				continue
		var resolved: DrawingResult = document._resolve_chunk(layer_id, tile_key)
		if not resolved.ok:
			_discard_dense_clear()
			return resolved
		var source: DrawingRasterTile = resolved.value as DrawingRasterTile
		if source == null:
			continue
		var pixels: Dictionary[int, int] = source.sparse_pixels()
		var patch: Dictionary[int, int] = {}
		var replacement: PackedByteArray = PackedByteArray()
		var min_x: int = stride
		var min_y: int = stride
		var max_x: int = -1
		var max_y: int = -1
		for local_index: int in pixels:
			var local_x: int = local_index % stride
			var local_y: int = local_index / stride
			var x: int = tile_x + local_x
			var y: int = tile_y + local_y
			if x < left or x >= right or y < top or y >= bottom \
					or (selection != null and not selection.allows(Vector2i(x, y))):
				continue
			count += 1
			if count > max_pixels:
				_discard_dense_clear()
				return DrawingResult.failure("REGION_LIMIT", "Clear exceeds occupied pixel budget")
			if replacement.is_empty():
				replacement = source.to_rgba8()
			replacement.encode_u32(local_index * 4, 0)
			patch[local_index] = 0
			min_x = mini(min_x, local_x)
			min_y = mini(min_y, local_y)
			max_x = maxi(max_x, local_x)
			max_y = maxi(max_y, local_y)
		if patch.is_empty():
			continue
		_clear_images[tile_key] = replacement
		_clear_sources[tile_key] = source
		_clear_bounds[tile_key] = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
		_source_tiles[tile_key] = source
		_preview_tiles[tile_key] = patch
		_preview_epoch += 1
		_preview_tile_versions[tile_key] = _preview_epoch
		_invalidate_exact_preview_display_index()
	_clear_change_count = count
	_clear_deferred = count > 0
	return DrawingResult.success(count)


func _discard_dense_clear() -> void:
	_clear_deferred = false
	_clear_change_count = 0
	_clear_images.clear()
	_clear_sources.clear()
	_clear_bounds.clear()
	_source_tiles.clear()
	_preview_tiles.clear()
	_preview_tile_versions.clear()
	_invalidate_exact_preview_display_index()


func _rollback_sparse_clear(before: Dictionary[String, int],
		after: Dictionary[String, int], failure: DrawingResult) -> DrawingResult:
	_before = before
	_after = after
	_rebuild_preview_tiles()
	return failure


## v1 native ABI: one opaque stroke handle, one packed input batch and one
## acknowledge/rollback path for both hard coverage and preset pigment.
## This temporary source adapter is removed with native tile ownership (T-148).
var _native_stroke: Object
var _native_handle: int = 0
var _native_clip_bounds: Rect2i = Rect2i()
var native_ffi_stats: Dictionary = {}
## T-185 opt-in diagnostic counters, not part of rendering or persistence.
## Stage time contains these nested phases; never add both as independent wall time.
var t185_native_stage: Dictionary = {
	"authorize_us": 0, "apply_us": 0, "dirty_query_us": 0,
	"stamp_us": 0, "index_us": 0, "dirty_entries": 0,
	"revisited_entries": 0, "batch_calls": 0, "unique_tiles": 0,
	"sample_pack_us": 0, "append_us": 0, "total_batch_us": 0,
}
## Native tile batches are optional only for historical direct adapter fixtures.
## Production Canvas opts into this Rust-owned staging path.
var _native_tiles: Object
var _native_transaction: int = 0
var _native_change_count: int = 0
var _native_preview_cache: Dictionary[String, PackedByteArray] = {}
var _native_preview_regions: Dictionary[String, Dictionary] = {}
var _native_selection: DrawingSelection


func begin_native_stroke(native: Object, preset_text: String,
		width: float, rgba: int, clip_bounds: Rect2i,
		use_native_tiles: bool = false, selection: DrawingSelection = null) -> DrawingResult:
	if _closed or native == null or _native_handle != 0 \
			or not native.has_method("stroke_abi_version") \
			or int(native.call("stroke_abi_version")) != 1:
		return DrawingResult.failure("NATIVE_ABI", "Required native stroke ABI v1 unavailable")
	var started: Dictionary = native.call("begin_stroke", layer_id,
		preset_text, width, rgba, expected_revision, clip_bounds)
	if not bool(started.get("ok", false)) or int(started.get("handle", 0)) <= 0:
		return DrawingResult.failure("NATIVE_BEGIN", str(started.get("error", "Native stroke begin failed")))
	_native_stroke = native
	_native_handle = int(started["handle"])
	_native_clip_bounds = clip_bounds
	if use_native_tiles:
		if not ClassDB.class_exists("DrawingNativeTiles"):
			_finish_native_stroke(false)
			return DrawingResult.failure("NATIVE_ABI", "Native tile store unavailable")
		_native_tiles = document._native_store_for_edit(expected_revision)
		if _native_tiles == null \
				or not _native_tiles.call("set_layer_editable", layer_id, true):
			_native_tiles = null
			_finish_native_stroke(false)
			return DrawingResult.failure("NATIVE_ABI", "Native tile store configuration failed")
		_native_selection = selection.detached_copy() if selection != null else null
		var opened: Dictionary = _native_tiles.call("begin_edit", layer_id,
			expected_revision, _native_selection != null and _native_selection.enabled)
		if not bool(opened.get("ok", false)):
			_native_tiles = null
			_finish_native_stroke(false)
			return DrawingResult.failure("NATIVE_BEGIN", str(opened.get("error", "Native tile edit unavailable")))
		_native_transaction = int(opened["transaction"])
	return DrawingResult.success(_native_handle)


func _finish_native_stroke(commit_native: bool) -> bool:
	if _native_handle == 0:
		return true
	var completed: bool = true
	if commit_native:
		native_ffi_stats = _native_stroke.call("stroke_stats", _native_handle, expected_revision)
		completed = bool(_native_stroke.call("commit_stroke", _native_handle, expected_revision))
	else:
		completed = bool(_native_stroke.call("abort_stroke", _native_handle))
	_native_handle = 0
	_native_stroke = null
	return completed


## One source import per storage tile; missing source is explicitly blank
## only after the document's lazy loader has successfully resolved it.
func _authorize_native_tiles(selection: DrawingSelection) -> DrawingResult:
	var needed: Dictionary = _native_stroke.call("required_tiles", _native_handle,
		expected_revision, document.tile_stride, anchor_x, anchor_y)
	if not bool(needed.get("ok", false)):
		return DrawingResult.failure("NATIVE_TILES", str(needed.get("error", "Native tile discovery failed")))
	var stride: int = document.tile_stride
	for identity: Dictionary in needed.get("tiles", []):
		var tile_x: int = int(identity["tile_x"])
		var tile_y: int = int(identity["tile_y"])
		var key: String = "%d,%d" % [tile_x, tile_y]
		if _source_tiles.has(key):
			continue
		var resolved: DrawingResult = document._resolve_chunk(layer_id, key)
		if not resolved.ok:
			return resolved
		# Lazy source providers execute user-owned code. Detect reentrant
		# structure/revision changes before importing source into Rust.
		if document.revision != expected_revision or not document._editable(layer_id):
			return DrawingResult.failure("STALE_REVISION",
				"Native source authorization changed during lazy load")
		var tile: DrawingRasterTile = resolved.value as DrawingRasterTile
		if bool(_native_tiles.call("has_source", layer_id, tile_x, tile_y,
				expected_revision)):
			if not document._native_source_matches(layer_id, key, tile):
				return DrawingResult.failure("STALE_PIXEL", "Native resident source was replaced " + key)
		else:
			var bytes: PackedByteArray = tile.to_rgba8() if tile != null else PackedByteArray()
			if not bool(_native_tiles.call("import_source", layer_id, tile_x, tile_y,
					expected_revision, bytes)):
				return DrawingResult.failure("NATIVE_SOURCE", "Native source import rejected " + key)
			document._remember_native_source(layer_id, key, tile)
		if selection != null and selection.enabled:
			var mask: PackedByteArray = PackedByteArray()
			mask.resize(stride * stride)
			for row: int in range(stride):
				for col: int in range(stride):
					if selection.allows(Vector2i(tile_x * stride + col - anchor_x,
							tile_y * stride + row - anchor_y)):
						mask[row * stride + col] = 1
			if not bool(_native_tiles.call("import_mask", _native_transaction,
					layer_id, tile_x, tile_y, mask)):
				return DrawingResult.failure("NATIVE_MASK", "Native selection import rejected " + key)
		_source_tiles[key] = tile
	return DrawingResult.success()


func _stage_native_tile_batch(erase: bool, selection: DrawingSelection) -> DrawingResult:
	# Each native transaction binds to its initial selection. Allowing a caller
	# to replace it between batches would leave already imported tile masks
	# authorized by the old selection while later batches use the new one.
	var frozen: DrawingSelection = _native_selection if _native_selection != null \
		and _native_selection.enabled else null
	var current: DrawingSelection = selection if selection != null \
		and selection.enabled else null
	if (frozen == null) != (current == null) or \
			(frozen != null and not frozen.same_as(current)):
		return DrawingResult.failure("NATIVE_SELECTION", "Gesture selection changed")
	var profile: bool = OS.has_environment("DRAWING_T185_PROFILE")
	var began_us: int = Time.get_ticks_usec() if profile else 0
	var authorized: DrawingResult = _authorize_native_tiles(frozen)
	if not authorized.ok:
		return authorized
	var authorized_us: int = Time.get_ticks_usec() if profile else 0
	var staged: Dictionary = _native_stroke.call("apply_tile_batch", _native_tiles,
		_native_handle, expected_revision, _native_transaction, anchor_x, anchor_y, erase)
	if not bool(staged.get("ok", false)):
		return DrawingResult.failure("NATIVE_BATCH", str(staged.get("error", "Native tile batch rejected")))
	var applied_us: int = Time.get_ticks_usec() if profile else 0
	# An opt-in, test-only counterfactual replays the original cumulative
	# invalidation *with the same binary and source hashes* for T-186 A/B runs.
	# Ordinary users always take the batch-local exact path.
	var counterfactual: bool = OS.has_environment("DRAWING_T186_CUMULATIVE_COUNTERFACTUAL")
	var changed: Array = _native_tiles.call("batch_dirty_tiles", _native_transaction)
	var dirty: Array = _native_tiles.call("dirty_tiles", _native_transaction) \
		if profile or counterfactual else []
	var queried_us: int = Time.get_ticks_usec() if profile else 0
	var revisited: int = 0
	if profile:
		# Count only keys known before this batch, as in T-185's baseline.
		for entry: Dictionary in dirty:
			if _preview_tile_versions.has("%d,%d" % [int(entry["tile_x"]), int(entry["tile_y"])]):
				revisited += 1
	if counterfactual:
		for entry: Dictionary in dirty:
			var key: String = "%d,%d" % [int(entry["tile_x"]), int(entry["tile_y"])]
			_preview_epoch += 1
			_preview_tile_versions[key] = _preview_epoch
			_native_preview_cache.erase(key)
			_native_preview_regions.erase(key)
		_invalidate_exact_preview_display_index()
	else:
		# Rust still retains cumulative rectangles for atomic commit/history.
		# Only actually modified native pixels may invalidate a warm texture.
		for entry: Dictionary in changed:
			var tile_x: int = int(entry["tile_x"])
			var tile_y: int = int(entry["tile_y"])
			var key: String = "%d,%d" % [tile_x, tile_y]
			_preview_epoch += 1
			_preview_tile_versions[key] = _preview_epoch
			_native_preview_cache.erase(key)
			_native_preview_regions.erase(key)
			_mark_native_preview_display_rect(tile_x, tile_y, entry["dirty"] as Rect2i)
	var stamped_us: int = Time.get_ticks_usec() if profile else 0
	if profile:
		var index_us: int = Time.get_ticks_usec()
		t185_native_stage["authorize_us"] += authorized_us - began_us
		t185_native_stage["apply_us"] += applied_us - authorized_us
		t185_native_stage["dirty_query_us"] += queried_us - applied_us
		t185_native_stage["stamp_us"] += stamped_us - queried_us
		t185_native_stage["index_us"] += index_us - stamped_us
		t185_native_stage["dirty_entries"] += dirty.size()
		t185_native_stage["revisited_entries"] += revisited
		t185_native_stage["batch_calls"] += 1
		t185_native_stage["unique_tiles"] = _preview_tile_versions.size()
	_native_change_count = _preview_tile_versions.size()
	return DrawingResult.success(_native_change_count)


func _commit_native_tile_stroke() -> DrawingResult:
	if not document._nodes.has(layer_id) or not document._editable(layer_id):
		cancel()
		return DrawingResult.failure("LOCKED", "Stroke target changed before publication")
	var dirty: Array = _native_tiles.call("dirty_tiles", _native_transaction)
	if dirty.is_empty():
		cancel()
		return DrawingResult.success(null, expected_revision)
	var images: Dictionary[String, PackedByteArray] = {}
	var sources: Dictionary[String, Variant] = {}
	var bounds: Dictionary[String, Rect2i] = {}
	for entry: Dictionary in dirty:
		var tile_x: int = int(entry["tile_x"])
		var tile_y: int = int(entry["tile_y"])
		var key: String = "%d,%d" % [tile_x, tile_y]
		if not _source_tiles.has(key):
			cancel()
			return DrawingResult.failure("STALE_PIXEL", "Native dirty tile missing source")
		var resolved: DrawingResult = document._resolve_chunk(layer_id, key)
		if not resolved.ok or resolved.value != _source_tiles[key]:
			cancel()
			return DrawingResult.failure("STALE_PIXEL", "Native commit source changed")
		var exported: Dictionary = _native_tiles.call("read_tile", layer_id, tile_x,
			tile_y, true)
		if not bool(exported.get("ok", false)):
			cancel()
			return DrawingResult.failure("NATIVE_TILE", "Native committed bytes unavailable")
		images[key] = exported.get("bytes", PackedByteArray())
		sources[key] = _source_tiles[key]
		bounds[key] = entry["dirty"]
	# The projection must be preflighted while Rust still owns the reversible
	# draft. A rejected source cannot leave a committed native transaction.
	var checked: DrawingResult = document._publish_native_tile_edit(layer_id,
		expected_revision, expected_revision + 1, images, sources, bounds, true, true)
	if not checked.ok:
		cancel()
		return checked
	native_ffi_stats = _native_stroke.call("stroke_stats", _native_handle,
		expected_revision)
	var native_commit: Dictionary = _native_stroke.call("commit_tiles", _native_tiles,
		_native_handle, expected_revision, _native_transaction)
	if not bool(native_commit.get("ok", false)):
		cancel()
		return DrawingResult.failure("NATIVE_COMMIT", str(native_commit.get("error", "Native commit rejected")))
	var new_revision: int = int(native_commit.get("revision", -1))
	var output: DrawingResult
	if bool(native_commit.get("no_change", false)):
		output = DrawingResult.success(null, expected_revision)
	else:
		output = document._install_prepared_native_tile_edit(layer_id, expected_revision,
			new_revision, checked, true, int(native_commit.get("history_token", 0)))
	var tile_stats: Dictionary = _native_tiles.call("stats")
	native_ffi_stats["tile_ffi_calls"] = int(tile_stats.get("ffi_calls", 0))
	native_ffi_stats["tile_bytes_imported"] = int(tile_stats.get("bytes_imported", 0))
	native_ffi_stats["tile_bytes_exported"] = int(tile_stats.get("bytes_exported", 0))
	native_ffi_stats["tile_pixel_stream_calls"] = int(tile_stats.get("pixel_stream_calls", -1))
	native_ffi_stats["tile_source_lookups"] = int(tile_stats.get("source_lookups", 0))
	_native_handle = 0
	_native_stroke = null
	_native_tiles = null
	_native_transaction = 0
	_native_preview_cache.clear()
	_native_preview_regions.clear()
	_source_tiles.clear()
	_preview_tile_versions.clear()
	_native_change_count = 0
	_closed = true
	return output


## Canvas passes source-coordinate segments; the frozen transform, layer,
## source revision and clip bind every batch to the original gesture. The
## interleaved packed samples keep one FFI call per batch, never per dab.
func paint_path_native(path: PackedVector2Array, rgba: int, erase: bool,
		selection: DrawingSelection, pressure: float = 1.0,
		delta_seconds: float = 0.01) -> DrawingResult:
	_stationary_dab_valid = false
	if _closed or _native_handle == 0 or path.is_empty() \
			or document.revision != expected_revision:
		return DrawingResult.failure("NATIVE_STALE", "Native stroke is closed or source revision changed")
	var pack_start_us: int = Time.get_ticks_usec()
	var inverse: Transform2D = view_transform.affine_inverse()
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(path.size() * 4)
	for index: int in range(path.size()):
		var relative: Vector2 = inverse * path[index]
		samples[index * 4] = relative.x
		samples[index * 4 + 1] = relative.y
		samples[index * 4 + 2] = pressure
		samples[index * 4 + 3] = delta_seconds
	var native_start_us: int = Time.get_ticks_usec()
	if OS.has_environment("DRAWING_T185_PROFILE"):
		t185_native_stage["sample_pack_us"] += native_start_us - pack_start_us
	var accepted: Dictionary = _native_stroke.call("append_samples", _native_handle,
		expected_revision, samples)
	if OS.has_environment("DRAWING_T185_PROFILE"):
		t185_native_stage["append_us"] += Time.get_ticks_usec() - native_start_us
	if not bool(accepted.get("ok", false)):
		return DrawingResult.failure("NATIVE_BATCH", str(accepted.get("error", "Sample batch rejected")))
	if _native_tiles != null:
		var result: DrawingResult = _stage_native_tile_batch(erase, selection)
		if OS.has_environment("DRAWING_T185_PROFILE"):
			t185_native_stage["total_batch_us"] += Time.get_ticks_usec() - pack_start_us
		return result
	var exported: Dictionary = _native_stroke.call("preview_changes", _native_handle, expected_revision)
	var native_elapsed_us: int = Time.get_ticks_usec() - native_start_us
	if not bool(exported.get("ok", false)):
		_native_stroke.call("acknowledge_batch", _native_handle, expected_revision, false)
		return DrawingResult.failure("NATIVE_PREVIEW", str(exported.get("error", "Preview unavailable")))
	var changed: PackedInt32Array = exported.get("changes", PackedInt32Array())
	var format: String = str(exported.get("format", ""))
	var staged: DrawingResult
	if format == "xy_rgba":
		staged = _stage_native_pigment_delta(changed, rgba, selection, erase)
		hokusai_perf["native_us"] = int(hokusai_perf["native_us"]) + native_elapsed_us
		hokusai_perf["pixels"] = int(hokusai_perf["pixels"]) + changed.size() / 3
	else:
		staged = DrawingResult.failure("NATIVE_FORMAT", "Unknown native pixel delta format")
	if not bool(_native_stroke.call("acknowledge_batch", _native_handle,
			expected_revision, staged.ok)):
		return DrawingResult.failure("NATIVE_ACK", "Native batch acknowledgement failed")
	return staged


func _stage_native_pigment_delta(changed: PackedInt32Array, rgba: int,
		selection: DrawingSelection, erase: bool) -> DrawingResult:
	if changed.size() % 3 != 0 or changed.size() > 1048576 * 3:
		return DrawingResult.failure("NATIVE_LIMIT", "Invalid native pigment buffer")
	var clip_bounds: Rect2i = _native_clip_bounds
	_brush_tile_publish = false
	_materialize_brush_preview()
	var stage_start_us: int = Time.get_ticks_usec()
	var opacity: int = (rgba >> 24) & 255
	var stride: int = document.tile_stride
	# Power-of-two storage strides cover the default 256px tiles and the
	# native 64px fixtures. Arithmetic right shifts implement floor division
	# for negative signed 64-bit anchors, while masking gives the exact local
	# remainder. Non-power-of-two strides retain the original general path.
	var power_of_two: bool = (stride & (stride - 1)) == 0
	var tile_shift: int = 0
	var tile_mask: int = stride - 1
	if power_of_two:
		var size: int = stride
		while size > 1:
			tile_shift += 1
			size >>= 1
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
		var storage_x: int = (global_x >> tile_shift) if power_of_two else DrawingDocument.TILES.floor_div(global_x, stride)
		var storage_y: int = (global_y >> tile_shift) if power_of_two else DrawingDocument.TILES.floor_div(global_y, stride)
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
		var local_index: int = ((global_y & tile_mask) * stride + (global_x & tile_mask)) \
			if power_of_two else (global_y - storage_y * stride) * stride + global_x - storage_x * stride
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
			source_pixels = tile.sparse_pixels()
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
			var replacement: int
			if erase:
				var remaining: int = (old >> 24) & 255
				var pigment_alpha: int = (pixels[index + 1] >> 24) & 255
				replacement = (old & 0xffffff) | (((remaining * (255 - pigment_alpha) + 127) / 255) << 24)
			else:
				replacement = _blend(pixels[index + 1], old)
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
		_invalidate_exact_preview_display_index()
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
	_brush_tile_journal.clear()
	_brush_change_count_before_batch = _brush_change_count
	var previous: Vector2 = _last
	var reusable_stationary_dab: bool = _stationary_dab_valid and _has_last \
		and selection == null and _stationary_dab_width == width \
		and _stationary_dab_rgba == rgba and _stationary_dab_erase == erase \
		and _stationary_dab_clip == clip_bounds \
		and _stationary_dab_budget == max_candidates \
		and _stationary_dab_transform == view_transform \
		and _stationary_dab_anchor_x == anchor_x \
		and _stationary_dab_anchor_y == anchor_y \
		and _stationary_dab_revision == document.revision \
		and _stationary_dab_preview_epoch == _preview_epoch
	var last_rasterized_was_dab: bool = false
	for index: int in range(path.size()):
		var position: Vector2 = inverse * path[index]
		if not position.is_finite() or absf(position.x) > 1000000000.0 or absf(position.y) > 1000000000.0:
			_rollback_paint()
			return DrawingResult.failure("COORD_RANGE", "Brush point is outside the view-relative range")
		var start: Vector2 = previous if index > 0 or _has_last else position
		# One-point batches from actual mouse events commonly repeat an
		# already accepted stationary dab. Only an unchanged, unmasked brush
		# context can reuse that result across calls. A different candidate
		# budget must still fail when the original dab would fail.
		if index == 0 and position == start and reusable_stationary_dab:
			_cross_batch_dabs_skipped += 1
			last_rasterized_was_dab = true
			previous = position
			continue
		# A repeated source position adds no coverage to the once-only hard
		# Brush/Eraser *within the same batch*. Repaint the first point of
		# every call: public callers may change width, selection or clip
		# between calls, exposing previously uncovered pixels at that point.
		# Hokusai uses a separate accumulating-pigment API and is untouched.
		if index > 0 and position == start:
			_duplicate_waypoints_skipped += 1
			previous = position
			continue
		var touched: DrawingResult = _paint_segment(start, position, width * 0.5, rgba,
			erase, selection, max_candidates, clip_bounds)
		if not touched.ok:
			_rollback_paint()
			return touched
		last_rasterized_was_dab = (start == position)
		previous = position
	_has_last = true
	_last = previous
	_stationary_dab_valid = last_rasterized_was_dab and selection == null
	if _stationary_dab_valid:
		_stationary_dab_width = width
		_stationary_dab_rgba = rgba
		_stationary_dab_erase = erase
		_stationary_dab_clip = clip_bounds
		_stationary_dab_budget = max_candidates
		_stationary_dab_transform = view_transform
		_stationary_dab_anchor_x = anchor_x
		_stationary_dab_anchor_y = anchor_y
		_stationary_dab_revision = document.revision
		_stationary_dab_preview_epoch = _preview_epoch
	_paint_journal.clear()
	_brush_tile_journal.clear()
	_journaling = false
	return DrawingResult.success(change_count())


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
	# Scanline bounds discard only candidates that cannot touch a dab/capsule.
	# Keep the original per-pixel squared-distance predicate at the edge. For
	# very large view coordinates, float32 Vector2 rounding could exceed our
	# two-pixel conservative margin; use the unbounded reference loop instead.
	var span_safe: bool = absf(start.x) < 1000000.0 and absf(start.y) < 1000000.0 \
		and absf(finish.x) < 1000000.0 and absf(finish.y) < 1000000.0
	if span_safe and start == finish:
		return _paint_dab_scanlines(start, radius, left, top, right, bottom,
			rgba, erase, selection)
	if span_safe and start != finish and (start.x == finish.x or start.y == finish.y):
		return _paint_axis_segment(start, finish, left, top, right, bottom,
			radius * radius, rgba, erase, selection)
	# Near-horizontal float32 deltas can underflow the Y-to-parameter
	# division. The original full-bounds Geometry2D path remains exact.
	if span_safe and start != finish and absf(finish.y - start.y) >= 0.001:
		return _paint_oblique_scanlines(start, finish, radius, left, top,
			right, bottom, rgba, erase, selection)
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
				selection, true, not erase, -1, true)
			if not result.ok:
				return result
	return DrawingResult.success()


## Bound an oblique capsule one row at a time. If a pixel center can be
## within radius of the segment, some point on the segment must be within
## radius in Y *and* X. The Y interval gives a conservative range of segment
## parameters; expanding its X range by the radius cannot discard a hit.
## Four extra pixels accommodate float32 arithmetic at supported view scales.
## Retain Geometry2D for final inclusion, and use the original full rectangle
## above 1M view coordinates where float32 rounding can be coarser.
func _paint_oblique_scanlines(start: Vector2, finish: Vector2, radius: float,
		left: int, top: int, right: int, bottom: int, rgba: int, erase: bool,
		selection: DrawingSelection) -> DrawingResult:
	var vertical_span: float = finish.y - start.y
	var broad_radius: float = radius + 4.0
	var radius_squared: float = radius * radius
	for y: int in range(top, bottom):
		var center_y: float = y + 0.5
		var t_a: float = (center_y - broad_radius - start.y) / vertical_span
		var t_b: float = (center_y + broad_radius - start.y) / vertical_span
		var t_low: float = maxf(0.0, minf(t_a, t_b))
		var t_high: float = minf(1.0, maxf(t_a, t_b))
		if t_low > t_high:
			continue
		var x_a: float = lerpf(start.x, finish.x, t_low)
		var x_b: float = lerpf(start.x, finish.x, t_high)
		var first_x: int = maxi(left, floori(minf(x_a, x_b) - broad_radius))
		var last_x: int = mini(right, ceili(maxf(x_a, x_b) + broad_radius + 1.0))
		var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
		for x: int in range(first_x, last_x):
			if covered_row.has(anchor_x + x):
				continue
			var center: Vector2 = Vector2(x + 0.5, center_y)
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(center, start, finish)
			if center.distance_squared_to(nearest) > radius_squared:
				continue
			var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
				selection, true, not erase, -1, true)
			if not result.ok:
				return result
	return DrawingResult.success()


## Conservative scanline windows are deliberately wider than the exact
## footprint; final acceptance uses the original Vector2 distance operation.
func _paint_dab_scanlines(center: Vector2, radius: float, left: int, top: int,
		right: int, bottom: int, rgba: int, erase: bool,
		selection: DrawingSelection) -> DrawingResult:
	var radius_squared: float = radius * radius
	var broad_radius: float = radius + 2.0
	var broad_squared: float = broad_radius * broad_radius
	for y: int in range(top, bottom):
		var dy: float = (y + 0.5) - center.y
		if dy * dy > broad_squared:
			continue
		var reach: float = sqrt(maxf(0.0, broad_squared - dy * dy))
		var first_x: int = maxi(left, floori(center.x - reach - 2.5))
		var last_x: int = mini(right, ceili(center.x + reach + 1.5))
		var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
		for x: int in range(first_x, last_x):
			if covered_row.has(anchor_x + x):
				continue
			var pixel_center: Vector2 = Vector2(x + 0.5, y + 0.5)
			if pixel_center.distance_squared_to(center) > radius_squared:
				continue
			var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
				selection, true, not erase, -1, true)
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
			var reach: float = sqrt(maxf(0.0, radius_squared - dy_squared))
			var first_x: int = maxi(left, floori(min_x - reach - 2.5))
			var last_x: int = mini(right, ceili(max_x + reach + 1.5))
			var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
			for x: int in range(first_x, last_x):
				if covered_row.has(anchor_x + x):
					continue
				var center_x: float = x + 0.5
				var dx: float = center_x - clampf(center_x, min_x, max_x)
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase, -1, true)
				if not result.ok:
					return result
	else:
		var min_y: float = minf(start.y, finish.y)
		var max_y: float = maxf(start.y, finish.y)
		for y: int in range(top, bottom):
			var center_y: float = y + 0.5
			var dy: float = center_y - clampf(center_y, min_y, max_y)
			var dy_squared: float = dy * dy
			if dy_squared > radius_squared:
				continue
			var reach: float = sqrt(maxf(0.0, radius_squared - dy_squared))
			var first_x: int = maxi(left, floori(start.x - reach - 2.5))
			var last_x: int = mini(right, ceili(start.x + reach + 1.5))
			var covered_row: Dictionary = _covered_rows.get(anchor_y + y, {})
			for x: int in range(first_x, last_x):
				if covered_row.has(anchor_x + x):
					continue
				var dx: float = (x + 0.5) - start.x
				if dx * dx + dy_squared > radius_squared:
					continue
				var result: DrawingResult = _stage(x, y, 0 if erase else rgba,
					selection, true, not erase, -1, true)
				if not result.ok:
					return result
	return DrawingResult.success()


func paint_polygon(polygon: PackedVector2Array, rgba: int,
		selection: DrawingSelection = null, max_pixels: int = 1048576) -> DrawingResult:
	if _closed:
		return DrawingResult.failure("CLOSED", "Gesture is already finished")
	if polygon.size() < 3:
		return DrawingResult.failure("SHAPE", "A filled polygon needs three vertices")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
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
	if not _bulk_area_in_view_range(area):
		return DrawingResult.failure("COORD_RANGE", "Polygon exceeds safe view-relative pixel coordinates")
	_materialize_hokusai_preview()
	# A failed mixed edit must restore the already accepted deferred Brush, not
	# an empty pre-materialization snapshot. Materialize before rollback state.
	_materialize_brush_preview()
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
	# Match _stage's accepted view-relative pixel and color ranges *before*
	# asking a lazy source provider for data. A provider is arbitrary external
	# code and must not be invoked for an edit that can never be published.
	if seed.x <= -1073741824 or seed.x >= 1073741824 \
			or seed.y <= -1073741824 or seed.y >= 1073741824:
		return DrawingResult.failure("COORD_RANGE", "Gesture view-relative pixel exceeds safe bounds")
	if rgba < 0 or rgba > 0xffffffff:
		return DrawingResult.failure("RGBA", "RGBA8 must contain four channels")
	# Begin-edit anchors permit a wider historical signed range than Rust's
	# canonical pixel projection. Validate the *global* seed before resolving
	# a lazy tile, not after staging at an unpublishable coordinate.
	var native_projection: bool = document._native_raster_store != null or (
		document.tile_stride >= 16 and document.tile_stride <= 2048
		and ClassDB.class_exists("DrawingNativeTiles"))
	if native_projection and not DrawingDocument.TILES.pixel_coordinates_in_projection_range(
			anchor_x + int(seed.x), anchor_y + int(seed.y)):
		return DrawingResult.failure("COORD_RANGE", "Fill seed exceeds native projection")
	# A masked-out seed cannot expand the fill frontier. Reject it before
	# resolving an arbitrary lazy source or flattening an accepted Brush.
	if selection != null and not selection.allows(seed):
		return DrawingResult.success(change_count())
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
	# A failed mixed edit must restore the already accepted deferred Brush, not
	# an empty pre-materialization snapshot. Materialize before rollback state.
	_materialize_brush_preview()
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
			# _stage() cannot publish beyond the signed view-relative range.
			# Do not inspect an unpublishable neighbor's arbitrary lazy source:
			# it can contain the same color and make an otherwise legal edge
			# fill fail after already staging the valid seed.
			if next.x <= -1073741824 or next.x >= 1073741824 \
					or next.y <= -1073741824 or next.y >= 1073741824:
				continue
			# This can overflow native projection even though the local offset is
			# valid. Do not enqueue/fetch a neighbor that Rust cannot publish.
			if native_projection and not DrawingDocument.TILES.pixel_coordinates_in_projection_range(
					anchor_x + int(next.x), anchor_y + int(next.y)):
				continue
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
