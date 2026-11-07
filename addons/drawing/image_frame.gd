class_name DrawingImageFrame
extends RefCounted
## Standalone image extent is an authoring guide, NOT sparse-document storage.
## Frame metadata never changes pixels, edits, image export, or Atlas regions.

const DEFAULT_BOUNDS: Rect2i = Rect2i(-256, -256, 512, 512)
const MAX_COORD: int = 1000000000
const MAX_SIZE: int = 1000000


static func encode(bounds: Rect2i) -> Dictionary:
	return {"origin": [str(bounds.position.x), str(bounds.position.y)],
		"size": [bounds.size.x, bounds.size.y]}


static func decode(value: Variant) -> DrawingResult:
	if not value is Dictionary or value.size() != 2:
		return DrawingResult.failure("IMAGE_FRAME", "Invalid standalone image-frame metadata")
	var origin: Variant = value.get("origin")
	var dimensions: Variant = value.get("size")
	if not origin is Array or origin.size() != 2 or not dimensions is Array or dimensions.size() != 2:
		return DrawingResult.failure("IMAGE_FRAME", "Image-frame origin and size need two coordinates")
	var coords: Array[int] = []
	for text: Variant in origin:
		if not text is String or text.is_empty() or text.length() > 11 or \
				not text.is_valid_int() or str(int(text)) != text:
			return DrawingResult.failure("IMAGE_FRAME", "Image-frame origin must use canonical signed decimal strings")
		var number: int = int(text)
		if absi(number) > MAX_COORD:
			return DrawingResult.failure("IMAGE_FRAME", "Image-frame origin is out of display range")
		coords.append(number)
	var widths: Array[int] = []
	for number: Variant in dimensions:
		if not (number is int or number is float) or not is_finite(float(number)) or \
				float(number) < 1.0 or float(number) > float(MAX_SIZE) or \
				floorf(float(number)) != float(number):
			return DrawingResult.failure("IMAGE_FRAME", "Image-frame dimensions must be positive integers")
		widths.append(int(number))
	if absf(float(coords[0]) + float(widths[0])) > MAX_COORD or \
			absf(float(coords[1]) + float(widths[1])) > MAX_COORD:
		return DrawingResult.failure("IMAGE_FRAME", "Image-frame edge exceeds display range")
	return DrawingResult.success(Rect2i(coords[0], coords[1], widths[0], widths[1]))


## Legacy files lack a frame. Enclose their existing source tiles and text,
## with a minimum usable size; never trim data to the resulting guide. For
## wildly distant sparse art, fall back to a centered guide, not a crop.
static func infer_legacy(document: DrawingDocument) -> Rect2i:
	if document == null:
		return DEFAULT_BOUNDS
	var stack: Array[String] = [DrawingDocument.ROOT_ID]
	var found: bool = false
	var lower: Vector2i = Vector2i.ZERO
	var upper: Vector2i = Vector2i.ZERO
	while not stack.is_empty():
		var parent: String = stack.pop_back()
		for node_id: String in document.list_children(parent):
			var meta: Dictionary = document.node_metadata(node_id)
			if meta["kind"] == DrawingLayerNode.GROUP:
				stack.append(node_id)
				continue
			var areas: Array[Rect2i] = []
			if meta["kind"] == DrawingLayerNode.TEXT:
				var node: DrawingLayerNode = document.inspect_node(node_id)
				if node.text_element != null:
					var measured: DrawingResult = DrawingTextRaster.bounds(node.text_element)
					if measured.ok:
						areas.append(measured.value as Rect2i)
			else:
				for key: String in document.tile_keys(node_id):
					var parts: PackedStringArray = key.split(",")
					if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
						continue
					# Check before integer multiplication: signed sparse tile IDs can
					# be much wider than the finite display guide's safe range.
					var world_x: float = float(int(parts[0])) * float(document.tile_stride)
					var world_y: float = float(int(parts[1])) * float(document.tile_stride)
					if absf(world_x) > MAX_COORD - document.tile_stride - 64 or \
							absf(world_y) > MAX_COORD - document.tile_stride - 64:
						return DEFAULT_BOUNDS
					var x: int = int(world_x)
					var y: int = int(world_y)
					areas.append(Rect2i(x, y, document.tile_stride, document.tile_stride))
			for area: Rect2i in areas:
				if not area.has_area():
					continue
				if absi(area.position.x) > MAX_COORD - 64 or absi(area.position.y) > MAX_COORD - 64 or \
						absi(area.end.x) > MAX_COORD - 64 or absi(area.end.y) > MAX_COORD - 64:
					return DEFAULT_BOUNDS
				if not found:
					lower = area.position
					upper = area.end
					found = true
				else:
					lower = Vector2i(mini(lower.x, area.position.x), mini(lower.y, area.position.y))
					upper = Vector2i(maxi(upper.x, area.end.x), maxi(upper.y, area.end.y))
	if not found:
		return DEFAULT_BOUNDS
	var dimensions: Vector2i = Vector2i(maxi(512, upper.x - lower.x + 64),
		maxi(512, upper.y - lower.y + 64))
	if dimensions.x > MAX_SIZE or dimensions.y > MAX_SIZE:
		return DEFAULT_BOUNDS
	var origin: Vector2i = Vector2i(lower.x - (dimensions.x - (upper.x - lower.x)) / 2,
		lower.y - (dimensions.y - (upper.y - lower.y)) / 2)
	if absi(origin.x) > MAX_COORD - dimensions.x or absi(origin.y) > MAX_COORD - dimensions.y:
		return DEFAULT_BOUNDS
	return Rect2i(origin, dimensions)
