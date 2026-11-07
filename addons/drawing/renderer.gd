class_name DrawingRenderer
extends RefCounted
## Bounded, render-on-demand source compositing; never allocates a whole canvas.


## A synchronous display frame may render hundreds of source-aligned tiles.
## Snapshot the visible layer order once, rather than walking the document tree
## for every tile. Plans are deliberately ephemeral and revision/epoch pinned:
## neither edits nor lazy-source registrations may reuse an older plan.
static func prepare_visible_layers(document: DrawingDocument) -> Dictionary:
	if document == null:
		return {}
	var layers: Array[String] = []
	_collect_visible(document, DrawingDocument.ROOT_ID, layers)
	return {"document": document, "revision": document.revision,
		"source_epoch": document.display_source_epoch, "layers": layers,
		# A frame-local read-only cache shared by adjacent display tiles. 256
		# references maximum; canonical sparse tiles remain document-owned.
		"source_chunks": {}}


static func render(document: DrawingDocument, view: Rect2i,
		origin_x: int = 0, origin_y: int = 0, max_pixels: int = 1048576,
		preview: DrawingEditSession = null, visible_plan: Dictionary = {}) -> DrawingResult:
	if document == null or view.size.x <= 0 or view.size.y <= 0 or view.size.x > max_pixels or view.size.y > max_pixels / view.size.x:
		return DrawingResult.failure("RENDER_LIMIT", "Viewport must be bounded")
	# Never mix a stale or unrelated edit with committed document pixels.
	if preview != null and (preview.document != document or
			preview.expected_revision != document.revision):
		return DrawingResult.failure("PREVIEW_REVISION", "Preview source revision is stale")
	var leaf_layers: Array[String] = []
	if visible_plan.is_empty():
		_collect_visible(document, DrawingDocument.ROOT_ID, leaf_layers)
	else:
		if visible_plan.get("document") != document \
				or visible_plan.get("revision") != document.revision \
				or visible_plan.get("source_epoch") != document.display_source_epoch:
			return DrawingResult.failure("RENDER_PLAN_STALE", "Visible layer plan no longer matches source")
		if not (visible_plan.get("layers") is Array):
			return DrawingResult.failure("RENDER_PLAN_INVALID", "Visible layer plan is malformed")
		leaf_layers = visible_plan["layers"] as Array[String]
		if not visible_plan.get("source_chunks") is Dictionary:
			return DrawingResult.failure("RENDER_PLAN_INVALID", "Source cache must be a dictionary")
	var shared_source_chunks: Dictionary = visible_plan.get("source_chunks", {})
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(view.size.x * view.size.y * 4)
	# Keep 64-bit camera anchors out of Vector2i, which truncates at 32 bits.
	var world_x: int = origin_x + int(view.position.x)
	var world_y: int = origin_y + int(view.position.y)
	if abs(world_x) > 1152921504606846976 or abs(world_y) > 1152921504606846976:
		return DrawingResult.failure("COORD_RANGE", "Viewport anchor outside Drawing range")
	var font_warnings: Array[String] = []
	for layer_id: String in leaf_layers:
		if document.node_metadata(layer_id)["kind"] == DrawingLayerNode.TEXT:
			var element: DrawingTextElement = document.inspect_node(layer_id).text_element
			if element != null:
				if world_x < -1073741824 or world_x > 1073741824 \
						or world_y < -1073741824 or world_y > 1073741824:
					return DrawingResult.failure("TEXT_VIEW_RANGE", "Text viewport must use an in-range coordinate")
				var text_view: Rect2i = Rect2i(Vector2i(world_x, world_y), view.size)
				var result: DrawingResult = DrawingTextRaster.composite(element, text_view, bytes)
				if not result.ok:
					return result
				if result.code == "GLYPH_FALLBACK" and not font_warnings.has(result.message):
					font_warnings.append(result.message)
			continue
		# The cold canvas passes a revision-pinned frame plan. Before walking
		# thousands of absent pixels across sparse, separate layers, ask whether
		# any committed or pending source chunk overlaps this display tile. Keep
		# the legacy direct-render path, bounded-large-footprint fallback, and
		# detached preview layer conservative so no newly staged dab disappears.
		var active_preview: DrawingEditSession = preview if preview != null and preview.layer_id == layer_id else null
		if not visible_plan.is_empty() and active_preview == null \
				and not document.raster_may_cover(layer_id, world_x, world_y,
				view.size.x, view.size.y):
			continue
		# Resolve at most one source tile per scanline run, not once per pixel.
		# The region is still bounded; source tiles stay immutable throughout render.
		var raster: DrawingResult = _composite_raster(document, layer_id,
			world_x, world_y, view.size, bytes, active_preview, shared_source_chunks)
		if not raster.ok:
			return raster
	var rendered: DrawingResult = DrawingResult.success(Image.create_from_data(view.size.x, view.size.y,
		false, Image.FORMAT_RGBA8, bytes), document.revision)
	if not font_warnings.is_empty():
		rendered.code = "GLYPH_FALLBACK"
		rendered.message = "\n".join(font_warnings)
	return rendered


static func _collect_visible(document: DrawingDocument, parent_id: String,
		leaf_layers: Array[String]) -> void:
	for node_id: String in document.list_children(parent_id):
		var metadata: Dictionary = document.node_metadata(node_id)
		if metadata.is_empty() or not metadata["visible"]:
			continue
		if metadata["kind"] == DrawingLayerNode.GROUP:
			_collect_visible(document, node_id, leaf_layers)
		elif metadata["kind"] in [DrawingLayerNode.RASTER, DrawingLayerNode.TEXT]:
			leaf_layers.append(node_id)


## Tile-run compositor: avoids allocating DrawingResult and parsing signed keys
## for every visible pixel. Do not convert 64-bit anchors through Vector2i.
static func _composite_raster(document: DrawingDocument, layer_id: String,
		world_x: int, world_y: int, size: Vector2i, bytes: PackedByteArray,
		preview: DrawingEditSession = null,
		shared_chunks: Dictionary = {}) -> DrawingResult:
	var stride: int = document.tile_stride
	# The source revision is fixed for this bounded render. Reuse each resolved
	# storage tile (including an absent/null tile) and detached preview patch
	# across its scanlines instead of repeatedly entering lazy chunk lookup.
	# Cap the references and reset at each storage-tile row. A 1px stride or
	# extremely wide view must not accumulate up to max_pixels cache entries.
	# A failed lazy resolution must still abort rather than cache a blank tile.
	const MAX_SOURCE_TILE_REFS: int = 256
	const MAX_FRAME_SOURCE_REFS: int = 256
	var source_tiles: Dictionary[String, Variant] = {}
	var preview_patches: Dictionary[String, Dictionary] = {}
	var cached_row: int = -9223372036854775807
	for y: int in range(size.y):
		var world_row: int = world_y + y
		var storage_row: int = DrawingDocument.TILES.floor_div(world_row, stride)
		if storage_row != cached_row:
			source_tiles.clear()
			preview_patches.clear()
			cached_row = storage_row
		var local_y: int = posmod(world_row, stride)
		var x: int = 0
		while x < size.x:
			var absolute_x: int = world_x + x
			var local_x: int = posmod(absolute_x, stride)
			var run_length: int = mini(size.x - x, stride - local_x)
			var key: String = DrawingDocument.TILES.tile_key64(absolute_x, world_y + y, stride)
			var tile: DrawingRasterTile = null
			var patch: Dictionary = {}
			if source_tiles.has(key):
				tile = source_tiles[key] as DrawingRasterTile
				patch = preview_patches.get(key, {})
			else:
				# Adjacent 128px display tiles often share a 256px storage
				# chunk. The revision/epoch-pinned visible plan can reuse the
				# resolved canonical reference across their separate renders.
				# Null (absent) chunks are cached too; errors are never cached.
				var shared_key: String = layer_id + ":" + key
				if shared_chunks.has(shared_key):
					tile = shared_chunks[shared_key] as DrawingRasterTile
				else:
					var fetched: DrawingResult = document._resolve_chunk(layer_id, key)
					if not fetched.ok:
						return fetched
					tile = fetched.value as DrawingRasterTile
					if shared_chunks.size() < MAX_FRAME_SOURCE_REFS:
						shared_chunks[shared_key] = tile
				# A preview patch is not canonical; always read the current
				# detached edit even when its source chunk was cached before.
				if preview != null:
					patch = preview.preview_tile(key)
				if stride > 1 and source_tiles.size() < MAX_SOURCE_TILE_REFS:
					source_tiles[key] = tile
					if preview != null:
						preview_patches[key] = patch
			if tile != null or not patch.is_empty():
				# Both the detached source tile and preview patch are immutable for
				# this synchronous render. Read the canonical sparse RGBA map by
				# linear tile index: the public coordinate-checked getter otherwise
				# adds a GDScript call and two assertions for *every* dense pixel.
				# Never alter the owned map or let preview pixels escape into it.
				var source_pixels: Dictionary[int, int] = {}
				if tile != null:
					source_pixels = tile._pixels
				var has_preview_patch: bool = not patch.is_empty()
				# A nearly empty 256px source tile can occupy four 128px
				# display tiles. Scanning every destination pixel would be
				# wasteful when only a handful of canonical pixels exist.
				# Restrict this path to committed sparse chunks: detached preview
				# patches may add or erase pixels not present in the source map.
				# The short-run/dense fallback avoids O(rows * stored_pixels)
				# iteration for 1px strides and ordinarily populated art.
				if preview == null and source_pixels.size() <= 12 and run_length >= 16:
					var first_index: int = local_y * stride
					for pixel_index: int in source_pixels:
						if pixel_index < first_index + local_x \
								or pixel_index >= first_index + local_x + run_length:
							continue
						var source: int = source_pixels[pixel_index]
						if (source & 0xff000000) == 0:
							continue
						var index: int = (y * size.x + x + pixel_index - first_index - local_x) * 4
						if ((source >> 24) & 255) == 255:
							bytes.encode_u32(index, source)
						else:
							bytes.encode_u32(index, DrawingEditSession._blend(
								source, bytes.decode_u32(index)))
				else:
					for offset: int in range(run_length):
						var pixel_index: int = local_y * stride + local_x + offset
						var source: int = int(source_pixels.get(pixel_index, 0))
						if has_preview_patch and patch.has(pixel_index):
							source = int(patch[pixel_index])
						if (source & 0xff000000) == 0:
							continue
						var index: int = (y * size.x + x + offset) * 4
						var result: int = source
						if ((source >> 24) & 255) != 255:
							# RGBA8 is packed little-endian in the canonical tile map.
							# Decode the destination as one native operation for blending.
							result = DrawingEditSession._blend(source, bytes.decode_u32(index))
						# Packed byte writes avoid four script-indexed assignments per
						# visible pixel without changing byte order or alpha semantics.
						bytes.encode_u32(index, result)
			x += run_length
	return DrawingResult.success()
