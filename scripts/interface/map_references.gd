class_name AtlasMapReferences
extends Node
## T-015: no registered child-board footprints exist in the active editor.
## Keep navigation source selection as UI context, without spatial captures,
## texture caches or in-canvas placement rendering.

var source_link_id: String = ""
var source_floor_id: String = ""
var frozen: bool = false
var omitted_count: int = 0
var _canvas: AtlasCanvas


func bind(canvas: AtlasCanvas) -> void:
	_canvas = canvas


func reset() -> void:
	source_link_id = ""
	source_floor_id = ""
	frozen = false
	omitted_count = 0


func select_source(link_id: String, floor_id: String = "") -> void:
	source_link_id = link_id
	source_floor_id = floor_id
	frozen = false


func set_frozen(value: bool) -> void:
	frozen = value


func refresh() -> void:
	# A link is a navigation marker only; there is nothing to project.
	pass


func draw_parent(_item: CanvasItem) -> void:
	pass


func draw_children(_item: Node2D) -> void:
	pass
