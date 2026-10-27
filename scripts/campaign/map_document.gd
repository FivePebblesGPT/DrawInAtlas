class_name AtlasMapDocument
extends Resource

## One independently editable board. Floors own ordered artwork layers.
## grid is the adjustable display overlay; terrain_grid (or a tile layer's
## explicit grid) preserves legacy cell geometry after the overlay is edited.

@export_storage var id: String = ""
@export_storage var display_name: String = ""
@export_storage var kind: String = "REGION"
@export_storage var tags: Array[String] = []
@export_storage var grid: AtlasGrid = AtlasGrid.new()
@export_storage var terrain_grid: AtlasGrid
@export_storage var floors: Array[AtlasFloor] = []
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


## Grid precedence is important for old saves: per-layer snapshot, legacy
## document terrain grid, then the current adjustable overlay.
func get_terrain_grid(floor_id: String = "") -> AtlasGrid:
	var selected_id: String = default_floor_id if floor_id.is_empty() else floor_id
	var floor: AtlasFloor = floor_by_id(selected_id)
	if floor != null and floor.terrain_layer() != null and floor.terrain_layer().grid != null:
		return floor.terrain_layer().grid
	return terrain_grid if terrain_grid != null else grid


func to_dict() -> Dictionary:
	var saved_floors: Array[Dictionary] = []
	for floor in floors:
		var saved: Dictionary = floor.to_dict()
		for layer: Dictionary in saved.layers:
			if layer.kind == "TILES" and layer.grid == null:
				layer.grid = get_terrain_grid(floor.id).to_dict()
		saved_floors.append(saved)
	return {
		"id": id, "name": display_name, "kind": kind, "tags": tags.duplicate(),
		"grid": grid.to_dict(), "terrain_grid": get_terrain_grid().to_dict(), "floors": saved_floors,
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
	var raw_terrain_grid: Variant = data.get("terrain_grid", raw_grid)
	var raw_floors: Variant = data.get("floors", [{"id": "ground", "name": "Ground"}])
	if not raw_grid is Dictionary or not raw_terrain_grid is Dictionary or not raw_floors is Array:
		return null
	map.grid = AtlasGrid.from_dict(raw_grid)
	map.terrain_grid = AtlasGrid.from_dict(raw_terrain_grid)
	if map.grid == null or map.terrain_grid == null:
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
		for layer: AtlasLayer in floor.layers:
			if layer is AtlasTileLayer and layer.grid == null:
				layer.grid = map.terrain_grid.copy()
		map.floors.append(floor)
	if map.floors.is_empty():
		return null
	var default_id: Variant = data.get("default_floor_id", map.floors[0].id)
	if not AtlasData.text(default_id):
		return null
	map.default_floor_id = default_id
	return map if map.floor_by_id(map.default_floor_id) != null else null
