extends SceneTree
## T-095: source-space pointer backlog must survive viewport-only navigation
## AFTER release. This exercises the actual Canvas state machine, 60px Brush,
## middle Pan and toolbar Pan, exact RGBA bytes, and single-step Undo/Redo.

const STROKE_WIDTH: float = 60.0
const INK: int = 0xb44387e5
const AREA: Rect2i = Rect2i(-85, -75, 170, 140)
const POINT_COUNT: int = 260

var checks: int = 0
var failures: int = 0


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("T095_NAV_FAILED: " + message)


func frames(count: int = 1) -> void:
    for i: int in range(count):
        await process_frame


func mouse_button(canvas: Control, index: MouseButton, pressed: bool) -> void:
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.button_index = index
    event.pressed = pressed
    event.position = canvas.size * 0.5
    canvas._gui_input(event)


func make_document(name: String) -> Dictionary:
    var document: DrawingDocument = DrawingDocument.new(name)
    var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
    return {"document": document, "layer": layer}


func scenario(mode: String) -> void:
    var setup: Dictionary = make_document("t095-navigation-" + mode)
    var document: DrawingDocument = setup["document"]
    var layer: String = setup["layer"]
    var canvas: Control = Control.new()
    canvas.set_script(load("res://addons/drawing/canvas.gd"))
    canvas.size = Vector2(380, 290)
    canvas.document = document
    canvas.layer_id = layer
    canvas.zoom = 7.86
    canvas.tool = "Brush"
    canvas.color_rgba = INK
    canvas.brush_width = STROKE_WIDTH
    root.add_child(canvas)
    await frames(2)

    var original_revision: int = document.revision
    var points: PackedVector2Array = PackedVector2Array()
    var start: Vector2 = Vector2(-18.5, -14.5)
    points.append(canvas.source_position(canvas.pixel_to_position(start)))
    canvas.start_gesture(canvas.pixel_to_position(start))
    for index: int in range(POINT_COUNT):
        var fraction: float = float(index) / float(POINT_COUNT - 1)
        var point: Vector2 = Vector2(42.5 * sin(TAU * 4.0 * fraction),
            -12.5 + 25.0 * cos(TAU * 7.0 * fraction))
        points.append(canvas.source_position(canvas.pixel_to_position(point)))
        canvas.update_gesture(canvas.pixel_to_position(point))
    var end: Vector2 = Vector2(-31.5, 21.5)
    points.append(canvas.source_position(canvas.pixel_to_position(end)))
    check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.CAPTURING,
        mode + " captured Brush samples before mouse-up")
    canvas.finish_gesture(canvas.pixel_to_position(end))
    check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
        mode + " mouse-up retains a pending native-test stroke backlog")
    check(document.revision == original_revision, mode + " draft remains detached")

    if mode == "wheel_middle":
        mouse_button(canvas, MOUSE_BUTTON_WHEEL_UP, true)
        mouse_button(canvas, MOUSE_BUTTON_MIDDLE, true)
        var move: InputEventMouseMotion = InputEventMouseMotion.new()
        move.position = canvas.size * 0.5 + Vector2(30, 22)
        canvas._gui_input(move)
        mouse_button(canvas, MOUSE_BUTTON_MIDDLE, false)
    elif mode == "toolbar_pan":
        canvas.tool = "Pan"
        mouse_button(canvas, MOUSE_BUTTON_LEFT, true)
        var move: InputEventMouseMotion = InputEventMouseMotion.new()
        move.position = canvas.size * 0.5 + Vector2(45, 18)
        canvas._gui_input(move)
        mouse_button(canvas, MOUSE_BUTTON_LEFT, false)
    else:
        canvas.zoom = 10.0
        canvas.camera = Vector2(53, -61)

    check(canvas.session != null and canvas._stroke_phase == canvas.StrokePhase.DRAINING,
        mode + " navigation never cancels released paint")
    check(canvas._finish_requested, mode + " original release request survives pan/zoom")
    # Settings are frozen at pointer-down; a new brush cannot modify the
    # tail of a released stroke.
    canvas.brush_width = 3.0
    canvas.color_rgba = 0xff000000

    var blocked: Dictionary = {"seen": false}
    canvas.canvas_error.connect(func(message: String) -> void:
        if message.contains("still draining"):
            blocked["seen"] = true
    )
    canvas.start_gesture(canvas.pixel_to_position(Vector2(3, 3)))
    check(bool(blocked["seen"]) and canvas.session != null, mode + " second stroke is explicitly blocked")
    var drain_frames: int = 0
    while canvas.session != null and drain_frames < 360:
        await frames(1)
        drain_frames += 1
    check(canvas.session == null and canvas._stroke_phase == canvas.StrokePhase.IDLE,
        mode + " released stroke completes without cancellation")
    check(document.revision == original_revision + 1, mode + " commits exactly once")
    check(int(canvas.last_gesture_metrics.get("samples_received", -1)) == POINT_COUNT + 2,
        mode + " all 60px Brush waypoints are accounted for")

    var oracle_setup: Dictionary = make_document("t095-oracle-" + mode)
    var oracle: DrawingDocument = oracle_setup["document"]
    var edit: DrawingEditSession = oracle.begin_edit(oracle_setup["layer"], oracle.revision).value
    check(edit.paint_path(points, INK, STROKE_WIDTH).ok and edit.commit().ok,
        mode + " independent single-call path oracle commits")
    var expected: DrawingResult = DrawingRenderer.render(oracle, AREA)
    var actual: DrawingResult = DrawingRenderer.render(document, AREA)
    check(actual.ok and expected.ok and actual.value.get_data() == expected.value.get_data(),
        mode + " preserves exact bytes at signed chunk edges after navigation")
    var committed: PackedByteArray = actual.value.get_data() if actual.ok else PackedByteArray()
    check(document.undo().ok, mode + " Undo removes full stroke in one step")
    var undone: DrawingResult = DrawingRenderer.render(document, AREA)
    check(undone.ok and undone.value.get_data() != committed,
        mode + " Undo erases the pending stroke without partial publication")
    check(document.redo().ok, mode + " Redo restores full stroke")
    var redone: DrawingResult = DrawingRenderer.render(document, AREA)
    check(redone.ok and redone.value.get_data() == committed,
        mode + " Redo is byte-identical")
    var position: Vector2 = Vector2(-21.5, 11.5)
    check(canvas.source_position(canvas.pixel_to_position(position)).distance_to(position) < 0.001,
        mode + " new viewport transform is reversible")
    print("T095_NAV mode=%s samples=%d drain_frames=%d release_to_commit_ms=%.3f" %
        [mode, POINT_COUNT + 2, drain_frames, float(int(canvas.last_gesture_metrics["commit_us"]) -
            int(canvas.last_gesture_metrics["release_us"])) / 1000.0])
    canvas.queue_free()
    await frames(2)


func run() -> void:
    for mode: String in ["wheel_middle", "toolbar_pan", "camera"]:
        await scenario(mode)
    print("T095_NAV_RESULT checks=%d failures=%d" % [checks, failures])
    quit(1 if failures else 0)


func _initialize() -> void:
    call_deferred("run")
