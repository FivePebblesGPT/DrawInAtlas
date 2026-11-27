class_name DrawingRasterTile
extends RefCounted
## Canonical straight RGBA8. Small/script edits use sparse int indices; native
## publications retain a dense byte buffer without per-pixel GDScript decoding.
## Packed RGBA8 is 0xAABBGGRR, including RGB when alpha is zero.

var stride: int = 0
var _pixels: Dictionary[int, int] = {}
var _rgba8: PackedByteArray = PackedByteArray()


func _init(tile_stride: int = 256) -> void:
	assert(tile_stride > 0 and tile_stride <= 2048)
	stride = tile_stride


func has_packed_rgba8() -> bool:
	return not _rgba8.is_empty()


## Detached snapshots are caller-owned. Validate backing storage before any
## encode_u32 or native descriptor construction, including hidden RGB.
func has_canonical_storage() -> bool:
	if stride <= 0 or stride > 2048:
		return false
	if has_packed_rgba8():
		return _rgba8.size() == stride * stride * 4 and _pixels.is_empty()
	for index: int in _pixels:
		if index < 0 or index >= stride * stride or _pixels[index] <= 0 or _pixels[index] > 0xffffffff:
			return false
	return true


func get_rgba(x: int, y: int) -> int:
	assert(x >= 0 and y >= 0 and x < stride and y < stride)
	var index: int = y * stride + x
	return _rgba8.decode_u32(index * 4) if has_packed_rgba8() else _pixels.get(index, 0)


func set_rgba(x: int, y: int, rgba: int) -> bool:
	assert(x >= 0 and y >= 0 and x < stride and y < stride)
	assert(rgba >= 0 and rgba <= 0xffffffff)
	var key: int = y * stride + x
	if has_packed_rgba8():
		if _rgba8.decode_u32(key * 4) == rgba:
			return false
		_rgba8.encode_u32(key * 4, rgba)
		return true
	var old: int = _pixels.get(key, 0)
	if old == rgba:
		return false
	if rgba == 0:
		_pixels.erase(key)
	else:
		_pixels[key] = rgba
	return true


## Explicit legacy editing APIs may request the sparse representation.
## This is intentionally NOT used by native tile publication or history.
func materialize_sparse() -> void:
	if not has_packed_rgba8():
		return
	var bytes: PackedByteArray = _rgba8
	var sparse: Dictionary[int, int] = {}
	for index: int in range(stride * stride):
		var rgba: int = bytes.decode_u32(index * 4)
		if rgba != 0:
			sparse[index] = rgba
	_pixels = sparse
	_rgba8 = PackedByteArray()


func sparse_pixels() -> Dictionary[int, int]:
	materialize_sparse()
	return _pixels


func is_empty() -> bool:
	return _rgba8.count(0) == _rgba8.size() if has_packed_rgba8() else _pixels.is_empty()


func pixel_count() -> int:
	if not has_packed_rgba8():
		return _pixels.size()
	var count: int = 0
	for index: int in range(stride * stride):
		if _rgba8.decode_u32(index * 4) != 0:
			count += 1
	return count


func detached_copy() -> DrawingRasterTile:
	var result: DrawingRasterTile = DrawingRasterTile.new(stride)
	result._pixels = _pixels.duplicate()
	result._rgba8 = _rgba8.duplicate()
	return result


## Preserve packed native tiles directly through serialization.
func to_rgba8() -> PackedByteArray:
	if has_packed_rgba8():
		return _rgba8.duplicate()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(stride * stride * 4)
	for index: int in _pixels:
		bytes.encode_u32(index * 4, _pixels[index])
	return bytes


static func from_rgba8(tile_stride: int, bytes: PackedByteArray) -> DrawingRasterTile:
	if tile_stride <= 0 or tile_stride > 2048 or bytes.size() != tile_stride * tile_stride * 4:
		return null
	var tile: DrawingRasterTile = DrawingRasterTile.new(tile_stride)
	tile._rgba8 = bytes.duplicate()
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
