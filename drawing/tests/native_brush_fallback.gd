extends SceneTree
## Validate clean startup and transactional fallback without a .gdextension
## binary; also exercise the presence case when the native class is installed.

var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures += 1
        printerr("T095_NATIVE_FALLBACK_FAILED " + label)

func run() -> void:
    var native_available: bool = ClassDB.class_exists("DrawingNativeBrush")
    var doc: DrawingDocument = DrawingDocument.new("native-fallback")
    var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
    var canvas: Control = Control.new()
    canvas.set_script(load("res://addons/drawing/canvas.gd"))
    canvas.size = Vector2(420, 360)
    canvas.zoom = 7.86
    canvas.brush_backend = "NativeHard"
    canvas.document = doc
    canvas.layer_id = layer
    canvas.brush_width = 60.0
    canvas.color_rgba = 0xff547aa5
    root.add_child(canvas)
    await process_frame
    canvas.start_gesture(canvas.pixel_to_position(Vector2(-10.5, -10.5)))
    check(canvas.session != null, "editing session begins regardless of native availability")
    var hard_native: Object = ClassDB.instantiate("DrawingNativeBrush") if native_available else null
    var hard_transaction_native: bool = hard_native != null and \
        hard_native.has_method("begin_hard_batch") and hard_native.has_method("commit_hard_batch") and \
        hard_native.has_method("rollback_hard_batch")
    check(canvas._active_brush_backend == ("NativeHard" if hard_transaction_native else "Legacy"),
        "NativeHard only starts when source-read rollback is available")
    if native_available and not hard_transaction_native:
        var incompatible: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
        var rejected: DrawingResult = incompatible.paint_path_native_hard(
            PackedVector2Array([Vector2(5.5, 5.5)]), 0xff547aa5, 60.0, false,
            null, hard_native)
        check(not rejected.ok and rejected.code == "NATIVE_BRUSH_TRANSACTION" and \
            incompatible.change_count() == 0,
            "old native binary rejects unsafe direct NativeHard edit without staging")
        incompatible.cancel()
    canvas.finish_gesture(canvas.pixel_to_position(Vector2(15.5, 18.5)))
    for frame: int in range(400):
        if canvas.session == null:
            break
        await process_frame
    check(canvas.session == null and doc.revision == 2,
        "fallback stroke commits exactly once without any startup failure")
    var area: Rect2i = Rect2i(-50, -50, 100, 100)
    var result: DrawingResult = DrawingRenderer.render(doc, area)
    var nonempty: bool = false
    if result.ok:
        var rgba: PackedByteArray = result.value.get_data()
        for index: int in range(3, rgba.size(), 4):
            if rgba[index] > 0:
                nonempty = true
                break
    check(result.ok and nonempty, "fallback produces nontransparent pixels")
    check(doc.undo().ok and doc.redo().ok,
        "fallback stroke remains Undo/Redo transactional")
    # A known-missing preset does not crash either branch.
    canvas.brush_backend = "Hokusai"
    canvas.brush_preset = "nonexistent-preset"
    canvas.start_gesture(canvas.pixel_to_position(Vector2(20.5, 20.5)))
    check(canvas._active_brush_backend == "Legacy" or
        (not native_available and canvas._native_brush == null),
        "invalid Hokusai preset falls back explicitly")
    canvas.cancel_gesture()
    # An old GDExtension may support Hokusai paint yet lack rollback.
    # Such a binary must choose Legacy *before* source-pigment sampling.
    canvas.brush_preset = "hard"
    var transactional_native: bool = native_available and ClassDB.instantiate(
        "DrawingNativeBrush").has_method("begin_preset_batch")
    canvas.start_gesture(canvas.pixel_to_position(Vector2(-3.5, 4.5)))
    check(canvas._active_brush_backend == ("Hokusai" if transactional_native else "Legacy"),
        "Hokusai selects native only when real cross-boundary rollback is supported")
    canvas.cancel_gesture()
    print("T095_NATIVE_FALLBACK_RESULT checks=%d failures=%d native=%s" %
        [checks, failures, str(native_available)])
    quit(1 if failures else 0)

func _initialize() -> void:
    call_deferred("run")
