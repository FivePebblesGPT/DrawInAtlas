class_name AtlasClipboardData
extends RefCounted
## Detached document-space artwork; the caller chooses its destination and placement.

## Interchange discriminator for exactly one of ink, raster or terrain content.
var kind: String = ""
## Detached editable copies in board units relative to the copied anchor.
## Paste adds its chosen destination; nothing points back to the source layer.
var strokes: Array[AtlasStroke] = []
var raster: AtlasRasterLayer
## Sparse terrain cell-coordinate/palette mapping; use grid to interpret keys.
var tiles: Dictionary = {}
var grid: AtlasGrid
