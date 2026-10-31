class_name AtlasMapDocument
extends Resource

## One independently editable board. Floors own ordered artwork layers.
## The grid is a spatial reference and edit-mask basis, independent of artwork.

@export_storage var id: String = ""
@export_storage var display_name: String = ""
## Legacy map category for independent documents, not an artwork/detail layer.
@export_storage var kind: String = "REGION"
@export_storage var tags: Array[String] = []
## Mutable display/grid-settings overlay, with no authority to move ink pixels.
@export_storage var grid: AtlasGrid = AtlasGrid.new()
## Canonical ordered floor contents; each floor independently owns its layers.
@export_storage var floors: Array[AtlasFloor] = []
## Saved default floor ID; opening a different floor is session-only view state.
@export_storage var default_floor_id: String = "ground"


func _init(map_id: String = "", map_name: String = "") -> void:
	id = map_id
	display_name = map_name
	floors.append(AtlasFloor.new())


func floor_by_id(floor_id: String) -> AtlasFloor:
	for floor in floors:
		if floor.id == floor_id:
			return floor
	return null


func to_dict() -> Dictionary:
	var saved_floors: Array[Dictionary] = []
	for floor: AtlasFloor in floors:
		saved_floors.append(floor.to_dict())
	return {
		"id": id, "name": display_name, "kind": kind, "tags": tags.duplicate(),
		"grid": grid.to_dict(), "floors": saved_floors,
		"default_floor_id": default_floor_id
	}


static func from_dict(data: Dictionary) -> AtlasMapDocument:
	var map_id: Variant = data.get("id")
	var map_name: Variant = data.get("name", map_id)
	var map_kind: Variant = data.get("kind", "REGION")
	if not AtlasData.text(map_id) or not AtlasData.text(map_name) or not AtlasData.text(map_kind):
		return null
	var map: AtlasMapDocument = AtlasMapDocument.new(map_id, map_name)
	map.kind = map_kind
	var raw_tags: Variant = data.get("tags", [])
	if not raw_tags is Array or raw_tags.size() > 128:
		return null
	var seen_tags: Dictionary[String, bool] = {}
	for value: Variant in raw_tags:
		if not AtlasData.text(value) or seen_tags.has(value.to_lower()):
			return null
		seen_tags[value.to_lower()] = true
		map.tags.append(value)
	var raw_grid: Variant = data.get("grid", {})
	var raw_floors: Variant = data.get("floors", [AtlasFloor.new().to_dict()])
	if not raw_grid is Dictionary or not raw_floors is Array or data.has("terrain_grid"):
		return null
	map.grid = AtlasGrid.from_dict(raw_grid)
	if map.grid == null:
		return null
	map.floors.clear()
	var floor_ids: Dictionary[String, bool] = {}
	for saved_floor: Variant in raw_floors:
		if not saved_floor is Dictionary:
			return null
		var floor: AtlasFloor = AtlasFloor.from_dict(saved_floor)
		if floor == null or floor_ids.has(floor.id):
			return null
		floor_ids[floor.id] = true
		map.floors.append(floor)
	if map.floors.is_empty():
		return null
	var default_id: Variant = data.get("default_floor_id", map.floors[0].id)
	if not AtlasData.text(default_id):
		return null
	map.default_floor_id = default_id
	return map if map.floor_by_id(map.default_floor_id) != null else null
