class_name AtlasObjectAsset
extends RefCounted
## Immutable value handle for a published Object source. No editable document
## escapes the AtlasObjectLibrary; edits use an AtlasObjectDraft instead.

var id: String = ""
var name: String = ""
var revision: int = 0
var relative_path: String = ""
var sha256: String = ""


static func from_record(record: Dictionary) -> AtlasObjectAsset:
	var asset: AtlasObjectAsset = AtlasObjectAsset.new()
	asset.id = record["id"]
	asset.name = record["name"]
	asset.revision = record["revision"]
	asset.relative_path = record["path"]
	asset.sha256 = record["sha256"]
	return asset
