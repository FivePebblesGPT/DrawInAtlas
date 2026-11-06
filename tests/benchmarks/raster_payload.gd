extends Resource

## Controlled codec alternatives for the benchmark, not a campaign file schema.
@export_storage var coord: Vector2i
@export_storage var width: int
@export_storage var height: int
@export_storage var pixel_hash: String
@export_storage var image: Image
@export_storage var bytes: PackedByteArray


func encode(chunk: AtlasRasterChunk, codec: String) -> bool:
	coord = chunk.coord
	width = chunk.width
	height = chunk.height
	pixel_hash = chunk.asset_id
	match codec:
		"image": image = chunk.image
		"webp": bytes = AtlasWebPStore.encode_lossless(chunk.image)
		"raw": bytes = chunk.image.get_data()
		"zstd": bytes = chunk.image.get_data().compress(FileAccess.COMPRESSION_ZSTD)
		_: return false
	return image != null or not bytes.is_empty()


func decode(codec: String) -> Image:
	match codec:
		"image": return image
		"webp": return AtlasWebPStore.decode_lossless(bytes, width, height)
		"raw": return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
		"zstd":
			return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8,
				bytes.decompress(width * height * 4, FileAccess.COMPRESSION_ZSTD))
	return null
