extends SceneTree

## Run: godot --headless --path . --script res://tests/smoke.gd
var failures: int = 0


func _initialize() -> void:
    _test_grids()
    _test_placements()
    _test_zoom_gate()
    _test_campaign_roundtrip()
    _test_webp()
    _test_editor_workflow()
    if failures == 0:
        print("ATLAS_TESTS_PASSED")
    else:
        push_error("ATLAS_TESTS_FAILED: %d" % failures)
    quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
    if not condition:
        failures += 1
        push_error("FAILED: " + description)


func _test_grids() -> void:
    for kind in [AtlasGrid.Kind.SQUARE, AtlasGrid.Kind.HEX_POINTY, AtlasGrid.Kind.HEX_FLAT]:
        var grid := AtlasGrid.new(kind, 42.0)
        grid.origin = Vector2(97.0, -28.0)
        grid.rotation = deg_to_rad(37.0)
        for x in range(-4, 5):
            for y in range(-4, 5):
                var cell := Vector2i(x, y)
                var center := grid.cell_to_document(cell)
                _check(grid.document_to_cell(center) == cell, "grid roundtrip %s %s" % [kind, cell])
                _check(grid.cell_polygon(cell).size() >= 4, "grid polygon is available")
        _check(grid.neighbors(Vector2i.ZERO).size() == (4 if kind == AtlasGrid.Kind.SQUARE else 6),
            "grid adjacency count")


func _test_placements() -> void:
    var placement := AtlasPlacement.new()
    placement.origin = Vector2(84.0, -17.0)
    placement.rotation = deg_to_rad(37.0)
    placement.parent_units_per_cell = 24.0
    placement.child_units_per_cell = 64.0
    placement.columns = 20
    placement.rows = 15
    var parent_position := placement.local_to_parent() * Vector2(8.0, 6.0)
    _check(placement.contains_parent_point(parent_position), "rotated placement hit test")
    _check(placement.parent_to_local(parent_position).distance_to(Vector2(8.0, 6.0)) < 0.001,
        "rotated placement inverse")
    _check(not placement.contains_parent_point(placement.local_to_parent() * Vector2(-1.0, 8.0)),
        "placement rejects outside")


func _test_zoom_gate() -> void:
    var gate := AtlasZoomGate.new()
    _check(not gate.accept_blocked_step(1, "city", 1000), "step one does not transition")
    _check(not gate.accept_blocked_step(1, "city", 1100), "step two does not transition")
    _check(gate.accept_blocked_step(1, "city", 1200), "step three transitions")
    _check(gate.count == 0, "gate resets after transition")
    gate.accept_blocked_step(1, "city", 1300)
    _check(not gate.accept_blocked_step(-1, "return", 1400), "reverse resets")
    _check(gate.count == 1, "reverse starts at one")
    _check(not gate.accept_blocked_step(-1, "return", 2800), "timeout resets")
    _check(gate.count == 1, "timeout starts at one")
    _check(not gate.accept_blocked_step(-1, "different", 2900), "candidate change resets")
    _check(gate.count == 1, "candidate starts at one")


func _test_campaign_roundtrip() -> void:
    var sample := AtlasCampaign.sample()
    var raw := JSON.stringify(sample.to_dict())
    var parsed: Variant = JSON.parse_string(raw)
    var restored := AtlasCampaign.from_dict(parsed)
    _check(restored != null, "campaign restore")
    if restored == null:
        return
    _check(restored.maps.size() == 2, "campaign has world and city")
    var world := restored.get_map("world")
    var anchor := world.grid.cell_to_document(Vector2i(2, 0))
    _check(restored.find_links_at("world", anchor).size() == 1, "city link index works")
    _check(world.floors[0].get_terrain(Vector2i.ZERO) > 0, "tile paint survives JSON")
    _check(AtlasCampaign.from_dict({"schema_version": 999}) == null, "version mismatch fails")


func _test_webp() -> void:
    var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.2, 0.4, 0.6, 1.0))
    var file_path := "user://atlas_smoke.webp"
    _check(AtlasWebPStore.write_image(file_path, image) == OK, "lossless WebP save")
    var restored := AtlasWebPStore.read_image(file_path)
    _check(restored != null, "lossless WebP decode")
    if restored != null:
        _check(restored.get_pixel(3, 3).is_equal_approx(image.get_pixel(3, 3)),
            "lossless WebP pixel match")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


func _test_editor_workflow() -> void:
    var editor: Variant = load("res://main.tscn").instantiate()
    root.add_child(editor)

    # At max zoom: exactly three *additional* logical steps enter the city.
    var canvas: AtlasCanvas = editor.canvas
    var world: AtlasMapDocument = editor.campaign.get_map("world")
    canvas.camera_center = world.grid.cell_to_document(Vector2i(2, 0))
    canvas.camera_zoom = 3.0
    var pointer := canvas.size * 0.5
    editor._on_wheel_step(1, pointer)
    editor._on_wheel_step(1, pointer)
    _check(canvas.map.id == "world", "two blocked inward steps stay on parent map")
    editor._on_wheel_step(1, pointer)
    _check(canvas.map.id == "greyhaven", "third blocked inward step enters city")

    var city: AtlasMapDocument = editor.campaign.get_map("greyhaven")
    var parent_before := JSON.stringify(city.floors[0].terrain)
    editor._on_create_battlemap(Vector2(-100, -70), Vector2(150, 125), deg_to_rad(37))
    _check(canvas.map.kind == "BATTLEMAP", "drag creation opens a child battlemap workspace")
    _check(editor.campaign.placements.size() == 1, "child has a placement")
    if not editor.campaign.placements.is_empty():
        var placement: AtlasPlacement = editor.campaign.placements[0]
        _check(not placement.symbolic, "city placement uses spatial reference")
        _check(is_equal_approx(rad_to_deg(placement.rotation), 37.0), "battlemap angle persists")

    editor._on_select(Vector2i(0, 0))
    editor.locked_to_cell = true
    editor._on_paint(Vector2i(1, 0))
    _check(canvas.floor.get_terrain(Vector2i(1, 0)) == 0, "cell lock blocks neighbor edit")
    editor._on_paint(Vector2i(0, 0))
    _check(canvas.floor.get_terrain(Vector2i(0, 0)) == editor.palette_id, "cell lock permits selected cell")
    _check(JSON.stringify(city.floors[0].terrain) == parent_before,
        "painting child does not change parent")

    canvas.camera_zoom = 0.5
    pointer = canvas.size * 0.5
    editor._on_wheel_step(-1, pointer)
    editor._on_wheel_step(-1, pointer)
    _check(canvas.map.kind == "BATTLEMAP", "two blocked outward steps stay in battlemap")
    editor._on_wheel_step(-1, pointer)
    _check(canvas.map.id == "greyhaven", "third blocked outward step returns to city")
    root.remove_child(editor)
    editor.free()
