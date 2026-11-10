extends SceneTree
## T-095: opt-in Rust coverage parity, real .myb Hokusai staged painting,
## canonical preview/history, alpha/erase, signed tiles and bundled assets.

var checks: int = 0
var failures: int = 0


func check(value: bool, message: String) -> void:
    checks += 1
    if not value:
        failures += 1
        printerr("T095_NATIVE_BRUSH_FAILED: " + message)


func frames(n: int = 1) -> void:
    for i: int in range(n):
        await process_frame


func make_canvas(engine: String, preset: String = "hard") -> Dictionary:
    var doc: DrawingDocument = DrawingDocument.new("native-" + engine)
    var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
    var canvas: Control = Control.new()
    canvas.set_script(load("res://addons/drawing/canvas.gd"))
    canvas.size = Vector2(420, 360)
    canvas.zoom = 7.86
    canvas.brush_backend = engine
    canvas.brush_preset = preset
    canvas.document = doc
    canvas.layer_id = layer
    canvas.brush_width = 60.0
    canvas.color_rgba = 0xa054a7d4
    canvas.tool = "Brush"
    root.add_child(canvas)
    return {"doc": doc, "layer": layer, "canvas": canvas}


func draw_stroke(canvas: Control, points: PackedVector2Array) -> Dictionary:
    var begin: int = Time.get_ticks_usec()
    canvas.start_gesture(canvas.pixel_to_position(points[0]))
    for index: int in range(1, points.size() - 1):
        canvas.update_gesture(canvas.pixel_to_position(points[index]))
    var preview_changes: int = canvas.session.change_count() if canvas.session != null else 0
    canvas.finish_gesture(canvas.pixel_to_position(points[points.size() - 1]))
    var queued: int = int(canvas._metrics.get("samples_received", 0))
    for frame: int in range(400):
        if canvas.session == null:
            break
        await frames()
    return {"elapsed_us": Time.get_ticks_usec() - begin,
        "preview_changes": preview_changes,
        "queued": queued,
        "metrics": canvas.last_gesture_metrics}


func run() -> void:
    check(ClassDB.class_exists("DrawingNativeBrush"), "GDExtension registered class")
    if not ClassDB.class_exists("DrawingNativeBrush"):
        quit(1)
        return
    var native: Object = ClassDB.instantiate("DrawingNativeBrush")
    native.call("reset_hard")
    var native_pixels: Dictionary = native.call("hard_segments",
        PackedVector2Array([Vector2(-2.5, -2.5), Vector2(2.5, 2.5)]),
        10.0, Rect2i())
    check(native_pixels.get("ok", false) and
        (native_pixels.get("points", PackedInt32Array()) as PackedInt32Array).size() > 0,
        "signed native hard coverage is nonempty")

    var source: PackedVector2Array = PackedVector2Array()
    for index: int in range(155):
        var t: float = float(index) / 154.0
        source.append(Vector2(-24.5 + 51.0 * t,
            -15.5 + sin(t * TAU * 5.0) * 23.0))
    var legacy_setup: Dictionary = make_canvas("Legacy")
    var fast_setup: Dictionary = make_canvas("NativeHard")
    await frames(3)
    var legacy: Control = legacy_setup["canvas"]
    var fast: Control = fast_setup["canvas"]
    var old_metrics: Dictionary = await draw_stroke(legacy, source)
    var new_metrics: Dictionary = await draw_stroke(fast, source)
    check(fast._native_brush == null and fast._active_brush_backend == "Legacy",
        "native state disposed after document commit")
    var area: Rect2i = Rect2i(-85, -85, 170, 170)
    var old_render: DrawingResult = DrawingRenderer.render(legacy_setup["doc"], area)
    var new_render: DrawingResult = DrawingRenderer.render(fast_setup["doc"], area)
    check(old_render.ok and new_render.ok, "both strokes render")
    check(old_render.ok and new_render.ok and
        old_render.value.get_data() == new_render.value.get_data(),
        "native hard 60px stroke matches legacy straight RGBA8 bytes")
    check(int(new_metrics["queued"]) == source.size(), "native samples are not dropped")
    check((new_metrics["metrics"] as Dictionary).get("commit_us", 0) > 0,
        "native stroke recorded a committed history transaction")
    var fast_doc: DrawingDocument = fast_setup["doc"]
    check(fast_doc.undo().ok, "native stroke Undo succeeds")
    check(fast_doc.redo().ok and
        DrawingRenderer.render(fast_doc, area).value.get_data() == new_render.value.get_data(),
        "native stroke Redo restores exact pixels")
    print("T095_NATIVE_HARD legacy_ms=%.3f native_ms=%.3f legacy_stage_ms=%.3f native_stage_ms=%.3f" %
        [float(old_metrics["elapsed_us"]) / 1000.0, float(new_metrics["elapsed_us"]) / 1000.0,
        float((old_metrics["metrics"] as Dictionary).get("stage_cpu_us", 0)) / 1000.0,
        float((new_metrics["metrics"] as Dictionary).get("stage_cpu_us", 0)) / 1000.0])

    # Same native hard engine must honor erasure and the once-per-stroke
    # transactional model when painting onto an existing nonempty layer.
    fast.tool = "Eraser"
    var previous: PackedByteArray = DrawingRenderer.render(fast_doc, area).value.get_data()
    var erase_stats: Dictionary = await draw_stroke(fast,
        PackedVector2Array([Vector2(-15.5, -15.5), Vector2(28.5, 13.5)]))
    check((erase_stats["metrics"] as Dictionary).get("commit_us", 0) > 0,
        "native eraser commits")
    check(DrawingRenderer.render(fast_doc, area).value.get_data() != previous,
        "native eraser changed canonical alpha")
    check(fast_doc.undo().ok and
        DrawingRenderer.render(fast_doc, area).value.get_data() == previous,
        "native eraser Undo restores original alpha")

    # Hokusai's actual .myb parser/rasterizer is exercised via Canvas, not
    # merely via a standalone CLI or class-instantiation smoke test.
    for preset: String in ["hard", "soft", "ink", "airbrush"]:
        var setup: Dictionary = make_canvas("Hokusai", preset)
        var canvas: Control = setup["canvas"]
        canvas.brush_width = 24.0
        canvas.color_rgba = 0xff38af74
        await frames(2)
        var stats: Dictionary = await draw_stroke(canvas,
            PackedVector2Array([Vector2(-4.5, -2.5),
                Vector2(3.5, 4.5), Vector2(12.5, 11.5)]))
        var doc: DrawingDocument = setup["doc"]
        var rendered: DrawingResult = DrawingRenderer.render(doc, Rect2i(-60, -60, 120, 120))
        var nonempty: bool = false
        if rendered.ok:
            var rgba: PackedByteArray = rendered.value.get_data()
            for a: int in range(3, rgba.size(), 4):
                if rgba[a] > 0:
                    nonempty = true
                    break
        check(doc.revision > 1 and nonempty,
            "Hokusai " + preset + " .myb paints and commits to DrawingDocument")
        check((stats["metrics"] as Dictionary).get("commit_us", 0) > 0,
            "Hokusai " + preset + " recorded one commit")
        check(doc.undo().ok and doc.redo().ok,
            "Hokusai " + preset + " Undo/Redo works")
        print("T095_HOKUSAI preset=%s stage_ms=%.3f" %
            [preset, float((stats["metrics"] as Dictionary).get("stage_cpu_us", 0)) / 1000.0])
        canvas.queue_free()
        await frames(2)
    # Selection mask expression: preserve an internal hole and signed edges.
    var selected_setup: Dictionary = make_canvas("Hokusai", "hard")
    var selected_canvas: Control = selected_setup["canvas"]
    await frames(2)
    var hole_mask: DrawingSelection = DrawingSelection.new(Rect2i(-30, -30, 60, 60), true)
    check(hole_mask.combine_rectangle(Rect2i(-4, -4, 9, 9), "Subtract"),
        "selection subtract operation built")
    selected_canvas.set_selection_mask(hole_mask)
    var selected_doc: DrawingDocument = selected_setup["doc"]
    var selected_area: Rect2i = Rect2i(-40, -40, 80, 80)
    selected_canvas.start_gesture(selected_canvas.pixel_to_position(Vector2(-12.5, 0.5)))
    selected_canvas.update_gesture(selected_canvas.pixel_to_position(Vector2(12.5, 0.5)))
    var detached: DrawingResult = DrawingRenderer.render(
        selected_doc, selected_area, 0, 0, 1048576, selected_canvas.session)
    check(detached.ok, "selected Hokusai detached preview renders")
    selected_canvas.finish_gesture(selected_canvas.pixel_to_position(Vector2(18.5, 0.5)))
    for frame: int in range(400):
        if selected_canvas.session == null:
            break
        await frames()
    var selected_render: DrawingResult = DrawingRenderer.render(selected_doc, selected_area)
    check(selected_render.ok, "selected Hokusai committed render succeeds")
    if selected_render.ok:
        var selected_bytes: PackedByteArray = selected_render.value.get_data()
        var hole_alpha: int = selected_bytes[(40 * 80 + 40) * 4 + 3]
        var outside_alpha: int = selected_bytes[(40 * 80 + 53) * 4 + 3]
        check(hole_alpha == 0, "Hokusai selection hole stays transparent")
        check(outside_alpha > 0, "Hokusai selected island paints")
    check(selected_doc.undo().ok and
        DrawingRenderer.render(selected_doc, selected_area).value.get_data().count(0) ==
        selected_area.size.x * selected_area.size.y * 4,
        "Hokusai selection Undo returns transparent source")
    selected_canvas.queue_free()
    await frames(2)

    print("T095_NATIVE_BRUSH_RESULT checks=%d failures=%d" % [checks, failures])
    quit(1 if failures else 0)


func _initialize() -> void:
    call_deferred("run")
