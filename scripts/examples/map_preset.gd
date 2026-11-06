class_name AtlasExampleMap
extends Resource

## Inspector-editable map in the bundled sample campaign (not the runtime model).
@export var document_id: String = ""
@export var display_name: String = ""
@export var kind: String = "REGION"
@export var grid: AtlasGrid


func create_document() -> AtlasMapDocument:
	var document: AtlasMapDocument = AtlasMapDocument.new(document_id, display_name)
	document.kind = kind
	# Never mutate the shared grid Resource when a board is edited.
	document.grid = grid.copy()
	return document
