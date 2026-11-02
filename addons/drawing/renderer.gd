class_name DrawingRenderer
extends RefCounted
## Bounded, render-on-demand source compositing; never allocates a whole canvas.


static func render(document: DrawingDocument, view: Rect2i,
		origin_x: int = 0, origin_y: int = 0, max_pixels: int = 1048576) -> DrawingResult:
	if document == null or view.size.x <= 0 or view.size.y <= 0 or view.size.x > max_pixels or view.size.y > max_pixels / view.size.x:
		return DrawingResult.failure("RENDER_LIMIT", "Viewport must be bounded")
	var leaf_layers: Array[String] = []
	_collect_visible(document, DrawingDocument.ROOT_ID, leaf_layers)
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
		# Resolve at most one source tile per scanline run, not once per pixel.
		# The region is still bounded; source tiles stay immutable throughout render.
		var raster: DrawingResult = _composite_raster(document, layer_id,
			world_x, world_y, view.size, bytes)
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
		world_x: int, world_y: int, size: Vector2i, bytes: PackedByteArray) -> DrawingResult:
	var stride: int = document.tile_stride
	for y: int in range(size.y):
		var local_y: int = posmod(world_y + y, stride)
		var x: int = 0
		while x < size.x:
			var absolute_x: int = world_x + x
			var local_x: int = posmod(absolute_x, stride)
			var run_length: int = mini(size.x - x, stride - local_x)
			var key: String = DrawingDocument.TILES.tile_key64(absolute_x, world_y + y, stride)
			var fetched: DrawingResult = document._resolve_chunk(layer_id, key)
			if not fetched.ok:
				return fetched
			var tile: DrawingRasterTile = fetched.value as DrawingRasterTile
			if tile != null:
				for offset: int in range(run_length):
					var source: int = tile.get_rgba(local_x + offset, local_y)
					if (source & 0xff000000) == 0:
						continue
					var index: int = (y * size.x + x + offset) * 4
					var destination: int = int(bytes[index]) | (int(bytes[index + 1]) << 8) \
						| (int(bytes[index + 2]) << 16) | (int(bytes[index + 3]) << 24)
					var result: int = DrawingEditSession._blend(source, destination)
					bytes[index] = result & 255
					bytes[index + 1] = (result >> 8) & 255
					bytes[index + 2] = (result >> 16) & 255
					bytes[index + 3] = (result >> 24) & 255
			x += run_length
	return DrawingResult.success()
