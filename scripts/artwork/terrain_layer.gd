class_name AtlasTileLayer
extends AtlasLayer

@export_storage var terrain: Dictionary[String, int] = {}
@export_storage var grid: AtlasGrid


func _init(layer_id: String = "terrain", layer_name: String = "Terrain") -> void:
	super(layer_id, layer_name)
	kind = "TILES"


func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	data["terrain"] = terrain.duplicate()
	data["grid"] = grid.to_dict() if grid != null else null
	return data
