class_name DrawingRasterImport
extends RefCounted

const TILES: Script = preload("res://addons/drawing/signed_tiles.gd")
## Import a source image into signed sparse tiles without a full-canvas allocation.
## Each bounded edit-region request uses canonical straight sRGB RGBA8, even on partial edges.
## Decoded samples are assumed sRGB. PNG gAMA can be transformed by the codec
## (gamma 2.2 approximation); arbitrary ICC profiles are not color-managed.
## Convert non-sRGB artwork externally first for accurate color.


## Read and decode the same bounded byte snapshot. A second path-based decode
## could import different bytes if an external editor replaced the file after
## header/length validation; it also repeated external file I/O.
static func load_file_image(path: String) -> DrawingResult:
	var extension: String = path.get_extension().to_lower()
	if extension not in ["png", "webp", "jpg", "jpeg"]:
		return DrawingResult.failure("FORMAT", "Unsupported file type. Open supports .drawing, PNG, WebP and JPEG.")
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return DrawingResult.failure("READ", "Image missing, unreadable or larger than the 64 MiB Open limit")
	var byte_count: int = stream.get_length()
	if byte_count <= 0 or byte_count > 64 * 1024 * 1024:
		stream.close()
		return DrawingResult.failure("READ_LIMIT", "Image missing, unreadable or larger than the 64 MiB Open limit")
	var source_bytes: PackedByteArray = stream.get_buffer(byte_count)
	stream.close()
	if source_bytes.size() != byte_count:
		return DrawingResult.failure("READ", "Image changed or truncated during Open; no Drawing was created")
	return decode_image_bytes(source_bytes, extension)


## Parse declared dimensions from the same captured bytes before asking a codec to
## allocate decoded pixels. An encoded 64 MiB limit alone cannot bound a very
## compressible image's RAM footprint; this also protects direct byte callers.
static func _big_endian_u16(source_bytes: PackedByteArray, offset: int) -> int:
	return (int(source_bytes[offset]) << 8) | int(source_bytes[offset + 1])


static func _big_endian_u32(source_bytes: PackedByteArray, offset: int) -> int:
	return (_big_endian_u16(source_bytes, offset) << 16) | \
		_big_endian_u16(source_bytes, offset + 2)


static func _little_endian_u24(source_bytes: PackedByteArray, offset: int) -> int:
	return int(source_bytes[offset]) | (int(source_bytes[offset + 1]) << 8) | \
		(int(source_bytes[offset + 2]) << 16)


static func _little_endian_u32(source_bytes: PackedByteArray, offset: int) -> int:
	return _little_endian_u24(source_bytes, offset) | (int(source_bytes[offset + 3]) << 24)


static func _declared_dimensions(source_bytes: PackedByteArray, kind: String) -> DrawingResult:
	var width: int = 0
	var height: int = 0
	match kind:
		"png":
			if source_bytes.size() < 33 or \
					source_bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or \
					_big_endian_u32(source_bytes, 8) != 13 or \
					source_bytes.slice(12, 16) != "IHDR".to_ascii_buffer():
				return DrawingResult.failure("HEADER", "Image header is invalid or does not match its PNG/WebP/JPEG extension")
			width = _big_endian_u32(source_bytes, 16)
			height = _big_endian_u32(source_bytes, 20)
		"webp":
			if source_bytes.size() < 20 or \
					source_bytes.slice(0, 4) != "RIFF".to_ascii_buffer() or \
					source_bytes.slice(8, 12) != "WEBP".to_ascii_buffer():
				return DrawingResult.failure("HEADER", "Invalid WebP RIFF container")
			# The first RIFF chunk declares the raster geometry (VP8, VP8L or VP8X).
			# Verify that the chunk is fully inside the single captured snapshot.
			var riff_size: int = _little_endian_u32(source_bytes, 4)
			var chunk_size: int = _little_endian_u32(source_bytes, 16)
			if riff_size < 12 or riff_size > source_bytes.size() - 8 or \
					chunk_size > source_bytes.size() - 20 or chunk_size > riff_size - 12:
				return DrawingResult.failure("HEADER", "Invalid WebP chunk length")
			var chunk: String = source_bytes.slice(12, 16).get_string_from_ascii()
			match chunk:
				"VP8 ":
					if chunk_size < 10 or source_bytes.size() < 30 or \
							source_bytes.slice(23, 26) != PackedByteArray([157, 1, 42]):
						return DrawingResult.failure("HEADER", "Invalid lossy WebP frame")
					width = int(source_bytes[26]) | ((int(source_bytes[27]) & 63) << 8)
					height = int(source_bytes[28]) | ((int(source_bytes[29]) & 63) << 8)
				"VP8L":
					if chunk_size < 5 or source_bytes.size() < 25 or source_bytes[20] != 47:
						return DrawingResult.failure("HEADER", "Invalid lossless WebP frame")
					width = 1 + int(source_bytes[21]) + ((int(source_bytes[22]) & 63) << 8)
					height = 1 + (int(source_bytes[22]) >> 6) + \
						(int(source_bytes[23]) << 2) + ((int(source_bytes[24]) & 15) << 10)
				"VP8X":
					if chunk_size < 10 or source_bytes.size() < 30:
						return DrawingResult.failure("HEADER", "Invalid extended WebP frame")
					width = 1 + _little_endian_u24(source_bytes, 24)
					height = 1 + _little_endian_u24(source_bytes, 27)
				_:
					return DrawingResult.failure("HEADER", "Unsupported WebP image chunk")
		"jpg", "jpeg":
			if source_bytes.size() < 4 or source_bytes[0] != 255 or \
					source_bytes[1] != 216:
				return DrawingResult.failure("HEADER", "Invalid JPEG SOI")
			var offset: int = 2
			var found_sof: bool = false
			while offset + 1 < source_bytes.size():
				if source_bytes[offset] != 255:
					return DrawingResult.failure("HEADER", "Invalid JPEG marker")
				while offset < source_bytes.size() and source_bytes[offset] == 255:
					offset += 1
				if offset >= source_bytes.size():
					break
				var marker: int = int(source_bytes[offset])
				offset += 1
				if marker == 1: # JPEG TEM is standalone (no segment length).
					continue
				if marker in [0, 216, 217, 218] or (marker >= 208 and marker <= 215):
					return DrawingResult.failure("HEADER", "JPEG is missing a valid SOF")
				if offset + 2 > source_bytes.size():
					break
				var segment_size: int = _big_endian_u16(source_bytes, offset)
				if segment_size < 2 or segment_size > source_bytes.size() - offset:
					return DrawingResult.failure("HEADER", "Invalid JPEG segment length")
				if marker in [192, 193, 194, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207]:
					if segment_size < 7:
						return DrawingResult.failure("HEADER", "Truncated JPEG SOF")
					height = _big_endian_u16(source_bytes, offset + 3)
					width = _big_endian_u16(source_bytes, offset + 5)
					found_sof = true
					break
				offset += segment_size
			if not found_sof:
				return DrawingResult.failure("HEADER", "JPEG SOF is missing or truncated")
	if width <= 0 or height <= 0:
		return DrawingResult.failure("HEADER", "Image dimensions must be positive")
	if width > 4096 or height > 4096 or width * height > 16777216:
		return DrawingResult.failure("IMAGE_LIMIT", "Image exceeds the 4096px-per-side / 16.8M-pixel import limit")
	return DrawingResult.success(Vector2i(width, height))


## Pure decoder for a single, previously captured snapshot. Useful for
## verifying race safety without replacing files between two system reads.
static func decode_image_bytes(source_bytes: PackedByteArray, extension: String) -> DrawingResult:
	var kind: String = extension.to_lower()
	if kind not in ["png", "webp", "jpg", "jpeg"]:
		return DrawingResult.failure("FORMAT", "Unsupported file type. Open supports .drawing, PNG, WebP and JPEG.")
	if source_bytes.is_empty() or source_bytes.size() > 64 * 1024 * 1024:
		return DrawingResult.failure("READ_LIMIT", "Image missing, unreadable or larger than the 64 MiB Open limit")
	var bounds: DrawingResult = _declared_dimensions(source_bytes, kind)
	if not bounds.ok:
		return bounds
	var image: Image = Image.new()
	var decoded: Error = ERR_FILE_CORRUPT
	match kind:
		"png":
			decoded = image.load_png_from_buffer(source_bytes)
		"webp":
			decoded = image.load_webp_from_buffer(source_bytes)
		"jpg", "jpeg":
			decoded = image.load_jpg_from_buffer(source_bytes)
	if decoded != OK or image.is_empty():
		return DrawingResult.failure("DECODE", "Cannot decode image. Source file is missing or corrupt; no Drawing was created.")
	# Never rely exclusively on untrusted header metadata for the post-decode
	# dimensions: the codec may find a different size or a corrupt payload.
	if image.get_width() != (bounds.value as Vector2i).x or \
			image.get_height() != (bounds.value as Vector2i).y:
		return DrawingResult.failure("HEADER", "Decoded dimensions differ from image header")
	return DrawingResult.success(image)

static func import_image(document: DrawingDocument, layer_id: String,
		source: Image, left: int, top: int, expected_revision: int,
		max_import_pixels: int = 16777216, region_edge: int = 128) -> DrawingResult:
	if document == null or source == null or source.is_empty() or region_edge <= 0:
		return DrawingResult.failure("IMPORT", "Missing image/document or invalid region size")
	var width: int = source.get_width()
	var height: int = source.get_height()
	if max_import_pixels <= 0 or width > max_import_pixels or height > max_import_pixels / width:
		return DrawingResult.failure("IMPORT_LIMIT", "Import exceeds pixel budget")
	if not TILES.document_anchor_in_range(left, top):
		return DrawingResult.failure("COORD_RANGE", "Image anchor exceeds safe signed 64-bit range")
	# The public anchor is only the first pixel. Check the inclusive opposite
	# corner before decoding, resolving a lazy source or opening an edit. After
	# the anchor and pixel-budget checks above, these additions cannot overflow
	# signed 64-bit; an image must not extend beyond the ±2^60 document range.
	if not TILES.document_anchor_in_range(left + width - 1, top + height - 1):
		return DrawingResult.failure("COORD_RANGE", "Image extent exceeds safe signed Drawing range")
	var image: Image = source.duplicate()
	if image.is_compressed() and image.decompress() != OK:
		return DrawingResult.failure("IMPORT", "Cannot decode source image")
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = image.get_data()
	if raw.size() != width * height * 4:
		return DrawingResult.failure("IMPORT", "Image does not contain canonical RGBA8 pixels")

	var opened: DrawingResult = document.begin_edit(layer_id, expected_revision,
		Transform2D.IDENTITY, left, top)
	if not opened.ok:
		return opened
	var transaction: DrawingEditSession = opened.value as DrawingEditSession
	for y: int in range(0, height, region_edge):
		var rows: int = mini(region_edge, height - y)
		for x: int in range(0, width, region_edge):
			var columns: int = mini(region_edge, width - x)
			var region_bytes: PackedByteArray = PackedByteArray()
			region_bytes.resize(columns * rows * 4)
			for row: int in range(rows):
				var start: int = ((y + row) * width + x) * 4
				for byte_index: int in range(columns * 4):
					region_bytes[row * columns * 4 + byte_index] = raw[start + byte_index]
			var applied: DrawingResult = transaction.apply_region(
				Rect2i(x, y, columns, rows), region_bytes)
			if not applied.ok:
				transaction.cancel()
				return applied
	if transaction.change_count() == 0:
		transaction.cancel()
		return DrawingResult.failure("NO_CHANGE", "Image pixels already match the destination")
	return transaction.commit()
