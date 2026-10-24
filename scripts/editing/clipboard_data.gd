class_name AtlasClipboardData
extends RefCounted
## Detached document-space artwork; the caller chooses its destination and placement.

var kind: String = ""
var strokes: Array[AtlasStroke] = []
var raster: AtlasRasterLayer
var tiles: Dictionary = {}
var grid: AtlasGrid
