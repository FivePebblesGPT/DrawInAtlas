class_name AtlasDrawingRegistry
extends RefCounted
## Atlas owns map/floor/detail identity. Each detail resolves exactly one generic
## DrawingDocument; collapsed groups and blank detail allocate no Drawing images.

const INDEX_SCHEMA: String = "atlas-drawing-index-v1"
const MAX_DETAIL: int = 32
const MAX_FLOORS: int = 256
const MAX_MAPS: int = 1024
const MAX_STRIDE: int = 2048

var _maps: Dictionary = {} # map ID -> ordered floor records
var _documents: Dictionary[String, DrawingDocument] = {}
var _ids: Dictionary[String, bool] = {}
## Keep deleted-floor records in memory for undo, but never project/save them.
var _orphan_floors: Dictionary[String, Dictionary] = {}


func attach_campaign(campaign: AtlasCampaign) -> DrawingResult:
	if campaign == null or campaign.maps.size() > MAX_MAPS:
		return DrawingResult.failure("CAMPAIGN", "Invalid campaign")
	# Validate the complete campaign before mutating any registry groups.
	for map_id: String in campaign.maps:
		var map: AtlasMapDocument = campaign.get_map(map_id)
		if map == null or map.id != map_id or not DrawingDocument.valid_identifier(map_id) \
				or map.floors.size() > MAX_FLOORS:
			return DrawingResult.failure("MAP", "Invalid map or floors")
		var seen_ids: Dictionary = {}
		for floor: AtlasFloor in map.floors:
			if floor == null or not DrawingDocument.valid_identifier(floor.id) or seen_ids.has(floor.id):
				return DrawingResult.failure("FLOOR", "Invalid or duplicate floor")
			seen_ids[floor.id] = true
	for map_id: String in campaign.maps:
		var map: AtlasMapDocument = campaign.get_map(map_id)
		var existing: Array = _maps.get(map_id, [])
		var ordered: Array[Dictionary] = []
		var seen: Dictionary = {}
		for floor: AtlasFloor in map.floors:
			if floor == null or not DrawingDocument.valid_identifier(floor.id) or seen.has(floor.id):
				return DrawingResult.failure("FLOOR", "Invalid or duplicate floor")
			seen[floor.id] = true
			var record: Dictionary = _floor(existing, floor.id)
			if record.is_empty() and _orphan_floors.has(map_id + "/" + floor.id):
				record = _orphan_floors[map_id + "/" + floor.id]
				_orphan_floors.erase(map_id + "/" + floor.id)
			if record.is_empty():
				record = {"id": floor.id, "name": floor.display_name, "visible": true, "details": []}
			record["name"] = floor.display_name
			if _level(record, 0).is_empty():
				_create_detail(record, 0, 1, 1, 256)
			ordered.append(record)
		# A removed floor may be restored by undo without generating new IDs.
		# Do not project or export it while it is absent from the campaign.
		for record: Dictionary in existing:
			if not seen.has(record["id"]):
				_orphan_floors[map_id + "/" + record["id"]] = record
		_maps[map_id] = ordered
	return DrawingResult.success()


func _floor(floors: Array, floor_id: String) -> Dictionary:
	for record: Dictionary in floors:
		if record["id"] == floor_id:
			return record
	return {}


func _level(floor: Dictionary, detail: int) -> Dictionary:
	for record: Dictionary in floor.get("details", []):
		if record["level"] == detail:
			return record
	return {}


func _record(map_id: String, floor_id: String, detail: int) -> Dictionary:
	return _level(_floor(_maps.get(map_id, []), floor_id), detail)


func _create_detail(floor: Dictionary, level: int, num: int, den: int, stride: int) -> String:
	var id: String = DrawingDocument.new_id()
	while _ids.has(id):
		id = DrawingDocument.new_id()
	_ids[id] = true
	(floor["details"] as Array).append({"id": "D%d" % level, "level": level,
		"document_id": id, "num": num, "den": den, "stride": stride, "visible": true})
	(floor["details"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["level"] < b["level"])
	return id


func ensure_detail(map_id: String, floor_id: String, level: int,
		num: int = 0, den: int = 1, stride: int = 256) -> DrawingResult:
	var floor: Dictionary = _floor(_maps.get(map_id, []), floor_id)
	if floor.is_empty() or level < 0 or level > MAX_DETAIL:
		return DrawingResult.failure("DETAIL", "Unknown floor or invalid detail")
	var existing: Dictionary = _level(floor, level)
	if not existing.is_empty():
		return DrawingResult.success(existing["document_id"])
	var density: int = num if num > 0 else AtlasWorldSpace.default_density(level)
	if not AtlasWorldSpace.valid_density(density, den) or stride <= 0 or stride > MAX_STRIDE:
		return DrawingResult.failure("DETAIL", "Invalid density or stride")
	return DrawingResult.success(_create_detail(floor, level, density, den, stride))


func set_density(map_id: String, floor_id: String, level: int, num: int, den: int) -> DrawingResult:
	var record: Dictionary = _record(map_id, floor_id, level)
	if record.is_empty() or not AtlasWorldSpace.valid_density(num, den):
		return DrawingResult.failure("DENSITY", "Unknown detail or invalid density")
	var doc: DrawingDocument = _documents.get(record["document_id"])
	if doc != null:
		var changed: DrawingResult = doc.set_density(num, den)
		if not changed.ok:
			return changed
	record["num"] = num
	record["den"] = den
	return DrawingResult.success()


func set_visibility(map_id: String, floor_id: String, level: int, visible: bool) -> DrawingResult:
	var floor: Dictionary = _floor(_maps.get(map_id, []), floor_id)
	if floor.is_empty():
		return DrawingResult.failure("FLOOR", "Unknown floor")
	if level == -1:
		floor["visible"] = visible
		return DrawingResult.success()
	var detail: Dictionary = _level(floor, level)
	if detail.is_empty():
		return DrawingResult.failure("DETAIL", "Unknown detail")
	detail["visible"] = visible
	return DrawingResult.success()


func document_at(map_id: String, floor_id: String, level: int, materialize: bool = false) -> DrawingResult:
	var record: Dictionary = _record(map_id, floor_id, level)
	if record.is_empty():
		return DrawingResult.failure("DETAIL", "Unknown detail")
	var id: String = record["document_id"]
	if materialize and not _documents.has(id):
		var document: DrawingDocument = DrawingDocument.new(id, record["stride"], record["num"], record["den"])
		document.set_external_history(true)
		_documents[id] = document
	return DrawingResult.success(_documents.get(id))


func document_count() -> int:
	return _documents.size()


func _blank(document: DrawingDocument) -> bool:
	if document == null:
		return true
	var manifest: DrawingResult = document.export_manifest()
	if not manifest.ok:
		return false
	for layer: Dictionary in manifest.value["layers"]:
		if not (layer["chunks"] as Array).is_empty() or layer["text_element"] != null \
				or not (layer["objects"] as Dictionary).is_empty():
			return false
	return true


func projection(map_id: String) -> Array[Dictionary]:
	var projected: Array[Dictionary] = []
	for floor: Dictionary in _maps.get(map_id, []):
		var details: Array[Dictionary] = []
		for detail: Dictionary in floor["details"]:
			var document: DrawingDocument = _documents.get(detail["document_id"])
			var layers: Array[String] = []
			if document != null:
				layers = document.list_children()
			details.append({"id": detail["id"], "document_id": detail["document_id"],
				"level": detail["level"], "density": [detail["num"], detail["den"]],
				"visible": floor["visible"] and detail["visible"], "blank": _blank(document),
				"layers": layers})
		projected.append({"id": floor["id"], "name": floor["name"],
			"visible": floor["visible"], "details": details})
	return projected


func render_detail(map_id: String, floor_id: String, level: int, view: Rect2i,
		max_pixels: int = 1048576) -> DrawingResult:
	var detail: Dictionary = _record(map_id, floor_id, level)
	if detail.is_empty():
		return DrawingResult.failure("DETAIL", "Unknown detail")
	if view.size.x <= 0 or view.size.y <= 0 or view.size.x > max_pixels \
			or view.size.y > max_pixels / view.size.x:
		return DrawingResult.failure("RENDER_LIMIT", "Viewport must be bounded")
	return render_detail_at(map_id, floor_id, level, view, 0, 0, max_pixels)


## Bounded viewport with a signed 64-bit pixel anchor. The local view stays
## small while raster source positions can be trillions of pixels away.
func render_detail_at(map_id: String, floor_id: String, level: int,
		local_view: Rect2i, pixel_anchor_x: int, pixel_anchor_y: int,
		max_pixels: int = 1048576) -> DrawingResult:
	var detail: Dictionary = _record(map_id, floor_id, level)
	if detail.is_empty():
		return DrawingResult.failure("DETAIL", "Unknown detail")
	if local_view.size.x <= 0 or local_view.size.y <= 0 or local_view.size.x > max_pixels \
			or local_view.size.y > max_pixels / local_view.size.x:
		return DrawingResult.failure("RENDER_LIMIT", "Viewport must be bounded")
	if abs(pixel_anchor_x) > AtlasWorldSpace.MAX_PIXELS or abs(pixel_anchor_y) > AtlasWorldSpace.MAX_PIXELS:
		return DrawingResult.failure("COORD_RANGE", "Invalid signed pixel anchor")
	var floor: Dictionary = _floor(_maps.get(map_id, []), floor_id)
	var document: DrawingDocument = _documents.get(detail["document_id"])
	if not floor["visible"] or not detail["visible"] or _blank(document):
		return DrawingResult.success(Image.create_empty(local_view.size.x, local_view.size.y,
			false, Image.FORMAT_RGBA8))
	return DrawingRenderer.render(document, local_view, pixel_anchor_x, pixel_anchor_y, max_pixels)


## Object Assets are NOT map background layers: their explicit detail_id
## controls visibility, with no automatic D0 placement fallback at D1/D32.
func visible_placements(library: AtlasObjectLibrary, map_id: String,
		floor_id: String, level: int) -> Array[String]:
	var result: Array[String] = []
	if library == null or _record(map_id, floor_id, level).is_empty():
		return result
	var floor: Dictionary = _floor(_maps.get(map_id, []), floor_id)
	var detail: Dictionary = _record(map_id, floor_id, level)
	if not floor["visible"] or not detail["visible"]:
		return result
	for instance_id: String in library.instance_ids():
		var record: Dictionary = library.instance_info(instance_id)
		if record.get("map_id") == map_id and record.get("floor_id") == floor_id \
				and record.get("detail_id") == "D%d" % level and record.get("visible", false) \
				and not record.get("placeholder", false) and record.get("status") == "linked":
			result.append(instance_id)
	return result


func begin_gesture(map_id: String, floor_id: String, level: int, layer: String,
		anchor_x: int = 0, anchor_y: int = 0) -> DrawingResult:
	var floor: Dictionary = _floor(_maps.get(map_id, []), floor_id)
	var detail: Dictionary = _record(map_id, floor_id, level)
	if detail.is_empty() or not floor["visible"] or not detail["visible"]:
		return DrawingResult.failure("HIDDEN", "Editing an invisible detail group is not allowed")
	var found: DrawingResult = document_at(map_id, floor_id, level, true)
	if not found.ok:
		return found
	var doc: DrawingDocument = found.value
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, anchor_x, anchor_y)
	if not begun.ok:
		return begun
	return DrawingResult.success({"document": doc, "document_id": doc.id,
		"level": level, "session": begun.value})


func begin_world_gesture(map_id: String, floor_id: String, level: int,
		layer: String, world_x_ticks: int, world_y_ticks: int) -> DrawingResult:
	var record: Dictionary = _record(map_id, floor_id, level)
	if record.is_empty():
		return DrawingResult.failure("DETAIL", "Unknown authored detail")
	var anchor: DrawingResult = AtlasWorldSpace.point_to_pixels(world_x_ticks, world_y_ticks,
		record["num"], record["den"])
	if not anchor.ok:
		return anchor
	return begin_gesture(map_id, floor_id, level, layer, anchor.value["x"], anchor.value["y"])


func export_index() -> Dictionary:
	var saved: Array[Dictionary] = []
	var ids: Array = _maps.keys()
	ids.sort()
	for map_id: String in ids:
		var floors: Array[Dictionary] = []
		for floor: Dictionary in _maps[map_id]:
			floors.append(floor.duplicate(true))
		saved.append({"id": map_id, "floors": floors})
	return {"schema": INDEX_SCHEMA, "world_ticks_per_unit": AtlasWorldSpace.TICKS_PER_UNIT,
		"maps": saved}


static func _integral(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= float(minimum) and float(value) <= float(maximum) \
		and floorf(float(value)) == float(value)


static func from_index(index: Dictionary, campaign: AtlasCampaign) -> DrawingResult:
	if campaign == null or index.get("schema") != INDEX_SCHEMA \
			or index.get("world_ticks_per_unit") != AtlasWorldSpace.TICKS_PER_UNIT \
			or not index.get("maps") is Array or index["maps"].size() > MAX_MAPS:
		return DrawingResult.failure("INDEX", "Invalid Drawing index header")
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	var seen_maps: Dictionary = {}
	for saved_map: Variant in index["maps"]:
		if not saved_map is Dictionary or not saved_map.get("floors") is Array \
				or saved_map["floors"].size() > MAX_FLOORS:
			return DrawingResult.failure("INDEX", "Invalid map record")
		var map_id: String = str(saved_map.get("id", ""))
		if not DrawingDocument.valid_identifier(map_id) or seen_maps.has(map_id) or campaign.get_map(map_id) == null:
			return DrawingResult.failure("INDEX", "Duplicate or unknown map ID")
		seen_maps[map_id] = true
		var floors: Array[Dictionary] = []
		var seen_floors: Dictionary = {}
		for floor: Variant in saved_map["floors"]:
			if not floor is Dictionary or not floor.get("details") is Array \
					or floor["details"].size() > MAX_DETAIL + 1 or not floor.get("name") is String \
					or not floor.get("visible") is bool:
				return DrawingResult.failure("INDEX", "Invalid floor record")
			var floor_id: String = str(floor.get("id", ""))
			if seen_floors.has(floor_id) or campaign.get_map(map_id).floor_by_id(floor_id) == null:
				return DrawingResult.failure("INDEX", "Unknown or duplicate floor")
			seen_floors[floor_id] = true
			var details: Array[Dictionary] = []
			var levels: Dictionary = {}
			for detail: Variant in floor["details"]:
				if not detail is Dictionary:
					return DrawingResult.failure("INDEX", "Invalid detail")
				var level: Variant = detail.get("level")
				var id: Variant = detail.get("document_id")
				var num: Variant = detail.get("num")
				var den: Variant = detail.get("den")
				var stride: Variant = detail.get("stride")
				if not _integral(level, 0, MAX_DETAIL) or not id is String \
						or not _integral(num, 1, AtlasWorldSpace.MAX_DENSITY) \
						or not _integral(den, 1, AtlasWorldSpace.MAX_DENSITY) \
						or not _integral(stride, 1, MAX_STRIDE):
					return DrawingResult.failure("INDEX", "Invalid detail scalar")
				level = int(level)
				num = int(num)
				den = int(den)
				stride = int(stride)
				if levels.has(level) or detail.get("id") != "D%d" % level \
						or not DrawingDocument.valid_identifier(id) or registry._ids.has(id) \
						or not detail.get("visible") is bool:
					return DrawingResult.failure("INDEX", "Invalid detail identity")
				levels[level] = true
				registry._ids[id] = true
				var normalized: Dictionary = detail.duplicate(true)
				normalized["level"] = level
				normalized["num"] = num
				normalized["den"] = den
				normalized["stride"] = stride
				details.append(normalized)
			if not levels.has(0):
				return DrawingResult.failure("INDEX", "Missing D0")
			details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["level"] < b["level"])
			floors.append({"id": floor_id, "name": floor["name"],
				"visible": floor["visible"], "details": details})
		registry._maps[map_id] = floors
	var synchronized: DrawingResult = registry.attach_campaign(campaign)
	return DrawingResult.success(registry) if synchronized.ok else synchronized


func attach_loaded_document(map_id: String, floor_id: String, level: int, doc: DrawingDocument) -> DrawingResult:
	var record: Dictionary = _record(map_id, floor_id, level)
	if record.is_empty() or doc == null or doc.id != record["document_id"] \
			or doc.tile_stride != record["stride"] or doc.density_numerator != record["num"] \
			or doc.density_denominator != record["den"]:
		return DrawingResult.failure("DOCUMENT", "Mismatched document and detail identities")
	if _documents.has(doc.id) and _documents[doc.id] != doc:
		return DrawingResult.failure("DOCUMENT", "Document ID is already live")
	var history: DrawingResult = doc.set_external_history(true)
	if not history.ok:
		return history
	_documents[doc.id] = doc
	return DrawingResult.success()
