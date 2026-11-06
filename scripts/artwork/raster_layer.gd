class_name AtlasRasterLayer
extends AtlasLayer

@export_storage var pixels_per_unit: float = 1.0
@export_storage var transform: Transform2D = Transform2D.IDENTITY
@export_storage var chunks: Dictionary[String, AtlasRasterChunk] = {}


func _init(layer_id: String = "raster", layer_name: String = "Raster") -> void:
	super(layer_id, layer_name)
	kind = "RASTER"


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


static func from_image(pixels: Image, scale: float = 1.0) -> AtlasRasterLayer:
	if pixels == null or pixels.is_empty() or not is_finite(scale) or scale <= 0.0:
		return null
	var layer: AtlasRasterLayer = AtlasRasterLayer.new()
	layer.pixels_per_unit = scale
	for y: int in range(0, pixels.get_height(), AtlasRasterChunk.SIZE):
		for x: int in range(0, pixels.get_width(), AtlasRasterChunk.SIZE):
			var region: Rect2i = Rect2i(x, y, mini(AtlasRasterChunk.SIZE, pixels.get_width() - x),
				mini(AtlasRasterChunk.SIZE, pixels.get_height() - y))
			var point: Vector2i = pixel_to_chunk(Vector2i(x, y))
			layer.chunks["%d,%d" % [point.x, point.y]] = AtlasRasterChunk.new(point, pixels.get_region(region))
	return layer


static func pixel_to_chunk(point: Vector2i) -> Vector2i:
	return Vector2i(floori(float(point.x) / AtlasRasterChunk.SIZE), floori(float(point.y) / AtlasRasterChunk.SIZE))
