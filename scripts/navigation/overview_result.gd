class_name AtlasOverviewResult
extends RefCounted

var entries: Array[AtlasOverviewEntry] = []
var truncated: bool = false
## Unique map/floor pairs considered, including the active source in graph modes.
var visited_count: int = 0
var message: String = ""
