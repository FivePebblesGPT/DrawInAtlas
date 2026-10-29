class_name AtlasFloor
extends Resource

@export_storage var id: String = "ground"
@export_storage var display_name: String = "Ground"
@export_storage var layers: Array[AtlasLayer] = [AtlasTileLayer.new(), AtlasInkLayer.new()]

# Compatibility views for the original terrain/ink APIs; ordered layers own the data.
var terrain: Dictionary:
	get:
		var layer: AtlasTileLayer = terrain_layer()
		return layer.terrain if layer != null else {}
	set(value):
		var layer: AtlasTileLayer = terrain_layer()
		if layer != null:
			layer.terrain.assign(value)
var strokes: Array[AtlasStroke]:
	get:
		var layer: AtlasInkLayer = ink_layer()
		return layer.strokes if layer != null else []
	set(value):
		var layer: AtlasInkLayer = ink_layer()
		if layer != null:
			layer.strokes = value


func layer_by_id(layer_id: String) -> AtlasLayer:
	for layer: AtlasLayer in layers:
		if layer.id == layer_id:
			return layer
	return null


func ink_layer() -> AtlasInkLayer:
	for layer: AtlasLayer in layers:
		if layer is AtlasInkLayer:
			return layer
	return null


func terrain_layer() -> AtlasTileLayer:
	for layer: AtlasLayer in layers:
		if layer is AtlasTileLayer:
			return layer
	return null


func paint(cell: Vector2i, palette_id: int) -> void:
	terrain["%d,%d" % [cell.x, cell.y]] = palette_id


func get_terrain(cell: Vector2i) -> int:
	return int(terrain.get("%d,%d" % [cell.x, cell.y], 0))


func to_dict() -> Dictionary:
	var saved: Array[Dictionary] = []
	for layer: AtlasLayer in layers:
		saved.append(layer.to_dict())
	return {"id": id, "name": display_name, "layers": saved}


static func from_dict(data: Dictionary) -> AtlasFloor:
	var floor: AtlasFloor = AtlasFloor.new()
	var floor_id: Variant = data.get("id", "ground")
	var floor_name: Variant = data.get("name", "Ground")
	if not AtlasData.text(floor_id) or not AtlasData.text(floor_name):
		return null
	floor.id = floor_id
	floor.display_name = floor_name
	if data.has("layers"):
		if not data.layers is Array or data.has("terrain") or data.has("strokes"):
			return null
		floor.layers.clear()
		var ids: Dictionary[String, bool] = {}
		for raw: Variant in data.layers:
			if not raw is Dictionary:
				return null
			var layer: AtlasLayer = AtlasLayerCodec.from_dict(raw)
			if layer == null or ids.has(layer.id):
				return null
			ids[layer.id] = true
			floor.layers.append(layer)
		return floor
	var legacy_ink: Dictionary = {"id": "ink", "name": "Ink", "kind": "INK", "strokes": data.get("strokes", [])}
	var legacy_tiles: Dictionary = {"id": "terrain", "name": "Terrain", "kind": "TILES", "terrain": data.get("terrain", {})}
	var ink: AtlasLayer = AtlasLayerCodec.from_dict(legacy_ink)
	var tiles: AtlasLayer = AtlasLayerCodec.from_dict(legacy_tiles)
	if ink == null or tiles == null:
		return null
	floor.layers = [tiles, ink]
	return floor
