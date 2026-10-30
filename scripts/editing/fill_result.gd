class_name AtlasFillResult
extends RefCounted
## A detached edit snapshot; applying it and choosing a command are caller concerns.

var ok: bool = false
var message: String = ""
## Detached candidate for a terrain fill: "x,y"/"q,r" -> palette ID.
var terrain: Dictionary = {}
## Detached cloned raster layer for a pixel fill; caller commits atomically.
var layer: AtlasRasterLayer
