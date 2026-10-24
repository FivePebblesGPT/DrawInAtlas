extends SceneTree
## Real-renderer acceptance for the read-only preview and its asynchronous cache.

var checks: int = 0
var failures: int = 0
var _editor: AtlasEditor
var _panel: AtlasPreviewPanel
var _campaign: AtlasCampaign


func _initialize() -> void:
    call_deferred("_run")


func _check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        push_error("PREVIEW UI FAILED: " + message)


func _run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Preview UI smoke requires a real renderer, not the headless dummy driver.")
        quit(1)
        return
    root.mode = Window.MODE_WINDOWED
    root.size = Vector2i(1280, 800)
    root.content_scale_size = root.size
    _campaign = _fixture()
    var scene: Node = load("res://main.tscn").instantiate()
    _editor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    _editor.campaign = _campaign
    _editor.load_saved_on_startup = false
    _editor.use_system_clipboard = false
    root.add_child(scene)
    await _frames(6)
    _panel = _editor.map_preview
    _panel.clear_preview()
    _panel.cache.invalidate()
    _editor.canvas.render_grid = false
    _editor.canvas.preview = AtlasCanvas.Preview.OFF
    _editor.canvas.show_reference = false
    var canonical: Dictionary = _campaign.to_dict()

    await _floor_pixels()
    await _input_isolation()
    _check(_campaign.to_dict() == canonical and not _editor.edits.is_dirty(),
        "floor rendering, cache hits and preview input never mutate canonical data")

    # Keep the panel available for capture while preventing browser auto-requests
    # from masking which explicit request is being tested below.
    _editor.sidebar.select_view(&"Layers")
    await _invalidation()
    await _latest_request()
    await _cancel_and_replace()
    await _neutral_and_invalid()

    root.remove_child(scene)
    scene.free()
    print("ATLAS_PREVIEW_UI_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
    quit(0 if failures == 0 else 1)


func _fixture() -> AtlasCampaign:
    var campaign: AtlasCampaign = AtlasCampaign.new()
    campaign.root_map_id = "tower"
    var tower: AtlasMapDocument = AtlasMapDocument.new("tower", "Tower")
    tower.grid = AtlasGrid.new(AtlasGrid.Kind.SQUARE, 16.0)
    tower.grid.distance_unit = "mi"
    tower.grid.distance_per_cell = 3.0
    tower.floors[0].layers.append(_raster("ground-image", Color.RED))
    tower.floors[0].strokes.append(AtlasStroke.new(
        PackedVector2Array([Vector2(-16, -8), Vector2(16, -8)]), Color.YELLOW, 4.0))
    var upper: AtlasFloor = AtlasFloor.new()
    upper.id = "upper"
    upper.display_name = "Upper"
    upper.layers.append(_raster("upper-image", Color.BLUE))
    tower.floors.append(upper)
    var blank: AtlasFloor = AtlasFloor.new()
    blank.id = "blank"
    blank.display_name = "Blank"
    tower.floors.append(blank)
    var hidden: AtlasInkLayer = AtlasInkLayer.new("hidden", "Hidden artwork")
    hidden.visible = false
    hidden.strokes.append(AtlasStroke.new(PackedVector2Array([Vector2(10000, 10000)]), Color.GREEN, 500.0))
    tower.floors[0].layers.append(hidden)
    campaign.add_map(tower)
    var annex: AtlasMapDocument = AtlasMapDocument.new("annex", "Annex")
    annex.floors[0].layers.append(_raster("annex-image", Color.GREEN))
    campaign.add_map(annex)
    var link: AtlasMapLink = AtlasMapLink.new()
    link.id = "tower-to-annex"
    link.source_map_id = tower.id
    link.target_map_id = annex.id
    link.anchor = Vector2.ZERO
    campaign.links.append(link)
    return campaign


func _raster(id: String, color: Color) -> AtlasRasterLayer:
    var image: Image = Image.create(64, 48, false, Image.FORMAT_RGBA8)
    image.fill(color)
    var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
    layer.id = id
    layer.transform.origin = Vector2(-32, -24)
    return layer


func _frames(count: int = 4) -> void:
    for frame: int in range(count):
        await process_frame
    await RenderingServer.frame_post_draw


func _image() -> Image:
    return _panel.texture_rect.texture.get_image() if _panel.texture_rect.texture != null else null


func _center_is(color: Color) -> bool:
    var image: Image = _image()
    return image != null and image.get_pixelv(AtlasPreviewPanel.PREVIEW_SIZE / 2).is_equal_approx(color)


func _floor_pixels() -> void:
    var camera: Vector2 = _editor.canvas.camera_center
    var zoom: float = _editor.canvas.camera_zoom
    var layer_id: String = _editor.canvas.active_layer_id
    await _panel.request_preview(_campaign, "tower", "ground")
    _check(_center_is(Color.RED), "ground preview contains its raster, without grid, links or another floor")
    _check(_image() != null and _image().get_size() == AtlasPreviewPanel.PREVIEW_SIZE,
        "native capture has the declared bounded size")
    var viewport: SubViewport = _panel.get_node("PreviewRenderer")
    var renderer: AtlasCanvas = viewport.get_node("Canvas")
    _check(viewport.world_2d != root.world_2d and viewport.gui_disable_input,
        "preview has an isolated world and no viewport GUI input")
    _check(not renderer.render_grid and not renderer.show_reference and renderer.preview == AtlasCanvas.Preview.OFF,
        "private renderer suppresses references, grids and recursive child previews")
    _check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
        "completed capture does not keep rendering in the background")
    _check(_panel.cache.entry_count() == 1, "native capture populates one cache entry")
    var captured: Image = _image()
    _panel.request_preview(_campaign, "tower", "ground")
    _check(_image() != null and _image().get_data() == captured.get_data()
        and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
        "unchanged preview is served synchronously without waking the renderer")
    await _panel.request_preview(_campaign, "tower", "upper")
    _check(_center_is(Color.BLUE) and _panel.cache.entry_count() == 2,
        "another floor produces distinct native pixels and a separate cached image")
    _check(_editor.canvas.floor.id == "ground" and _editor.canvas.active_layer_id == layer_id
        and _editor.canvas.camera_center == camera and _editor.canvas.camera_zoom == zoom,
        "previewing a floor leaves the workspace's floor, layer and camera alone")
    _editor.switch_floor("upper")
    await _frames()
    var center: Vector2i = Vector2i(_editor.canvas.get_global_rect().get_center())
    _check(root.get_texture().get_image().get_pixelv(center).is_equal_approx(Color.BLUE),
        "active upper floor renders independently in the main canvas")
    _editor.switch_floor("ground")
    await _frames()
    _check(root.get_texture().get_image().get_pixelv(center).is_equal_approx(Color.RED),
        "returning to ground restores its own main-canvas artwork")
    await _panel.request_preview(_campaign, "tower", "upper")
    await _frames()
    var preview_center: Vector2i = Vector2i(_panel.texture_rect.get_global_rect().get_center())
    var screen: Image = root.get_texture().get_image()
    _check(screen.get_pixelv(preview_center).is_equal_approx(Color.BLUE),
        "sidebar texture displays the requested floor's actual pixels")
    DirAccess.make_dir_recursive_absolute("user://validation")
    _check(screen.save_png("user://validation/floors-and-preview.png") == OK, "save native floor/preview evidence")


func _input_isolation() -> void:
    var before: Dictionary = _campaign.to_dict()
    var center: Vector2 = _panel.texture_rect.get_global_rect().get_center()
    var camera: Vector2 = _editor.canvas.camera_center
    var zoom: float = _editor.canvas.camera_zoom
    _mouse(center, MOUSE_BUTTON_LEFT, true)
    var motion: InputEventMouseMotion = InputEventMouseMotion.new()
    motion.position = center + Vector2(25, 10)
    motion.global_position = motion.position
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(motion, true)
    _mouse(motion.position, MOUSE_BUTTON_LEFT, false)
    _mouse(center, MOUSE_BUTTON_WHEEL_UP, true)
    _mouse(center, MOUSE_BUTTON_WHEEL_UP, false)
    await _frames()
    var renderer: AtlasCanvas = _panel.get_node("PreviewRenderer/Canvas")
    _check(not _editor.canvas.is_editing() and not renderer.is_editing() and renderer.selection.is_empty(),
        "click/drag/wheel on the displayed preview starts no editing or selection")
    _check(_editor.canvas.camera_center == camera and _editor.canvas.camera_zoom == zoom
        and _campaign.to_dict() == before, "preview input cannot pan, zoom or paint the active document")


func _mouse(position: Vector2, button: MouseButton, pressed: bool) -> void:
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.position = position
    event.global_position = position
    event.button_index = button
    event.pressed = pressed
    root.push_input(event, true)


func _invalidation() -> void:
    var tower: AtlasMapDocument = _campaign.get_map("tower")
    var ground: AtlasRasterLayer = tower.floors[0].layer_by_id("ground-image") as AtlasRasterLayer
    ground.chunks["0,0"].image.fill(Color.GREEN)
    _check(_panel.cache.get_image(tower, "ground") == null, "in-place pixel edit invalidates the rendered floor")
    var before: Dictionary = _campaign.to_dict()
    await _panel.request_preview(_campaign, "tower", "ground")
    _check(_center_is(Color.GREEN), "recapture uses edited source pixels rather than stale GPU textures")
    ground.opacity = 0.5
    await _panel.request_preview(_campaign, "tower", "ground")
    var image: Image = _image()
    _check(image != null and image.get_pixel(96, 64).g > AtlasCanvas.EMPTY_COLOR.g
        and image.get_pixel(96, 64).g < Color.GREEN.g, "layer opacity invalidates and changes native composited pixels")
    ground.opacity = 1.0
    _check(_campaign.to_dict() == before, "capture does not materialize grids or modify artwork")
    ground.visible = false
    await _panel.request_preview(_campaign, "tower", "ground")
    _check(_center_is(Color.YELLOW), "hidden raster no longer affects preview framing or pixels")
    ground.visible = true


func _latest_request() -> void:
    _panel.cache.invalidate()
    _panel.request_preview(_campaign, "tower", "ground")
    _panel.request_preview(_campaign, "tower", "upper")
    await _panel.request_preview(_campaign, "annex", "ground")
    _check(_center_is(Color.GREEN) and _panel.caption.text.contains("Annex"),
        "rapid requests show only the latest selected destination")
    await _frames(6)
    _check(_center_is(Color.GREEN) and _panel.cache.entry_count() == 1
        and _panel.cache.get_image(_campaign.get_map("tower"), "ground") == null,
        "cancelled older captures cannot overwrite the image or cache later")
    _panel.cache.invalidate()
    _panel.request_preview(_campaign, "tower", "ground")
    var layer: AtlasRasterLayer = _campaign.get_map("tower").floors[0].layer_by_id("ground-image") as AtlasRasterLayer
    layer.chunks["0,0"].image.fill(Color.MAGENTA)
    await _frames(6)
    _check(_panel.texture_rect.texture == null and _panel.cache.entry_count() == 0
        and _panel.caption.text.contains("changed"), "source edits during capture never enter the cache as a consistent snapshot")
    await _panel.request_preview(_campaign, "tower", "ground")
    _check(_center_is(Color.MAGENTA), "a fresh request after an in-flight change captures the current artwork")


func _cancel_and_replace() -> void:
    _panel.cache.invalidate()
    _panel.request_preview(_campaign, "tower", "upper")
    _panel.clear_preview()
    await _frames(6)
    _check(_panel.texture_rect.texture == null and _panel.cache.entry_count() == 0,
        "clearing a pending preview cancels both publication and caching")
    var renderer: AtlasCanvas = _panel.get_node("PreviewRenderer/Canvas")
    _check(renderer.map == null and renderer.floor == null and renderer.campaign == null,
        "clear releases the renderer's source document references")
    _panel.request_preview(_campaign, "tower", "upper")
    var previous: AtlasMapDocument = _campaign.get_map("tower")
    var replacement: AtlasMapDocument = AtlasMapDocument.new("tower", "Replacement")
    _campaign.maps["tower"] = replacement
    await _frames(6)
    _check(_panel.texture_rect.texture == null and _panel.cache.entry_count() == 0,
        "a replaced campaign document cannot publish an older capture under the same ID")
    _campaign.maps["tower"] = previous


func _neutral_and_invalid() -> void:
    var before: Dictionary = _campaign.to_dict()
    await _panel.request_preview(_campaign, "tower", "blank")
    _check(_center_is(AtlasCanvas.EMPTY_COLOR) and _panel.caption.text.contains("empty"),
        "empty floor displays a neutral board without fabricated content")
    _panel.request_preview(_campaign, "tower", "absent")
    _check(_panel.texture_rect.texture == null and _panel.caption.text == "Preview unavailable",
        "missing floor clears the previous image and explains the unavailable preview")
    _check(_campaign.to_dict() == before, "empty/invalid requests preserve canonical floors, grid and layers")
