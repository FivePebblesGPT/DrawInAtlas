class_name AtlasOverviewEntry
extends RefCounted
## Detached navigation metadata. A nonempty broken_reason disables opening the target.

var map_id: String = ""
var floor_id: String = ""
var source_map_id: String = ""
var source_floor_id: String = ""
var link_id: String = ""
var caption: String = ""
var breadcrumb: String = ""
var depth: int = 0
var broken_reason: String = ""
var source_focus: Vector2 = Vector2.ZERO
var can_focus: bool = false
