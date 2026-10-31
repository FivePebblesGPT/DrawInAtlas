class_name AtlasWebPStore
extends RefCounted

## Canonical chunks must survive the codec byte-for-byte, including hidden RGB.
## An empty encoding reports an unsupported exact roundtrip, never normalization.

static func encode_lossless(image: Image) -> PackedByteArray:
	var canonical: Image = canonical_rgba8(image)
	if canonical == null:
		return PackedByteArray()
	var bytes: PackedByteArray = canonical.save_webp_to_buffer(false)
	var decoded: Image = decode(bytes)
	if decoded == null or decoded.get_width() != canonical.get_width() \
			or decoded.get_height() != canonical.get_height() \
			or decoded.get_data() != canonical.get_data():
		return PackedByteArray()
	return bytes


static func canonical_rgba8(image: Image) -> Image:
	if image == null or image.is_empty() or image.is_compressed():
		return null
	var result: Image = image.duplicate() as Image
	result.clear_mipmaps()
	result.convert(Image.FORMAT_RGBA8)
	return result


static func decode(bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image: Image = Image.new()
	if image.load_webp_from_buffer(bytes) != OK:
		return null
	return canonical_rgba8(image)


static func decode_lossless(bytes: PackedByteArray, width: int, height: int) -> Image:
	# Inspect the container and dimensions before entering the image decoder.
	# Canonical assets cannot be previews, animations, or oversized images.
	if bytes.size() < 25 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WEBP" \
			or bytes.decode_u32(4) != bytes.size() - 8:
		return null
	var offset: int = 12
	var found: bool = false
	while offset + 8 <= bytes.size():
		var tag: String = bytes.slice(offset, offset + 4).get_string_from_ascii()
		var length: int = bytes.decode_u32(offset + 4)
		var start: int = offset + 8
		if length > bytes.size() - start:
			return null
		if tag in ["VP8 ", "ANIM", "ANMF"]:
			return null
		if tag == "VP8L":
			if found or length < 5 or bytes[start] != 0x2f:
				return null
			var dimensions: int = bytes.decode_u32(start + 1)
			if dimensions >> 29 != 0 or (dimensions & 0x3fff) + 1 != width \
					or ((dimensions >> 14) & 0x3fff) + 1 != height:
				return null
			found = true
		offset = start + length + (length % 2)
	return decode(bytes) if found and offset == bytes.size() else null


static func write_image(path: String, image: Image, preview: bool = false) -> Error:
	if image == null or image.is_empty() or not path.to_lower().ends_with(".webp"):
		return ERR_INVALID_PARAMETER
	var data: PackedByteArray = image.save_webp_to_buffer(true, 0.82) if preview else encode_lossless(image)
	if data.is_empty():
		return ERR_CANT_CREATE if preview else ERR_UNAVAILABLE
	return AtlasStoreIO.new().write_bytes(path, data)


static func read_image(path: String) -> Image:
	if not path.to_lower().ends_with(".webp") or not FileAccess.file_exists(path):
		return null
	return decode(AtlasStoreIO.new().read_bytes(path))
