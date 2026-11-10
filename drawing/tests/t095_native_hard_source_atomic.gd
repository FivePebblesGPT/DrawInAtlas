extends SceneTree
## T-095: a rejected GDScript source tile must rewind the real NativeHard
## coverage set and cursor, not merely the detached DrawingEditSession patch.

const ANCHOR_X: int = 2147483653
const ANCHOR_Y: int = -2147483669
const WINDOW: Rect2i = Rect2i(-58, -58, 116, 116)
const TINT: int = 0x9b52d6a1
const WIDTH: float = 12.0
var FIRST: PackedVector2Array = PackedVector2Array([
	Vector2(-28.5, -24.5), Vector2(-22.5, -20.5)])
var SECOND: PackedVector2Array = PackedVector2Array([
	Vector2(-18.5, -13.5), Vector2(27.5, 23.5)])
var THIRD: PackedVector2Array = PackedVector2Array([
	Vector2(29.5, 18.5), Vector2(29.5, -9.5)])

class FaultDocument:
	extends DrawingDocument
	var reject_resolution: int = -1
	var resolutions: int = 0

	func _resolve_chunk(layer: String, key: String) -> DrawingResult:
		if reject_resolution > 0:
			resolutions += 1
			if resolutions == reject_resolution:
				return DrawingResult.failure("INJECTED_TILE", "Delayed source-tile failure")
		return super._resolve_chunk(layer, key)

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_NATIVE_HARD_SOURCE_ATOMIC_FAILED: " + label)

func make_pair(faulty: bool, erase: bool) -> Dictionary:
	var doc: DrawingDocument = FaultDocument.new("fault", 16) if faulty else DrawingDocument.new("reference", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value
	var field_ok: bool = true
	if erase:
		field_ok = seed.fill_rect(Rect2i(-36, -33, 70, 65), 0x7f2960d3).ok
	check(field_ok and seed._stage(-25, -23, 0x0060bb22).ok and
		seed._stage(22, 20, 0x8141762b).ok and seed.commit().ok,
		"transparent hidden RGB, partial alpha and Eraser source field seeded")
	var native: Object = ClassDB.instantiate("DrawingNativeBrush")
	native.call("reset_hard")
	return {"doc": doc, "layer": layer,
		"edit": doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value,
		"native": native}

func paint(data: Dictionary, path: PackedVector2Array, mask: DrawingSelection,
		erase: bool) -> DrawingResult:
	return (data["edit"] as DrawingEditSession).paint_path_native_hard(
		path, TINT, WIDTH, erase, mask, data["native"], Rect2i(-52, -52, 104, 104))

func preview(data: Dictionary, detached: bool) -> PackedByteArray:
	var doc: DrawingDocument = data["doc"]
	var edit: DrawingEditSession = data["edit"] if detached else null
	var render: DrawingResult = DrawingRenderer.render(
		doc, WINDOW, ANCHOR_X, ANCHOR_Y, 1048576, edit)
	check(render.ok, "detached/committed image renders")
	return render.value.get_data() if render.ok else PackedByteArray()

func case_source_failure(retry_after_failure: bool, erase: bool) -> void:
	var faulty: Dictionary = make_pair(true, erase)
	var reference: Dictionary = make_pair(false, erase)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-50, -50, 101, 101), true)
	check(mask.combine_rectangle(Rect2i(-6, -6, 13, 13), "Subtract"),
		"selection hole configured")
	check(paint(faulty, FIRST, mask, erase).ok and paint(reference, FIRST, mask, erase).ok,
		"first NativeHard batch accepted")
	var first_image: PackedByteArray = preview(reference, true)
	check(preview(faulty, true) == first_image and
		(faulty["edit"] as DrawingEditSession).change_count() > 0,
		"first detached NativeHard preview contains actual painted source pixels")
	var doc: FaultDocument = faulty["doc"]
	var edit: DrawingEditSession = faulty["edit"]
	var first_changes: int = edit.change_count()
	var revision: int = doc.revision
	doc.resolutions = 0
	doc.reject_resolution = 2
	var rejected: DrawingResult = paint(faulty, SECOND, mask, erase)
	check(not rejected.ok and rejected.code == "INJECTED_TILE" and doc.resolutions == 2,
		"second batch fails after earlier successful GDScript source resolution")
	doc.reject_resolution = -1
	check(doc.revision == revision and edit.change_count() == first_changes and
		preview(faulty, true) == first_image,
		"failed batch rolls back preview/transaction without document publication")
	if retry_after_failure:
		check(paint(faulty, SECOND, mask, erase).ok and paint(reference, SECOND, mask, erase).ok,
			"identical failed NativeHard batch retries")
		check(preview(faulty, true) == preview(reference, true) and
			edit.change_count() == (reference["edit"] as DrawingEditSession).change_count(),
			"retry exactly reproduces independent NativeHard preview")
		check(paint(faulty, THIRD, mask, erase).ok and paint(reference, THIRD, mask, erase).ok,
			"later NativeHard cursor/coverage accepts next stroke")
		check(preview(faulty, true) == preview(reference, true),
			"post-retry native coverage bytes match uninterrupted stroke")
	else:
		check(paint(faulty, THIRD, mask, erase).ok and paint(reference, THIRD, mask, erase).ok,
			"later batch after rejected edit matches skipped reference geometry")
		check(preview(faulty, true) == preview(reference, true),
			"skipped failed batch does not consume native coverage/cursor")
	var expected: PackedByteArray = preview(reference, true)
	check(edit.commit().ok and (reference["edit"] as DrawingEditSession).commit().ok,
		"atomic single edit-history commit")
	check(preview(faulty, false) == expected and
		preview(faulty, false) == preview(reference, false),
		"committed signed world source RGBA8 matches independent reference")
	check(doc.undo().ok and (reference["doc"] as DrawingDocument).undo().ok and
		preview(faulty, false) == preview(reference, false),
		"Undo parity")
	check(doc.redo().ok and (reference["doc"] as DrawingDocument).redo().ok and
		preview(faulty, false) == preview(reference, false),
		"Redo parity")

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush"), "real extension registered")
	if ClassDB.class_exists("DrawingNativeBrush"):
		for erase: bool in [false, true]:
			case_source_failure(true, erase)
			case_source_failure(false, erase)
	print("T095_NATIVE_HARD_SOURCE_ATOMIC_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_NATIVE_HARD_SOURCE_ATOMIC_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
