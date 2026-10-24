extends SceneTree

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
    _floors()
    _guards()
    _metadata()
    _viewer()
    print("ATLAS_FLOORS_VIEW_%s checks=%d failures=%d" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
    quit(0 if _failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
    _checks += 1
    if not condition:
        _failures += 1
        printerr("FAIL: " + label)

func _floor(id: String) -> AtlasFloor:
    var floor: AtlasFloor = AtlasFloor.new()
    floor.id = id
    floor.terrain["-2,3"] = 4
    floor.strokes.append(AtlasStroke.new(PackedVector2Array([Vector2(-3, 4), Vector2(7, 9)]), Color.BLUE, 2.5))
    var image: Image = Image.create_empty(2, 3, false, Image.FORMAT_RGBA8)
    image.fill(Color.RED)
    floor.layers.append(AtlasRasterLayer.from_image(image, 2.5))
    return floor

func _copy(floors: Array[AtlasFloor]) -> Array[AtlasFloor]:
    var result: Array[AtlasFloor] = []
    for floor: AtlasFloor in floors:
        var copy: AtlasFloor = AtlasFloor.new()
        copy.id = floor.id
        copy.display_name = floor.display_name
        copy.layers = AtlasLayerCodec.clone_all(floor.layers)
        result.append(copy)
    return result

func _campaign() -> AtlasCampaign:
    var campaign: AtlasCampaign = AtlasCampaign.new()
    campaign.root_map_id = "m"
    var map: AtlasMapDocument = AtlasMapDocument.new("m", "Map")
    map.tags = ["City"]
    map.grid.distance_unit = "ft"
    map.terrain_grid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 23.0)
    map.terrain_grid.distance_unit = "km"
    map.floors = [_floor("ground"), _floor("upper")]
    map.floors[1].terrain_layer().grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 17.0)
    campaign.add_map(map)
    campaign.add_map(AtlasMapDocument.new("other", "Other"))
    return campaign

func _floors() -> void:
    var campaign: AtlasCampaign = _campaign()
    var map: AtlasMapDocument = campaign.get_map("m")
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "m"
    var board: AtlasGrid = map.grid
    var legacy: AtlasGrid = map.terrain_grid
    var original_art: Array[AtlasLayer] = AtlasLayerCodec.clone_all(map.floors[1].layers)
    for operation: String in ["create", "name", "reorder", "default", "delete"]:
        var saved: Dictionary = campaign.to_dict()
        var before: Array[AtlasFloor] = _copy(map.floors)
        var after: Array[AtlasFloor] = _copy(before)
        var next_default: String = map.default_floor_id
        match operation:
            "create": after.append(_floor("cellar"))
            "name": after[2].display_name = "Cellar renamed"
            "reorder": after.reverse()
            "default": next_default = "upper"
            "delete": after.remove_at(2)
        var command: AtlasFloorEdit = AtlasFloorEdit.new("m", before, after, map.default_floor_id, next_default)
        var expected: Array[AtlasFloor] = _copy(after)
        for source: AtlasFloor in before + after:
            source.display_name = "Caller mutation"
            source.strokes[0].points[0] = Vector2(999, 999)
            source.terrain["-2,3"] = 99
            if source.terrain_layer().grid != null:
                source.terrain_layer().grid.cell_size = 888.0
            (source.layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.BLUE)
        history.mark_saved()
        _check(history.execute(command) and history.is_dirty() and map.default_floor_id == next_default, operation + " executes")
        for index: int in range(expected.size()):
            _check(map.floors[index].to_dict() == expected[index].to_dict(), operation + " detached floor snapshots/pixels")
        var applied: Dictionary = campaign.to_dict()
        _check(history.undo() and not history.is_dirty() and campaign.to_dict() == saved, operation + " undo")
        _check(history.redo() and history.is_dirty() and campaign.to_dict() == applied, operation + " redo")
        _check(map.grid == board and map.terrain_grid == legacy and map.tags == ["City"] and campaign.links.is_empty(), operation + " preserves map fields")
        _check(AtlasLayerCodec.same_layers(map.floor_by_id("upper").layers, original_art), operation + " preserves artwork/grid/scale")
        if map.floor_by_id("ground") != null:
            _check(map.floor_by_id("ground").terrain_layer().grid == null and map.get_terrain_grid("ground") == legacy, "null grid uses legacy, never another floor")
    _check(not history.execute(AtlasFloorEdit.new("m", map.floors, map.floors, "upper", "upper")), "floor no-op")

func _guards() -> void:
    var campaign: AtlasCampaign = _campaign()
    var map: AtlasMapDocument = campaign.get_map("m")
    var saved: Dictionary = campaign.to_dict()
    var remove: AtlasFloorEdit = AtlasFloorEdit.new("m", map.floors, [map.floors[0]], "ground", "ground")
    _check(not AtlasFloorEdit.new("m", map.floors, [map.floors[1]], "ground", "ground").apply(campaign), "cannot remove default without valid replacement default")
    for flag: String in ["hidden", "locked"]:
        map.floors[1].layers[0].visible = flag != "hidden"
        map.floors[1].layers[0].locked = flag == "locked"
        var guarded: AtlasFloorEdit = AtlasFloorEdit.new("m", map.floors, [map.floors[0]], "ground", "ground")
        _check(not guarded.apply(campaign), flag + " deletion rejected")
        map.floors[1].layers[0].visible = true
        map.floors[1].layers[0].locked = false
    var link: AtlasMapLink = AtlasMapLink.new()
    link.id = "link"
    for source: bool in [true, false]:
        link.source_map_id = "m" if source else "other"
        link.target_map_id = "other" if source else "m"
        link.source_floor_id = "upper" if source else "ground"
        link.target_floor_id = "ground" if source else "upper"
        campaign.links = [link]
        _check(not remove.apply(campaign), "source/target reference blocks delete")
        campaign.links.clear()
    for invalid: String in ["empty", "duplicate", "name", "id", "default", "layer", "content", "grid", "pixels"]:
        var after: Array[AtlasFloor] = _copy(map.floors)
        var next_default: String = "ground"
        match invalid:
            "empty": after.clear()
            "duplicate": after.append(after[0])
            "name": after[0].display_name = " "
            "id": after[0].id = ""
            "default": next_default = "missing"
            "layer": after[0].layers.append(after[0].layers[0])
            "content": after[0].terrain["0,0"] = 7
            "grid": after[0].terrain_layer().grid = AtlasGrid.new()
            "pixels": (after[0].layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image.fill(Color.GREEN)
        _check(not AtlasFloorEdit.new("m", map.floors, after, "ground", next_default).apply(campaign) and campaign.to_dict() == saved, invalid + " atomic rejection")
    map.default_floor_id = "upper"
    _check(not remove.apply(campaign), "stale default rejected")
    map.default_floor_id = "ground"
    map.floors.reverse()
    _check(not remove.apply(campaign), "stale order rejected")
    map.floors.reverse()
    _check(remove.apply(campaign) and remove.revert(campaign) and campaign.to_dict() == saved, "visible art deletion undo restores pixels")
    var create: AtlasFloorEdit = AtlasFloorEdit.new("m", [map.floors[0]], map.floors, "ground", "ground")
    campaign.links = [link]
    _check(not create.revert(campaign), "undo creation protects newly linked floor")
    link.source_map_id = "m"
    link.source_floor_id = "upper"
    link.target_map_id = "other"
    _check(not create.revert(campaign), "undo creation protects new source floor reference")
    campaign.links.clear()
    map.floors[1].layers[0].locked = true
    _check(not create.revert(campaign), "undo creation protects newly locked floor")
    map.floors[1].layers[0].locked = false
    var pixels: Image = (map.floors[1].layer_by_id("raster") as AtlasRasterLayer).chunks["0,0"].image
    pixels.fill(Color.BLUE)
    _check(not create.revert(campaign), "undo creation rejects stale pixels")
    pixels.fill(Color.RED)
    _check(create.revert(campaign) and create.apply(campaign), "creation undo/redo restores detached pixels")

func _metadata() -> void:
    var campaign: AtlasCampaign = _campaign()
    var map: AtlasMapDocument = campaign.get_map("m")
    var saved: Dictionary = campaign.to_dict()
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "m"
    var before: Array[String] = ["City"]
    var after: Array[String] = ["Dungeon", "Coast"]
    var edit: AtlasMapMetadataEdit = AtlasMapMetadataEdit.new("m", "Map", before, "Renamed", after)
    before[0] = "changed"
    after.clear()
    _check(history.execute(edit) and history.is_dirty() and map.tags == ["Dungeon", "Coast"] and map.display_name == "Renamed", "metadata detached apply/history")
    var expected: Dictionary = saved.duplicate(true)
    expected.maps[0].name = "Renamed"
    expected.maps[0].tags = ["Dungeon", "Coast"]
    _check(campaign.to_dict() == expected, "metadata mutates only name/tags")
    _check(history.undo() and not history.is_dirty() and campaign.to_dict() == saved and history.redo(), "metadata history undo/redo")
    var loaded: AtlasCampaign = AtlasCampaign.from_dict(campaign.to_dict())
    _check(AtlasCampaign.SCHEMA_VERSION == 6 and loaded != null and loaded.to_dict() == campaign.to_dict(), "v6 tags roundtrip")
    for version: int in [1, 2, 3, 4, 5]:
        var legacy: Dictionary = saved.duplicate(true)
        legacy.schema_version = version
        legacy.maps[0].erase("tags")
        loaded = AtlasCampaign.from_dict(legacy)
        _check(loaded != null and loaded.get_map("m").tags.is_empty(), "legacy v%d tags default empty" % version)
    var too_many: Array[String] = []
    for index: int in range(129): too_many.append(str(index))
    var boundary: Array[String] = too_many.duplicate()
    boundary.pop_back()
    var limit: AtlasMapMetadataEdit = AtlasMapMetadataEdit.new("m", map.display_name, map.tags, "Limit", boundary)
    _check(limit.apply(campaign) and map.tags.size() == 128 and limit.revert(campaign), "128 tag boundary accepted/undoable")
    var invalid_tags: Array[Array] = [[""], [" "], ["City", "city"], too_many]
    for raw: Array in invalid_tags:
        var tags: Array[String] = []
        tags.assign(raw)
        _check(not AtlasMapMetadataEdit.new("m", map.display_name, map.tags, "Next", tags).apply(campaign), "invalid tags rejected")
    _check(not AtlasMapMetadataEdit.new("m", "Renamed", map.tags, " ", []).apply(campaign), "empty map name rejected")
    _check(not AtlasMapMetadataEdit.new("m", "Renamed", map.tags, "Renamed", map.tags).apply(campaign) and not edit.apply(campaign), "metadata no-op/stale apply")
    map.tags.append("External")
    _check(not edit.revert(campaign), "metadata stale undo rejected")

func _viewer() -> void:
    var campaign: AtlasCampaign = _campaign()
    var map: AtlasMapDocument = campaign.get_map("m")
    var saved: Dictionary = campaign.to_dict()
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    var session: AtlasViewSession = AtlasViewSession.new()
    var state: AtlasViewState = session.resolve(campaign, "m", "", Vector2(8, -7), 0.375)
    _check(state != null and state.floor_id == "ground" and state.focus == Vector2(8, -7) and state.zoom == 0.375, "first visit fallback/default")
    var detached: AtlasViewState = state.copy()
    _check(detached != state and detached.map_id == state.map_id and detached.floor_id == state.floor_id and detached.focus == state.focus and detached.zoom == state.zoom and detached.layer_id == state.layer_id, "state copy retains every field")
    session.remember(AtlasViewState.new("m", "upper", Vector2(-13.25, 7.5), 2.125, "raster"))
    state = session.resolve(campaign, "m")
    _check(state.floor_id == "upper" and state.focus == Vector2(-13.25, 7.5) and state.zoom == 2.125 and state.layer_id == "raster", "implicit last floor exact camera/layer")
    state.focus = Vector2(999, 999)
    _check(session.resolve(campaign, "m").focus == Vector2(-13.25, 7.5), "resolved state detached")
    var input: AtlasViewState = AtlasViewState.new("m", "ground", Vector2(1, 2), 0.75, "gone")
    session.remember(input)
    input.zoom = 99.0
    _check(session.resolve(campaign, "m").zoom == 0.75 and session.resolve(campaign, "m").layer_id == "ink", "remember detached/missing layer fallback")
    _check(session.resolve(campaign, "missing") == null and session.resolve(campaign, "m", "missing") == null and session.resolve(null, "m") == null, "invalid explicit targets")
    _check(session.resolve(campaign, "other", "", Vector2(NAN, 0), 1.0) == null, "invalid fallback focus rejected")
    for zoom: float in [0.0, -1.0, INF, NAN]:
        session.remember(AtlasViewState.new("m", "ground", Vector2.ZERO, zoom))
        _check(session.resolve(campaign, "m").zoom == 0.75 and session.resolve(campaign, "other", "ground", Vector2.ZERO, zoom) == null, "invalid zoom rejected")
    session.remember(AtlasViewState.new("m", "ground", Vector2(INF, 0), 1.0))
    _check(session.resolve(campaign, "m").focus == Vector2(1, 2) and campaign.to_dict() == saved and not history.is_dirty(), "invalid focus/viewer never mutates canonical document")
    map.floors.remove_at(0)
    map.default_floor_id = "upper"
    session.prune(campaign)
    _check(session.resolve(campaign, "m").floor_id == "upper", "deleted last floor uses document default")
    map.floors.append(_floor("ground"))
    _check(session.resolve(campaign, "m", "ground", Vector2(4, 5), 3.0).zoom == 3.0, "prune deleted floor state")
    map.floors[0].layers.remove_at(1)
    session.remember(AtlasViewState.new("m", "upper", Vector2.ZERO, 1.0, "gone"))
    _check(session.resolve(campaign, "m").layer_id == "raster", "missing ink selects last valid layer")
    campaign.maps.erase("m")
    session.prune(campaign)
    campaign.add_map(AtlasMapDocument.new("m", "Replacement"))
    _check(session.resolve(campaign, "m", "", Vector2.ZERO, 4.0).zoom == 4.0, "prune deleted map state")
    for pair: Array in [["a:b", "c"], ["a", "b:c"]]:
        var special: AtlasMapDocument = AtlasMapDocument.new(pair[0], "Special")
        special.floors[0].id = pair[1]
        special.default_floor_id = pair[1]
        campaign.add_map(special)
        session.remember(AtlasViewState.new(pair[0], pair[1], Vector2.ZERO, 2.0 if pair[0] == "a" else 3.0))
    _check(session.resolve(campaign, "a:b").zoom == 3.0 and session.resolve(campaign, "a").zoom == 2.0, "special IDs cannot collide")
    session.remember(AtlasViewState.new("a", "deleted", Vector2.ZERO, 7.0))
    _check(session.resolve(campaign, "a").floor_id == "b:c" and session.resolve(campaign, "a").zoom == 2.0, "invalid remembered floor uses default even before prune")
    session.reset()
    _check(session.resolve(campaign, "a", "", Vector2.ZERO, 5.0).zoom == 5.0, "session reset")
