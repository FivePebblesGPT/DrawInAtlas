class_name AtlasInkLayer
extends AtlasLayer

@export_storage var strokes: Array[AtlasStroke] = []


func _init(layer_id: String = "ink", layer_name: String = "Ink") -> void:
	super(layer_id, layer_name)
	kind = "INK"


func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	var artwork: Array[Dictionary] = []
	for stroke: AtlasStroke in strokes:
		artwork.append(stroke.to_dict())
	data["strokes"] = artwork
	return data
