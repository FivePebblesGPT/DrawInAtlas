class_name AtlasLayer
extends Resource

@export_storage var id: String
@export_storage var display_name: String
@export_storage var kind: String
@export_storage var visible: bool = true
@export_storage var locked: bool = false
@export_storage var opacity: float = 1.0


func _init(layer_id: String = "", layer_name: String = "") -> void:
	id = layer_id
	display_name = layer_name


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "kind": kind,
		"visible": visible, "locked": locked, "opacity": opacity}


func is_editable() -> bool:
	return visible and not locked
