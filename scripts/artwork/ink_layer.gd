class_name AtlasInkLayer
extends AtlasObjectsLayer
## Deprecated resource type, retained to read prototype saves. New authoring uses
## AtlasObjectsLayer for semantic objects and AtlasRasterLayer for all drawing.

func _init(layer_id: String = "ink", layer_name: String = "Ink") -> void:
	super(layer_id, layer_name)


func layer_kind() -> String:
	return "INK"
