extends SceneTree

var failures: int = 0


func _initialize() -> void:
    call_deferred("_run")


func _check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error("LAYER UI FAILED: " + message)


func _run() -> void:
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    editor.save_path = "user://layer-ui-%d.json" % Time.get_ticks_usec()
    root.add_child(scene)
    for frame: int in range(6):
        await process_frame
    # The fixed workspace and reusable panels must come from scene files.
    _check(editor.canvas == editor.get_node("Shell/CanvasAndInspector/Canvas"),
        "the editor uses the scene-owned canvas")
    _check(editor.board_dialog.grid_controls ==
        editor.board_dialog.get_node("Scroll/Margin/Form/GridControls"),
        "board creation uses the embedded grid form scene")
    _check(editor.grid_controls.distance_spinner ==
        editor.grid_controls.get_node("DistanceRow/DistanceSpinner"),
        "inspector grid form binds its scene controls")
    _check(editor.layer_panel.layer_list == editor.layer_panel.get_node("LayerList"),
        "layer panel binds its scene controls")
    _check(editor.overview_panel.preview == editor.overview_panel.get_node("Preview"),
        "overview embeds its preview panel")
    _check(editor.map_preview.texture_rect == editor.map_preview.get_node("TextureRect"),
        "map preview binds its scene texture display")

    _check_wrapped_labels(scene)

    var floor: AtlasFloor = editor.canvas.floor
    var basis: PackedVector2Array = editor.canvas.map.get_terrain_grid().cell_polygon(Vector2i.ZERO)
    var overlay: AtlasGrid = editor.canvas.map.grid.copy()
    overlay.cell_size = 90.0
    overlay.rotation = deg_to_rad(37)
    editor.apply_grid(overlay)
    editor.layer_panel._add_ink()
    var id: String = editor.canvas.active_layer_id
    _check(id != "ink" and floor.layer_by_id(id) is AtlasInkLayer, "new ink becomes the explicit edit target")
    _check(editor.canvas.map.get_terrain_grid().cell_polygon(Vector2i.ZERO) == basis,
        "adding a layer after an overlay change never rebases existing terrain")
    var stroke: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2(-3.125, 0.25), Vector2(30.5, 10.75)]))
    editor._on_stroke(stroke, false)
    _check((floor.layer_by_id(id) as AtlasInkLayer).strokes.size() == 1 and floor.strokes.is_empty(),
        "ink goes only into the selected layer")
    editor.layer_panel.lock_checkbox.button_pressed = true
    var command: AtlasEditCommand = editor.edits.get_undo_command()
    editor._on_stroke(stroke, false)
    _check((floor.layer_by_id(id) as AtlasInkLayer).strokes.size() == 1
        and editor.edits.get_undo_command() == command, "locked edit is rejected without adding history")
    editor._on_undo()
    _check(not floor.layer_by_id(id).locked, "undo unlocks the correct layer")
    editor.layer_panel.visibility_checkbox.button_pressed = false
    command = editor.edits.get_undo_command()
    editor._on_stroke(stroke, true)
    _check((floor.layer_by_id(id) as AtlasInkLayer).strokes.size() == 1
        and editor.edits.get_undo_command() == command, "hidden layer cannot be erased")
    editor._on_undo()
    editor.layer_panel.opacity_spinner.value = 0.5
    _check(floor.layer_by_id(id).opacity == 0.5, "opacity control edits selected layer metadata")
    editor.layer_panel._move(-1)
    _check(floor.layers[1].id == id, "lower moves the selected layer in canonical order")
    editor._on_undo()
    _check(floor.layers[-1].id == id, "undo restores canonical layer order")
    editor._on_redo()
    var pixels: Image = Image.create(9, 7, false, Image.FORMAT_RGBA8)
    pixels.fill(Color(0.2, 0.4, 0.6, 0.5))
    editor.import_raster(pixels)
    var raster_id: String = editor.canvas.active_layer_id
    var raster: AtlasRasterLayer = floor.layer_by_id(raster_id) as AtlasRasterLayer
    _check(raster != null and raster.chunks.size() == 1, "import creates a typed chunked raster layer")
    editor.select_layer("terrain")
    command = editor.edits.get_undo_command()
    editor._on_stroke(stroke, false)
    _check(editor.edits.get_undo_command() == command, "pen cannot treat terrain cells as ink")
    editor._on_save()
    var checkpoint: Dictionary = editor.campaign.to_dict()
    _check(not editor.edits.is_dirty(), "validated save clears dirty state")
    editor.select_layer(id)
    editor.layer_panel._rename("Renamed ink")
    editor._on_save()
    _check(FileAccess.file_exists(editor.save_path + ".bak"), "second save retains the previous checkpoint")
    _corrupt(editor.save_path)
    editor._on_load()
    _check(editor.campaign.to_dict() == checkpoint and editor.edits.is_dirty(),
        "Load recovers the complete previous checkpoint and marks it for repair")
    _check(editor.status_label.text.contains("Recovered backup"), "recovery is reported in the UI")
    var recovered_raster: AtlasRasterLayer = editor.canvas.floor.layer_by_id(raster_id) as AtlasRasterLayer
    _check(recovered_raster != null and recovered_raster.chunks["0,0"].image.get_data() == pixels.get_data(),
        "UI recovery hydrates exact raster pixels")
    _corrupt(editor.save_path + ".bak")
    var retained: AtlasCampaign = editor.campaign
    editor._on_load()
    _check(editor.campaign == retained and editor.edits.is_dirty(), "failed load never replaces active work or history")
    editor._on_save()
    _check(not editor.edits.is_dirty(), "saving recovered work establishes a valid new head")
    for suffix: String in ["", ".bak", ".pending", ".bak.pending"]:
        var file_path: String = editor.save_path + suffix
        if FileAccess.file_exists(file_path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
    var directory: String = editor.save_path + ".assets"
    for chunk: AtlasRasterChunk in recovered_raster.chunks.values():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(chunk.asset_id + ".webp")))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
    root.remove_child(scene)
    scene.free()
    if failures == 0:
        print("ATLAS_LAYER_UI_PASSED")
    quit(0 if failures == 0 else 1)


## Godot warns if an autowrapping Label has no positive width constraint.
## Traverse the instantiated scene, including embedded panel scenes and the
## remaining code-built inspector labels, so new controls cannot regress.
func _check_wrapped_labels(node: Node) -> void:
    if node is Label:
        var label: Label = node as Label
        if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
            _check(label.custom_minimum_size.x > 0.0,
                "wrapping label has explicit minimum width: " + str(label.get_path()))
    for child: Node in node.get_children():
        _check_wrapped_labels(child)


func _corrupt(path: String) -> void:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("invalid checkpoint")
    file.close()
