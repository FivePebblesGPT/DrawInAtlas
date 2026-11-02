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
	for y: int in range(view.size.y):
		for x: int in range(view.size.x):
			var color: int = 0
			for layer_id: String in leaf_layers:
				var pixel: DrawingResult = document.read_pixel(layer_id,
					origin_x + view.position.x + x, origin_y + view.position.y + y)
				if not pixel.ok:
					return pixel
				color = DrawingEditSession._blend(int(pixel.value), color)
			var index: int = (y * view.size.x + x) * 4
			for channel: int in range(4):
				bytes[index + channel] = (color >> (channel * 8)) & 255
	return DrawingResult.success(Image.create_from_data(view.size.x, view.size.y,
		false, Image.FORMAT_RGBA8, bytes), document.revision)


static func _collect_visible(document: DrawingDocument, parent_id: String,
		leaf_layers: Array[String]) -> void:
	for node_id: String in document.list_children(parent_id):
		var metadata: Dictionary = document.node_metadata(node_id)
		if metadata.is_empty() or not metadata["visible"]:
			continue
		if metadata["kind"] == DrawingLayerNode.GROUP:
			_collect_visible(document, node_id, leaf_layers)
		elif metadata["kind"] == DrawingLayerNode.RASTER:
			leaf_layers.append(node_id)
