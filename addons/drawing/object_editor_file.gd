class_name DrawingObjectEditorFile
extends RefCounted
## Optional portable Object-source metadata on top of an ordinary .drawing
## payload. Both the Object Editor and ordinary Drawing can read the pixels.

const SCHEMA: String = "drawing-object-source-v1"


static func _frame_valid(origin: Variant, bounds: Variant) -> bool:
	if not origin is Array or origin.size() != 2 or \
			not bounds is Array or bounds.size() != 4:
		return false
	for number: Variant in origin:
		if not _number_valid(number, false):
			return false
	for index: int in range(4):
		if not _number_valid(bounds[index], index >= 2):
			return false
	return true


static func _number_valid(value: Variant, nonnegative: bool) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and absf(float(value)) <= 1000000000.0 \
		and (not nonnegative or value >= 0) and floorf(float(value)) == float(value)


static func save(document: DrawingDocument, path: String, name: String,
		origin: Vector2i, bounds: Rect2i, version: int) -> DrawingResult:
	if document == null or name.strip_edges().is_empty() or name.length() > 128 or \
			"\n" in name or "\r" in name or \
			version < 1 or not _frame_valid([origin.x, origin.y],
			[bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]):
		return DrawingResult.failure("OBJECT_META", "Invalid Object source name or local frame")
	var metadata: Dictionary = {"schema": SCHEMA, "source_id": document.id,
		"name": name, "revision": version, "origin": [origin.x, origin.y],
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]}
	return DrawingFileIO.save(document, path, {"object_source": metadata})


## Inspect the outer source identity/frame for an already SHA-verified Atlas
## registry entry without expanding canonical pixel tiles. This is NOT an
## authorization to edit, preview, import or place an Object: those paths must
## continue to use open(), which validates every referenced tile.
static func inspect_metadata(path: String) -> DrawingResult:
	var envelope: DrawingResult = DrawingFileIO.read_payload(path)
	if not envelope.ok:
		return envelope
	var parsed: Dictionary = envelope.value
	if parsed.get("standalone_schema") != DrawingFileIO.SCHEMA or \
			parsed.get("blob_encoding") != "base64-rgba8":
		return DrawingResult.failure("SCHEMA", "Unsupported standalone Drawing file")
	var manifest: Variant = parsed.get("document")
	if not manifest is Dictionary or not manifest.get("id") is String or \
			not DrawingDocument.valid_identifier(String(manifest["id"])) or \
			not manifest.get("layers") is Array or not parsed.get("blobs") is Dictionary:
		return DrawingResult.failure("FILE", "Malformed Drawing source envelope")
	return _read_metadata(parsed.get("object_source", {}), String(manifest["id"]), path)


static func _read_metadata(meta: Variant, document_id: String, path: String) -> DrawingResult:
	if not meta is Dictionary:
		return DrawingResult.failure("OBJECT_META", "Malformed Object source metadata")
	if meta.is_empty():
		return DrawingResult.success({"source_id": document_id,
			"name": path.get_file().trim_suffix(".drawing"), "source_revision": 1,
			"origin": Vector2i.ZERO, "bounds": Rect2i()})
	var origin: Variant = meta.get("origin")
	var bounds: Variant = meta.get("bounds")
	var version: Variant = meta.get("revision")
	if meta.get("schema") != SCHEMA or meta.get("source_id") != document_id or \
			not meta.get("name") is String or (meta["name"] as String).strip_edges().is_empty() \
			or (meta["name"] as String).length() > 128 or \
			"\n" in meta["name"] or "\r" in meta["name"] or \
			not _frame_valid(origin, bounds) or not _number_valid(version, true) or \
			version < 1 or version > 2147483647:
		return DrawingResult.failure("OBJECT_META", "Invalid Object source identity or frame")
	return DrawingResult.success({"source_id": document_id,
		"source_revision": int(version), "name": meta["name"],
		"origin": Vector2i(int(origin[0]), int(origin[1])),
		"bounds": Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3]))})


static func open(path: String) -> DrawingResult:
	# Pixels and identity must be validated from the same bounded envelope.
	var envelope: DrawingResult = DrawingFileIO.read_payload(path)
	if not envelope.ok:
		return envelope
	return decode_payload(envelope.value, path)


## Reuse a previously parsed envelope when its bytes were captured and hashed
## by the Asset Browser index; do not reopen the path for unrelated metadata.
static func decode_payload(parsed: Dictionary, path: String) -> DrawingResult:
	var opened: DrawingResult = DrawingFileIO.decode(parsed)
	if not opened.ok:
		return opened
	var document: DrawingDocument = opened.value
	var metadata: DrawingResult = _read_metadata(parsed.get("object_source", {}), document.id, path)
	if not metadata.ok:
		return metadata
	var result: Dictionary = metadata.value
	result["document"] = document
	return DrawingResult.success(result)
