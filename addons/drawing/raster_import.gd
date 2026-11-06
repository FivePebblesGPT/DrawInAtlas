class_name DrawingRasterImport
extends RefCounted
## Import a source image into signed sparse tiles without a full-canvas allocation.
## Each bounded edit-region request uses canonical straight RGBA8, even on partial edges.


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
