class_name AtlasLayer
extends RefCounted

var id: String
var display_name: String
var kind: String
var visible: bool = true
var locked: bool = false
var opacity: float = 1.0


func _init(layer_id: String = "", layer_name: String = "") -> void:
    id = layer_id
    display_name = layer_name


func to_dict() -> Dictionary:
    return {"id": id, "name": display_name, "kind": kind,
        "visible": visible, "locked": locked, "opacity": opacity}


func is_editable() -> bool:
    return visible and not locked
