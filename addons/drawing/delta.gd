class_name DrawingDelta
extends RefCounted
## Compact per-pixel canonical RGBA8 changes, detached from live tiles.

var layer_id: String = ""
var before: Dictionary[String, int] = {}
var after: Dictionary[String, int] = {}


func _init(target: String = "", originals: Dictionary[String, int] = {},
		replacements: Dictionary[String, int] = {}) -> void:
	layer_id = target
	before = originals.duplicate()
	after = replacements.duplicate()
