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

## A search result is a snapshot, not permission to navigate an edited graph.
## These values are transient and never included in campaign persistence.
var campaign_instance_id: int = 0
var target_map_instance_id: int = 0
var target_floor_instance_id: int = 0
var source_map_instance_id: int = 0
var source_floor_instance_id: int = 0
var link_snapshot: Dictionary = {}
var placement_snapshot: Dictionary = {}
var source_label_snapshot: String = ""
var path_snapshots: Array[Dictionary] = []
