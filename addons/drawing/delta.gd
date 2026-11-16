class_name DrawingDelta
extends RefCounted
## Compact per-pixel canonical RGBA8 changes, detached from live tiles.

var layer_id: String = ""
var before: Dictionary[String, int] = {}
var after: Dictionary[String, int] = {}
## A native raster gesture carries full reversible RGBA8 storage tiles instead
## of one global String key per changed pixel. Empty bytes mean absent/blank.
var tile_stride: int = 0
## Persistent Rust history identity. Zero means a legacy or detached
## tile snapshot that must be replayed through the document projection.
var native_history_token: int = 0
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


## Freeze one history payload for a second owner (e.g. Atlas's global
## timeline). Native whole-tile deltas must never be downgraded to the legacy
## per-pixel maps, nor share mutable RGBA8 buffers with the commit result.
func detached_copy() -> DrawingDelta:
	var copy: DrawingDelta = DrawingDelta.new(layer_id, before, after)
	copy.tile_stride = tile_stride
	copy.native_history_token = native_history_token
	for key: String in before_tiles:
		copy.before_tiles[key] = before_tiles[key].duplicate()
	for key: String in after_tiles:
		copy.after_tiles[key] = after_tiles[key].duplicate()
	return copy
