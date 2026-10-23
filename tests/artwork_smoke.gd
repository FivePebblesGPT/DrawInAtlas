extends SceneTree

## Run: godot --headless --path . --script res://tests/artwork_smoke.gd
# Wire fixtures assume points are [x, y] pairs and color is [r, g, b, a].
# History queries are methods; AtlasStrokeEraser.erase is a static service entry point.
const EPSILON: float = 0.001

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("_run_suite")


func _run_suite() -> void:
    _test_stroke_roundtrip()
    _test_invalid_strokes()
    _test_vector_persistence()
    _test_legacy_campaign()
    _test_partial_erase()
    _test_dot_erase()
    _test_erase_no_op()
    _test_stroke_transaction()
    _test_captured_payload()
    _test_original_document_target()
    _test_rejected_commands()
    _test_saved_state_and_branch()
    _test_external_change_and_reset()
    if failures == 0:
        print("ATLAS_ARTWORK_PASSED (%d checks)" % checks)
    else:
        push_error("ATLAS_ARTWORK_FAILED: %d of %d checks failed" % [failures, checks])
    quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("ARTWORK FAILED: " + description)


func _dot(point: Vector2 = Vector2(-0.25, 0.125)) -> AtlasStroke:
    return AtlasStroke.new(PackedVector2Array([point]), Color(0.2, 0.4, 0.6, 0.75), 4.0)


func _line() -> AtlasStroke:
    return AtlasStroke.new(
        PackedVector2Array([Vector2(-50.0, 0.0), Vector2(50.0, 0.0)]),
        Color(0.8, 0.25, 0.5, 0.625), 4.0)


func _same_stroke(actual: AtlasStroke, expected: AtlasStroke) -> bool:
    if actual == null or expected == null:
        return false
    if actual.points.size() != expected.points.size():
        return false
    if not actual.color.is_equal_approx(expected.color):
        return false
    if not is_equal_approx(actual.width, expected.width):
        return false
    for index: int in range(actual.points.size()):
        if actual.points[index].distance_to(expected.points[index]) > EPSILON:
            return false
    return true


func _same_strokes(actual: Array[AtlasStroke], expected: Array[AtlasStroke]) -> bool:
    if actual.size() != expected.size():
        return false
    for index: int in range(actual.size()):
        if not _same_stroke(actual[index], expected[index]):
            return false
    return true


func _copies(strokes: Array[AtlasStroke]) -> Array[AtlasStroke]:
    var result: Array[AtlasStroke] = []
    for stroke: AtlasStroke in strokes:
        result.append(stroke.copy())
    return result


func _json_value(value: Variant) -> bool:
    if value == null or value is bool or value is String or value is int:
        return true
    if value is float:
        return is_finite(float(value))
    if value is Array:
        for item: Variant in value:
            if not _json_value(item):
                return false
        return true
    if value is Dictionary:
        for key: Variant in value:
            if not key is String or not _json_value(value[key]):
                return false
        return true
    return false


func _test_stroke_roundtrip() -> void:
    var defaults: AtlasStroke = AtlasStroke.new()
    _check(defaults.points.is_empty() and defaults.color == Color.BLACK
        and defaults.width == 8.0, "stroke constructor defaults")
    var examples: Array[AtlasStroke] = [
        _dot(),
        AtlasStroke.new(PackedVector2Array([
            Vector2(-12.875, -3.125), Vector2(-0.25, 0.125), Vector2(0.375, -0.625)
        ]), Color(0.125, 0.375, 0.625, 0.5), 0.75)
    ]
    for original: AtlasStroke in examples:
        _check(original.is_valid(), "dots and negative/subcell coordinates are valid")
        var data: Dictionary = original.to_dict()
        _check(_json_value(data), "stroke serialization contains only finite JSON primitives")
        var parsed: Variant = JSON.parse_string(JSON.stringify(data))
        _check(parsed is Dictionary, "stroke serializes to a JSON object")
        if not parsed is Dictionary:
            continue
        var restored: AtlasStroke = AtlasStroke.from_dict(parsed)
        _check(_same_stroke(restored, original), "stroke geometry, width and RGBA survive JSON")
        if restored != null:
            restored.points[0] = Vector2(999.0, 999.0)
            _check(not restored.points[0].is_equal_approx(original.points[0]),
                "deserialized points are independent of source")
        var snapshot: AtlasStroke = original.copy()
        _check(snapshot != original and _same_stroke(snapshot, original), "copy preserves value")
        if snapshot != null:
            snapshot.points[0] = Vector2(500.0, 500.0)
            snapshot.color = Color.WHITE
            snapshot.width = 100.0
            _check(original.points[0] != snapshot.points[0]
                and original.color != snapshot.color and original.width != snapshot.width,
                "copy mutation cannot change original points, color or width")


func _test_invalid_strokes() -> void:
    var invalid: Array[AtlasStroke] = [
        AtlasStroke.new(),
        AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.BLACK, 0.0),
        AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.BLACK, -1.0)
    ]
    for nonfinite: float in [INF, -INF, NAN]:
        invalid.append(AtlasStroke.new(PackedVector2Array([Vector2(nonfinite, 0.0)])))
        invalid.append(AtlasStroke.new(PackedVector2Array([Vector2(0.0, nonfinite)])))
        invalid.append(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.BLACK, nonfinite))
        for channel: int in range(4):
            var color: Color = Color(0.2, 0.4, 0.6, 0.8)
            color[channel] = nonfinite
            invalid.append(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), color))
    for index: int in range(invalid.size()):
        _check(not invalid[index].is_valid(), "invalid stroke rejected: case %d" % index)

    var valid: Dictionary = _dot().to_dict()
    var malformed: Array[Dictionary] = [{}]
    for bad_points: Variant in [[], "not points", [[0.0]], [["x", 0.0]]]:
        var data: Dictionary = valid.duplicate(true)
        data["points"] = bad_points
        malformed.append(data)
    for bad_width: Variant in [0.0, -1.0, "wide", null]:
        var data: Dictionary = valid.duplicate(true)
        data["width"] = bad_width
        malformed.append(data)
    for bad_color: Variant in [[], [0.0, 0.0], ["red", 0.0, 0.0, 1.0], null]:
        var data: Dictionary = valid.duplicate(true)
        data["color"] = bad_color
        malformed.append(data)
    # Inject nonfinite values directly: JSON itself cannot represent them faithfully.
    for nonfinite: float in [INF, -INF, NAN]:
        for coordinate: int in range(2):
            var data: Dictionary = valid.duplicate(true)
            var point: Array[float] = [0.0, 0.0]
            point[coordinate] = nonfinite
            data["points"] = [point]
            malformed.append(data)
        var data: Dictionary = valid.duplicate(true)
        data["width"] = nonfinite
        malformed.append(data)
        for channel: int in range(4):
            var color_data: Dictionary = valid.duplicate(true)
            var rgba: Array[float] = [0.2, 0.4, 0.6, 0.8]
            rgba[channel] = nonfinite
            color_data["color"] = rgba
            malformed.append(color_data)
    for index: int in range(malformed.size()):
        _check(AtlasStroke.from_dict(malformed[index]) == null,
            "malformed/nonfinite stroke dictionary returns null: case %d" % index)


func _campaign() -> AtlasCampaign:
    var campaign: AtlasCampaign = AtlasCampaign.new()
    campaign.root_map_id = "world"
    var world: AtlasMapDocument = AtlasMapDocument.new("world", "Artwork test")
    var upper: AtlasFloor = AtlasFloor.new()
    upper.id = "upper"
    upper.display_name = "Upper"
    world.floors.append(upper)
    campaign.add_map(world)
    campaign.add_map(AtlasMapDocument.new("other", "Other map"))
    return campaign


func _test_vector_persistence() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floor_by_id("ground")
    var expected: Array[AtlasStroke] = [_line(), _dot()]
    floor.strokes = _copies(expected)
    floor.paint(Vector2i(-2, 3), 7)
    var floor_data: Dictionary = floor.to_dict()
    _check(floor_data.has("strokes"), "floor persists strokes explicitly")
    _check(_json_value(floor_data), "floor artwork is canonical JSON vector data")
    var restored_floor: AtlasFloor = AtlasFloor.from_dict(floor_data)
    _check(restored_floor != null, "floor with artwork restores")
    if restored_floor != null:
        _check(_same_strokes(restored_floor.strokes, expected), "floor preserves stroke order and values")
    var parsed: Variant = JSON.parse_string(JSON.stringify(campaign.to_dict()))
    _check(parsed is Dictionary, "campaign with artwork serializes without raster assets")
    if not parsed is Dictionary:
        return
    var restored: AtlasCampaign = AtlasCampaign.from_dict(parsed)
    _check(restored != null, "campaign with artwork restores from JSON")
    if restored == null:
        return
    var restored_map: AtlasMapDocument = restored.get_map("world")
    _check(restored_map != null, "artwork campaign retains original map")
    if restored_map == null:
        return
    var loaded: AtlasFloor = restored_map.floor_by_id("ground")
    _check(loaded != null, "artwork campaign retains original floor")
    if loaded != null:
        _check(_same_strokes(loaded.strokes, expected), "campaign JSON preserves full vector artwork")
        _check(loaded.get_terrain(Vector2i(-2, 3)) == 7, "artwork persistence retains terrain")
    _check(restored.get_map("other").floors[0].strokes.is_empty(),
        "empty artwork on another map remains empty")


func _test_legacy_campaign() -> void:
    var legacy_floor: Dictionary = {"id": "ground", "name": "Ground", "terrain": {"-2,3": 7}}
    var floor: AtlasFloor = AtlasFloor.from_dict(legacy_floor)
    _check(floor != null, "legacy floor without strokes loads")
    if floor != null:
        _check(floor.strokes.is_empty(), "legacy floor defaults to empty artwork")
        _check(floor.get_terrain(Vector2i(-2, 3)) == 7, "legacy floor retains terrain")
    var legacy: Dictionary = {
        "schema_version": 1, "name": "Legacy v1", "root_map_id": "world",
        "maps": [{"id": "world", "name": "Legacy world", "kind": "WORLD",
            "grid": {}, "floors": [legacy_floor], "default_floor_id": "ground"}],
        "links": [], "placements": []
    }
    var restored: AtlasCampaign = AtlasCampaign.from_dict(legacy)
    _check(restored != null, "legacy v1 campaign without artwork loads")
    if restored != null:
        var map: AtlasMapDocument = restored.get_map("world")
        _check(map != null, "legacy campaign retains root map")
        if map != null:
            _check(map.floors[0].strokes.is_empty(), "legacy campaign has empty artwork")


func _centerline_contains(strokes: Array[AtlasStroke], point: Vector2) -> bool:
    for stroke: AtlasStroke in strokes:
        if stroke == null or stroke.points.is_empty():
            continue
        if stroke.points.size() == 1 and stroke.points[0].distance_to(point) < EPSILON:
            return true
        for index: int in range(1, stroke.points.size()):
            var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
                point, stroke.points[index - 1], stroke.points[index])
            if closest.distance_to(point) < EPSILON:
                return true
    return false


func _test_partial_erase() -> void:
    var source: Array[AtlasStroke] = [_line()]
    var expected: Array[AtlasStroke] = _copies(source)
    # Two distant samples must erase their entire sweep, including the crossing.
    var path: PackedVector2Array = PackedVector2Array([Vector2(0.0, -1000.0), Vector2(0.0, 1000.0)])
    var path_before: PackedVector2Array = path.duplicate()
    var result: Array[AtlasStroke] = AtlasStrokeEraser.erase(source, path, 8.0)
    _check(result.size() == 2, "crossing eraser splits one line into two surviving parts")
    _check(_centerline_contains(result, Vector2(-40.0, 0.0))
        and _centerline_contains(result, Vector2(40.0, 0.0)), "partial erase keeps both far ends")
    _check(not _centerline_contains(result, Vector2.ZERO), "long gesture erases between path samples")
    _check(not _centerline_contains(result, Vector2(-5.0, 0.0))
        and not _centerline_contains(result, Vector2(5.0, 0.0)),
        "erase radius includes half the original stroke width")
    _check(_centerline_contains(result, Vector2(-7.0, 0.0))
        and _centerline_contains(result, Vector2(7.0, 0.0)), "partial erase preserves nearby outside geometry")
    for fragment: AtlasStroke in result:
        _check(fragment != null and fragment.is_valid(), "surviving fragment is a valid stroke")
        if fragment == null:
            continue
        _check(fragment.color.is_equal_approx(expected[0].color)
            and is_equal_approx(fragment.width, expected[0].width),
            "eraser preserves original style instead of inserting a background placeholder")
        _check(fragment != source[0], "eraser returns independent fragment objects")
    _check(_same_strokes(source, expected), "partial erase does not mutate source artwork")
    _check(path == path_before, "partial erase does not mutate gesture path")
    if not result.is_empty() and result[0] != null and not result[0].points.is_empty():
        result[0].points[0] = Vector2(900.0, 900.0)
        result[0].color = Color.WHITE
        _check(_same_strokes(source, expected), "mutating erased output cannot mutate source")


func _test_dot_erase() -> void:
    var source: Array[AtlasStroke] = [
        _dot(Vector2.ZERO), _dot(Vector2(5.0, 0.0)), _dot(Vector2(9.0, 0.0))
    ]
    var expected: Array[AtlasStroke] = _copies(source)
    var result: Array[AtlasStroke] = AtlasStrokeEraser.erase(
        source, PackedVector2Array([Vector2.ZERO]), 8.0)
    _check(result.size() == 1 and _same_stroke(result[0], expected[2]),
        "single-point eraser removes touched dots including stroke-radius overlap")
    _check(_same_strokes(source, expected), "dot erasing leaves all source dots unchanged")
    var cap_dots: Array[AtlasStroke] = [_dot(Vector2(3.0, 14.0)), _dot(Vector2(5.0, 15.0))]
    var cap_result: Array[AtlasStroke] = AtlasStrokeEraser.erase(cap_dots,
        PackedVector2Array([Vector2(0.0, -10.0), Vector2(0.0, 10.0)]), 8.0)
    _check(cap_result.size() == 1 and _same_stroke(cap_result[0], cap_dots[1]),
        "swept eraser has round endpoint coverage")
    var only_dot: Array[AtlasStroke] = [_dot(Vector2.ZERO)]
    _check(AtlasStrokeEraser.erase(only_dot, PackedVector2Array([Vector2.ZERO]), 8.0).is_empty(),
        "fully erased artwork is empty, with no background-colored replacement")


func _test_erase_no_op() -> void:
    var source: Array[AtlasStroke] = [_line(), _dot()]
    var expected: Array[AtlasStroke] = _copies(source)
    var result: Array[AtlasStroke] = AtlasStrokeEraser.erase(source,
        PackedVector2Array([Vector2(100.0, 100.0), Vector2(200.0, 200.0)]), 8.0)
    _check(_same_strokes(result, expected), "distant eraser is a value no-op")
    if result.size() == source.size():
        for index: int in range(result.size()):
            _check(result[index] != source[index], "no-op eraser still returns stroke copies")
        if result[0] != null and not result[0].points.is_empty():
            result[0].points[0] = Vector2(400.0, 400.0)
            _check(_same_strokes(source, expected), "no-op result points are independent")
    var empty_path: Array[AtlasStroke] = AtlasStrokeEraser.erase(source, PackedVector2Array(), 8.0)
    _check(_same_strokes(empty_path, expected), "empty eraser gesture leaves artwork unchanged")
    var empty: Array[AtlasStroke] = []
    _check(AtlasStrokeEraser.erase(empty, PackedVector2Array([Vector2.ZERO]), 8.0).is_empty(),
        "erasing an empty floor adds no artwork")


func _test_stroke_transaction() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floors[0]
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var empty: Array[AtlasStroke] = []
    var gesture: Array[AtlasStroke] = [AtlasStroke.new(PackedVector2Array([
        Vector2(-4.25, 1.125), Vector2(-1.5, 2.25), Vector2(0.25, 0.375), Vector2(8.5, -3.0)
    ]), Color(0.3, 0.5, 0.7, 0.8), 3.5)]
    _check(not history.is_dirty() and not history.can_undo() and not history.can_redo(),
        "new history begins saved and empty")
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, gesture)),
        "full multi-point stroke gesture executes as one transaction")
    _check(_same_strokes(floor.strokes, gesture), "transaction applies all gesture points")
    _check(history.can_undo() and history.is_dirty(), "stroke transaction is undoable and dirty")
    _check(history.undo() and floor.strokes.is_empty(), "one undo removes the entire stroke gesture")
    _check(not history.can_undo() and history.can_redo() and not history.is_dirty(),
        "single gesture has one undo step returning to initial saved state")
    _check(not history.undo(), "undo at beginning returns false")
    _check(history.redo() and _same_strokes(floor.strokes, gesture), "one redo restores full gesture")
    _check(not history.redo(), "redo at end returns false")
    var fragments: Array[AtlasStroke] = AtlasStrokeEraser.erase(floor.strokes,
        PackedVector2Array([Vector2(0.0, -100.0), Vector2(0.0, 100.0)]), 2.0)
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", floor.strokes, fragments)),
        "eraser output executes as one artwork transaction")
    _check(_same_strokes(floor.strokes, fragments), "erase transaction applies fragments")
    _check(history.undo() and _same_strokes(floor.strokes, gesture),
        "one undo restores pre-erase artwork completely")


func _test_captured_payload() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floors[0]
    var before: Array[AtlasStroke] = [_line()]
    var after: Array[AtlasStroke] = [_line(), _dot()]
    var expected_before: Array[AtlasStroke] = _copies(before)
    var expected_after: Array[AtlasStroke] = _copies(after)
    floor.strokes = _copies(before)
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var command: AtlasStrokeEdit = AtlasStrokeEdit.new("world", "ground", before, after)
    before[0].points[0] = Vector2(999.0, 999.0)
    before[0].color = Color.WHITE
    before[0].width = 90.0
    after[0].points[0] = Vector2(888.0, 888.0)
    after[1].color = Color.BLACK
    after[1].width = 80.0
    before.clear()
    after.clear()
    _check(history.execute(command), "command captures before/after payload at construction")
    _check(_same_strokes(floor.strokes, expected_after), "input mutation cannot alter captured after state")
    if floor.strokes.is_empty():
        return
    var detached_after: AtlasStroke = floor.strokes[0]
    _check(history.undo() and _same_strokes(floor.strokes, expected_before),
        "input mutation cannot alter captured before state")
    detached_after.points[0] = Vector2(777.0, 777.0)
    detached_after.color = Color.WHITE
    detached_after.width = 70.0
    if floor.strokes.is_empty():
        return
    var detached_before: AtlasStroke = floor.strokes[0]
    _check(history.redo() and _same_strokes(floor.strokes, expected_after),
        "applied document objects cannot mutate captured redo payload")
    detached_before.points[0] = Vector2(666.0, 666.0)
    _check(history.undo() and _same_strokes(floor.strokes, expected_before),
        "restored document objects cannot mutate captured undo payload")


func _test_original_document_target() -> void:
    var campaign: AtlasCampaign = _campaign()
    var ground: AtlasFloor = campaign.get_map("world").floor_by_id("ground")
    var target: AtlasFloor = campaign.get_map("world").floor_by_id("upper")
    var other: AtlasFloor = campaign.get_map("other").floors[0]
    ground.strokes = [_dot(Vector2(-30.0, 1.0))]
    other.strokes = [_dot(Vector2(30.0, 1.0))]
    var ground_before: Array[AtlasStroke] = _copies(ground.strokes)
    var other_before: Array[AtlasStroke] = _copies(other.strokes)
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var empty: Array[AtlasStroke] = []
    var artwork: Array[AtlasStroke] = [_line()]
    _check(history.execute(AtlasStrokeEdit.new("world", "upper", empty, artwork)),
        "command targets an explicit non-default floor")
    history.active_map_id = "other"
    _check(history.undo() and target.strokes.is_empty(), "undo targets original map/floor after navigation")
    _check(history.redo() and _same_strokes(target.strokes, artwork),
        "redo targets original map/floor after navigation")
    _check(_same_strokes(ground.strokes, ground_before) and _same_strokes(other.strokes, other_before),
        "navigation history never edits the current map or another floor")


func _test_rejected_commands() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floors[0]
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var empty: Array[AtlasStroke] = []
    var artwork: Array[AtlasStroke] = [_line()]
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", empty, empty)),
        "empty no-op is rejected")
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", artwork, empty)),
        "stale before snapshot is rejected")
    history.active_map_id = "missing"
    _check(not history.execute(AtlasStrokeEdit.new("missing", "ground", empty, artwork)),
        "unknown map is rejected")
    history.active_map_id = "world"
    _check(not history.execute(AtlasStrokeEdit.new("world", "missing", empty, artwork)),
        "unknown floor is rejected")
    var invalid: Array[AtlasStroke] = [AtlasStroke.new()]
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", empty, invalid)),
        "invalid stroke payload is rejected")
    history.active_map_id = "other"
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", empty, artwork)),
        "execute rejects a target that is not the active map")
    history.active_map_id = "world"
    _check(floor.strokes.is_empty() and not history.is_dirty()
        and not history.can_undo() and not history.can_redo(),
        "rejected commands preserve artwork, saved state and empty history")
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, artwork)),
        "valid edit still executes after rejected commands")
    history.mark_saved()
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", artwork, _copies(artwork))),
        "value-identical nonempty snapshots are a no-op")
    _check(not history.is_dirty(), "nonempty no-op preserves saved state")
    _check(history.undo() and floor.strokes.is_empty(), "no-op adds no undo step")
    _check(not history.execute(AtlasStrokeEdit.new("world", "ground", empty, empty)),
        "no-op while redo is available is rejected")
    _check(history.can_redo(), "rejected no-op preserves redo branch")
    _check(history.redo() and not history.is_dirty(), "redo still reaches saved state after no-op")


func _test_saved_state_and_branch() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floors[0]
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var empty: Array[AtlasStroke] = []
    var saved_artwork: Array[AtlasStroke] = [_line()]
    var branch_artwork: Array[AtlasStroke] = [_dot()]
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, saved_artwork)),
        "saved-state setup executes")
    history.mark_saved()
    _check(not history.is_dirty(), "mark_saved makes current state clean")
    _check(history.undo() and history.is_dirty(), "undo away from saved state is dirty")
    _check(history.redo() and not history.is_dirty(), "redo back to saved state is clean")
    _check(history.undo(), "undo prepares a divergent branch")
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, branch_artwork)),
        "divergent edit executes at same history length as saved state")
    _check(_same_strokes(floor.strokes, branch_artwork) and history.is_dirty(),
        "same-length divergent branch has a unique dirty history state")
    _check(not history.can_redo() and not history.redo(), "new branch invalidates former redo")
    _check(history.undo() and history.is_dirty(), "branch undo cannot falsely reach discarded saved state")
    _check(history.redo() and history.is_dirty(), "branch redo remains dirty until explicitly saved")
    history.mark_saved()
    _check(not history.is_dirty(), "new branch can be marked saved")


func _test_external_change_and_reset() -> void:
    var campaign: AtlasCampaign = _campaign()
    var floor: AtlasFloor = campaign.get_map("world").floors[0]
    var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
    history.active_map_id = "world"
    var empty: Array[AtlasStroke] = []
    var first: Array[AtlasStroke] = [_line()]
    var second: Array[AtlasStroke] = [_line(), _dot()]
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, first)),
        "external-change first transaction executes")
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", first, second)),
        "external-change second transaction executes")
    _check(history.undo() and history.can_redo(), "external-change setup has a redo branch")
    history.mark_saved()
    floor.strokes.append(_dot(Vector2(30.0, 30.0)))
    var external_artwork: Array[AtlasStroke] = _copies(floor.strokes)
    history.mark_external_change()
    _check(history.is_dirty(), "external change makes saved document dirty")
    _check(not history.can_redo() and not history.redo(), "external change invalidates redo")
    _check(_same_strokes(floor.strokes, external_artwork), "invalidated redo preserves external edit")
    history.mark_saved()
    _check(not history.is_dirty(), "external edit can be marked saved")
    history.mark_external_change()
    _check(history.is_dirty(), "external metadata change is dirty without a stroke transaction")

    var replacement: AtlasCampaign = _campaign()
    var replacement_floor: AtlasFloor = replacement.get_map("world").floors[0]
    history.reset(replacement)
    _check(not history.is_dirty() and not history.can_undo() and not history.can_redo(),
        "reset defaults to saved and discards all old commands")
    _check(not history.undo() and not history.redo(), "reset cannot replay old-campaign commands")
    history.active_map_id = "world"
    _check(history.execute(AtlasStrokeEdit.new("world", "ground", empty, first)),
        "history accepts edits against replacement campaign")
    _check(_same_strokes(replacement_floor.strokes, first)
        and _same_strokes(floor.strokes, external_artwork), "reset binds edits only to replacement campaign")
    history.reset(replacement, false)
    _check(history.is_dirty() and not history.can_undo() and not history.can_redo(),
        "reset(saved=false) starts dirty with no old commands")
    history.mark_saved()
    _check(not history.is_dirty(), "dirty reset state can be saved")
