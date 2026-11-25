class_name DrawingFileIO
extends RefCounted
## Standalone-only .drawing file. Atlas campaign publication is owned by T-066.
## Canonical RGBA8 blobs preserve hidden RGB and enable portable single files.
## The legacy dictionary codec also remains available for Atlas registry revisions.

const IMAGE_FRAME: Script = preload("res://addons/drawing/image_frame.gd")
const SCHEMA: String = "drawing-standalone-v1"
const MAX_FILE_BYTES: int = 134217728
const MAX_BLOBS: int = 4096
const BINARY_SCHEMA: String = "drawing-standalone-v2"
const BINARY_MAGIC: String = "DIADRAW2"
const BINARY_VERSION: int = 1
const HEADER_BYTES: int = 56
const MAX_DECODED_BYTES: int = 134217728


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()


static func is_supported_payload(payload: Dictionary) -> bool:
	return (payload.get("standalone_schema") == SCHEMA and payload.get("blob_encoding") == "base64-rgba8") or \
		(payload.get("standalone_schema") == BINARY_SCHEMA and payload.get("blob_encoding") == "raw-rgba8")


static func encode(document: DrawingDocument, binary: bool = false) -> DrawingResult:
	if document == null:
		return DrawingResult.failure("DOCUMENT", "Missing document")
	var exported: DrawingResult = document.export_manifest()
	if not exported.ok:
		return exported
	var manifest: Dictionary = exported.value
	if manifest["layers"].size() > 4096:
		return DrawingResult.failure("FILE_LIMIT", "Too many layers for standalone file")
	var blobs: Dictionary = {}
	var count: int = 0
	for record: Dictionary in manifest["layers"]:
		# Semantic records may contain Vector2 and Color, which JSON.stringify
		# would silently coerce to strings. Encode trusted built-in Variants without
		# serializing Object instances; bytes_to_var disallows Object creation.
		var objects: Dictionary = record["objects"]
		if not binary and not objects.is_empty():
			var semantic_bytes: PackedByteArray = var_to_bytes(objects)
			if semantic_bytes.is_empty() or semantic_bytes.size() > MAX_FILE_BYTES:
				return DrawingResult.failure("SEMANTIC_LIMIT", "Invalid semantic-object payload")
			record["objects_variant64"] = Marshalls.raw_to_base64(semantic_bytes)
			var semantic_hash: HashingContext = HashingContext.new()
			semantic_hash.start(HashingContext.HASH_SHA256)
			semantic_hash.update(semantic_bytes)
			record["objects_sha256"] = semantic_hash.finish().hex_encode()
			record["objects"] = {}
		var layer_id: String = record["id"]
		for chunk: Dictionary in record["chunks"]:
			count += 1
			if count > MAX_BLOBS or count * document.tile_stride * document.tile_stride * 4 > MAX_DECODED_BYTES:
				return DrawingResult.failure("FILE_LIMIT", "Too many chunks for standalone file")
			var coords: Array = chunk["coord"]
			var loaded: DrawingResult = document.request_chunk_at(layer_id, coords[0], coords[1])
			if not loaded.ok:
				return loaded
			var tile: DrawingRasterTile = loaded.value as DrawingRasterTile
			if tile == null:
				return DrawingResult.failure("MISSING_TILE", "Referenced chunk has no pixels")
			var bytes: PackedByteArray = tile.to_rgba8()
			var fingerprint: String = DrawingRasterTile.digest_rgba8(bytes, document.tile_stride)
			if fingerprint != chunk["sha256"]:
				return DrawingResult.failure("CORRUPT_TILE", "Chunk changed during serialization")
			blobs[fingerprint] = bytes if binary else Marshalls.raw_to_base64(bytes)
			chunk["ref"] = fingerprint
			# Write signed tile coordinates as decimal strings to avoid JSON float truncation.
			if not binary:
				chunk["coord"] = [str(coords[0]), str(coords[1])]
	# A portable file carries its licensed known font bytes with a stable identity.
	var fonts: Dictionary = {}
	for record: Dictionary in manifest["layers"]:
		var element: Variant = record.get("text_element")
		if element == null:
			continue
		var font_id: String = element["font_id"]
		var supported: DrawingResult = DrawingTextRaster.font_status(font_id)
		if not supported.ok:
			return supported
		if not fonts.has(font_id):
			# A packaged Godot app contains .fontdata, not the original .ttf path.
			var source: PackedByteArray = (supported.value as FontFile).get_data()
			if source.is_empty():
				return DrawingResult.failure("FONT_MISSING", "Known bundled font disappeared")
			var hash: HashingContext = HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update(source)
			fonts[font_id] = {"sha256": hash.finish().hex_encode(),
				("bytes" if binary else "bytes64"): source if binary else Marshalls.raw_to_base64(source),
				"license": FileAccess.get_file_as_string("res://addons/drawing/fonts/OFL-1.1.txt")}
	return DrawingResult.success({"standalone_schema": BINARY_SCHEMA if binary else SCHEMA,
		"document": manifest, "blobs": blobs, "font_assets": fonts,
		"blob_encoding": "raw-rgba8" if binary else "base64-rgba8"})


static func decode(payload: Dictionary) -> DrawingResult:
	if not is_supported_payload(payload):
		return DrawingResult.failure("SCHEMA", "Unsupported standalone Drawing file")
	var binary: bool = payload["standalone_schema"] == BINARY_SCHEMA
	if binary and not _portable_value(payload):
		return DrawingResult.failure("SEMANTIC_LIMIT", "Nonportable binary Drawing metadata")
	# Optional extent affects only standalone presentation. Reject corruption
	# before accepting any associated canonical pixel data.
	if payload.has("image_frame"):
		var checked_frame: DrawingResult = IMAGE_FRAME.decode(payload["image_frame"])
		if not checked_frame.ok:
			return checked_frame
	var manifest_value: Variant = payload.get("document")
	var blob_value: Variant = payload.get("blobs")
	if not manifest_value is Dictionary or not blob_value is Dictionary or blob_value.size() > MAX_BLOBS:
		return DrawingResult.failure("FILE", "Malformed Drawing file")
	var manifest: Dictionary = manifest_value.duplicate(true)
	var blobs: Dictionary = blob_value
	var assets: Variant = payload.get("font_assets", {})
	if not assets is Dictionary or assets.size() > 8:
		return DrawingResult.failure("FONT_RECORD", "Malformed font bundle")
	for font_id: Variant in assets:
		if not font_id is String or not assets[font_id] is Dictionary:
			return DrawingResult.failure("FONT_RECORD", "Malformed font identity")
		var font_data: Dictionary = assets[font_id]
		var font_bytes: Variant = font_data.get("bytes" if binary else "bytes64")
		if not font_data.get("sha256") is String or \
				(binary and (not font_bytes is PackedByteArray or font_bytes.size() > MAX_FILE_BYTES)) or \
				(not binary and (not font_bytes is String or font_bytes.length() > MAX_FILE_BYTES)):
			return DrawingResult.failure("FONT_RECORD", "Malformed font payload")
		var license_text: String = FileAccess.get_file_as_string("res://addons/drawing/fonts/OFL-1.1.txt")
		if not font_data.get("license") is String or license_text.is_empty() or font_data["license"] != license_text:
			return DrawingResult.failure("FONT_LICENSE", "Portable font requires its bundled OFL license")
		var content: PackedByteArray = font_bytes if binary else Marshalls.base64_to_raw(font_bytes)
		var hash: HashingContext = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(content)
		if hash.finish().hex_encode() != font_data["sha256"]:
			return DrawingResult.failure("FONT_CORRUPT", "Bundled font digest mismatch")
		var supported: DrawingResult = DrawingTextRaster.font_status(font_id)
		if not supported.ok:
			return supported
		if (supported.value as FontFile).get_data() != content:
			return DrawingResult.failure("FONT_VERSION", "Document font differs from licensed bundled font")
	# JSON numeric literals parse as floats in Godot. Validate before conversion.
	for field: String in ["tile_stride", "revision"]:
		var number: Variant = manifest.get(field)
		if (binary and not number is int) or not _integral(number, 0, 2147483647):
			return DrawingResult.failure("FILE", "Invalid numeric manifest field: " + field)
		manifest[field] = int(number)
	var density: Variant = manifest.get("density")
	if not density is Array or density.size() != 2:
		return DrawingResult.failure("FILE", "Invalid density")
	for index: int in range(2):
		if (binary and not density[index] is int) or not _integral(density[index], 1, 2147483647):
			return DrawingResult.failure("FILE", "Invalid density fraction")
		density[index] = int(density[index])
	var records: Variant = manifest.get("layers")
	if not records is Array or records.size() > 4096:
		return DrawingResult.failure("FILE", "Invalid layer metadata")
	var expanded: DrawingResult = expanded_raster_bytes(payload)
	if not expanded.ok:
		return expanded
	var stride: int = manifest["tile_stride"]
	if stride < 1 or stride > 2048:
		return DrawingResult.failure("FILE", "Invalid tile stride")
	for record: Variant in records:
		if not record is Dictionary:
			return DrawingResult.failure("FILE", "Malformed layer metadata")
		if record.has("objects_variant64"):
			if binary:
				return DrawingResult.failure("FILE", "Unexpected legacy semantic payload")
			if not record["objects_variant64"] is String or \
					(record["objects_variant64"] as String).length() > MAX_FILE_BYTES:
				return DrawingResult.failure("FILE", "Malformed semantic-object payload")
			var semantic_bytes: PackedByteArray = Marshalls.base64_to_raw(record["objects_variant64"])
			var semantic_hash: HashingContext = HashingContext.new()
			semantic_hash.start(HashingContext.HASH_SHA256)
			semantic_hash.update(semantic_bytes)
			if not record.get("objects_sha256") is String or \
					record["objects_sha256"] != semantic_hash.finish().hex_encode():
				return DrawingResult.failure("CORRUPT_SEMANTIC", "Invalid semantic-object digest")
			var semantic_value: Variant = bytes_to_var(semantic_bytes)
			if not semantic_value is Dictionary or not record.get("objects", {}) is Dictionary or \
					not record.get("objects", {}).is_empty():
				return DrawingResult.failure("FILE", "Invalid semantic-object payload")
			record["objects"] = semantic_value
			record.erase("objects_variant64")
			record.erase("objects_sha256")
		var element: Variant = record.get("text_element")
		if element != null:
			if not element is Dictionary:
				return DrawingResult.failure("TEXT_RECORD", "Malformed text record")
			for field: String in ["font_size", "rgba"]:
				if (binary and not element.get(field) is int) or not _integral(element.get(field), 0, 4294967295):
					return DrawingResult.failure("TEXT_RECORD", "Invalid text number")
				element[field] = int(element[field])
			if not assets.has(element.get("font_id", "")):
				return DrawingResult.failure("FONT_MISSING", "Portable file lacks referenced font")
		var chunks: Variant = record.get("chunks", [])
		if not chunks is Array:
			return DrawingResult.failure("FILE", "Malformed chunk metadata")
		for chunk: Variant in chunks:
			if not chunk is Dictionary:
				return DrawingResult.failure("FILE", "Malformed chunk record")
			var coords: Variant = chunk.get("coord")
			if not coords is Array or coords.size() != 2:
				return DrawingResult.failure("FILE", "Missing signed tile coordinates")
			for index: int in range(2):
				var coordinate: Variant = coords[index]
				if binary:
					if not coordinate is int:
						return DrawingResult.failure("FILE", "Invalid binary signed coordinate")
					continue
				if not coordinate is String or coordinate.length() > 19 or not coordinate.is_valid_int():
					return DrawingResult.failure("FILE", "Invalid signed tile coordinate")
				var parsed: int = int(coordinate)
				if str(parsed) != coordinate:
					return DrawingResult.failure("FILE", "Noncanonical signed tile coordinate")
				coords[index] = parsed
	if blobs.size() * stride * stride * 4 > MAX_DECODED_BYTES:
		return DrawingResult.failure("FILE_LIMIT", "Unique chunk budget exceeded")
	var canonical: Dictionary[String, PackedByteArray] = {}
	for key: Variant in blobs:
		if not key is String or key.length() != 64 or not key.is_valid_hex_number(false) or key != key.to_lower():
			return DrawingResult.failure("FILE", "Invalid blob identity")
		var encoded: Variant = blobs[key]
		if (binary and not encoded is PackedByteArray) or (not binary and not encoded is String):
			return DrawingResult.failure("FILE", "Invalid blob data")
		if not binary and encoded.length() > MAX_FILE_BYTES:
			return DrawingResult.failure("FILE_LIMIT", "Encoded chunk exceeds limit")
		var decoded: PackedByteArray = encoded if binary else Marshalls.base64_to_raw(encoded)
		if decoded.size() != stride * stride * 4 or DrawingRasterTile.digest_rgba8(decoded, stride) != key:
			return DrawingResult.failure("CORRUPT_TILE", "Invalid or missing canonical chunk bytes")
		canonical[key] = decoded
	# The in-memory loader retains validated bytes; no filesystem dependency after open.
	var loader: Callable = func(ref: String) -> Variant:
		return canonical.get(ref, null)
	var opened: DrawingResult = DrawingDocument.open_manifest(manifest, loader)
	if not opened.ok:
		return opened
	var document: DrawingDocument = opened.value as DrawingDocument
	# Verify every referenced chunk eagerly, including chunks outside today's viewport.
	for record: Dictionary in manifest["layers"]:
		for chunk: Dictionary in record["chunks"]:
			var ref: String = chunk["ref"]
			if not canonical.has(ref):
				return DrawingResult.failure("MISSING_TILE", "File lacks referenced blob")
			var coords: Array = chunk["coord"]
			var checked: DrawingResult = document.request_chunk_at(record["id"], coords[0], coords[1])
			if not checked.ok:
				return checked
	var adopted: DrawingResult = document._adopt_opened_raster_sources()
	if not adopted.ok:
		return adopted
	return DrawingResult.success(document, document.revision)


static func _integral(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and \
		float(value) >= float(minimum) and float(value) <= float(maximum) and \
		floorf(float(value)) == float(value)


static func save(document: DrawingDocument, path: String,
		extra: Dictionary = {}, legacy: bool = false) -> DrawingResult:
	if path.is_empty() or not path.is_absolute_path():
		return DrawingResult.failure("PATH", "Choose an absolute file path")
	var encoded: DrawingResult = encode(document, not legacy)
	if not encoded.ok:
		return encoded
	if not extra.is_empty():
		for key: Variant in extra:
			if key == "object_source" and extra[key] is Dictionary:
				(encoded.value as Dictionary)["object_source"] = (extra[key] as Dictionary).duplicate(true)
			elif key == "image_frame":
				var checked: DrawingResult = IMAGE_FRAME.decode(extra[key])
				if not checked.ok:
					return checked
				(encoded.value as Dictionary)["image_frame"] = IMAGE_FRAME.encode(checked.value as Rect2i)
			else:
				return DrawingResult.failure("METADATA", "Unrecognized standalone document metadata")
	# Text rotation is a float64; retain round-trip precision for editable transforms.
	var packed: DrawingResult = DrawingResult.success(JSON.stringify(encoded.value, "", true, true).to_utf8_buffer()) if legacy else pack_binary(encoded.value)
	if not packed.ok:
		return packed
	var file_bytes: PackedByteArray = packed.value
	if file_bytes.size() > MAX_FILE_BYTES:
		return DrawingResult.failure("FILE_LIMIT", "Drawing file exceeds standalone limit")
	var temporary: String = path + ".pending-" + DrawingDocument.new_id()
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return DrawingResult.failure("WRITE", "Unable to create temporary Drawing file")
	file.store_buffer(file_bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return DrawingResult.failure("WRITE", "Unable to flush Drawing file")
	var rename_error: Error = DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return DrawingResult.failure("WRITE", "Unable to publish Drawing file")
	var refs: Dictionary[String, String] = {}
	for record: Dictionary in (encoded.value as Dictionary)["document"]["layers"]:
		for chunk: Dictionary in record["chunks"]:
			var coords: Array = chunk["coord"]
			refs[record["id"] + ":" + str(coords[0]) + "," + str(coords[1])] = chunk["ref"]
	var published: DrawingResult = document.mark_published(document.revision, refs)
	return published


static func _portable_value(value: Variant, depth: int = 0) -> bool:
	# Do not let Variant serialization silently turn Objects/Callables/RIDs
	# into meaningless identifiers or nulls. Bound recursion for nested metadata.
	if depth > 64 or typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return false
	if value is Dictionary:
		if value.get_typed_key_builtin() in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID] or \
				value.get_typed_value_builtin() in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
			return false
		for key: Variant in value:
			if not _portable_value(key, depth + 1) or not _portable_value(value[key], depth + 1):
				return false
	elif value is Array:
		if value.get_typed_builtin() in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
			return false
		for entry: Variant in value:
			if not _portable_value(entry, depth + 1):
				return false
	return true


## Versioned little-endian envelope: magic, version, compression, raw length,
## stored length, SHA-256 of stored bytes, then one object-free Variant buffer.
## Compress sparse/deduplicated data together; incompressible data stays raw.
static func pack_binary(payload: Dictionary) -> DrawingResult:
	if payload.get("standalone_schema") != BINARY_SCHEMA:
		return DrawingResult.failure("SCHEMA", "Expected typed binary payload")
	if not _portable_value(payload):
		return DrawingResult.failure("SEMANTIC_LIMIT", "Nonportable or excessively nested metadata")
	var raw: PackedByteArray = var_to_bytes(payload)
	if raw.is_empty() or raw.size() > MAX_DECODED_BYTES:
		return DrawingResult.failure("FILE_LIMIT", "Binary Drawing payload exceeds decoded limit")
	var stored: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var compressed: bool = not stored.is_empty() and stored.size() < raw.size()
	if not compressed:
		stored = raw
	if stored.size() + HEADER_BYTES > MAX_FILE_BYTES:
		return DrawingResult.failure("FILE_LIMIT", "Binary Drawing file exceeds limit")
	var header: PackedByteArray = BINARY_MAGIC.to_ascii_buffer()
	header.resize(HEADER_BYTES)
	header.encode_u32(8, BINARY_VERSION)
	header.encode_u32(12, 1 if compressed else 0)
	header.encode_u32(16, raw.size())
	header.encode_u32(20, stored.size())
	var digest: PackedByteArray = _digest(stored)
	for index: int in range(32):
		header[24 + index] = digest[index]
	header.append_array(stored)
	return DrawingResult.success(header)


## Decode the same bounded bytes used by filesystem and authenticated Object
## consumers. A binary header never falls through to JSON after an error.
static func parse_payload(bytes: PackedByteArray, decoded_limit: int = MAX_DECODED_BYTES) -> DrawingResult:
	if bytes.is_empty() or bytes.size() > mini(MAX_FILE_BYTES, decoded_limit):
		return DrawingResult.failure("FILE_LIMIT", "Drawing file is empty or exceeds limit")
	if bytes.slice(0, 8) == BINARY_MAGIC.to_ascii_buffer():
		if bytes.size() < HEADER_BYTES:
			return DrawingResult.failure("FILE", "Truncated binary Drawing header")
		if bytes.decode_u32(8) != BINARY_VERSION:
			return DrawingResult.failure("SCHEMA", "Unsupported binary Drawing version")
		var compression: int = bytes.decode_u32(12)
		var raw_size: int = bytes.decode_u32(16)
		var stored_size: int = bytes.decode_u32(20)
		if compression not in [0, 1] or raw_size <= 0 or raw_size > mini(MAX_DECODED_BYTES, decoded_limit) or \
				stored_size <= 0 or stored_size != bytes.size() - HEADER_BYTES or \
				(compression == 0 and stored_size != raw_size):
			return DrawingResult.failure("FILE_LIMIT", "Invalid binary Drawing lengths or compression")
		var stored: PackedByteArray = bytes.slice(HEADER_BYTES)
		if _digest(stored) != bytes.slice(24, HEADER_BYTES):
			return DrawingResult.failure("CORRUPT_FILE", "Binary Drawing checksum mismatch")
		var raw: PackedByteArray = stored.decompress(raw_size, FileAccess.COMPRESSION_ZSTD) if compression == 1 else stored
		if raw.size() != raw_size:
			return DrawingResult.failure("CORRUPT_FILE", "Binary Drawing decompression failed")
		# Godot's Variant decoder can consume one value and ignore a suffix.
		# The envelope represents exactly one value, never concatenated records.
		if raw.decode_var_size(0) != raw.size():
			return DrawingResult.failure("CORRUPT_FILE", "Invalid or trailing binary Variant bytes")
		var payload: Variant = bytes_to_var(raw)
		if not payload is Dictionary or payload.get("standalone_schema") != BINARY_SCHEMA or \
				not is_supported_payload(payload) or not _portable_value(payload):
			return DrawingResult.failure("SCHEMA", "Invalid binary Drawing payload")
		return DrawingResult.success(payload)
	var text_data: String = bytes.get_string_from_utf8()
	if text_data.to_utf8_buffer() != bytes:
		return DrawingResult.failure("FILE", "Invalid Drawing UTF-8")
	var json: JSON = JSON.new()
	if json.parse(text_data) != OK or not json.data is Dictionary or json.data.get("standalone_schema") != SCHEMA:
		return DrawingResult.failure("FILE", "Invalid legacy Drawing JSON")
	return DrawingResult.success(json.data)


## Cost of a validated envelope, including repeated tile references that can
## expand into separate resident raster tiles. Linked source graphs must not
## use compressed file length alone as their aggregate admission budget.
static func expanded_raster_bytes(payload: Dictionary) -> DrawingResult:
	var manifest: Variant = payload.get("document")
	if not manifest is Dictionary or not _integral(manifest.get("tile_stride"), 1, 2048) or \
			not manifest.get("layers") is Array or manifest["layers"].size() > 4096:
		return DrawingResult.failure("FILE", "Invalid raster budget metadata")
	var stride: int = int(manifest["tile_stride"])
	var count: int = 0
	for layer: Variant in manifest["layers"]:
		if not layer is Dictionary or not layer.get("chunks", []) is Array:
			return DrawingResult.failure("FILE", "Malformed chunk metadata")
		count += layer.get("chunks", []).size()
		if count > MAX_BLOBS or count * stride * stride * 4 > MAX_DECODED_BYTES:
			return DrawingResult.failure("FILE_LIMIT", "Expanded chunk budget exceeded")
	return DrawingResult.success(count * stride * stride * 4)


## Call only after parse_payload succeeds. JSON has no compressed envelope.
static func decoded_payload_size(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(16) if bytes.slice(0, 8) == BINARY_MAGIC.to_ascii_buffer() and bytes.size() >= HEADER_BYTES else bytes.size()


static func read_payload(path: String) -> DrawingResult:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DrawingResult.failure("OPEN", "Unable to read Drawing file")
	var length: int = file.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		file.close()
		return DrawingResult.failure("FILE_LIMIT", "Drawing file is empty or exceeds limit")
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return DrawingResult.failure("FILE", "Truncated Drawing file")
	return parse_payload(bytes)


static func open_with_frame(path: String) -> DrawingResult:
	var payload: DrawingResult = read_payload(path)
	if not payload.ok:
		return payload
	var opened: DrawingResult = decode(payload.value)
	if not opened.ok:
		return opened
	var document: DrawingDocument = opened.value as DrawingDocument
	var bounds: Rect2i = IMAGE_FRAME.infer_legacy(document)
	if (payload.value as Dictionary).has("image_frame"):
		var decoded: DrawingResult = IMAGE_FRAME.decode(payload.value["image_frame"])
		if not decoded.ok:
			return decoded
		bounds = decoded.value as Rect2i
	return DrawingResult.success({"document": document, "image_frame": bounds}, document.revision)


static func open(path: String) -> DrawingResult:
	# Keep generic and Object Asset consumers on the original document-only
	# path: legacy frame inference belongs to the standalone workspace UI.
	var payload: DrawingResult = read_payload(path)
	if not payload.ok:
		return payload
	return decode(payload.value)
