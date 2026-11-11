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


## Internal handoff for freshly built, unaliased publication maps only.
## Public construction intentionally continues to detach caller-owned maps.
static func from_owned_maps(target: String, originals: Dictionary[String, int],
		replacements: Dictionary[String, int]) -> DrawingDelta:
	var result: DrawingDelta = DrawingDelta.new(target)
	result.before = originals
	result.after = replacements
	return result
