class_name AtlasMapLink
extends RefCounted

var id: String = ""
var source_map_id: String = ""
var target_map_id: String = ""
var anchor: Vector2 = Vector2.ZERO
var hit_radius: float = 48.0
var target_focus: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0
var target_floor_id: String = "ground"
var placement_id: String = ""


func to_dict() -> Dictionary:
    return {
        "id": id, "source_map_id": source_map_id, "target_map_id": target_map_id,
        "anchor": [anchor.x, anchor.y], "hit_radius": hit_radius,
        "target_focus": [target_focus.x, target_focus.y],
        "target_zoom": target_zoom, "target_floor_id": target_floor_id,
        "placement_id": placement_id
    }


static func from_dict(data: Dictionary) -> AtlasMapLink:
    var link := AtlasMapLink.new()
    link.id = str(data.get("id", ""))
    link.source_map_id = str(data.get("source_map_id", ""))
    link.target_map_id = str(data.get("target_map_id", ""))
    var source: Array = data.get("anchor", [0.0, 0.0])
    var target: Array = data.get("target_focus", [0.0, 0.0])
    link.anchor = Vector2(float(source[0]), float(source[1]))
    link.target_focus = Vector2(float(target[0]), float(target[1]))
    link.hit_radius = float(data.get("hit_radius", 48.0))
    link.target_zoom = float(data.get("target_zoom", 1.0))
    link.target_floor_id = str(data.get("target_floor_id", "ground"))
    link.placement_id = str(data.get("placement_id", ""))
    return link
