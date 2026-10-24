class_name AtlasRasterChunk
extends RefCounted
## A bounded RGBA8 image, addressed independently of its location by pixel content.

const SIZE: int = 256

var coord: Vector2i
var image: Image
var width: int = SIZE
var height: int = SIZE
var _asset_id: String = ""
var asset_id: String:
    get:
        return image_hash(image) if image != null else _asset_id
    set(value):
        _asset_id = value


func _init(position: Vector2i = Vector2i.ZERO, pixels: Image = null) -> void:
    coord = position
    if pixels != null and not pixels.is_empty():
        image = canonical_image(pixels)
        if image != null:
            width = image.get_width()
            height = image.get_height()


func is_valid(require_image: bool = false) -> bool:
    if width < 1 or height < 1 or width > SIZE or height > SIZE:
        return false
    if image != null:
        return (not image.is_empty() and image.get_format() == Image.FORMAT_RGBA8
            and not image.has_mipmaps() and image.get_width() == width and image.get_height() == height)
    return not require_image and valid_asset_id(_asset_id)


func to_dict() -> Dictionary:
    return {"coord": [coord.x, coord.y], "width": width, "height": height, "asset": asset_id + ".webp"}


static func from_dict(data: Dictionary) -> AtlasRasterChunk:
    var point: Variant = data.get("coord")
    var w: Variant = data.get("width")
    var h: Variant = data.get("height")
    var asset: Variant = data.get("asset")
    if not AtlasData.vector(point) or not AtlasData.integer(point[0]) or not AtlasData.integer(point[1]):
        return null
    if not AtlasData.integer(w) or not AtlasData.integer(h) or not asset is String:
        return null
    if not asset.ends_with(".webp") or not valid_asset_id(asset.trim_suffix(".webp")):
        return null
    var chunk: AtlasRasterChunk = AtlasRasterChunk.new(Vector2i(int(point[0]), int(point[1])))
    chunk.width = int(w)
    chunk.height = int(h)
    chunk.asset_id = asset.trim_suffix(".webp")
    return chunk if chunk.is_valid() else null


static func valid_asset_id(value: String) -> bool:
    return value.length() == 64 and value.is_valid_hex_number(false) and value == value.to_lower()


static func canonical_image(source: Image) -> Image:
    if source == null or source.is_empty():
        return null
    var pixels: Image = source.duplicate()
    if pixels.is_compressed() and pixels.decompress() != OK:
        return null
    pixels.clear_mipmaps()
    pixels.convert(Image.FORMAT_RGBA8)
    return pixels


static func image_hash(pixels: Image) -> String:
    if pixels == null or pixels.is_empty():
        return ""
    var normalized: Image = pixels
    if pixels.get_format() != Image.FORMAT_RGBA8 or pixels.has_mipmaps():
        normalized = canonical_image(pixels)
    if normalized == null:
        return ""
    var context: HashingContext = HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(("%d,%d:" % [normalized.get_width(), normalized.get_height()]).to_utf8_buffer())
    context.update(normalized.get_data())
    return context.finish().hex_encode()
