extends SceneTree

## Run: godot --headless --path . --script res://tests/smoke.gd
var failures: int = 0


func _initialize() -> void:
    # The SceneTree root is not ready during _initialize; defer UI integration checks.
    call_deferred("_run_suite")


func _run_suite() -> void:
    _test_grids()
    _test_placements()
    _test_zoom_gate()
    _test_campaign_roundtrip()
    _test_webp()
    await _test_editor_workflow()
    await _test_drawing_input()
    await _test_board_workflow()
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
    var city: AtlasMapDocument = restored.get_map("greyhaven")
    city.grid.distance_per_cell = 7.5
    city.grid.distance_unit = "km"
    var path: String = "user://atlas_smoke_campaign.json"
    _check(AtlasCampaignStore.save_campaign(restored, path) == OK, "campaign saves through real store")
    var reopened: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
    _check(reopened != null, "campaign reopens through real store")
    if reopened != null:
        _check(reopened.get_map("greyhaven").grid.distance_unit == "km"
            and reopened.get_map("greyhaven").grid.distance_per_cell == 7.5,
            "native per-map measurement survives file roundtrip")
        _check(reopened.get_map("world").grid.distance_unit == "mi"
            and reopened.get_map("world").grid.distance_per_cell == 3.0,
            "linked maps retain independent units through file roundtrip")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    root.add_child(scene)
    for frame: int in range(6):
        await process_frame
    _check(editor.canvas.clip_contents, "canvas drawing is clipped away from editor chrome")
    _check(is_equal_approx(editor.canvas.global_position.y, editor.sidebar.global_position.y),
        "canvas begins below the single menubar without duplicate workspace bars")
    var menu_bars: Array[Node] = scene.find_children("*", "MenuBar", true, false)
    _check(menu_bars.size() == 1 and (menu_bars[0] as MenuBar).get_menu_count() == 3,
        "one native MenuBar owns File, Edit and View menus")
    _check(not editor.automatic_navigation, "ordinary board zoom never navigates by default")
    _check(editor.map_list.item_count == 2, "sidebar maps are populated")
    editor._refresh_search_list("grey")
    _check(editor.search_map_ids == ["greyhaven"], "sidebar search filters campaign maps")
    editor._refresh_search_list("")

    # At max zoom: exactly three *additional* logical steps enter the city.
    var canvas: AtlasCanvas = editor.canvas
    var world: AtlasMapDocument = editor.campaign.get_map("world")
    canvas.camera_center = world.grid.cell_to_document(Vector2i(2, 0))
    canvas.camera_zoom = 3.0
    var pointer := canvas.size * 0.5
    for step: int in range(5):
        editor._on_wheel_step(1, pointer)
    _check(canvas.map.id == "world", "repeated boundary scroll stays on board unless enabled")
    editor.automatic_navigation = true
    editor._on_wheel_step(1, pointer)
    editor._on_wheel_step(1, pointer)
    editor._on_pointer_moved(pointer + Vector2(500, 500))
    _check(editor.zoom_gate.count == 0, "leaving a link discards pending automatic navigation")
    editor._on_wheel_step(1, pointer)
    editor._on_wheel_step(1, pointer)
    _check(canvas.map.id == "world", "two blocked inward steps stay on parent map")
    editor._on_wheel_step(1, pointer)
    _check(canvas.map.id == "greyhaven", "third blocked inward step enters city")

    var city_units: String = canvas.map.grid.distance_unit
    var city_cell_size: float = canvas.map.grid.cell_size
    editor._on_distance_changed(3.0)
    editor._on_unit_changed(1)
    _check(canvas.map.grid.distance_per_cell == 3.0 and canvas.map.grid.distance_unit == "km",
        "native distance and units can be chosen per map")
    _check(world.grid.distance_per_cell == 3.0 and world.grid.distance_unit == "mi",
        "changing city units never harmonizes world units")
    _check(canvas.map.grid.cell_size == city_cell_size, "measurement metadata never rescales artwork")
    _check(city_units == "ft", "sample maps start with independent native units")

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
    editor.sidebar.select_view(&"Maps")
    var maps_button: Button = editor.sidebar.get_node("%MapsButton")
    maps_button.pressed.emit()
    for frame: int in range(3):
        await process_frame
    _check(not editor.sidebar.is_panel_expanded(), "active sidebar icon collapses panel")
    maps_button.pressed.emit()
    for frame: int in range(3):
        await process_frame
    _check(editor.sidebar.is_panel_expanded(), "active sidebar icon reopens panel")
    root.remove_child(scene)
    scene.free()


func _test_drawing_input() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    editor.save_path = "user://atlas_input_smoke.json"
    root.add_child(scene)
    for frame: int in range(6):
        await process_frame
    var canvas: AtlasCanvas = editor.canvas
    canvas.map.grid.kind = AtlasGrid.Kind.GRIDLESS
    canvas.floor.terrain.clear()
    canvas.camera_center = Vector2(-100.25, 50.125)
    canvas.camera_zoom = 2.0
    editor.edits.reset(editor.campaign, true)
    editor.edits.active_map_id = canvas.map.id
    var ui: Control = scene.get_node("Interface/UI")
    var edit_menu: PopupMenu = ui.get_node("%Edit")
    var file_menu: PopupMenu = ui.get_node("%File")
    var view_menu: PopupMenu = ui.get_node("%View")
    _check(edit_menu.is_item_disabled(0) and edit_menu.is_item_disabled(1),
        "Edit menu disables undo and redo for a fresh history")
    view_menu.id_pressed.emit(1)
    _check(not canvas.show_grid and not view_menu.is_item_checked(1),
        "View menu changes the real grid setting and checked state together")
    view_menu.id_pressed.emit(1)
    (ui.get_node("%MenuBar") as MenuBar).grab_focus()
    _key(KEY_B, true)
    for frame: int in range(3):
        await process_frame
    _check(not editor.sidebar.is_panel_expanded(), "Ctrl+B toggles once when the menubar has focus")
    _key(KEY_B, true)
    for frame: int in range(3):
        await process_frame
    _check(editor.sidebar.is_panel_expanded(), "Ctrl+B restores the sidebar before another action")
    # Visibility is now undoable; discard the setup edits before testing ink checkpoints.
    editor.edits.reset(editor.campaign, true)
    editor.edits.active_map_id = canvas.map.id
    var start: Vector2 = Vector2(40, 100)
    var middle: Vector2 = Vector2(140, 100)
    var finish: Vector2 = Vector2(240, 100)
    var expected_start: Vector2 = canvas.local_to_document(start)
    _pointer_button(canvas, start, true)
    _pointer_motion(canvas, middle)
    _check(canvas.floor.strokes.is_empty(), "in-flight drawing is preview only")
    _check(not editor.edits.is_dirty(), "preview alone does not dirty the document")
    _pointer_motion(canvas, finish)
    _pointer_button(canvas, finish, false)
    _check(canvas.floor.strokes.size() == 1, "one full input gesture commits one stroke")
    if canvas.floor.strokes.is_empty():
        root.remove_child(scene)
        scene.free()
        return
    _check(canvas.floor.strokes[0].points[0].is_equal_approx(expected_start),
        "input is transformed into continuous negative document coordinates")
    _check(canvas.floor.terrain.is_empty(), "gridless drawing never fabricates a terrain cell")
    var original: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
    _check(editor.edits.is_dirty(), "drawing marks unsaved work")
    _check(not edit_menu.is_item_disabled(0) and edit_menu.is_item_disabled(1),
        "Edit menu reflects current drawing history")
    _check(editor.title_label.text.begins_with("* "), "single menubar title shows unsaved work")
    editor.brush_width_spinner.get_line_edit().grab_focus()
    _key(KEY_Z, true)
    _check(AtlasStroke.same_artwork(original, canvas.floor.strokes),
        "menu accelerator hints do not steal undo from a focused numeric input")
    canvas.grab_focus()
    _key(KEY_Z, true)
    _check(canvas.floor.strokes.is_empty() and not editor.edits.is_dirty(),
        "Ctrl+Z undoes entire gesture back to clean state")
    _key(KEY_Z, true, true)
    _check(AtlasStroke.same_artwork(original, canvas.floor.strokes), "Ctrl+Shift+Z restores exact artwork")
    _pointer_button(canvas, Vector2(90, 80), true)
    _pointer_button(canvas, Vector2(90, 80), false)
    _check(canvas.floor.strokes.size() == 2 and canvas.floor.strokes[-1].points.size() == 1,
        "a click without motion commits an undoable ink dot")
    editor._on_undo()
    _key(KEY_E)
    canvas.brush_width = 20.0
    _pointer_button(canvas, Vector2(140, 60), true)
    _pointer_motion(canvas, Vector2(140, 140))
    _pointer_button(canvas, Vector2(140, 140), false)
    _check(canvas.floor.strokes.size() == 2, "eraser gesture cuts a real gap into ink")
    edit_menu.id_pressed.emit(0)
    _check(AtlasStroke.same_artwork(original, canvas.floor.strokes), "eraser undo restores unsplit ink")
    edit_menu.id_pressed.emit(1)
    file_menu.id_pressed.emit(0)
    _check(not editor.edits.is_dirty(), "successful Save establishes a clean checkpoint")
    _check(not editor.title_label.text.begins_with("* "), "File Save clears the global dirty marker")
    var saved: Array[AtlasStroke] = AtlasStroke.clone_all(canvas.floor.strokes)
    editor._on_undo()
    _check(editor.edits.is_dirty(), "undo away from saved state is dirty")
    editor.save_path = "user://atlas_missing_directory_582701/campaign.json"
    editor._on_save()
    _check(editor.edits.is_dirty(), "failed Save cannot clear dirty state")
    editor.save_path = "user://atlas_input_smoke.json"
    file_menu.id_pressed.emit(1)
    _check(not editor.edits.is_dirty() and not editor.edits.can_undo(), "Load starts a fresh clean history")
    _check(AtlasStroke.same_artwork(saved, canvas.floor.strokes), "Save/Load preserves erased vector geometry")
    _key(KEY_B)
    _pointer_button(canvas, start, true)
    _pointer_motion(canvas, finish)
    var zoom_before: float = canvas.camera_zoom
    var wheel: InputEventMouseButton = InputEventMouseButton.new()
    wheel.position = canvas.global_position + finish
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP
    wheel.pressed = true
    root.push_input(wheel, true)
    _check(canvas.is_editing() and canvas.camera_zoom == zoom_before,
        "wheel zoom cannot distort an in-flight document-space stroke")
    _key(KEY_ESCAPE)
    _pointer_button(canvas, finish, false)
    _check(AtlasStroke.same_artwork(saved, canvas.floor.strokes) and not editor.edits.is_dirty(),
        "Escape cancels a preview without adding history")
    _pointer_button(canvas, start, true)
    _pointer_motion(canvas, Vector2(canvas.size.x + 20, 100))
    _pointer_button(canvas, Vector2(canvas.size.x + 20, 100), false)
    _check(canvas.floor.strokes.size() == saved.size() + 1
        and canvas.floor.strokes[-1].points.size() == 1,
        "dragging into editor chrome never records off-canvas points")
    editor._on_undo()
    _pointer_button(canvas, start, true)
    _pointer_motion(canvas, finish)
    var original_floor: AtlasFloor = canvas.floor
    editor._show_map(editor.campaign.get_map("greyhaven"))
    _pointer_button(canvas, finish, false)
    _check(AtlasStroke.same_artwork(saved, original_floor.strokes) and canvas.floor.strokes.is_empty(),
        "map switch cancels pending ink instead of committing into another document")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(editor.save_path))
    root.remove_child(scene)
    scene.free()


func _pointer_button(canvas: AtlasCanvas, local_position: Vector2, pressed: bool) -> void:
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.position = canvas.global_position + local_position
    event.global_position = event.position
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    root.push_input(event, true)


func _pointer_motion(canvas: AtlasCanvas, local_position: Vector2) -> void:
    var event: InputEventMouseMotion = InputEventMouseMotion.new()
    event.position = canvas.global_position + local_position
    event.global_position = event.position
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(event, true)


func _key(keycode: Key, control: bool = false, shift: bool = false) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.keycode = keycode
    event.ctrl_pressed = control
    event.shift_pressed = shift
    event.pressed = true
    root.push_input(event, true)
    event = event.duplicate() as InputEventKey
    event.pressed = false
    root.push_input(event, true)


func _test_board_workflow() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    editor.save_path = "user://atlas_board_workflow.json"
    root.add_child(scene)
    for frame: int in range(6):
        await process_frame
    editor.edits.mark_saved()
    var source_before: Dictionary = editor.canvas.map.to_dict().duplicate(true)
    var ui: Control = scene.get_node("Interface/UI")
    (ui.get_node("%File") as PopupMenu).id_pressed.emit(3)
    _check(editor.board_dialog.visible and not editor.edits.is_dirty(), "New board opens without mutating the campaign")
    editor.board_dialog.name_input.text = "  "
    editor.board_dialog.name_input.text_changed.emit(editor.board_dialog.name_input.text)
    _check(editor.board_dialog.get_ok_button().disabled, "blank board name disables Create")
    editor.board_dialog._request_board()
    _check(editor.campaign.maps.size() == 2, "invalid confirmation creates no map")
    var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 80.0)
    grid.origin = Vector2(-30.25, 20.5)
    grid.rotation = deg_to_rad(15)
    grid.distance_per_cell = 3.0
    grid.distance_unit = "mi"
    editor.board_dialog.name_input.text = "  Exploration  "
    editor.board_dialog.name_input.text_changed.emit(editor.board_dialog.name_input.text)
    editor.board_dialog.grid_controls.set_grid(grid)
    editor.board_dialog._request_board()
    var id: String = editor.canvas.map.id
    _check(editor.campaign.maps.size() == 3 and editor.canvas.map.display_name == "Exploration",
        "dialog creates and opens a named independent board")
    _check(editor.canvas.map.grid.same_as(grid) and editor.canvas.floor.strokes.is_empty()
        and editor.canvas.floor.terrain.is_empty(), "new board keeps chosen grid/units without copying artwork")
    _check(editor.campaign.links.size() == 1 and editor.campaign.placements.is_empty(),
        "blank board creation does not invent links or placements")
    editor._on_undo()
    _check(editor.canvas.map.id == "world" and not editor.campaign.maps.has(id) and not editor.edits.is_dirty(),
        "undo creation returns safely to the saved source board")
    editor._on_redo()
    _check(editor.canvas.map.id == id and editor.canvas.map.grid.same_as(grid),
        "redo creation restores the same board identity and configuration")
    editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-10.125, 3.25), Vector2(45.5, -30.75)])), false)
    var ink_before: Array[AtlasStroke] = AtlasStroke.clone_all(editor.canvas.floor.strokes)
    editor.grid_controls.size_spinner.value = 120.0
    editor.grid_controls.rotation_spinner.value = 37.0
    editor.grid_controls.origin_x_spinner.value = 50.25
    editor.grid_controls.origin_y_spinner.value = -80.5
    editor.grid_controls.shape_picker.select(AtlasGrid.Kind.SQUARE)
    editor.grid_controls.shape_picker.item_selected.emit(AtlasGrid.Kind.SQUARE)
    editor.grid_controls.distance_spinner.value = 2.5
    editor.grid_controls.unit_picker.select(1)
    editor.grid_controls.unit_picker.item_selected.emit(1)
    (ui.get_node("%View") as PopupMenu).id_pressed.emit(1)
    var updated: AtlasGrid = editor.canvas.map.grid
    _check(updated.kind == AtlasGrid.Kind.SQUARE and updated.cell_size == 120.0
        and updated.origin == Vector2(50.25, -80.5) and is_equal_approx(rad_to_deg(updated.rotation), 37.0),
        "inspector edits grid shape, spacing, origin and rotation")
    _check(updated.distance_per_cell == 2.5 and updated.distance_unit == "km" and not updated.visible,
        "native units and visibility belong to this board")
    _check(AtlasStroke.same_artwork(ink_before, editor.canvas.floor.strokes), "grid controls never rescale ink")
    _check(editor.campaign.get_map("world").to_dict() == source_before, "grid editing leaves source artwork and units untouched")
    var saved_grid: AtlasGrid = updated.copy()
    editor._on_save()
    editor._on_load()
    var restored: AtlasMapDocument = editor.campaign.get_map(id)
    _check(restored != null and restored.grid.same_as(saved_grid), "board identity and all grid settings survive Save/Load")
    if restored != null:
        _check(AtlasStroke.same_artwork(restored.floors[0].strokes, ink_before), "board artwork survives grid configuration roundtrip")
    _check(not editor.edits.is_dirty() and not editor.edits.can_undo(), "loading starts a clean board history")
    editor.open_board_dialog()
    editor.board_dialog.hide()
    _check(editor.campaign.maps.size() == 3 and not editor.edits.is_dirty(), "canceling creation changes no data or history")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(editor.save_path))
    root.remove_child(scene)
    scene.free()
