extends RefCounted
## Reproduce two source/time-identical Hokusai transactions without passing
## through the live Canvas's deferred queue or its rendered callbacks.


static func stroke(canvas: Control, recorded: Dictionary, color: int,
        width: float, erase: bool, mask: DrawingSelection) -> bool:
    var points: PackedVector2Array = recorded["points"]
    var times: PackedInt64Array = recorded["times"]
    if points.size() < 2 or points.size() != times.size():
        return false
    canvas.tool = "Eraser" if erase else "Brush"
    canvas.color_rgba = color
    canvas.brush_width = width
    canvas.set_selection_mask(mask)
    canvas.start_gesture(Vector2.ZERO, points[0], {"press_us": times[0],
        "tool": canvas.tool, "preset": "hard", "color": color,
        "width": width, "selection": mask.detached_copy()})
    if canvas.session == null or canvas._active_brush_backend != "Hokusai":
        return false
    for i: int in range(1, points.size() - 1):
        canvas._enqueue_sample_at_time(points[i], times[i])
    canvas.finish_gesture(Vector2.ZERO, points[-1], times[-1])
    var attempts: int = 0
    while canvas.session != null and attempts < 400:
        canvas._drain_segments(canvas.MAX_SEGMENTS_PER_FRAME)
        attempts += 1
    return canvas.session == null


static func commit(host: Window, first: Dictionary, second: Dictionary,
        first_color: int, first_width: float, second_color: int,
        second_width: float, erase_second: bool = false,
        selection: DrawingSelection = null) -> Dictionary:
    var doc: DrawingDocument = DrawingDocument.new("native-queue-reference")
    var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root")
    if not layer.ok:
        return {"ok": false, "document": doc}
    var canvas: Control = Control.new()
    canvas.set_script(load("res://addons/drawing/canvas.gd"))
    canvas.size = Vector2(650, 540)
    canvas.visible = false
    canvas.document = doc
    canvas.layer_id = str(layer.value)
    host.add_child(canvas)
    if RenderingServer.frame_post_draw.is_connected(canvas._on_frame_post_draw):
        RenderingServer.frame_post_draw.disconnect(canvas._on_frame_post_draw)
    var mask: DrawingSelection = selection if selection != null else DrawingSelection.new()
    var revision: int = doc.revision
    var first_ok: bool = stroke(canvas, first, first_color, first_width, false, mask)
    first_ok = first_ok and doc.revision == revision + 1 and doc.history_length() == 1
    var second_ok: bool = first_ok and stroke(canvas, second, second_color,
        second_width, erase_second, mask)
    second_ok = second_ok and doc.revision == revision + 2 and doc.history_length() == 2
    canvas.queue_free()
    return {"ok": second_ok, "document": doc}
