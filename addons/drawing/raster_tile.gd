class_name DrawingRasterTile
extends RefCounted
## Sparse canonical straight RGBA8 storage for one tile; unmodified hidden RGB survives.
## Packed RGBA8 is 0xAABBGGRR. A zero value is implicit absent/transparent black.

var stride: int = 0
var _pixels: Dictionary[int, int] = {}


func _init(tile_stride: int = 256) -> void:
	assert(tile_stride > 0 and tile_stride <= 2048)
	stride = tile_stride


func get_rgba(x: int, y: int) -> int:
	assert(x >= 0 and y >= 0 and x < stride and y < stride)
	return _pixels.get(y * stride + x, 0)


func set_rgba(x: int, y: int, rgba: int) -> bool:
	assert(x >= 0 and y >= 0 and x < stride and y < stride)
	assert(rgba >= 0 and rgba <= 0xffffffff)
	var key: int = y * stride + x
	var old: int = _pixels.get(key, 0)
	if old == rgba:
		return false
	if rgba == 0:
		_pixels.erase(key)
	else:
		_pixels[key] = rgba
	return true


func is_empty() -> bool:
	return _pixels.is_empty()


func pixel_count() -> int:
	return _pixels.size()


func detached_copy() -> DrawingRasterTile:
	var result: DrawingRasterTile = DrawingRasterTile.new(stride)
	result._pixels = _pixels.duplicate()
	return result


## Only materialize a whole tile when a consumer explicitly requests its bytes.
func to_rgba8() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(stride * stride * 4)
	for index: int in _pixels:
		var value: int = _pixels[index]
		var offset: int = index * 4
		for channel: int in range(4):
			bytes[offset + channel] = (value >> (channel * 8)) & 255
	return bytes


static func from_rgba8(tile_stride: int, bytes: PackedByteArray) -> DrawingRasterTile:
	if tile_stride <= 0 or tile_stride > 2048 or bytes.size() != tile_stride * tile_stride * 4:
		return null
	var tile: DrawingRasterTile = DrawingRasterTile.new(tile_stride)
	for index: int in range(tile_stride * tile_stride):
		var offset: int = index * 4
		var rgba: int = (int(bytes[offset]) | (int(bytes[offset + 1]) << 8)
			| (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24))
		if rgba != 0:
			tile._pixels[index] = rgba
	return tile


static func from_image(source: Image) -> DrawingRasterTile:
	if source == null or source.is_empty() or source.get_width() != source.get_height():
		return null
	var image: Image = source.duplicate()
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return from_rgba8(image.get_width(), image.get_data())


static func digest_rgba8(bytes: PackedByteArray, tile_stride: int) -> String:
	var context: HashingContext = HashingContext.new()
	if tile_stride < 1 or bytes.size() != tile_stride * tile_stride * 4:
		return ""
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(("%d,%d:RGBA8:" % [tile_stride, tile_stride]).to_utf8_buffer())
	context.update(bytes)
	return context.finish().hex_encode()
