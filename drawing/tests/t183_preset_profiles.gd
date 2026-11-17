extends SceneTree
## T-183: exercise the production workspace selector -> Canvas -> Rust/MyPaint
## path, then independently sample committed source pixels and the framebuffer.

const PRESETS: Array[String] = ["hard", "soft", "ink", "airbrush"]
const WIDTHS: Array[int] = [60, 96]
const AREA: Rect2i = Rect2i(-120, -60, 240, 120)
var path: PackedVector2Array = PackedVector2Array([
    Vector2(-40.5, 0.5), Vector2(-30.5, 0.5), Vector2(-20.5, 0.5),
    Vector2(-10.5, 0.5), Vector2(0.5, 0.5), Vector2(10.5, 0.5),
    Vector2(20.5, 0.5), Vector2(30.5, 0.5), Vector2(40.5, 0.5)])

var checks: int = 0
var failures: int = 0
var output: String = OS.get_environment("T183_OUTPUT_DIR")
var control: bool = OS.get_environment("T183_CONTROL") == "1"
var observations: Array[Dictionary] = []


func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("T183_FAILED: " + message)


func frame() -> void:
    await process_frame
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw


func alpha_at(bytes: PackedByteArray, x: int, y: int) -> int:
    if not AREA.has_point(Vector2i(x, y)):
        return 0
    return bytes[((y - AREA.position.y) * AREA.size.x + x - AREA.position.x) * 4 + 3]


func alpha_profile(bytes: PackedByteArray, width: int) -> Array[int]:
    var result: Array[int] = []
    for fraction: float in [0.0, 0.25, 0.50, 0.75, 0.90, 0.95, 1.0, 1.05, 1.20, 1.50]:
        result.append(alpha_at(bytes, 0, roundi(float(width) * fraction * 0.5)))
    return result


func rgb_difference(a: Color, b: Color) -> float:
    return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func sample_counts(bytes: PackedByteArray) -> Dictionary:
    var result: Dictionary = {"zero": 0, "partial": 0, "opaque": 0, "alpha_sum": 0}
    for index: int in range(3, bytes.size(), 4):
        var alpha: int = bytes[index]
        result["alpha_sum"] += alpha
        if alpha == 0:
            result["zero"] += 1
        elif alpha == 255:
            result["opaque"] += 1
        else:
            result["partial"] += 1
    return result


func wait_for_commit(canvas: Control, label: String) -> void:
    for i: int in range(360):
        if canvas.session == null:
            return
        await frame()
    check(false, label + " commit drained within 360 frames")


func draw(canvas: Control, points: PackedVector2Array) -> Dictionary:
    canvas.start_gesture(canvas.pixel_to_position(points[0]))
    check(canvas.session != null and canvas.session._native_tiles != null,
        "actual workspace opens native transaction")
    if canvas.session == null:
        return {}
    for index: int in range(1, points.size() - 1):
        canvas.update_gesture(canvas.pixel_to_position(points[index]))
        await frame()
    var preview: DrawingResult = DrawingRenderer.render(canvas.document, AREA,
        0, 0, 1048576, canvas.session)
    check(preview.ok, "held stroke produces native detached preview")
    canvas.finish_gesture(canvas.pixel_to_position(points[points.size() - 1]))
    await wait_for_commit(canvas, "stroke")
    check(canvas.session == null, "native gesture commits")
    return {"preview": preview.value.get_data() if preview.ok else PackedByteArray(),
        "metrics": canvas.last_gesture_metrics}


func save_screen(preset: String, width: int, zoom: float) -> void:
    if output.is_empty() or DisplayServer.get_name() == "headless":
        return
    await frame()
    var filename: String = "%s/%s-%d-zoom-%s.png" % [output, preset, width,
        "100" if is_equal_approx(zoom, 1.0) else "50"]
    check(root.get_texture().get_image().save_png(filename) == OK,
        "graphical capture " + filename)


func _initialize() -> void:
    call_deferred("run")


func run() -> void:
    check(ClassDB.class_exists("DrawingNativeBrush") and
        ClassDB.class_exists("DrawingNativeTiles"), "native extension registered")
    if not output.is_empty():
        DirAccess.make_dir_recursive_absolute(output)
    root.size = Vector2i(1000, 720)
    root.content_scale_size = root.size
    for width: int in WIDTHS:
        for preset_index: int in range(PRESETS.size()):
            var preset: String = PRESETS[preset_index]
            if not OS.get_environment("T183_FILTER").is_empty() and OS.get_environment("T183_FILTER") != preset:
                continue
            var workspace: Control = load("res://main.tscn").instantiate()
            workspace.layout_persistence_enabled = false
            workspace.preferences_persistence_enabled = false
            root.add_child(workspace)
            await frame()
            await frame()
            var canvas: Control = workspace.canvas
            var picker: OptionButton = workspace.brush_preset_control
            workspace._change_tool("Brush")
            workspace.width_spin.value = width
            picker.select(preset_index)
            picker.item_selected.emit(preset_index)
            check(canvas.brush_preset == preset and canvas.brush_width == float(width),
                "selector freezes matching preset/width for " + preset)
            check(not picker.get_popup().get_item_tooltip(preset_index).is_empty(),
                "preset has user-facing tip behavior description: " + preset)
            canvas.zoom = 1.0
            canvas.camera = Vector2.ZERO
            canvas.image_bounds = Rect2i(-128, -128, 256, 256)
            var doc: DrawingDocument = workspace.current_document()
            var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER,
                "T183 " + preset).value)
            canvas.layer_id = layer
            await frame()
            var revision: int = doc.revision
            var center_screen: Vector2i = Vector2i(canvas.global_position +
                canvas.pixel_to_position(Vector2(0.5, 0.5)))
            var blank_center: Color = root.get_texture().get_image().get_pixelv(center_screen)
            var stroke: Dictionary = await draw(canvas, path)
            var rendered: DrawingResult = DrawingRenderer.render(doc, AREA)
            check(rendered.ok and doc.revision == revision + 1,
                "one committed native revision: " + preset)
            if not rendered.ok:
                workspace.queue_free()
                await frame()
                continue
            var bytes: PackedByteArray = rendered.value.get_data()
            var profile: Array[int] = alpha_profile(bytes, width)
            var counts: Dictionary = sample_counts(bytes)
            var changed: int = 0
            var preview: PackedByteArray = stroke.get("preview", PackedByteArray())
            for index: int in range(3, mini(preview.size(), bytes.size()), 4):
                if preview[index] > 0:
                    changed += 1
            check(changed > 0 and counts["partial"] + counts["opaque"] > 0,
                "held preview and committed document contain pigment")
            if preset == "hard" and not control:
                check(profile[0] >= 245, "Hard Round has fully covered center")
                check(profile[4] >= 220, "Hard Round has filled edge inside radius")
                check(profile[8] <= 45, "Hard Round has near-clear pixels outside radius")
            if preset == "soft" and not control:
                check(profile[0] > profile[3] and profile[3] > profile[7],
                    "Soft retains meaningful gradual falloff")
            if preset == "airbrush" and not control:
                check(profile[0] > profile[7], "Airbrush has soft falloff")
            if preset == "ink" and not control:
                check(profile[0] > profile[7], "Ink preserves a defined tip")
            var observed: Dictionary = {"preset": preset, "width_px": width,
                "radial_alpha": profile, "counts": counts,
                "brush_sha256": FileAccess.get_sha256(canvas.BUNDLED_PRESETS[preset]),
                "stage_cpu_us": int(stroke.get("metrics", {}).get("stage_cpu_us", 0)),
                "commit_cpu_us": int(stroke.get("metrics", {}).get("commit_cpu_us", 0))}
            observations.append(observed)
            print("T183_PROFILE " + JSON.stringify(observed))
            await save_screen(preset, width, 1.0)
            if DisplayServer.get_name() != "headless":
                var painted_center: Color = root.get_texture().get_image().get_pixelv(center_screen)
                check(rgb_difference(painted_center, blank_center) > 0.03,
                    "source alpha is visible on 100% framebuffer: " + preset)
            canvas.zoom = 0.5
            await save_screen(preset, width, 0.5)
            var small_screen: Vector2i = Vector2i(canvas.global_position +
                canvas.pixel_to_position(Vector2(0.5, 0.5)))
            var small_painted: Color = root.get_texture().get_image().get_pixelv(small_screen)
            check(doc.undo().ok, "native Undo works " + preset)
            canvas.queue_redraw()
            await frame()
            if DisplayServer.get_name() != "headless":
                var small_blank: Color = root.get_texture().get_image().get_pixelv(small_screen)
                check(rgb_difference(small_painted, small_blank) > 0.03,
                    "source alpha is visible on 50% framebuffer: " + preset)
            check(DrawingRenderer.render(doc, AREA).value.get_data() != bytes,
                "Undo removes source pigment " + preset)
            check(doc.redo().ok, "native Redo works " + preset)
            check(DrawingRenderer.render(doc, AREA).value.get_data() == bytes,
                "Redo restores exact source RGBA8 " + preset)
            canvas.zoom = 1.0
            workspace._change_tool("Eraser")
            canvas.layer_id = layer
            var erased: Dictionary = await draw(canvas, path)
            var after_erase: DrawingResult = DrawingRenderer.render(doc, AREA)
            var after_counts: Dictionary = sample_counts(after_erase.value.get_data()) if after_erase.ok else {}
            check(after_erase.ok and int(after_counts.get("alpha_sum", 0)) < int(counts["alpha_sum"]),
                "Eraser lowers source alpha " + preset + " before=" + str(counts["alpha_sum"]) +
                " after=" + str(after_counts.get("alpha_sum", -1)))
            check(doc.undo().ok and DrawingRenderer.render(doc, AREA).value.get_data() == bytes,
                "Eraser Undo restores native committed source " + preset)
            check(doc.redo().ok and DrawingRenderer.render(doc, AREA).value.get_data() == after_erase.value.get_data(),
                "Eraser Redo restores native erased state " + preset)
            check(erased.has("preview"), "Eraser uses preview path " + preset)
            workspace.queue_free()
            await frame()
    print("T183_RESULT checks=%d failures=%d control=%s" % [checks, failures, control])
    if failures == 0:
        print("T183_PASSED checks=%d failures=0" % checks)
    quit(0 if failures == 0 else 1)
