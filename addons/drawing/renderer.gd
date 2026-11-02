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
	var world_view: Rect2i = Rect2i(view.position + Vector2i(origin_x, origin_y), view.size)
	var font_warnings: Array[String] = []
	for layer_id: String in leaf_layers:
		if document.node_metadata(layer_id)["kind"] == DrawingLayerNode.TEXT:
			var element: DrawingTextElement = document.inspect_node(layer_id).text_element
			if element != null:
				var result: DrawingResult = DrawingTextRaster.composite(element, world_view, bytes)
				if not result.ok:
					return result
				if result.code == "GLYPH_FALLBACK" and not font_warnings.has(result.message):
					font_warnings.append(result.message)
			continue
		for y: int in range(view.size.y):
			for x: int in range(view.size.x):
				var pixel: DrawingResult = document.read_pixel(layer_id,
					world_view.position.x + x, world_view.position.y + y)
				if not pixel.ok:
					return pixel
				var index: int = (y * view.size.x + x) * 4
				var background: int = 0
				for channel: int in range(4):
					background |= int(bytes[index + channel]) << (channel * 8)
				var composite: int = DrawingEditSession._blend(int(pixel.value), background)
				for channel: int in range(4):
					bytes[index + channel] = (composite >> (channel * 8)) & 255
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
