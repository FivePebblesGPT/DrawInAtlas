class_name AtlasPreviewCache
extends RefCounted
## Editor artwork snapshots. Audience partitions entries; it does not filter content.

var _max_entries: int
## Derived rendered previews keyed by audience/map/view; not canonical art.
var _entries: Dictionary[String, Dictionary] = {}
## Least-recently-used key order, not a persisted order of saved documents.
var _lru: Array[String] = []


func _init(max_entries: int = 16) -> void:
	_max_entries = maxi(0, max_entries)


func signature(document: AtlasMapDocument, floor_id: String) -> String:
	if document == null:
		return ""
	var floor: AtlasFloor = document.floor_by_id(floor_id)
	if floor == null:
		return ""
	var layers: Array[Dictionary] = []
	for layer: AtlasLayer in floor.layers:
		if not layer.visible or layer.opacity <= 0.0:
			continue
		var saved: Dictionary = layer.to_dict()
		if layer is AtlasRasterLayer:
			# Asset hashes cover in-place pixel edits; residency affects what can be drawn.
			var resident: Array[bool] = []
			var keys: Array[String] = layer.chunks.keys()
			keys.sort()
			for key: String in keys:
				resident.append(layer.chunks[key].image != null)
			saved["resident"] = resident
		layers.append(saved)
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([document.id, document.display_name, floor.id, floor.display_name, layers]))
	return context.finish().hex_encode()


func get_image(document: AtlasMapDocument, floor_id: String,
		size: Vector2i = Vector2i(192, 128), audience: String = "editor") -> Image:
	if not _valid_request(document, floor_id, size):
		return null
	var key: String = _key(document.id, floor_id, size, audience)
	if not _entries.has(key):
		return null
	if _entries[key].signature != signature(document, floor_id):
		_entries.erase(key)
		_lru.erase(key)
		return null
	_touch(key)
	return _entries[key].image.duplicate() as Image


func put_image(document: AtlasMapDocument, floor_id: String, size: Vector2i,
		image: Image, audience: String = "editor") -> void:
	if _max_entries == 0 or not _valid_request(document, floor_id, size):
		return
	if image == null or image.is_empty() or image.get_size() != size:
		return
	var key: String = _key(document.id, floor_id, size, audience)
	_entries[key] = {"map_id": document.id, "signature": signature(document, floor_id),
		"image": image.duplicate()}
	_touch(key)
	while _lru.size() > _max_entries:
		_entries.erase(_lru.pop_front())


func invalidate(map_id: String = "") -> void:
	for key: String in _entries.keys():
		if map_id.is_empty() or _entries[key].map_id == map_id:
			_entries.erase(key)
			_lru.erase(key)


func entry_count() -> int:
	return _entries.size()


func _valid_request(document: AtlasMapDocument, floor_id: String, size: Vector2i) -> bool:
	return (document != null and size.x > 0 and size.y > 0
		and document.floor_by_id(floor_id) != null)


func _key(map_id: String, floor_id: String, size: Vector2i, audience: String) -> String:
	# Structured strings preserve boundaries, including Unicode, quotes and newlines.
	return JSON.stringify([map_id, floor_id, size.x, size.y, audience])


func _touch(key: String) -> void:
	_lru.erase(key)
	_lru.append(key)
