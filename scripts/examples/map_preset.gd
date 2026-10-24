class_name AtlasExampleMap
extends Resource

## Inspector-editable map in the bundled sample campaign (not the runtime model).
## Terrain keys are axial/square "x,y" cells, and values are palette IDs.
@export var document_id: String = ""
@export var display_name: String = ""
@export var kind: String = "REGION"
@export var grid: AtlasGrid
@export var terrain_cells: Dictionary[String, int] = {}


func create_document() -> AtlasMapDocument:
    var document: AtlasMapDocument = AtlasMapDocument.new(document_id, display_name)
    document.kind = kind
    # The editor may change the grid or tiles; never mutate the shared .tres.
    document.grid = grid.copy()
    document.floors[0].terrain = terrain_cells.duplicate()
    return document
