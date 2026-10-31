class_name AtlasClipboardData
extends RefCounted
## Detached document-space artwork; the caller chooses its destination and placement.

## Interchange discriminator for ink or raster content.
var kind: String = ""
## Detached editable copies in board units relative to the copied anchor.
## Paste adds its chosen destination; nothing points back to the source layer.
var strokes: Array[AtlasStroke] = []
var raster: AtlasRasterLayer
