extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("_run")


func _check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("ORGANIZATION UI FAILED: " + message)


func _run() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    editor.use_system_clipboard = false
    var directory: String = "user://organization-ui-%d" % Time.get_ticks_usec()
    editor.save_path = directory + "/campaign.json"
    root.add_child(scene)
    for frame: int in range(6):
        await process_frame
    var canvas: AtlasCanvas = editor.canvas
    canvas.camera_center = Vector2(-20.5, 14.25)
    canvas.camera_zoom = 1.7
    var overlay: AtlasGrid = canvas.map.grid.copy()
    overlay.kind = AtlasGrid.Kind.SQUARE
    overlay.cell_size = 80.0
    editor.apply_grid(overlay)
    _check(editor.create_floor("Upper"), "add creates an independent floor")
    var world: AtlasMapDocument = canvas.map
    var upper_id: String = canvas.floor.id
    _check(world.default_floor_id == "ground" and upper_id != "ground" and world.floors.size() == 2,
        "adding/activating floor does not change document default")
    _check(canvas.floor.strokes.is_empty() and canvas.floor.terrain.is_empty(), "new floor copies no artwork")
    _check(canvas.camera_center == Vector2(-20.5, 14.25) and canvas.camera_zoom == 1.7,
        "first visit inherits camera for aligned floors")
    canvas.camera_center = Vector2(140, -75)
    canvas.camera_zoom = 2.3
    editor.layer_panel._add_ink()
    var upper_layer: String = canvas.active_layer_id
    editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2(-1.25, 0.5), Vector2(24.125, 12.75)])), false)
    editor.edits.mark_saved()
    var canonical: Dictionary = editor.campaign.to_dict()
    _check(editor.switch_floor("ground"), "existing floor activates")
    _check(canvas.floor.id == "ground" and canvas.camera_center == Vector2(-20.5, 14.25)
        and canvas.camera_zoom == 1.7, "ground camera is restored exactly")
    _check(editor.campaign.to_dict() == canonical and not editor.edits.is_dirty(), "floor navigation never dirties canonical data")
    editor._on_stroke(AtlasStroke.new(PackedVector2Array([Vector2.ZERO]), Color.RED), false)
    _check((world.floor_by_id(upper_id).layer_by_id(upper_layer) as AtlasInkLayer).strokes.size() == 1
        and world.floor_by_id("ground").strokes.size() == 1, "artwork edit targets only the active floor")
    _check(editor.switch_floor(upper_id) and canvas.camera_center == Vector2(140, -75)
        and canvas.camera_zoom == 2.3 and canvas.active_layer_id == upper_layer, "return restores floor camera and layer preference")
    editor.floor_name_input.text = "Tower top"
    editor.floor_name_input.text_submitted.emit(editor.floor_name_input.text)
    _check(canvas.floor.display_name == "Tower top", "floor rename is wired through UI")
    editor._on_undo()
    _check(canvas.floor.display_name == "Upper", "undo floor rename keeps its art and identity")
    editor._on_redo()
    _check(editor.move_floor(-1) and world.floors[0].id == upper_id and canvas.floor.id == upper_id,
        "floor reorder keeps the viewer on the same stable identity")
    _check(editor.make_floor_default() and world.default_floor_id == upper_id, "default floor changes only on explicit action")
    _check(world.get_terrain_grid("ground").kind == AtlasGrid.Kind.HEX_POINTY
        and world.get_terrain_grid("ground").cell_size == 45.0
        and world.get_terrain_grid(upper_id).cell_size == 80.0, "default/reorder never rebase legacy terrain geometry")
    _check(world.grid.cell_size == 80.0 and world.grid.distance_unit == "mi" and world.grid.distance_per_cell == 3.0,
        "floor controls never change board grid or exploration scale")
    _check(editor.open_map("greyhaven") and editor.create_floor("Roof"), "another board has its own floor set")
    var roof_id: String = canvas.floor.id
    var pixels: Image = Image.create(12, 10, false, Image.FORMAT_RGBA8)
    pixels.fill(Color(0.2, 0.4, 0.6, 0.5))
    editor.import_raster(pixels)
    var roof_layer: String = canvas.active_layer_id
    _check(editor.update_map_metadata("Greyhaven tower", ["town", "tower"]), "board rename and tags are reversible metadata edits")
    editor._on_back()
    _check(canvas.map.id == "world" and canvas.floor.id == upper_id
        and canvas.camera_center == Vector2(140, -75) and canvas.camera_zoom == 2.3
        and canvas.active_layer_id == upper_layer, "Back restores source floor, exact camera and selected layer")
    var link: AtlasMapLink = AtlasMapLink.new()
    link.id = "upper-to-roof"
    link.source_map_id = "world"
    link.source_floor_id = upper_id
    link.target_map_id = "greyhaven"
    link.target_floor_id = roof_id
    link.anchor = Vector2(-200, -200)
    link.target_focus = Vector2(33.5, -11.25)
    link.target_zoom = 2.0
    editor.campaign.links.append(link)
    editor._enter_link(link)
    _check(canvas.map.id == "greyhaven" and canvas.floor.id == roof_id and canvas.camera_center == link.target_focus
        and canvas.camera_zoom == 2.0 and canvas.active_layer_id == roof_layer, "link arrives at its explicit floor/camera with valid layer preference")
    editor._on_back()
    var count: int = editor.history.size()
    var focus: Vector2 = canvas.camera_center
    var valid_floor: String = link.target_floor_id
    link.target_floor_id = "missing"
    editor._enter_link(link)
    _check(editor.history.size() == count and canvas.floor.id == upper_id and canvas.camera_center == focus,
        "failed floor arrival keeps source view and history untouched")
    link.target_floor_id = valid_floor
    editor.edits.mark_saved()
    canonical = editor.campaign.to_dict()
    editor.overview_panel.mode_picker.select(AtlasOverview.Filter.MAP)
    editor._refresh_search_list("")
    _check(editor.overview_panel.entries.size() == 1 and editor.overview_panel.entries[0].link_id == link.id,
        "current-floor overview excludes ground-floor entrances")
    _check(editor.campaign.find_links_at("world", link.anchor, "ground").is_empty()
        and editor.campaign.find_links_at("world", link.anchor, upper_id).size() == 1, "canvas hit tests honor source floor")
    editor.overview_panel.mode_picker.select(AtlasOverview.Filter.CAMPAIGN)
    editor._refresh_search_list("#tower")
    _check(editor.overview_panel.entries.size() == 2, "tag query finds both floors of the tagged board")
    editor._refresh_search_list("Roof")
    _check(editor.overview_panel.entries.size() == 1 and editor.overview_panel.entries[0].floor_id == roof_id,
        "floor-name search retains exact target floor metadata")
    editor.overview_panel.entry_activated.emit(editor.overview_panel.entries[0])
    _check(canvas.map.id == "greyhaven" and canvas.floor.id == roof_id, "overview Open activates the selected floor")
    _check(editor.campaign.to_dict() == canonical and not editor.edits.is_dirty(), "search/open/preview requests are read-only")
    _check(not editor.remove_floor() and canvas.map.floor_by_id(roof_id) != null, "referenced floor cannot be removed")
    _check(editor.create_floor("Spare"), "unreferenced floor create")
    var spare_id: String = canvas.floor.id
    _check(editor.remove_floor() and canvas.map.floor_by_id(canvas.floor.id) != null,
        "deleting active floor selects a valid fallback")
    editor._on_undo()
    _check(canvas.map.floor_by_id(spare_id) != null and editor.switch_floor(spare_id), "undo removal restores floor identity and contents")
    editor._on_save()
    var saved: Dictionary = editor.campaign.to_dict()
    editor._on_load()
    _check(editor.campaign.to_dict() == saved and canvas.map.id == "world" and canvas.floor.id == upper_id,
        "schema6 save/load preserves metadata/floors and uses persisted startup default")
    var city: AtlasMapDocument = editor.campaign.get_map("greyhaven")
    var raster: AtlasRasterLayer = city.floor_by_id(roof_id).layer_by_id(roof_layer) as AtlasRasterLayer
    _check(raster != null and raster.chunks["0,0"].image.get_data() == pixels.get_data(), "inactive floor raster data is fully persisted")
    root.remove_child(scene)
    scene.free()
    _remove(directory)
    print("ATLAS_ORGANIZATION_UI_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
    quit(0 if failures == 0 else 1)


func _remove(path: String) -> void:
    for name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(name))
    for name: String in DirAccess.get_directories_at(path):
        _remove(path.path_join(name))
    DirAccess.remove_absolute(path)
