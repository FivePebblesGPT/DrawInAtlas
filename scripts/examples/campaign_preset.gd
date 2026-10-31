class_name AtlasExampleCampaign
extends Resource

## Bundled, Inspector-editable demonstration data. Saved campaigns still use
## AtlasCampaignStore's validated single-file native .scn format for recovery.
@export var display_name: String = "Northern Marches (sample)"
@export var world: AtlasExampleMap
@export var city: AtlasExampleMap
@export var entrance: AtlasMapLink
@export var entrance_source_cell: Vector2i = Vector2i(2, 0)
