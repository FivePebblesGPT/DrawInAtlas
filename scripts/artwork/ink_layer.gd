class_name AtlasInkLayer
extends AtlasLayer

## Canonical ordered objects; indices are transient selection identities and
## can change after edits. Commands copy the objects for before/after snapshots.
@export_storage var strokes: Array[AtlasStroke] = []


func _init(layer_id: String = "ink", layer_name: String = "Ink") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "INK"

func to_dict() -> Dictionary:
	var data: Dictionary = super.to_dict()
	var artwork: Array[Dictionary] = []
	for stroke: AtlasStroke in strokes:
		artwork.append(stroke.to_dict())
	data["strokes"] = artwork
	return data
