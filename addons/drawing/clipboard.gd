class_name DrawingClipboard
extends RefCounted
## Independent pixel payload. A copied selection has no references to source tiles.

var width: int = 0
var height: int = 0
var _pixels: Dictionary[Vector2i, int] = {}
## Store the source mask separately from the pixel payload: holes must remain
## holes when a selection is pasted or moved. No reference to live selection.
var source_position: Vector2i = Vector2i.ZERO
var source_selection: DrawingSelection


static func capture(document: DrawingDocument, layer_id: String,
		area: Rect2i, selection: DrawingSelection = null,
		origin_x: int = 0, origin_y: int = 0, max_pixels: int = 1048576) -> DrawingResult:
	if document == null or area.size.x <= 0 or area.size.y <= 0 or area.size.x > max_pixels or area.size.y > max_pixels / area.size.x:
		return DrawingResult.failure("CLIPBOARD_LIMIT", "Clipboard region is invalid or too large")
	if document.node_metadata(layer_id).get("kind", "") != DrawingLayerNode.RASTER:
		return DrawingResult.failure("LAYER", "Clipboard source is not a raster layer")
	var result: DrawingClipboard = DrawingClipboard.new()
	result.width = area.size.x
	result.height = area.size.y
	result.source_position = area.position
	result.source_selection = selection.detached_copy() if selection != null else null
	# A clipboard stores only nonzero RGBA8 values. Visit the occupied source
	# chunks and their stored pixels rather than scanning the enclosing marquee
	# (which can be a million mostly empty cells). Work in global 64-bit tile
	# coordinates so negative tiles and nonzero Atlas origins are exact.
	var stride: int = document.tile_stride
	var left: int = origin_x + int(area.position.x)
	var top: int = origin_y + int(area.position.y)
	var right: int = left + int(area.size.x)
	var bottom: int = top + int(area.size.y)
	for cy: int in range(DrawingDocument.TILES.floor_div(top, stride),
			DrawingDocument.TILES.floor_div(bottom - 1, stride) + 1):
		for cx: int in range(DrawingDocument.TILES.floor_div(left, stride),
				DrawingDocument.TILES.floor_div(right - 1, stride) + 1):
			var chunk_x: int = cx * stride
			var chunk_y: int = cy * stride
			if not document.raster_may_cover(layer_id, chunk_x, chunk_y, stride, stride):
				continue
			var key: String = "%d,%d" % [cx, cy]
			# Preserve the original lazy-source error boundary: an entirely
			# deselected pending chunk must not be fetched (or fail to load).
			# Resident chunks need no such area scan: their occupied cells are
			# tested against the selection below.
			if selection != null and selection.enabled and \
					document._pending_tiles.has(layer_id + ":" + key):
				var allowed: bool = false
				for gy: int in range(maxi(top, chunk_y), mini(bottom, chunk_y + stride)):
					for gx: int in range(maxi(left, chunk_x), mini(right, chunk_x + stride)):
						if selection.allows(Vector2i(gx - origin_x, gy - origin_y)):
							allowed = true
							break
					if allowed:
						break
				if not allowed:
					continue
			var fetched: DrawingResult = document._resolve_chunk(layer_id, key)
			if not fetched.ok:
				return fetched
			var tile: DrawingRasterTile = fetched.value as DrawingRasterTile
			if tile == null:
				continue
			for index: int in tile._pixels:
				var global_x: int = chunk_x + index % stride
				var global_y: int = chunk_y + index / stride
				if global_x < left or global_x >= right or global_y < top or global_y >= bottom:
					continue
				var local: Vector2i = Vector2i(global_x - origin_x, global_y - origin_y)
				if selection != null and not selection.allows(local):
					continue
				result._pixels[local - area.position] = tile._pixels[index]
	return DrawingResult.success(result, document.revision)


func paste(edit: DrawingEditSession, top_left: Vector2i,
		selection: DrawingSelection = null, transparent: bool = true) -> DrawingResult:
	if edit == null:
		return DrawingResult.failure("CLIPBOARD", "No destination edit session")
	var before: Dictionary[String, int] = edit._before.duplicate()
	var after: Dictionary[String, int] = edit._after.duplicate()
	var failure: DrawingResult
	# Capture stores only nonzero RGBA8 pixels. Most large selections contain
	# far fewer such pixels than their enclosing rectangle; scanning each empty
	# cell again on every transparent paste causes visible latency. The dense
	# path remains authoritative for opaque pastes, which must clear holes.
	if transparent and _pixels.size() * 4 < width * height:
		for point: Vector2i in _pixels:
			# Keep row-major paste's bounds and source-mask semantics even if a
			# caller has constructed a payload instead of using capture().
			if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height:
				continue
			if source_selection != null and not source_selection.allows(source_position + point):
				continue
			var rgba: int = _pixels[point]
			if rgba == 0:
				continue
			var staged: DrawingResult = edit._stage(top_left.x + point.x,
				top_left.y + point.y, rgba, selection)
			if not staged.ok:
				failure = staged
				break
	else:
		for y: int in range(height):
			for x: int in range(width):
				var point: Vector2i = Vector2i(x, y)
				if source_selection != null and not source_selection.allows(source_position + point):
					continue
				var rgba: int = _pixels.get(point, 0)
				if rgba == 0 and transparent:
					continue
				var staged: DrawingResult = edit._stage(top_left.x + x, top_left.y + y,
					rgba, selection)
				if not staged.ok:
					failure = staged
					break
			if failure != null:
				break
	if failure != null:
		edit._before = before
		edit._after = after
		edit._rebuild_preview_tiles()
		return failure
	return DrawingResult.success(edit.change_count())


## Stage a move against an already captured immutable source. This keeps
## transparent source cells transparent (they are not cleared or pasted), while
## preserving nonzero hidden-RGB pixels, overlaps and one undo delta.
## A sparse payload costs O(nonzero selected pixels), not O(area) per drag.
static func move_captured(edit: DrawingEditSession, clipboard: DrawingClipboard,
		displacement: Vector2i) -> DrawingResult:
	if edit == null or clipboard == null:
		return DrawingResult.failure("CLIPBOARD", "Missing edit session or captured payload")
	var before: Dictionary[String, int] = edit._before.duplicate()
	var after: Dictionary[String, int] = edit._after.duplicate()
	var failure: DrawingResult
	for local: Vector2i in clipboard._pixels:
		var source: Vector2i = clipboard.source_position + local
		var cleared: DrawingResult = edit._stage(source.x, source.y, 0)
		if not cleared.ok:
			failure = cleared
			break
	if failure == null:
		for local: Vector2i in clipboard._pixels:
			var target: Vector2i = clipboard.source_position + local + displacement
			var pasted: DrawingResult = edit._stage(target.x, target.y,
				clipboard._pixels[local])
			if not pasted.ok:
				failure = pasted
				break
	if failure == null:
		return DrawingResult.success(edit.change_count())
	edit._before = before
	edit._after = after
	edit._rebuild_preview_tiles()
	return failure


## Public edit API preserves atomicity even if the caller already staged work.
static func move_selection(edit: DrawingEditSession, source_area: Rect2i,
		displacement: Vector2i, selection: DrawingSelection = null) -> DrawingResult:
	if edit == null:
		return DrawingResult.failure("CLIPBOARD", "Missing document edit session")
	var captured: DrawingResult = capture(edit.document, edit.layer_id, source_area,
		selection, edit.anchor_x, edit.anchor_y)
	if not captured.ok:
		return captured
	if edit.change_count() > 0:
		# Preserve legacy semantics for a caller which already staged pixels:
		# even originally transparent selected cells must erase that draft.
		var before: Dictionary[String, int] = edit._before.duplicate()
		var after: Dictionary[String, int] = edit._after.duplicate()
		var cleared: DrawingResult = edit.clear_rect(source_area, selection)
		if cleared.ok:
			var pasted: DrawingResult = (captured.value as DrawingClipboard).paste(
				edit, source_area.position + displacement)
			if pasted.ok:
				return pasted
			cleared = pasted
		edit._before = before
		edit._after = after
		edit._rebuild_preview_tiles()
		return cleared
	return move_captured(edit, captured.value as DrawingClipboard, displacement)
