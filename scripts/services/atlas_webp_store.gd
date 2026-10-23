class_name AtlasWebPStore
extends RefCounted

## Canonical raster chunks: lossless WebP. Thumbnails: optionally lossy WebP.
## Uses buffers + FileAccess for portability to browser's user:// sandbox.

static func write_image(path: String, image: Image, preview: bool = false) -> Error:
    if image.is_empty() or not path.to_lower().ends_with(".webp"):
        return ERR_INVALID_PARAMETER
    var data: PackedByteArray = image.save_webp_to_buffer(preview, 0.82)
    if data.is_empty():
        return ERR_CANT_CREATE
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_buffer(data)
    file.close()
    return OK


static func read_image(path: String) -> Image:
    if not path.to_lower().ends_with(".webp") or not FileAccess.file_exists(path):
        return null
    var data := FileAccess.get_file_as_bytes(path)
    var image := Image.new()
    if data.is_empty() or image.load_webp_from_buffer(data) != OK:
        return null
    return image
