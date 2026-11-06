class_name AtlasObjectInstance
extends RefCounted
## One independent map placement, not a Drawing layer or raster copy.

var id: String = ""
var generation: String = ""
var source_id: String = ""
var map_id: String = ""
var floor_id: String = ""
var detail_id: String = ""
var transform: Transform2D = Transform2D.IDENTITY
var visible: bool = true
var placeholder: bool = false
var revision: int = 0
var metadata: Dictionary = {}


func as_record() -> Dictionary:
	return {"id": id, "generation": generation, "source_id": source_id,
		"map_id": map_id, "floor_id": floor_id, "detail_id": detail_id,
		"transform": [transform.x.x, transform.x.y, transform.y.x,
			transform.y.y, transform.origin.x, transform.origin.y],
		"visible": visible, "placeholder": placeholder, "revision": revision,
		"metadata": metadata.duplicate(true)}


static func from_record(record: Dictionary) -> AtlasObjectInstance:
	var instance: AtlasObjectInstance = AtlasObjectInstance.new()
	instance.id = record["id"]
	instance.generation = record["generation"]
	instance.source_id = record["source_id"]
	instance.map_id = record["map_id"]
	instance.floor_id = record["floor_id"]
	instance.detail_id = record["detail_id"]
	var values: Array = record["transform"]
	instance.transform = Transform2D(Vector2(float(values[0]), float(values[1])),
		Vector2(float(values[2]), float(values[3])),
		Vector2(float(values[4]), float(values[5])))
	instance.visible = record["visible"]
	instance.placeholder = record["placeholder"]
	instance.revision = record["revision"]
	instance.metadata = (record.get("metadata", {}) as Dictionary).duplicate(true)
	return instance
