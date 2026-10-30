## Grid-indexed terrain palette cells; not a Godot TileMap or a board transform.
## `grid` is the historical cell basis (the display overlay may change).
class_name AtlasTerrainLayer
extends AtlasLayer

@export_storage var terrain: Dictionary[String, int] = {}
@export_storage var grid: AtlasGrid


func _init(layer_id: String = "terrain", layer_name: String = "Terrain") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "TILES"

func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	data["terrain"] = terrain.duplicate()
	data["grid"] = grid.to_dict() if grid != null else null
	return data
