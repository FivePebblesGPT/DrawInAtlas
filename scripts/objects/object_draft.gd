class_name AtlasObjectDraft
extends RefCounted
## Object Editor-owned working copy. Never used by placed-instance rendering.

var document: DrawingDocument
var source_id: String = ""
var source_revision: int = -1
var origin_instance_id: String = ""
var origin_generation: String = ""
var origin_binding_revision: int = -1
var name: String = ""
var origin: Vector2i = Vector2i.ZERO
var bounds: Rect2i = Rect2i()


func _init(source: DrawingDocument = null, asset_id: String = "",
		asset_revision: int = -1, label: String = "") -> void:
	document = source
	source_id = asset_id
	source_revision = asset_revision
	name = label
