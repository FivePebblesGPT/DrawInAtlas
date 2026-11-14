class_name DrawingRasterImport
extends RefCounted
## Import a source image into signed sparse tiles without a full-canvas allocation.
## Each bounded edit-region request uses canonical straight RGBA8, even on partial edges.


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


## Pure decoder for a single, previously captured snapshot. Useful for
## verifying race safety without replacing files between two system reads.
static func decode_image_bytes(source_bytes: PackedByteArray, extension: String) -> DrawingResult:
	var kind: String = extension.to_lower()
	if kind not in ["png", "webp", "jpg", "jpeg"]:
		return DrawingResult.failure("FORMAT", "Unsupported file type. Open supports .drawing, PNG, WebP and JPEG.")
	var header_valid: bool = false
	match kind:
		"png":
			header_valid = source_bytes.size() >= 33 and source_bytes.slice(0, 8) == PackedByteArray(
				[137, 80, 78, 71, 13, 10, 26, 10])
		"webp":
			header_valid = source_bytes.size() >= 12 and \
				source_bytes.slice(0, 4) == "RIFF".to_ascii_buffer() and \
				source_bytes.slice(8, 12) == "WEBP".to_ascii_buffer()
		"jpg", "jpeg":
			header_valid = source_bytes.size() >= 3 and source_bytes[0] == 255 and \
				source_bytes[1] == 216 and source_bytes[2] == 255
	if not header_valid:
		return DrawingResult.failure("HEADER", "Image header is invalid or does not match its PNG/WebP/JPEG extension")
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
	if image.get_width() > 4096 or image.get_height() > 4096 or \
			image.get_width() * image.get_height() > 16777216:
		return DrawingResult.failure("IMAGE_LIMIT", "Image exceeds the 4096px-per-side / 16.8M-pixel import limit")
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
	if abs(left) > 1152921504606846976 or abs(top) > 1152921504606846976:
		return DrawingResult.failure("COORD_RANGE", "Image anchor exceeds safe signed 64-bit range")
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
