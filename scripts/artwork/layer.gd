class_name AtlasLayer
extends Resource

## Stable within one floor; editing history and viewer selection refer to this ID,
## never the display name or position in the ordered layer list.
@export_storage var id: String
@export_storage var display_name: String
## Runtime type comes from the Resource class. `kind` is a read-only-in-practice
## compatibility discriminator for existing native saves and dictionary/clipboard
## boundaries, not a second mutable source of type truth.
## Old native files still write this property; reject a mismatched serialized
## value instead of silently interpreting the resource as another layer type.
var _type_marker_valid: bool = true
@export_storage var kind: String:
	get:
		return layer_kind()
	set(value):
		_type_marker_valid = value == layer_kind()
@export_storage var visible: bool = true
@export_storage var locked: bool = false
## Persisted compositing opacity in [0, 1], separate from each stroke's alpha.
@export_storage var opacity: float = 1.0
## Authored artwork group, not a coordinate transform or an independent board.
## Different detail levels on the same floor use the same document coordinates.
## Authored D0–D32 group ID, not a zoom multiplier. All groups share board space.
@export_storage var detail_level: int = 0

const MAX_DETAIL_LEVEL: int = 32


func _init(layer_id: String = "", layer_name: String = "") -> void:
	id = layer_id
	display_name = layer_name


## Subclasses report their wire-format discriminator; the class owns the type.
func layer_kind() -> String:
	return ""


func has_valid_type_marker() -> bool:
	return _type_marker_valid and not layer_kind().is_empty()


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "kind": kind,
		"visible": visible, "locked": locked, "opacity": opacity,
		"detail_level": detail_level}


func is_editable() -> bool:
	return visible and not locked
