class_name AtlasRasterLayer
extends AtlasLayer

const PAINT_PIXELS_PER_UNIT: float = 4.0

## Positive density of raster pixels per *local* board unit. A local pixel at
## (x, y) maps to (x, y) / pixels_per_unit before applying transform.
@export_storage var pixels_per_unit: float = 1.0
## Affine local-board -> document-board transform; must be finite/invertible.
## Moving a raster changes this field, not the stored pixel bytes.
@export_storage var transform: Transform2D = Transform2D.IDENTITY
## Canonical sparse chunk ownership: key "cx,cy" matches chunk.coord, with signed
## chunk indexes and 256-pixel strides. Each chunk owns independent RGBA8 bytes;
## absent chunks are not implicit editable pixels.
@export_storage var chunks: Dictionary[String, AtlasRasterChunk] = {}


func _init(layer_id: String = "raster", layer_name: String = "Raster") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "RASTER"


static func paint_layer(layer_id: String = "raster", layer_name: String = "Raster") -> AtlasRasterLayer:
	var layer: AtlasRasterLayer = AtlasRasterLayer.new(layer_id, layer_name)
	layer.pixels_per_unit = PAINT_PIXELS_PER_UNIT
	return layer


## Increase pixel density with exact nearest-neighbor replication, preserving
## document size, placement, signed chunk addresses and the source snapshot.
func at_paint_density() -> AtlasRasterLayer:
	var copy: AtlasRasterLayer = AtlasLayerCodec.clone(self) as AtlasRasterLayer
	if copy == null:
		return null
	var factor: int = maxi(1, ceili(PAINT_PIXELS_PER_UNIT / pixels_per_unit))
	if factor == 1:
		return copy
	copy.pixels_per_unit *= factor
	copy.chunks.clear()
	for original: AtlasRasterChunk in chunks.values():
		var image: Image = original.image.duplicate()
		image.resize(original.width * factor, original.height * factor, Image.INTERPOLATE_NEAREST)
		var tiles: AtlasRasterLayer = from_image_chunks(image, copy.pixels_per_unit)
		for chunk: AtlasRasterChunk in tiles.chunks.values():
			chunk.coord += original.coord * factor
			copy.chunks["%d,%d" % [chunk.coord.x, chunk.coord.y]] = chunk
	return copy

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
