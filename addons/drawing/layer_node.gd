class_name DrawingLayerNode
extends RefCounted
## Plain generic metadata; group children ordered by stable ID, not display name.

const GROUP: String = "group"
const RASTER: String = "raster"
const TEXT: String = "text"
const OBJECTS: String = "objects"

var id: String = ""
var parent_id: String = ""
var kind: String = ""
var name: String = ""
var visible: bool = true
var locked: bool = false
var children: Array[String] = []
var tiles: Dictionary[String, DrawingRasterTile] = {}
var objects: Dictionary[String, Dictionary] = {}
var text_value: String = ""
var text_element: DrawingTextElement


func _init(identifier: String = "", layer_kind: String = GROUP,
		label: String = "", parent: String = "") -> void:
	id = identifier
	kind = layer_kind
	name = label
	parent_id = parent


func detached_copy() -> DrawingLayerNode:
	var result: DrawingLayerNode = DrawingLayerNode.new(id, kind, name, parent_id)
	result.visible = visible
	result.locked = locked
	result.children = children.duplicate()
	result.text_value = text_value
	result.text_element = text_element.detached_copy() if text_element != null else null
	result.objects = objects.duplicate(true)
	for key: String in tiles:
		result.tiles[key] = tiles[key].detached_copy()
	return result
