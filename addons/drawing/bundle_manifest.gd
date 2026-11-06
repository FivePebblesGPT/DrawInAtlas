class_name DrawingBundleManifest
extends RefCounted
## Format-neutral document metadata adapter for sparse multi-file consumers.
## No Atlas imports; signed addresses remain strings on disk to avoid JSON float loss.

const SCHEMA: String = "drawing-sparse-manifest-v1"
const MAX_MANIFEST_BYTES: int = 16777216
const MAX_LAYERS: int = 4096
const MAX_CHUNKS: int = 1000000


static func encode(document: DrawingDocument) -> DrawingResult:
	if document == null:
		return DrawingResult.failure("DOCUMENT", "Missing document")
	var exported: DrawingResult = document.export_manifest()
	if not exported.ok:
		return exported
	var manifest: Dictionary = exported.value
	var count: int = 0
	for record: Dictionary in manifest["layers"]:
		var objects: Dictionary = record["objects"]
		if not objects.is_empty():
			var semantic: PackedByteArray = var_to_bytes(objects)
			if semantic.size() > MAX_MANIFEST_BYTES:
				return DrawingResult.failure("SEMANTIC_LIMIT", "Semantic layer is too large")
			record["objects_variant64"] = Marshalls.raw_to_base64(semantic)
			record["objects_sha256"] = _hash(semantic)
			record["objects"] = {}
		for chunk: Dictionary in record["chunks"]:
			count += 1
			if count > MAX_CHUNKS:
				return DrawingResult.failure("CHUNK_LIMIT", "Too many sparse chunks")
			var coords: Array = chunk["coord"]
			chunk["coord"] = [str(coords[0]), str(coords[1])]
	manifest["physical_schema"] = SCHEMA
	var data: PackedByteArray = JSON.stringify(manifest, "", true, true).to_utf8_buffer()
	if data.size() > MAX_MANIFEST_BYTES:
		return DrawingResult.failure("MANIFEST_LIMIT", "Document metadata is too large")
	return DrawingResult.success({"bytes": data, "manifest": manifest})


static func decode(bytes: PackedByteArray, loader: Callable) -> DrawingResult:
	if bytes.is_empty() or bytes.size() > MAX_MANIFEST_BYTES:
		return DrawingResult.failure("MANIFEST", "Missing or oversized document manifest")
	var json: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not json is Dictionary or json.get("physical_schema") != SCHEMA:
		return DrawingResult.failure("SCHEMA", "Invalid sparse document schema")
	var manifest: Dictionary = json
	for field: String in ["tile_stride", "revision"]:
		if not _integer(manifest.get(field), 0, 2147483647):
			return DrawingResult.failure("MANIFEST", "Invalid numeric field " + field)
		manifest[field] = int(manifest[field])
	var density: Variant = manifest.get("density")
	if not density is Array or density.size() != 2:
		return DrawingResult.failure("MANIFEST", "Invalid density")
	for i: int in range(2):
		if not _integer(density[i], 1, 2147483647):
			return DrawingResult.failure("MANIFEST", "Invalid density fraction")
		density[i] = int(density[i])
	var layers: Variant = manifest.get("layers")
	if not layers is Array or layers.size() > MAX_LAYERS:
		return DrawingResult.failure("MANIFEST", "Invalid layer count")
	var count: int = 0
	for record: Variant in layers:
		if not record is Dictionary:
			return DrawingResult.failure("MANIFEST", "Invalid layer metadata")
		if record.has("objects_variant64"):
			if not record["objects_variant64"] is String or (record["objects_variant64"] as String).length() > MAX_MANIFEST_BYTES * 2:
				return DrawingResult.failure("SEMANTIC", "Invalid semantic encoding")
			var raw: PackedByteArray = Marshalls.base64_to_raw(record["objects_variant64"])
			if raw.is_empty() or _hash(raw) != record.get("objects_sha256"):
				return DrawingResult.failure("SEMANTIC", "Semantic digest mismatch")
			var decoded: Variant = bytes_to_var(raw)
			if not decoded is Dictionary or not record.get("objects", {}).is_empty():
				return DrawingResult.failure("SEMANTIC", "Invalid semantic dictionary")
			record["objects"] = decoded
			record.erase("objects_variant64")
			record.erase("objects_sha256")
		var element: Variant = record.get("text_element")
		if element != null:
			if not element is Dictionary:
				return DrawingResult.failure("TEXT", "Invalid editable text element")
			for field: String in ["font_size", "rgba"]:
				if not _integer(element.get(field), 0, 4294967295):
					return DrawingResult.failure("TEXT", "Invalid text field " + field)
				element[field] = int(element[field])
		var chunks: Variant = record.get("chunks", [])
		if not chunks is Array:
			return DrawingResult.failure("CHUNKS", "Invalid chunk records")
		for chunk: Variant in chunks:
			count += 1
			if count > MAX_CHUNKS or not chunk is Dictionary or not chunk.get("coord") is Array:
				return DrawingResult.failure("CHUNKS", "Invalid chunk descriptor")
			var coord: Array = chunk["coord"]
			if coord.size() != 2:
				return DrawingResult.failure("COORD", "Invalid signed coordinate pair")
			for i: int in range(2):
				if not coord[i] is String or (coord[i] as String).length() > 19 or not (coord[i] as String).is_valid_int():
					return DrawingResult.failure("COORD", "Invalid signed chunk coordinate")
				var signed: int = int(coord[i])
				if str(signed) != coord[i]:
					return DrawingResult.failure("COORD", "Noncanonical signed coordinate")
				coord[i] = signed
	return DrawingDocument.open_manifest(manifest, loader)


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= float(low) \
		and float(value) <= float(high) and floorf(float(value)) == float(value)


static func _hash(data: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()
