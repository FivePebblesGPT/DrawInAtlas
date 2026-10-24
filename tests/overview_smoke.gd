extends SceneTree

const Overview = preload("res://scripts/navigation/overview.gd")
var _checks: int = 0
var _failures: int = 0

class ArtworkSentinel extends AtlasLayer:
    var inspections: int = 0
    func to_dict() -> Dictionary:
        inspections += 1
        return super.to_dict()

func _initialize() -> void:
    _graph_and_text()
    _spatial()
    _broken()
    _limits()
    _readonly()
    print("ATLAS_OVERVIEW_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
    quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("OVERVIEW FAILED: " + label)

func _map(c: AtlasCampaign, id: String, name: String = "", floors: Array[String] = ["ground"]) -> AtlasMapDocument:
    var map: AtlasMapDocument = AtlasMapDocument.new(id, name if not name.is_empty() else id)
    map.floors.clear()
    for floor_id: String in floors:
        var floor: AtlasFloor = AtlasFloor.new()
        floor.id = floor_id
        floor.display_name = floor_id.capitalize()
        map.floors.append(floor)
    c.add_map(map)
    return map

func _link(c: AtlasCampaign, id: String, source: String, target: String,
        source_floor: String = "ground", target_floor: String = "ground") -> AtlasMapLink:
    var link: AtlasMapLink = AtlasMapLink.new()
    link.id = id
    link.source_map_id = source
    link.source_floor_id = source_floor
    link.target_map_id = target
    link.target_floor_id = target_floor
    link.hit_radius = 1.0
    c.links.append(link)
    return link

func _ids(result: AtlasOverviewResult) -> Array[String]:
    var ids: Array[String] = []
    for entry: AtlasOverviewEntry in result.entries:
        ids.append(entry.link_id)
    return ids

func _box(x: float, y: float, width: float, height: float) -> PackedVector2Array:
    return PackedVector2Array([Vector2(x, y), Vector2(x + width, y), Vector2(x + width, y + height), Vector2(x, y + height)])

func _fixture() -> AtlasCampaign:
    var c: AtlasCampaign = AtlasCampaign.new()
    _map(c, "a", "Atlas", ["ground", "upper"])
    _map(c, "b", "Bridge", ["ground", "upper"])
    var cave: AtlasMapDocument = _map(c, "c", "Moon Cave")
    cave.kind = "DUNGEON"
    cave.tags = ["Hidden", "Ruins"]
    _link(c, "02-door", "a", "b")
    _link(c, "01-door", "a", "b")
    _link(c, "03-stair", "a", "b", "ground", "upper")
    _link(c, "04-wrong-source-floor", "a", "c", "upper")
    _link(c, "05-cellar", "b", "c", "upper")
    _link(c, "06-cycle", "c", "a")
    return c

func _graph_and_text() -> void:
    var c: AtlasCampaign = _fixture()
    var r: AtlasOverviewResult = Overview.query(c, "a", "ground", Overview.Filter.MAP)
    _check(_ids(r) == ["01-door", "02-door", "03-stair", "05-cellar", "06-cycle"], "BFS keeps entrances, floors and cycle edge; ignores inactive floor")
    _check(r.visited_count == 4 and not r.truncated, "unique map/floor visitation terminates cycle")
    _check(r.entries[3].source_floor_id == "upper" and r.entries[3].floor_id == "ground" and r.entries[3].depth == 2, "every hop honors source and target floor")
    _check(r.entries[3].breadcrumb == "Atlas / Ground → Bridge / Upper → Moon Cave / Ground", "breadcrumb follows accepted entrance path")
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.MAP, "", _box(99, 99, 1, 1), false)) == ["01-door", "02-door", "03-stair"], "nonrecursive MAP ignores region")
    _check(_ids(Overview.query(c, "a", "upper", Overview.Filter.MAP, "", PackedVector2Array(), false)) == ["04-wrong-source-floor"], "active floor switches first hop")
    for text: String in ["moon dungeon #HIDDEN ruins", "\tMOON\n#ruins\r"]:
        _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.MAP, text)) == ["05-cellar"], "unmatched parents still traversed: " + text)
    for text: String in ["#hid", "#hidden #missing", "moon city"]:
        _check(Overview.query(c, "a", "ground", Overview.Filter.MAP, text).entries.is_empty(), "AND tokens and exact tags: " + text)
    r = Overview.query(c, "missing", "missing")
    _check(r.entries.size() == 5 and r.visited_count == 5 and not r.truncated, "campaign enumerates all map/floor pairs without recursion or active source")
    _check(r.entries[0].map_id == "a" and r.entries[1].floor_id == "upper" and r.entries[0].link_id.is_empty(), "campaign deterministic map/floor ordering")
    r = Overview.query(c, "a", "ground", Overview.Filter.CAMPAIGN, "dungeon #HIDDEN")
    _check(r.entries.size() == 1 and r.entries[0].caption.contains("1 floors") and r.entries[0].caption.contains("#Ruins"), "campaign caption contains floor count and tags")
    _check(Overview.query(c, "a", "ground", Overview.Filter.CAMPAIGN, "bridge upper").entries.size() == 1, "floor names match independently")
    _check(Overview.query(c, "a", "ground", Overview.Filter.CAMPAIGN, "atlas ground").entries[0].caption.contains("2 floors"), "campaign multiple-floor caption")
    c.links.reverse()
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.MAP)) == ["01-door", "02-door", "03-stair", "05-cellar", "06-cycle"], "input link order does not affect results")
    var pairs: AtlasCampaign = AtlasCampaign.new()
    _map(pairs, "a", "A", ["b:c"])
    _map(pairs, "a:b", "AB", ["c"])
    _map(pairs, "end")
    _link(pairs, "one", "a", "a:b", "b:c", "c")
    _link(pairs, "two", "a:b", "end", "c")
    _check(_ids(Overview.query(pairs, "a", "b:c", Overview.Filter.MAP)) == ["one", "two"], "delimiter-bearing map/floor IDs cannot collide")

func _spatial() -> void:
    var c: AtlasCampaign = AtlasCampaign.new()
    for id: String in ["a", "b", "c", "d"]:
        _map(c, id)
    var circle: AtlasMapLink = _link(c, "circle", "a", "b")
    circle.anchor = Vector2(-1, 0.5)
    var placed: AtlasMapLink = _link(c, "placed", "a", "c")
    placed.placement_id = "rotated"
    var p: AtlasPlacement = AtlasPlacement.new()
    p.id = "rotated"
    p.parent_map_id = "a"
    p.child_map_id = "c"
    p.origin = Vector2(10, 10)
    p.columns = 4
    p.rows = 1
    p.parent_units_per_cell = 1.0
    p.rotation = PI / 4.0
    c.placements.append(p)
    _link(c, "descendant", "c", "d").anchor = Vector2(999, 999)
    for mode: Overview.Filter in [Overview.Filter.VISIBLE, Overview.Filter.CELL]:
        _check(_ids(Overview.query(c, "a", "ground", mode, "", _box(0, 0, 1, 1))) == ["circle"], "circle edge tangency includes anchor outside region")
        _check(Overview.query(c, "a", "ground", mode, "", _box(0.01, 0, 1, 1)).entries.is_empty(), "circle just outside region misses")
        _check(_ids(Overview.query(c, "a", "ground", mode, "", _box(11.2, 11.8, 0.1, 0.1))) == ["placed", "descendant"], "rotated footprint accepts region inside; descendants ignore region")
        _check(Overview.query(c, "a", "ground", mode, "", _box(9.4, 12, 0.1, 0.1)).entries.is_empty(), "rotated AABB false positive rejected")
        _check(_ids(Overview.query(c, "a", "ground", mode, "", _box(8, 8, 8, 8), false)) == ["placed"], "region encloses full footprint")
        var empty: AtlasOverviewResult = Overview.query(c, "a", "ground", mode)
        _check(empty.entries.is_empty() and not empty.message.is_empty(), "spatial mode requires region")
    _check(Overview.query(c, "a", "ground", Overview.Filter.CELL).message.contains("Select a cell"), "selected-cell explanation")
    var r: AtlasOverviewResult = Overview.query(c, "a", "ground", Overview.Filter.MAP)
    _check(r.entries[1].source_focus.is_equal_approx(p.local_to_parent() * Vector2(2, 0.5)) and r.entries[1].can_focus, "placement focus is rotated center including origin")
    _check(r.entries[0].source_focus == circle.anchor and r.entries[0].can_focus, "anchor source focus preserved")
    var diamond: PackedVector2Array = PackedVector2Array([Vector2(-0.5, 0.5), Vector2(0.5, -0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5)])
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", diamond)) == ["circle"], "convex nonrectangular document region")
    diamond.reverse()
    diamond.append(diamond[0])
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.CELL, "", diamond)) == ["circle"], "clockwise closed polygon accepted")
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", _box(9, 11.5, 5, 0.01), false)) == ["placed"], "footprint edges cross region without vertex containment")
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", _box(-0.9, 0.4, 0.1, 0.1))) == ["circle"], "circle encloses region")
    _check(_ids(Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", _box(-2, -2, 4, 4))) == ["circle"], "region contains circle center")
    for region: PackedVector2Array in [PackedVector2Array(), PackedVector2Array([Vector2.ZERO, Vector2.ONE]), PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(2, 2)]), _box(INF, 0, 1, 1), PackedVector2Array([Vector2.ZERO, Vector2(2, 0), Vector2(0.5, 0.5), Vector2(0, 2)]), PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(1, 0), Vector2(0, 1)])]:
        r = Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", region)
        _check(r.entries.is_empty() and not r.message.is_empty() and r.visited_count == 0, "invalid region rejected before traversal")

func _broken() -> void:
    var c: AtlasCampaign = AtlasCampaign.new()
    _map(c, "a")
    _map(c, "b")
    _map(c, "c")
    _link(c, "1-map", "a", "missing")
    _link(c, "2-floor", "a", "b", "ground", "missing")
    _link(c, "3-placement", "a", "b").placement_id = "absent"
    var mismatched: AtlasMapLink = _link(c, "4-owner", "a", "b")
    mismatched.placement_id = "bad"
    var p: AtlasPlacement = AtlasPlacement.new()
    p.id = "bad"
    p.parent_map_id = "c"
    p.child_map_id = "b"
    c.placements.append(p)
    _link(c, "5-child", "b", "c")
    var r: AtlasOverviewResult = Overview.query(c, "a", "ground", Overview.Filter.MAP)
    _check(r.entries.size() == 4 and r.visited_count == 1, "broken refs produce placeholders and never queue")
    for entry: AtlasOverviewEntry in r.entries:
        _check(not entry.broken_reason.is_empty() and entry.can_focus and entry.source_focus == Vector2.ZERO, "broken target retains valid source focus: " + entry.link_id)
    p.parent_map_id = "a"
    p.child_map_id = "c"
    _check(not Overview.query(c, "a", "ground", Overview.Filter.MAP).entries[3].broken_reason.is_empty(), "placement child ownership validated")
    _check(Overview.query(c, "a", "ground", Overview.Filter.VISIBLE, "", _box(-0.5, -0.5, 1, 1)).entries.size() == 4, "broken placement fallback uses anchor circle")
    _link(c, "orphan", "absent", "b")
    _link(c, "orphan-floor", "a", "b", "absent")
    for source: String in ["absent", "a"]:
        r = Overview.query(c, source, "ground" if source == "absent" else "absent", Overview.Filter.MAP)
        _check(r.entries.size() == 1 and not r.entries[0].can_focus and not r.entries[0].broken_reason.is_empty(), "invalid source disables focus and traversal")
    _check(not Overview.query(null, "a", "ground").message.is_empty(), "null campaign reports explanation")
    _check(not Overview.query(c, "absent", "absent", Overview.Filter.MAP).message.is_empty(), "invalid source without outgoing links explains empty result")

func _limits() -> void:
    var c: AtlasCampaign = _fixture()
    var r: AtlasOverviewResult = Overview.query(c, "a", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, 2)
    _check(r.entries.size() == 2 and r.truncated and not r.message.is_empty(), "entry cap reports truncation")
    _check(not Overview.query(c, "a", "ground", Overview.Filter.MAP, "", PackedVector2Array(), false, 3).truncated, "exact entry cap is not falsely truncated")
    for depth: int in [0, 1]:
        r = Overview.query(c, "a", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, 128, depth)
        _check(r.truncated and r.entries.size() == (0 if depth == 0 else 3), "depth cap bounds entries")
    _check(Overview.query(c, "a", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, -1).entries.is_empty(), "negative entry cap clamps to zero")
    _check(Overview.query(c, "a", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, 128, -1).entries.is_empty(), "negative depth clamps to zero")
    var chain: AtlasCampaign = AtlasCampaign.new()
    for i: int in range(20):
        _map(chain, str(i))
        if i > 0:
            _link(chain, str(i), str(i - 1), str(i))
    r = Overview.query(chain, "0", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, 999, 999)
    _check(r.entries.size() == 16 and r.entries[-1].depth == 16 and r.truncated, "depth clamps to sixteen")
    var wide: AtlasCampaign = AtlasCampaign.new()
    _map(wide, "root")
    for i: int in range(520):
        _map(wide, "%04d" % i)
        _link(wide, "%04d" % i, "root", "%04d" % i)
    r = Overview.query(wide, "root", "ground", Overview.Filter.MAP, "", PackedVector2Array(), true, 999)
    _check(r.entries.size() == 256 and r.truncated, "entry cap clamps to 256")
    r = Overview.query(wide, "root", "ground", Overview.Filter.MAP, "never-match")
    _check(r.visited_count == 512 and r.entries.is_empty() and r.truncated, "unmatched traversal respects 512 visit cap")
    r = Overview.query(wide, "root", "ground", Overview.Filter.CAMPAIGN, "never-match")
    _check(r.visited_count == 512 and r.truncated, "campaign scan also bounded")

func _readonly() -> void:
    var c: AtlasCampaign = _fixture()
    var sentinel: ArtworkSentinel = ArtworkSentinel.new()
    c.get_map("a").floors[0].layers = [sentinel]
    var before: String = JSON.stringify(c.to_dict(), "", true, true).sha256_text()
    sentinel.inspections = 0
    for mode: Overview.Filter in [Overview.Filter.CAMPAIGN, Overview.Filter.MAP, Overview.Filter.VISIBLE, Overview.Filter.CELL]:
        var r: AtlasOverviewResult = Overview.query(c, "a", "ground", mode, "", _box(-2, -2, 4, 4))
        if not r.entries.is_empty():
            r.entries[0].caption = "detached"
            r.entries[0].map_id = "detached"
        r.entries.clear()
    _check(sentinel.inspections == 0, "queries never serialize artwork sentinel")
    _check(JSON.stringify(c.to_dict(), "", true, true).sha256_text() == before, "canonical campaign checksum unchanged after all modes and result edits")
