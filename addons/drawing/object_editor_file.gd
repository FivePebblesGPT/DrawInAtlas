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


static func open(path: String) -> DrawingResult:
	# The file and metadata must be from one bounded parse, not from two reads
	# that could straddle an external source replacement. Decode still verifies
	# every canonical blob before Open/preview/drop can trust the document.
	var envelope: DrawingResult = DrawingFileIO.read_payload(path)
	if not envelope.ok:
		return envelope
	var parsed: Dictionary = envelope.value
	var opened: DrawingResult = DrawingFileIO.decode(parsed)
	if not opened.ok:
		return opened
	var document: DrawingDocument = opened.value
	var meta: Variant = parsed.get("object_source", {})
	if not meta is Dictionary:
		return DrawingResult.failure("OBJECT_META", "Malformed Object source metadata")
	if meta.is_empty():
		return DrawingResult.success({"document": document, "source_id": document.id,
			"name": path.get_file().trim_suffix(".drawing"), "source_revision": 1,
			"origin": Vector2i.ZERO, "bounds": Rect2i()})
	var origin: Variant = meta.get("origin")
	var bounds: Variant = meta.get("bounds")
	var version: Variant = meta.get("revision")
	if meta.get("schema") != SCHEMA or meta.get("source_id") != document.id or \
			not meta.get("name") is String or (meta["name"] as String).strip_edges().is_empty() \
			or (meta["name"] as String).length() > 128 or \
			"\n" in meta["name"] or "\r" in meta["name"] or \
			not _frame_valid(origin, bounds) or not _number_valid(version, true) or \
			version < 1 or version > 2147483647:
		return DrawingResult.failure("OBJECT_META", "Invalid Object source identity or frame")
	return DrawingResult.success({"document": document, "source_id": document.id,
		"source_revision": int(version), "name": meta["name"],
		"origin": Vector2i(int(origin[0]), int(origin[1])),
		"bounds": Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3]))})
