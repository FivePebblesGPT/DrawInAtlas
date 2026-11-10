extends SceneTree
## Native/GDScript two-phase source-read rollback: the actual Hokusai surface,
## brush RNG/state and quantized export cache must survive a rejected batch.

const ANCHOR_X: int = 2147483651
const ANCHOR_Y: int = -2147483671
const WINDOW: Rect2i = Rect2i(-58, -58, 116, 116)
const TINT: int = 0x9c30a4de
var FIRST: PackedVector2Array = PackedVector2Array([
    Vector2(-26.5, -24.5), Vector2(-22.5, -20.5)])
var SECOND: PackedVector2Array = PackedVector2Array([
    Vector2(-12.5, -8.5), Vector2(24.5, 24.5)])
var THIRD: PackedVector2Array = PackedVector2Array([
    Vector2(26.5, 18.5), Vector2(30.5, -8.5)])

class FaultDocument:
    extends DrawingDocument
    var reject_resolution: int = -1
    var resolutions: int = 0

    func _resolve_chunk(layer: String, key: String) -> DrawingResult:
        if reject_resolution > 0:
            resolutions += 1
            if resolutions == reject_resolution:
                return DrawingResult.failure("INJECTED_TILE", "Late lazy-source read rejected")
        return super._resolve_chunk(layer, key)

var checks: int = 0
var failures: int = 0

func check(valid: bool, description: String) -> void:
    checks += 1
    if not valid:
        failures += 1
        printerr("T095_NATIVE_PIGMENT_ATOMIC_FAILED: " + description)

func make_preset() -> Object:
    var native: Object = ClassDB.instantiate("DrawingNativeBrush")
    var myb: String = FileAccess.get_file_as_string(
        "res://addons/drawing/brushes/hard_round.myb")
    check(not myb.is_empty() and native.call("configure_preset", myb, 14.0, TINT),
        "real bundled Hokusai preset configures")
    return native

func make_edit(name: String, faulty: bool) -> Dictionary:
    var doc: DrawingDocument = FaultDocument.new(name, 16) if faulty else DrawingDocument.new(name, 16)
    var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
    var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
        Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
    check(seed._stage(-25, -23, 0x0045f0ab).ok and
        seed._stage(21, 21, 0x814075c0).ok and seed.commit().ok,
        "hidden-RGB and translucent source pixels seeded")
    var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
        Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
    return {"doc": doc, "layer": layer, "edit": edit, "native": make_preset()}

func preview(doc: DrawingDocument, edit: DrawingEditSession) -> PackedByteArray:
    var image: DrawingResult = DrawingRenderer.render(
        doc, WINDOW, ANCHOR_X, ANCHOR_Y, 1048576, edit)
    check(image.ok, "detached source preview renders")
    return image.value.get_data() if image.ok else PackedByteArray()

func committed(doc: DrawingDocument) -> PackedByteArray:
    var image: DrawingResult = DrawingRenderer.render(doc, WINDOW, ANCHOR_X, ANCHOR_Y)
    check(image.ok, "committed source renders")
    return image.value.get_data() if image.ok else PackedByteArray()

func verify_case(retry_after_failure: bool) -> void:
    var failing: Dictionary = make_edit("native-fault", true)
    var clean: Dictionary = make_edit("native-oracle", false)
    var faulty_doc: FaultDocument = failing["doc"]
    var clean_doc: DrawingDocument = clean["doc"]
    var faulty_edit: DrawingEditSession = failing["edit"]
    var clean_edit: DrawingEditSession = clean["edit"]
    var mask: DrawingSelection = DrawingSelection.new(Rect2i(-50, -50, 101, 101), true)
    check(mask.combine_rectangle(Rect2i(-5, -5, 11, 11), "Subtract"),
        "selection hole configured")
    var native: Object = failing["native"]
    var oracle_native: Object = clean["native"]
    var clip: Rect2i = Rect2i(-52, -52, 104, 104)

    check(faulty_edit.paint_path_hokusai(FIRST, TINT, mask, native, clip).ok and
        clean_edit.paint_path_hokusai(FIRST, TINT, mask, oracle_native, clip).ok,
        "first batch accepted in both real Hokusai engines")
    var expected_before: PackedByteArray = preview(clean_doc, clean_edit)
    check(faulty_edit.change_count() > 0 and preview(faulty_doc, faulty_edit) == expected_before,
        "first actual native pigment preview matches independent engine")
    var before_count: int = faulty_edit.change_count()
    var original_revision: int = faulty_doc.revision
    faulty_doc.reject_resolution = 2
    faulty_doc.resolutions = 0
    var failure: DrawingResult = faulty_edit.paint_path_hokusai(
        SECOND, TINT, mask, native, clip)
    check(not failure.ok and failure.code == "INJECTED_TILE" and
        faulty_doc.resolutions == 2, "late source failure occurs after one source resolution")
    faulty_doc.reject_resolution = -1
    check(faulty_doc.revision == original_revision and
        faulty_edit.change_count() == before_count and
        preview(faulty_doc, faulty_edit) == expected_before,
        "failed batch does not publish detached or committed GDScript changes")

    if retry_after_failure:
        check(faulty_edit.paint_path_hokusai(SECOND, TINT, mask, native, clip).ok and
            clean_edit.paint_path_hokusai(SECOND, TINT, mask, oracle_native, clip).ok,
            "the exact failed source batch retries on the same native object")
        check(preview(faulty_doc, faulty_edit) == preview(clean_doc, clean_edit) and
            faulty_edit.change_count() == clean_edit.change_count(),
            "replayed pigment/preview exactly equals uninterrupted native stroke")
        check(faulty_edit.paint_path_hokusai(THIRD, TINT, mask, native, clip).ok and
            clean_edit.paint_path_hokusai(THIRD, TINT, mask, oracle_native, clip).ok,
            "next batch exercises retained Hokusai brush state and cache")
        check(preview(faulty_doc, faulty_edit) == preview(clean_doc, clean_edit),
            "later RGBA8 bytes and hole/clip remain identical after retry")

    var expected_preview: PackedByteArray = preview(clean_doc, clean_edit)
    check(faulty_edit.commit().ok and clean_edit.commit().ok,
        "both histories commit once")
    check(committed(faulty_doc) == committed(clean_doc) and
        committed(faulty_doc) == expected_preview,
        "signed 64-bit committed RGBA8 bytes and detached preview are equal")
    check(faulty_doc.undo().ok and clean_doc.undo().ok and
        committed(faulty_doc) == committed(clean_doc),
        "undo restores original source pixels on both documents")
    check(faulty_doc.redo().ok and clean_doc.redo().ok and
        committed(faulty_doc) == committed(clean_doc),
        "redo restores exact committed bytes and history")

func run() -> void:
    check(ClassDB.class_exists("DrawingNativeBrush"), "real extension registered")
    if ClassDB.class_exists("DrawingNativeBrush"):
        verify_case(true)
        verify_case(false)
    print("T095_NATIVE_PIGMENT_ATOMIC_RESULT checks=%d failures=%d" % [checks, failures])
    if failures == 0:
        print("T095_NATIVE_PIGMENT_ATOMIC_PASSED")
    quit(1 if failures else 0)

func _initialize() -> void:
    call_deferred("run")
