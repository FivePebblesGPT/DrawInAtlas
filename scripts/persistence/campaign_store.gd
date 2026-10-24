class_name AtlasCampaignStore
extends RefCounted

const DEFAULT_PATH: String = "user://drawinatlas_campaign.json"


static func save_campaign(campaign: AtlasCampaign, path: String = DEFAULT_PATH,
        io: AtlasStoreIO = null) -> Error:
    if campaign == null or path.is_empty():
        return ERR_INVALID_PARAMETER
    var storage: AtlasStoreIO = io if io != null else AtlasStoreIO.new()
    var data: Dictionary = campaign.to_dict()
    if not _json_safe(data) or not _asset_names_safe(data) \
            or AtlasCampaign.from_dict(data) == null:
        return ERR_INVALID_DATA
    var chunks: Array[AtlasRasterChunk] = _chunks(campaign)
    # Validate every source before performing any filesystem mutation.
    for chunk: AtlasRasterChunk in chunks:
        if not chunk.is_valid() or not _hash_valid(chunk.asset_id):
            return ERR_INVALID_DATA
        if chunk.image != null and (not chunk.is_valid(true) \
                or chunk.image.get_format() != Image.FORMAT_RGBA8):
            return ERR_INVALID_DATA
    var error: Error = storage.make_dir(path.get_base_dir())
    if error != OK:
        return error
    if not chunks.is_empty():
        error = storage.make_dir(path + ".assets")
        if error != OK:
            return error
    for chunk: AtlasRasterChunk in chunks:
        error = _store_chunk(chunk, path + ".assets", storage)
        if error != OK:
            return error
    data["_checkpoint"] = {"sha256": _canonical(data).sha256_text()}
    var bytes: PackedByteArray = _canonical(data).to_utf8_buffer()
    error = _stage(path + ".pending", bytes, storage)
    if error != OK:
        return error
    var staged: AtlasStoreResult = _load_one(path + ".pending", path, storage)
    if staged.error != OK:
        return staged.error
    # Only a fully validated head may replace the previous recovery generation.
    # A corrupt head must never overwrite an existing valid backup.
    var previous: AtlasStoreResult = _load_one(path, path, storage)
    if previous.error == OK:
        var previous_bytes: PackedByteArray = storage.read_bytes(path)
        error = _stage(path + ".bak.pending", previous_bytes, storage)
        if error != OK:
            return error
        var backup: AtlasStoreResult = _load_one(path + ".bak.pending", path, storage)
        if backup.error != OK:
            return backup.error
        error = storage.rename(path + ".bak.pending", path + ".bak")
        if error != OK:
            return error
    return storage.rename(path + ".pending", path)


static func load_campaign(path: String = DEFAULT_PATH, io: AtlasStoreIO = null) -> AtlasCampaign:
    return load_result(path, io).campaign


static func load_result(path: String = DEFAULT_PATH, io: AtlasStoreIO = null) -> AtlasStoreResult:
    var storage: AtlasStoreIO = io if io != null else AtlasStoreIO.new()
    var head: AtlasStoreResult = _load_one(path, path, storage)
    if head.error == OK:
        return head
    var backup: AtlasStoreResult = _load_one(path + ".bak", path, storage)
    if backup.error == OK:
        backup.recovered = true
        backup.message = "Recovered backup; head: " + head.message
        return backup
    return AtlasStoreResult.failure(head.error,
        "Head: %s; backup: %s" % [head.message, backup.message], path)


static func _load_one(metadata_path: String, path: String, io: AtlasStoreIO) -> AtlasStoreResult:
    if not io.exists(metadata_path):
        return AtlasStoreResult.failure(ERR_FILE_NOT_FOUND, "Missing " + metadata_path, metadata_path)
    var bytes: PackedByteArray = io.read_bytes(metadata_path)
    var json: JSON = JSON.new()
    if bytes.is_empty() or json.parse(bytes.get_string_from_utf8()) != OK \
            or not json.data is Dictionary:
        return AtlasStoreResult.failure(ERR_FILE_CORRUPT, "Invalid JSON at " + metadata_path, metadata_path)
    var data: Dictionary = json.data
    if not _json_safe(data) or not _asset_names_safe(data):
        return AtlasStoreResult.failure(ERR_INVALID_DATA, "Invalid metadata at " + metadata_path, metadata_path)
    var version: Variant = data.get("schema_version")
    if not AtlasData.integer(version) or int(version) < 1 or int(version) > AtlasCampaign.SCHEMA_VERSION:
        return AtlasStoreResult.failure(ERR_FILE_UNRECOGNIZED, "Unsupported schema at " + metadata_path, metadata_path)
    var checkpoint: Variant = data.get("_checkpoint")
    if data.has("_checkpoint") or int(version) >= 4:
        data.erase("_checkpoint")
        if not checkpoint is Dictionary or not checkpoint.get("sha256") is String \
                or checkpoint.get("sha256") != _canonical(data).sha256_text():
            return AtlasStoreResult.failure(ERR_FILE_CORRUPT, "Checksum mismatch at " + metadata_path, metadata_path)
    var campaign: AtlasCampaign = AtlasCampaign.from_dict(data)
    if campaign == null:
        return AtlasStoreResult.failure(ERR_INVALID_DATA, "Invalid campaign at " + metadata_path, metadata_path)
    for chunk: AtlasRasterChunk in _chunks(campaign):
        var expected: String = chunk.asset_id
        if not chunk.is_valid() or not _hash_valid(expected):
            return AtlasStoreResult.failure(ERR_INVALID_DATA, "Invalid raster reference at " + metadata_path, metadata_path)
        # Legacy inline data, if provided by a migration, is already hydrated.
        if chunk.image != null:
            continue
        var asset_path: String = path + ".assets/" + expected + ".webp"
        var image: Image = _read_chunk(asset_path, chunk, io)
        if image == null:
            return AtlasStoreResult.failure(ERR_FILE_CORRUPT, "Missing or corrupt chunk " + asset_path, metadata_path)
        chunk.image = image
    var result: AtlasStoreResult = AtlasStoreResult.new()
    result.campaign = campaign
    result.source_path = metadata_path
    return result


static func _chunks(campaign: AtlasCampaign) -> Array[AtlasRasterChunk]:
    var result: Array[AtlasRasterChunk] = []
    for map: AtlasMapDocument in campaign.maps.values():
        for floor: AtlasFloor in map.floors:
            for layer: AtlasLayer in floor.layers:
                if layer is AtlasRasterLayer:
                    var raster: AtlasRasterLayer = layer as AtlasRasterLayer
                    result.append_array(raster.chunks.values())
    return result


static func _read_chunk(path: String, chunk: AtlasRasterChunk, io: AtlasStoreIO) -> Image:
    if not io.exists(path):
        return null
    var image: Image = AtlasWebPStore.decode_lossless(io.read_bytes(path), chunk.width, chunk.height)
    if image == null or image.get_width() != chunk.width or image.get_height() != chunk.height \
            or image.get_width() > AtlasRasterChunk.SIZE or image.get_height() > AtlasRasterChunk.SIZE \
            or AtlasRasterChunk.image_hash(image) != chunk.asset_id:
        return null
    return image


static func _store_chunk(chunk: AtlasRasterChunk, directory: String, io: AtlasStoreIO) -> Error:
    var path: String = directory + "/" + chunk.asset_id + ".webp"
    if io.exists(path):
        # Immutable assets are never overwritten, even when corrupt.
        return OK if _read_chunk(path, chunk, io) != null else ERR_FILE_CORRUPT
    if chunk.image == null:
        return ERR_FILE_NOT_FOUND
    var bytes: PackedByteArray = AtlasWebPStore.encode_lossless(chunk.image)
    if bytes.is_empty():
        return ERR_UNAVAILABLE
    var error: Error = _stage(path + ".pending", bytes, io)
    if error != OK:
        return error
    if _read_chunk(path + ".pending", chunk, io) == null:
        return ERR_FILE_CORRUPT
    return io.rename(path + ".pending", path)


static func _stage(path: String, bytes: PackedByteArray, io: AtlasStoreIO) -> Error:
    var error: Error = io.write_bytes(path, bytes)
    if error != OK:
        return error
    return OK if io.read_bytes(path) == bytes else ERR_FILE_CORRUPT


static func _canonical(data: Dictionary) -> String:
    # JSON.parse represents every number as float. Hash that same representation
    # on both sides, without rounding the significant digits of native doubles.
    var numeric_json: Variant = JSON.parse_string(JSON.stringify(data, "", true, true))
    return JSON.stringify(numeric_json, "", true, true)


static func _hash_valid(value: String) -> bool:
    if value.length() != 64:
        return false
    for character: String in value:
        if not character in "0123456789abcdef":
            return false
    return true


static func _asset_names_safe(value: Variant) -> bool:
    if value is Dictionary:
        for key: Variant in value:
            if key == "asset":
                var asset: Variant = value[key]
                if not asset is String or not asset.ends_with(".webp") \
                        or not _hash_valid(asset.trim_suffix(".webp")):
                    return false
            elif not _asset_names_safe(value[key]):
                return false
    elif value is Array:
        for item: Variant in value:
            if not _asset_names_safe(item):
                return false
    return true


static func _json_safe(value: Variant) -> bool:
    if value == null or value is bool or value is String:
        return true
    if value is int:
        return value >= -9007199254740991 and value <= 9007199254740991
    if value is float:
        return is_finite(value)
    if value is Array:
        for item: Variant in value:
            if not _json_safe(item):
                return false
        return true
    if value is Dictionary:
        for key: Variant in value:
            if not key is String or not _json_safe(value[key]):
                return false
        return true
    return false
