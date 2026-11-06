class_name AtlasObjectAsset
extends RefCounted
## Immutable value handle for a published Object source. No editable document
## escapes the AtlasObjectLibrary; edits use an AtlasObjectDraft instead.

var id: String = ""
var name: String = ""
var revision: int = 0
var relative_path: String = ""
var sha256: String = ""
var origin: Vector2i = Vector2i.ZERO
var bounds: Rect2i = Rect2i()


static func from_record(record: Dictionary) -> AtlasObjectAsset:
	var asset: AtlasObjectAsset = AtlasObjectAsset.new()
	asset.id = record["id"]
	asset.name = record["name"]
	asset.revision = record["revision"]
	asset.relative_path = record["path"]
	asset.sha256 = record["sha256"]
	var origin_values: Array = record.get("origin", [0, 0])
	var bounds_values: Array = record.get("bounds", [0, 0, 0, 0])
	asset.origin = Vector2i(int(origin_values[0]), int(origin_values[1]))
	asset.bounds = Rect2i(int(bounds_values[0]), int(bounds_values[1]),
		int(bounds_values[2]), int(bounds_values[3]))
	return asset
