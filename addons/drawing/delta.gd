class_name DrawingDelta
extends RefCounted
## Compact per-pixel canonical RGBA8 changes, detached from live tiles.

var layer_id: String = ""
var before: Dictionary[String, int] = {}
var after: Dictionary[String, int] = {}
## A native raster gesture carries full reversible RGBA8 storage tiles instead
## of one global String key per changed pixel. Empty bytes mean absent/blank.
var tile_stride: int = 0
var before_tiles: Dictionary[String, PackedByteArray] = {}
var after_tiles: Dictionary[String, PackedByteArray] = {}


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


## The publisher owns these detached snapshots; no caller retains mutable
## aliases to its PackedByteArray values. Other edit APIs keep pixel deltas.
static func from_owned_tile_bytes(target: String, stride: int,
		originals: Dictionary[String, PackedByteArray],
		replacements: Dictionary[String, PackedByteArray]) -> DrawingDelta:
	var result: DrawingDelta = DrawingDelta.new(target)
	result.tile_stride = stride
	result.before_tiles = originals
	result.after_tiles = replacements
	return result
