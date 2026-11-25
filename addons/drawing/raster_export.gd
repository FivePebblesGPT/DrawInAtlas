class_name DrawingRasterExport
extends RefCounted
## A bounded, detached composite; raster publication is never a Drawing savepoint.

const MAX_SIDE: int = 4096
const MAX_PIXELS: int = 4194304
const MAX_ENCODED_BYTES: int = 33554432

static func valid_size(size: Vector2i) -> bool:
	return size.x > 0 and size.y > 0 and size.x <= MAX_SIDE and size.y <= MAX_SIDE \
		and int(size.x) * int(size.y) <= MAX_PIXELS


static func render(document: DrawingDocument, bounds: Rect2i) -> DrawingResult:
	if document == null or not valid_size(bounds.size):
		return DrawingResult.failure("EXPORT_LIMIT", "Export requires a non-empty frame, at most 4096 px per side and 4,194,304 pixels")
	if not DrawingImageFrame.decode(DrawingImageFrame.encode(bounds)).ok:
		return DrawingResult.failure("EXPORT_BOUNDS", "Export frame is outside the supported signed range")
	if document.has_unpublished_edit():
		return DrawingResult.failure("EXPORT_PENDING", "Finish or cancel the pending edit before exporting")
	var revision: int = document.revision
	var epoch: int = document.display_source_epoch
	var plan: Dictionary = DrawingRenderer.prepare_visible_layers(document)
	var rendered: DrawingResult = DrawingRenderer.render(document, bounds, 0, 0, MAX_PIXELS, null, plan)
	if not rendered.ok:
		return rendered
	if document.revision != revision or document.display_source_epoch != epoch or document.has_unpublished_edit():
		return DrawingResult.failure("EXPORT_STALE", "Document changed during export rendering")
	return rendered


static func extensions(format: String) -> PackedStringArray:
	match format:
		"png": return PackedStringArray(["png"])
		"webp": return PackedStringArray(["webp"])
		"jpeg": return PackedStringArray(["jpg", "jpeg"])
	return PackedStringArray()


static func encode(image: Image, format: String, lossless: bool = true,
		quality: float = 0.9, matte: Color = Color.WHITE) -> DrawingResult:
	if image == null or not valid_size(image.get_size()) or image.get_format() != Image.FORMAT_RGBA8:
		return DrawingResult.failure("EXPORT_IMAGE", "Export needs a bounded RGBA8 composite")
	if extensions(format).is_empty():
		return DrawingResult.failure("EXPORT_FORMAT", "Unsupported export format")
	if (format == "jpeg" or (format == "webp" and not lossless)) and \
			(not is_finite(quality) or quality < 0.0 or quality > 1.0):
		return DrawingResult.failure("EXPORT_QUALITY", "Quality must be between 0 and 100 percent")
	var bytes: PackedByteArray = PackedByteArray()
	match format:
		"png":
			bytes = image.save_png_to_buffer()
		"webp":
			bytes = image.save_webp_to_buffer(not lossless, quality if not lossless else 1.0)
		"jpeg":
			if not is_finite(matte.r) or not is_finite(matte.g) or not is_finite(matte.b) or matte.a != 1.0 or matte.r < 0.0 or matte.r > 1.0 \
					or matte.g < 0.0 or matte.g > 1.0 or matte.b < 0.0 or matte.b > 1.0:
				return DrawingResult.failure("EXPORT_MATTE", "JPEG requires an opaque RGB matte")
			# Composite into a detached opaque image using the canonical byte blend.
			# Do not change the source image or silently discard its alpha.
			var pixels: PackedByteArray = image.get_data()
			var background: int = roundi(matte.r * 255.0) | (roundi(matte.g * 255.0) << 8) \
				| (roundi(matte.b * 255.0) << 16) | 0xff000000
			for offset: int in range(0, pixels.size(), 4):
				var source: int = pixels.decode_u32(offset)
				if (source >> 24) == 0:
					pixels.encode_u32(offset, background)
				elif (source >> 24) != 255:
					pixels.encode_u32(offset, DrawingEditSession._blend(source, background))
			var opaque: Image = Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
			opaque.convert(Image.FORMAT_RGB8)
			bytes = opaque.save_jpg_to_buffer(quality)
	if bytes.is_empty() or bytes.size() > MAX_ENCODED_BYTES:
		return DrawingResult.failure("EXPORT_ENCODE", "Encoder failed or exceeded the 32 MiB output limit")
	return DrawingResult.success(bytes)


## Same-directory staging and rename: never truncate an existing destination on
## encoding/write failure. The caller owns overwrite authorization.
static func publish(path: String, format: String, bytes: PackedByteArray,
		allow_overwrite: bool = false) -> DrawingResult:
	if not path.is_absolute_path() or path.get_extension().to_lower() not in extensions(format):
		return DrawingResult.failure("EXPORT_PATH", "Choose an absolute path with the selected format's extension")
	if bytes.is_empty() or bytes.size() > MAX_ENCODED_BYTES:
		return DrawingResult.failure("EXPORT_ENCODE", "No bounded encoded image to publish")
	if DirAccess.dir_exists_absolute(path) or (FileAccess.file_exists(path) and not allow_overwrite):
		return DrawingResult.failure("EXPORT_EXISTS", "Destination exists; confirm overwrite or choose another file")
	var temporary: String = path + ".pending-" + DrawingDocument.new_id()
	var stream: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if stream == null:
		return DrawingResult.failure("EXPORT_WRITE", "Unable to create temporary export file")
	stream.store_buffer(bytes)
	stream.flush()
	var write_error: Error = stream.get_error()
	var complete: bool = stream.get_length() == bytes.size()
	stream.close()
	if write_error != OK or not complete or (FileAccess.file_exists(path) and not allow_overwrite):
		DirAccess.remove_absolute(temporary)
		return DrawingResult.failure("EXPORT_WRITE", "Export write failed or destination appeared; original file retained")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return DrawingResult.failure("EXPORT_WRITE", "Unable to publish export; original file retained")
	return DrawingResult.success(path)
