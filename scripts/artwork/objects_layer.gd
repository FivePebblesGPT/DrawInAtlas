class_name AtlasObjectsLayer
extends AtlasLayer
## Editable semantic objects. Ordinary brush strokes and shapes belong to raster.

## Ordered objects; the stored field name is retained for resource compatibility.
@export_storage var strokes: Array[AtlasStroke] = []


func _init(layer_id: String = "objects", layer_name: String = "Objects") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "OBJECTS"


func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	var objects: Array[Dictionary] = []
	for object: AtlasStroke in strokes:
		objects.append(object.to_dict())
	data["strokes"] = objects
	return data
