class_name DrawingLinkedObjects
extends RefCounted
## Bounded standalone source authorization. Files may name stable IDs, never
## filesystem paths. Only the user-selected flat Objects/ catalog is trusted.
## Atlas immutable revision directories/registry records are not standalone links.

const MAX_DEPTH: int = 8
const MAX_SOURCE_BYTES: int = 128 * 1024 * 1024
const MAX_VISITS: int = 128
const MAX_SOURCE_COORD: int = 1000000000


static func flat_entry(index: DrawingAssetBrowserIndex, entry: Dictionary) -> bool:
	return index != null and entry.get("path") is String and \
		String(entry["path"]).get_base_dir() == index.root_path and \
		not entry.has("embedded_id")


## A loose source inside a campaign-owned root is not a standalone catalog.
## Mirror the existing portable import's bounded registry-marker preflight.
static func standalone_catalog(index: DrawingAssetBrowserIndex) -> bool:
	if index == null or index.root_path.is_empty() or not index.warnings.is_empty() or \
			not DrawingAssetBrowserIndex.path_has_no_links(index.root_path):
		return false
	var directory: DirAccess = DirAccess.open(index.root_path)
	if directory == null or directory.list_dir_begin() != OK:
		return false
	var count: int = 0
	var safe: bool = true
	while true:
		var name: String = directory.get_next()
		if name.is_empty():
			break
		count += 1
		if count > DrawingAssetBrowserIndex.MAX_CANDIDATES or name.ends_with(".atlas-object-index.json"):
			safe = false
			break
	directory.list_dir_end()
	return safe


static func entry_for_token(index: DrawingAssetBrowserIndex, token: Dictionary) -> Dictionary:
	if token.get("kind") != "drawing-object-source-v1" or not standalone_catalog(index):
		return {}
	for entry: Dictionary in index.entries:
		if flat_entry(index, entry) and entry.get("id") == token.get("id") and \
				entry.get("revision") == token.get("revision") and entry.get("path") == token.get("path") and \
				entry.get("sha256") == token.get("sha256") and entry.get("name") == token.get("name") and \
				token.get("embedded_id") == entry["id"] and token.get("embedded_revision") == entry["revision"]:
			return entry
	return {}


## Decode the exact bytes authenticated by the advertised digest, not a later
## reopen of the filename. Reuse the existing index's path/identity policy.
static func _open(index: DrawingAssetBrowserIndex, entry: Dictionary, budget: Dictionary) -> DrawingResult:
	if not flat_entry(index, entry) or not index.safe_to_open(entry):
		return DrawingResult.failure("LINK_STALE", "Source is stale, unsafe or not a standalone Object; refresh the browser")
	var path: String = entry["path"]
	var stream: FileAccess = FileAccess.open(path, FileAccess.READ)
	if stream == null:
		return DrawingResult.failure("LINK_STALE", "Object source disappeared")
	var length: int = stream.get_length()
	if length <= 0 or length > DrawingAssetBrowserIndex.MAX_OBJECT_BYTES or length > int(budget["bytes"]):
		stream.close()
		return DrawingResult.failure("LINK_LIMIT", "Linked source byte budget exceeded")
	var bytes: PackedByteArray = stream.get_buffer(length)
	stream.close()
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	if bytes.size() != length or digest.finish().hex_encode() != entry["sha256"] or not index.safe_to_open(entry):
		return DrawingResult.failure("LINK_STALE", "Object source changed during authorization")
	var envelope: DrawingResult = DrawingFileIO.parse_payload(bytes, int(budget["bytes"]))
	if not envelope.ok:
		return DrawingResult.failure("LINK_LIMIT", "Linked source decoded byte budget exceeded") if envelope.code == "FILE_LIMIT" else envelope
	var raster_cost: DrawingResult = DrawingFileIO.expanded_raster_bytes(envelope.value)
	if not raster_cost.ok:
		return raster_cost
	var cost: int = maxi(length, maxi(DrawingFileIO.decoded_payload_size(bytes), int(raster_cost.value)))
	if cost > int(budget["bytes"]):
		return DrawingResult.failure("LINK_LIMIT", "Linked source expanded raster byte budget exceeded")
	var opened: DrawingResult = DrawingObjectEditorFile.decode_payload(envelope.value, path)
	if not opened.ok:
		return opened
	if opened.value["source_id"] != entry["id"] or opened.value["source_revision"] != entry["revision"]:
		return DrawingResult.failure("LINK_STALE", "Object source identity changed")
	budget["bytes"] = int(budget["bytes"]) - cost
	return opened


## Every dependency must be authorized and acyclic, including hidden links.
## Expand the graph with a visit cap (not just a unique-node cap), since a DAG
## can still multiply rendering work exponentially. Nothing is published here.
static func resolve(document: DrawingDocument, index: DrawingAssetBrowserIndex,
		extra: Dictionary = {}) -> DrawingResult:
	var links: Array[Dictionary] = document.linked_records()
	if not extra.is_empty():
		links.append(extra)
	if links.is_empty():
		return DrawingResult.success({})
	if not standalone_catalog(index):
		return DrawingResult.failure("LINK_ROOT", "Choose or refresh an unambiguous standalone Objects/ folder")
	var catalog: Dictionary = {}
	for entry: Dictionary in index.entries:
		if flat_entry(index, entry):
			catalog[entry["id"]] = entry
	var snapshots: Dictionary = {}
	var budget: Dictionary = {"bytes": MAX_SOURCE_BYTES, "visits": MAX_VISITS}
	var result: DrawingResult = _walk(links, {document.id: true}, 0, index, catalog, snapshots, budget)
	return DrawingResult.success(snapshots) if result.ok else result


static func _walk(links: Array[Dictionary], ancestors: Dictionary, depth: int,
		index: DrawingAssetBrowserIndex, catalog: Dictionary, snapshots: Dictionary,
		budget: Dictionary) -> DrawingResult:
	if links.size() > DrawingDocument.MAX_LINKS or (not links.is_empty() and depth >= MAX_DEPTH):
		return DrawingResult.failure("LINK_LIMIT", "Linked Object graph exceeds the depth or placement budget")
	for link: Dictionary in links:
		if not DrawingDocument.valid_link(link):
			return DrawingResult.failure("LINK_RECORD", "Malformed Object link")
		var source_id: String = link["source_id"]
		if ancestors.has(source_id):
			return DrawingResult.failure("LINK_CYCLE", "Object references must not contain self or cyclic links")
		if not catalog.has(source_id):
			return DrawingResult.failure("LINK_MISSING", "Missing authorized standalone Object: " + source_id)
		budget["visits"] = int(budget["visits"]) - 1
		if int(budget["visits"]) < 0:
			return DrawingResult.failure("LINK_LIMIT", "Linked Object expanded graph exceeds its budget")
		if not snapshots.has(source_id):
			var opened: DrawingResult = _open(index, catalog[source_id], budget)
			if not opened.ok:
				return opened
			snapshots[source_id] = opened.value
		var next: Dictionary = ancestors.duplicate()
		next[source_id] = true
		var nested: DrawingResult = _walk((snapshots[source_id]["document"] as DrawingDocument).linked_records(),
			next, depth + 1, index, catalog, snapshots, budget)
		if not nested.ok:
			return nested
		if not snapshots[source_id].has("coverage"):
			var measured: DrawingResult = _coverage(snapshots[source_id]["document"], DrawingDocument.ROOT_ID, snapshots)
			if not measured.ok:
				return measured
			snapshots[source_id]["coverage"] = measured.value
		var translated: DrawingResult = _translated(link, snapshots[source_id])
		if not translated.ok:
			return translated
	return DrawingResult.success()


## Conservative occupied bounds are calculated once per authorized source.
## Optional Object frame bounds are a guide, never a crop of sparse artwork.
static func _coverage(document: DrawingDocument, parent: String, sources: Dictionary) -> DrawingResult:
	var result: Rect2i = Rect2i()
	for layer: String in document.list_children(parent):
		var info: Dictionary = document.node_metadata(layer)
		if not info["visible"]:
			continue
		var area: Rect2i = Rect2i()
		match info["kind"]:
			DrawingLayerNode.GROUP:
				var nested: DrawingResult = _coverage(document, layer, sources)
				if not nested.ok:
					return nested
				area = nested.value
			DrawingLayerNode.RASTER:
				for key: String in document.tile_keys(layer):
					var parts: PackedStringArray = key.split(",")
					var x: int = int(parts[0]) * document.tile_stride
					var y: int = int(parts[1]) * document.tile_stride
					if not _inside(x, y, document.tile_stride, document.tile_stride):
						return DrawingResult.failure("LINK_RANGE", "Linked artwork is outside the standalone signed coordinate range")
					var tile: Rect2i = Rect2i(x, y, document.tile_stride, document.tile_stride)
					area = tile if not area.has_area() else area.merge(tile)
			DrawingLayerNode.TEXT:
				var element: DrawingTextElement = document.inspect_node(layer).text_element
				if element != null:
					var measured: DrawingResult = DrawingTextRaster.bounds(element)
					if not measured.ok:
						return measured
					area = measured.value
			DrawingLayerNode.OBJECTS:
				for link: Dictionary in document.layer_links(layer):
					var translated: DrawingResult = _translated(link, sources[link["source_id"]])
					if not translated.ok:
						return translated
					var child: Rect2i = translated.value
					if child.has_area():
						area = child if not area.has_area() else area.merge(child)
		if area.has_area():
			if not _inside(area.position.x, area.position.y, area.size.x, area.size.y):
				return DrawingResult.failure("LINK_RANGE", "Linked artwork is outside the standalone signed coordinate range")
			result = area if not result.has_area() else result.merge(area)
	return DrawingResult.success(result)


static func _inside(x: int, y: int, width: int, height: int) -> bool:
	return x >= -MAX_SOURCE_COORD and y >= -MAX_SOURCE_COORD and \
		x + width <= MAX_SOURCE_COORD and y + height <= MAX_SOURCE_COORD


static func _translated(link: Dictionary, source: Dictionary) -> DrawingResult:
	var area: Rect2i = source["coverage"]
	if not area.has_area():
		return DrawingResult.success(area)
	var anchor: Vector2i = link["position"]
	var origin: Vector2i = source["origin"]
	var x: int = int(area.position.x) + int(anchor.x) - int(origin.x)
	var y: int = int(area.position.y) + int(anchor.y) - int(origin.y)
	if not _inside(x, y, area.size.x, area.size.y):
		return DrawingResult.failure("LINK_RANGE", "Object placement exceeds the standalone signed coordinate range")
	area.position = Vector2i(x, y)
	return DrawingResult.success(area)


static func link_coverage(link: Dictionary, sources: Dictionary) -> Rect2i:
	var anchor: Vector2i = link["position"]
	var source_id: String = link["source_id"]
	if sources.has(source_id):
		var translated: DrawingResult = _translated(link, sources[source_id])
		if translated.ok:
			return translated.value
	# A missing source is a conspicuous local marker, not silent blank art.
	return Rect2i(anchor - Vector2i(8, 8), Vector2i(16, 16))
