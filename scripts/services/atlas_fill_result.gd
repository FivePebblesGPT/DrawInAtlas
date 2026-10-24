class_name AtlasFillResult
extends RefCounted
## A detached edit snapshot; applying it and choosing a command are caller concerns.

var ok: bool = false
var message: String = ""
var terrain: Dictionary = {}
var layer: AtlasRasterLayer
