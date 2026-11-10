extends SceneTree
## T-095: the hot swept-Brush loop may reuse a private success result, but
## direct _stage() users retain independent, mutable DrawingResult objects.

const INK: int = 0x906738ad
const AREA: Rect2i = Rect2i(-40, -40, 80, 80)

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_BRUSH_RESULT_FAILED: " + description)


func snapshot(doc: DrawingDocument, session: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(doc, AREA, 0, 0,
		AREA.size.x * AREA.size.y, session)
	check(result.ok, "pixel snapshot rendered")
	return result.value.get_data() if result.ok else PackedByteArray()


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("brush-results", 64)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root").value)
	var original: PackedByteArray = snapshot(doc)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	var first: DrawingResult = edit._stage(-3, -2, INK)
	var second: DrawingResult = edit._stage(-2, -2, INK)
	check(first.ok and second.ok and first != second,
		"ordinary per-pixel callers receive independent success objects")
	first.ok = false
	first.code = "TEST_MUTATION"
	check(second.ok and second.code.is_empty(),
		"mutating an ordinary caller's result cannot contaminate another")
	var internal_first: DrawingResult = edit._stage(-1, -2, INK,
		null, true, false, -1, true)
	var internal_second: DrawingResult = edit._stage(0, -2, INK,
		null, true, false, -1, true)
	check(internal_first.ok and internal_second.ok and internal_first == internal_second,
		"brush-owned successful pixels reuse one private result")
	check(internal_first != first and internal_first != second,
		"private brush result is not shared with ordinary callers")
	var denied: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 1, 1), true)
	var count_before: int = edit.change_count()
	check(edit._stage(-20, -20, INK, denied, true, false, -1, true) == internal_first
		and edit.change_count() == count_before,
		"selection rejection is a no-op and uses private brush result")
	check(edit._stage(-1, -2, INK, null, true, false, -1, true) == internal_first
		and edit.change_count() == count_before,
		"once-only covered pixel is a no-op using the private result")
	var invalid: DrawingResult = edit._stage(2, -2, 0x100000000,
		null, true, false, -1, true)
	check(not invalid.ok and invalid.code == "RGBA" and invalid != internal_first,
		"internal brush error uses a distinct failure result")
	check(internal_first.ok and internal_first.code.is_empty(),
		"failed pixel does not poison subsequent success")
	check(edit._stage(1, -2, INK, null, true, false, -1, true) == internal_first,
		"a valid pixel after an error still succeeds")
	var preview: PackedByteArray = snapshot(doc, edit)
	check(snapshot(doc) == original, "private success path keeps document detached")
	check(edit.commit().ok, "private success and ordinary edits commit together")
	check(snapshot(doc) == preview, "commit pixels match detached preview")
	check(doc.undo().ok and snapshot(doc) == original, "Undo restores exact pixels")
	check(doc.redo().ok and snapshot(doc) == preview, "Redo restores exact pixels")

	var next_edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(next_edit._brush_stage_ok != edit._brush_stage_ok,
		"reusable result belongs to one edit session, never global state")
	var path: PackedVector2Array = PackedVector2Array([
		Vector2(-26.5, -22.5), Vector2(27.5, 23.5),
		Vector2(-23.5, 27.5)])
	check(next_edit.paint_path(path, INK, 60.0).ok,
		"actual 60px oblique Brush uses reusable staging result")
	check(next_edit._brush_stage_ok.ok, "swept Brush retains valid success result")
	var wide_preview: PackedByteArray = snapshot(doc, next_edit)
	check(next_edit.commit().ok and snapshot(doc) == wide_preview,
		"wide Brush preview and commit remain identical")
	check(doc.undo().ok and snapshot(doc) == preview,
		"wide Brush Undo restores previous history step")
	check(doc.redo().ok and snapshot(doc) == wide_preview,
		"wide Brush Redo restores exact pixels")
	print("T095_BRUSH_RESULT_PASSED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
