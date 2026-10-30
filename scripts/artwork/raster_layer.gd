class_name AtlasRasterLayer
extends AtlasLayer

@export_storage var pixels_per_unit: float = 1.0
@export_storage var transform: Transform2D = Transform2D.IDENTITY
@export_storage var chunks: Dictionary[String, AtlasRasterChunk] = {}


func _init(layer_id: String = "raster", layer_name: String = "Raster") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "RASTER"

func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	var saved: Array[Dictionary] = []
	var keys: Array[String] = chunks.keys()
	keys.sort()
	for key: String in keys:
		saved.append(chunks[key].to_dict())
	data["pixels_per_unit"] = pixels_per_unit
	data["chunks"] = saved
	data["transform"] = [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]
	return data


## Compatibility entry point for existing import callers; new code should use from_image_chunks().
static func from_image(pixels: Image, scale: float = 1.0) -> AtlasRasterLayer:
	return from_image_chunks(pixels, scale)


## Copy an image anchored at local pixel (0, 0) into independently owned RGBA8 chunks.
## Visits chunk rectangles (not individual pixels in GDScript). get_region() copies each
## rectangle; AtlasRasterChunk duplicates it again to clear mipmaps and convert to RGBA8.
## Total copied/converted pixels scale with image area; the temporary region is <= 256².
## The final right/bottom rectangles keep their true dimensions, not padded pixels.
static func from_image_chunks(source: Image, scale: float = 1.0) -> AtlasRasterLayer:
	if source == null or source.is_empty() or not is_finite(scale) or scale <= 0.0:
		return null
	var layer: AtlasRasterLayer = AtlasRasterLayer.new()
	layer.pixels_per_unit = scale
	var chunk_size: int = AtlasRasterChunk.SIZE
	for top: int in range(0, source.get_height(), chunk_size):
		var height: int = mini(chunk_size, source.get_height() - top)
		for left: int in range(0, source.get_width(), chunk_size):
			var width: int = mini(chunk_size, source.get_width() - left)
			var region: Rect2i = Rect2i(left, top, width, height)
			var coord: Vector2i = pixel_to_chunk(region.position)
			var chunk: AtlasRasterChunk = AtlasRasterChunk.new(coord, source.get_region(region))
			if not chunk.is_valid(true):
				return null
			layer.chunks["%d,%d" % [coord.x, coord.y]] = chunk
	return layer


static func pixel_to_chunk(point: Vector2i) -> Vector2i:
	return Vector2i(floori(float(point.x) / AtlasRasterChunk.SIZE), floori(float(point.y) / AtlasRasterChunk.SIZE))
