class_name AtlasOverview
extends RefCounted
## Metadata-only queries; artwork, persistence and navigation belong to callers.

enum Filter { CAMPAIGN, MAP, VISIBLE, CELL }

const MAX_VISITS: int = 512
const MAX_ENTRIES: int = 256
const MAX_DEPTH: int = 16


static func query(campaign: AtlasCampaign, map_id: String, floor_id: String,
        mode: Filter = Filter.CAMPAIGN, text: String = "",
        region: PackedVector2Array = PackedVector2Array(), recursive: bool = true,
        limit: int = 128, max_depth: int = 6) -> AtlasOverviewResult:
    var result: AtlasOverviewResult = AtlasOverviewResult.new()
    if campaign == null:
        result.message = "No campaign is available."
        return result
    if mode < Filter.CAMPAIGN or mode > Filter.CELL:
        result.message = "Unknown overview filter."
        return result
    var spatial: bool = mode == Filter.VISIBLE or mode == Filter.CELL
    var polygon: PackedVector2Array = region.duplicate()
    if polygon.size() > 1 and polygon[0] == polygon[-1]:
        polygon.remove_at(polygon.size() - 1)
    if spatial and not _valid_region(polygon):
        result.message = ("Select a cell to use the selected-cell overview; a finite convex document polygon is required."
            if mode == Filter.CELL else "Visible overview requires a finite convex document polygon.")
        return result
    var tokens: PackedStringArray = text.to_lower().replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)
    var entry_limit: int = clampi(limit, 0, MAX_ENTRIES)
    if mode == Filter.CAMPAIGN:
        _campaign_entries(campaign, tokens, entry_limit, result)
    else:
        _walk(campaign, map_id, floor_id, tokens, polygon, spatial, recursive,
            entry_limit, clampi(max_depth, 0, MAX_DEPTH), result)
    if result.truncated:
        result.message = "Overview truncated by the entry, depth or visit limit."
    elif result.entries.is_empty() and result.message.is_empty():
        result.message = "No matching overview entries."
    return result


static func _campaign_entries(campaign: AtlasCampaign, tokens: PackedStringArray,
        limit: int, result: AtlasOverviewResult) -> void:
    var map_ids: Array[String] = []
    map_ids.assign(campaign.maps.keys())
    map_ids.sort()
    for map_id: String in map_ids:
        var map: AtlasMapDocument = campaign.get_map(map_id)
        var floor_ids: Array[String] = []
        if map != null:
            for floor: AtlasFloor in map.floors:
                floor_ids.append(floor.id)
        if floor_ids.is_empty():
            floor_ids.append("")
        floor_ids.sort()
        for floor_id: String in floor_ids:
            if result.visited_count >= MAX_VISITS:
                result.truncated = true
                return
            result.visited_count += 1
            var entry: AtlasOverviewEntry = _destination(campaign, map_id, floor_id)
            if _matches(campaign, entry, tokens) and not _append(result, entry, limit):
                return


static func _walk(campaign: AtlasCampaign, map_id: String, floor_id: String,
        tokens: PackedStringArray, region: PackedVector2Array, spatial: bool,
        recursive: bool, limit: int, max_depth: int, result: AtlasOverviewResult) -> void:
    var root: AtlasOverviewEntry = _destination(campaign, map_id, floor_id)
    var queue: Array[AtlasOverviewEntry] = [root]
    # Separate map and floor keys avoid collisions even when IDs contain delimiters.
    var visited: Dictionary[String, Dictionary] = {}
    _visit(visited, map_id, floor_id)
    result.visited_count = 1
    var cursor: int = 0
    while cursor < queue.size():
        var parent: AtlasOverviewEntry = queue[cursor]
        cursor += 1
        var links: Array[AtlasMapLink] = campaign.outgoing_links(parent.map_id, parent.floor_id)
        links.sort_custom(_link_less)
        for link: AtlasMapLink in links:
            # outgoing_links treats an empty floor as a wildcard; overview never does.
            if link.source_floor_id != parent.floor_id:
                continue
            var placement: AtlasPlacement = _owned_placement(campaign, link)
            if spatial and parent.depth == 0 and not _hits(link, placement, region):
                continue
            if parent.depth >= max_depth:
                result.truncated = true
                continue
            var entry: AtlasOverviewEntry = _link_entry(campaign, link, placement, parent)
            if _matches(campaign, entry, tokens) and not _append(result, entry, limit):
                return
            if not recursive or not entry.broken_reason.is_empty():
                continue
            if visited.has(entry.map_id) and visited[entry.map_id].has(entry.floor_id):
                continue
            if result.visited_count >= MAX_VISITS:
                result.truncated = true
                continue
            _visit(visited, entry.map_id, entry.floor_id)
            result.visited_count += 1
            queue.append(entry)
    if not root.broken_reason.is_empty() and result.entries.is_empty():
        result.message = root.broken_reason


static func _visit(visited: Dictionary[String, Dictionary], map_id: String, floor_id: String) -> void:
    if not visited.has(map_id):
        visited[map_id] = {}
    visited[map_id][floor_id] = true


static func _append(result: AtlasOverviewResult, entry: AtlasOverviewEntry, limit: int) -> bool:
    if result.entries.size() >= limit:
        result.truncated = true
        return false
    result.entries.append(entry)
    return true


static func _destination(campaign: AtlasCampaign, map_id: String, floor_id: String) -> AtlasOverviewEntry:
    var entry: AtlasOverviewEntry = AtlasOverviewEntry.new()
    entry.map_id = map_id
    entry.floor_id = floor_id
    var map: AtlasMapDocument = campaign.get_map(map_id)
    if map == null:
        entry.broken_reason = "Missing map: " + map_id
        entry.caption = "Missing map: %s / %s" % [map_id, floor_id]
    else:
        var floor: AtlasFloor = map.floor_by_id(floor_id)
        var floor_name: String = floor.display_name if floor != null else floor_id
        entry.caption = "%s · %s · %s · %d floors" % [map.display_name, map.kind, floor_name, map.floors.size()]
        if not map.tags.is_empty():
            entry.caption += " · #" + " #".join(map.tags)
        if floor == null:
            entry.broken_reason = "Missing floor: %s / %s" % [map_id, floor_id]
    entry.breadcrumb = _label(campaign, map_id, floor_id)
    return entry


static func _link_entry(campaign: AtlasCampaign, link: AtlasMapLink,
        placement: AtlasPlacement, parent: AtlasOverviewEntry) -> AtlasOverviewEntry:
    var entry: AtlasOverviewEntry = _destination(campaign, link.target_map_id, link.target_floor_id)
    entry.source_map_id = link.source_map_id
    entry.source_floor_id = link.source_floor_id
    entry.link_id = link.id
    entry.depth = parent.depth + 1
    entry.breadcrumb = parent.breadcrumb + " → " + entry.breadcrumb
    entry.source_focus = link.anchor
    if placement != null:
        entry.source_focus = placement.local_to_parent() * (Vector2(placement.columns, placement.rows) * 0.5)
    var source: AtlasMapDocument = campaign.get_map(link.source_map_id)
    entry.can_focus = source != null and source.floor_by_id(link.source_floor_id) != null and entry.source_focus.is_finite()
    if not entry.can_focus:
        entry.broken_reason = _reason(entry.broken_reason, "Missing or invalid source map/floor: %s / %s" % [link.source_map_id, link.source_floor_id])
    if not link.placement_id.is_empty() and placement == null:
        entry.broken_reason = _reason(entry.broken_reason, "Missing or mismatched placement: " + link.placement_id)
    return entry


static func _reason(previous: String, next: String) -> String:
    return next if previous.is_empty() else previous + "; " + next


static func _label(campaign: AtlasCampaign, map_id: String, floor_id: String) -> String:
    var map: AtlasMapDocument = campaign.get_map(map_id)
    if map == null:
        return "%s / %s" % [map_id, floor_id]
    var floor: AtlasFloor = map.floor_by_id(floor_id)
    return "%s / %s" % [map.display_name, floor.display_name if floor != null else floor_id]


static func _matches(campaign: AtlasCampaign, entry: AtlasOverviewEntry, tokens: PackedStringArray) -> bool:
    var map: AtlasMapDocument = campaign.get_map(entry.map_id)
    var tags: PackedStringArray = PackedStringArray()
    var fields: PackedStringArray = PackedStringArray([entry.floor_id])
    if map == null:
        fields.append(entry.map_id)
    if map != null:
        fields.append(map.display_name)
        fields.append(map.kind)
        var floor: AtlasFloor = map.floor_by_id(entry.floor_id)
        if floor != null:
            fields.append(floor.display_name)
        for tag: String in map.tags:
            tags.append(tag.to_lower())
            fields.append(tag)
    var haystack: String = "\n".join(fields).to_lower()
    for token: String in tokens:
        if token.begins_with("#"):
            if not tags.has(token.substr(1)):
                return false
        elif not haystack.contains(token):
            return false
    return true


static func _link_less(a: AtlasMapLink, b: AtlasMapLink) -> bool:
    return a.id < b.id


static func _owned_placement(campaign: AtlasCampaign, link: AtlasMapLink) -> AtlasPlacement:
    if link.placement_id.is_empty():
        return null
    var placement: AtlasPlacement = campaign.placement_by_id(link.placement_id)
    if placement == null or placement.parent_map_id != link.source_map_id or placement.child_map_id != link.target_map_id:
        return null
    return placement


static func _hits(link: AtlasMapLink, placement: AtlasPlacement, region: PackedVector2Array) -> bool:
    if placement != null:
        var corners: PackedVector2Array = placement.corners()
        return not _separated(corners, region) and not _separated(region, corners)
    # A broken placement retains the link's anchor marker as its source hit region.
    if not link.anchor.is_finite() or not is_finite(link.hit_radius) or link.hit_radius < 0.0:
        return false
    if Geometry2D.is_point_in_polygon(link.anchor, region):
        return true
    for index: int in range(region.size()):
        var closest: Vector2 = Geometry2D.get_closest_point_to_segment(link.anchor, region[index], region[(index + 1) % region.size()])
        if closest.distance_squared_to(link.anchor) <= link.hit_radius * link.hit_radius:
            return true
    return false


static func _separated(a: PackedVector2Array, b: PackedVector2Array) -> bool:
    # Separating-axis test includes edge/corner contact, unlike area-only clipping.
    for index: int in range(a.size()):
        var edge: Vector2 = a[(index + 1) % a.size()] - a[index]
        var axis: Vector2 = Vector2(-edge.y, edge.x)
        var low_a: float = INF
        var high_a: float = -INF
        var low_b: float = INF
        var high_b: float = -INF
        for point: Vector2 in a:
            low_a = minf(low_a, point.dot(axis))
            high_a = maxf(high_a, point.dot(axis))
        for point: Vector2 in b:
            low_b = minf(low_b, point.dot(axis))
            high_b = maxf(high_b, point.dot(axis))
        if high_a < low_b or high_b < low_a:
            return true
    return false


static func _valid_region(region: PackedVector2Array) -> bool:
    if region.size() < 3:
        return false
    var orientation: float = 0.0
    for point: Vector2 in region:
        if not point.is_finite():
            return false
    for index: int in range(region.size()):
        var start: Vector2 = region[index]
        var edge: Vector2 = region[(index + 1) % region.size()] - start
        if edge == Vector2.ZERO:
            return false
        for point: Vector2 in region:
            var cross: float = edge.cross(point - start)
            if cross == 0.0:
                continue
            if orientation == 0.0:
                orientation = signf(cross)
            elif cross * orientation < 0.0:
                return false
    return orientation != 0.0
