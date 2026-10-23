extends SceneTree
## Run with a real display/renderer; compares actual framebuffer pixels outside the canvas.


func _initialize() -> void:
    call_deferred("_run_suite")


func _run_suite() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Visual smoke requires a real renderer, not the headless dummy driver.")
        quit(1)
        return
    root.mode = Window.MODE_WINDOWED
    root.size = Vector2i(1280, 720)
    root.content_scale_size = Vector2i(1280, 720)
    var scene: Node = load("res://main.tscn").instantiate()
    var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
    editor.load_saved_on_startup = false
    root.add_child(scene)
    for frame: int in range(8):
        await process_frame

    editor.canvas.self_modulate = Color(1, 1, 1, 0)
    await process_frame
    await RenderingServer.frame_post_draw
    var chrome_only: Image = root.get_texture().get_image()
    editor.canvas.self_modulate = Color.WHITE
    editor.canvas.camera_zoom = 0.5
    editor.canvas.queue_redraw()
    await process_frame
    await RenderingServer.frame_post_draw
    var with_canvas: Image = root.get_texture().get_image()
    var bounds: Rect2 = editor.canvas.get_global_rect()
    var changed_outside: int = 0
    var changed_inside: int = 0
    for y: int in range(0, with_canvas.get_height(), 4):
        for x: int in range(0, with_canvas.get_width(), 4):
            if not chrome_only.get_pixel(x, y).is_equal_approx(with_canvas.get_pixel(x, y)):
                if bounds.has_point(Vector2(x, y)):
                    changed_inside += 1
                else:
                    changed_outside += 1
    var directory: String = "user://validation"
    DirAccess.make_dir_recursive_absolute(directory)
    var screenshot_error: Error = with_canvas.save_png(directory.path_join("integrated-editor.png"))
    var passed: bool = (changed_outside == 0 and changed_inside > 100
        and screenshot_error == OK and bounds.size.y >= 500.0)
    var canvas: AtlasCanvas = editor.canvas
    canvas.map.grid.kind = AtlasGrid.Kind.GRIDLESS
    canvas.camera_center = Vector2.ZERO
    canvas.camera_zoom = 1.0
    canvas.preview = AtlasCanvas.Preview.OFF
    canvas.show_reference = false
    canvas.floor.terrain.clear()
    var ink: Color = Color("#f5b545")
    editor._on_stroke(AtlasStroke.new(PackedVector2Array([
        Vector2(-140, 0), Vector2(140, 0)
    ]), ink, 20.0), false)
    await process_frame
    await RenderingServer.frame_post_draw
    var drawn: Image = root.get_texture().get_image()
    var center: Vector2i = Vector2i(canvas.global_position + canvas.size * 0.5)
    passed = passed and drawn.get_pixelv(center).is_equal_approx(ink)
    passed = passed and drawn.save_png(directory.path_join("freehand.png")) == OK
    editor._on_stroke(AtlasStroke.new(PackedVector2Array([
        Vector2(0, -40), Vector2(0, 40)
    ]), Color.BLACK, 30.0), true)
    await process_frame
    await RenderingServer.frame_post_draw
    var erased: Image = root.get_texture().get_image()
    var real_gap: bool = erased.get_pixelv(center).is_equal_approx(AtlasCanvas.EMPTY_COLOR)
    var surviving_ink: bool = erased.get_pixelv(center + Vector2i(-100, 0)).is_equal_approx(ink)
    passed = passed and real_gap and surviving_ink
    passed = passed and erased.save_png(directory.path_join("erased.png")) == OK
    editor._on_undo()
    await process_frame
    await RenderingServer.frame_post_draw
    var undo_image: Image = root.get_texture().get_image()
    var restored_ink: bool = undo_image.get_pixelv(center).is_equal_approx(ink)
    passed = passed and restored_ink
    passed = passed and undo_image.save_png(directory.path_join("undo-erase.png")) == OK
    root.content_scale_size = Vector2i(800, 600)
    root.size = Vector2i(800, 600)
    for frame: int in range(6):
        await process_frame
    await RenderingServer.frame_post_draw
    var compact: Image = root.get_texture().get_image()
    var compact_layout: bool = (
        is_equal_approx(canvas.global_position.y, editor.sidebar.global_position.y)
        and editor.title_label.get_global_rect().end.x <= 800.0
        and canvas.get_global_rect().end.x <= 800.0
    )
    passed = passed and compact_layout
    passed = passed and compact.save_png(directory.path_join("compact-editor.png")) == OK
    print("ATLAS_VISUAL_%s outside=%d inside=%d screenshot=%s" % [
        "PASSED" if passed else "FAILED", changed_outside, changed_inside,
        ProjectSettings.globalize_path(directory.path_join("integrated-editor.png"))
    ])
    print("ATLAS_INK_PIXELS gap=%s surviving_ink=%s undo=%s" % [real_gap, surviving_ink, restored_ink])
    print("ATLAS_COMPACT_LAYOUT %s" % compact_layout)
    root.remove_child(scene)
    scene.free()
    quit(0 if passed else 1)
