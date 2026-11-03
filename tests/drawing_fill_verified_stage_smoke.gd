extends SceneTree
## T-068: stage a verified fill-source pixel without reading its tile twice.
## Mixed session commands must still capture original, immutable before-bytes.

const ORIGINAL: int = 0x00335577 # Transparent RGB is significant.
const BARRIER: int = 0xff111111
const EARLY: int = 0xff225588
const FILL: int = 0x80997755
const LATE: int = 0xffabcdef

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T068_VERIFIED_STAGE_FAILED: " + description)


func _run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("staged-source", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var initial: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	_check(initial.fill_rect(Rect2i(0, 0, 5, 3), ORIGINAL).ok,
		"seed connected region with nonzero hidden RGB")
	_check(initial.fill_rect(Rect2i(2, 0, 1, 1), BARRIER).ok,
		"place an unequal barrier without changing other pixels")
	_check(initial.commit().ok, "publish original pixels")
	var revision: int = doc.revision
	var session: DrawingEditSession = doc.begin_edit(layer, revision).value
	_check(session.fill_rect(Rect2i(1, 1, 1, 1), EARLY).ok,
		"preceding same-session raster operation records its own before-pixel")
	_check(session.change_count() == 1 and
		int(session._before.get("1,1", -1)) == ORIGINAL,
		"earlier operation records canonical source, not its preview")
	var rejected: DrawingResult = session.flood_fill(Vector2i.ZERO, FILL, null, 2)
	_check(not rejected.ok and rejected.code == "FILL_LIMIT",
		"insufficient unique-candidate budget fails atomically")
	_check(session.change_count() == 1 and
		int(session._after.get("1,1", -1)) == EARLY,
		"failed fill retains the previously staged operation")
	_check(doc.revision == revision and
		int(doc.read_pixel(layer, 1, 1).value) == ORIGINAL,
		"failed fill never publishes source mutations")
	var filled: DrawingResult = session.flood_fill(Vector2i.ZERO, FILL, null, 128)
	_check(filled.ok and session.change_count() == 14,
		"flood fill supersedes earlier same-session edit from immutable source")
	_check(int(session._before.get("1,1", -1)) == ORIGINAL and
		int(session._after.get("1,1", -1)) == FILL,
		"verified source retains the true before-pixel in the shared delta")
	_check(session.fill_rect(Rect2i(1, 1, 1, 1), LATE).ok,
		"later ordinary edit can replace an already filled pixel")
	_check(int(session._before.get("1,1", -1)) == ORIGINAL and
		int(session._after.get("1,1", -1)) == LATE,
		"ordinary edit after fill retains the exact original before-pixel")
	_check(int(doc.read_pixel(layer, 1, 1).value) == ORIGINAL and
		int(doc.read_pixel(layer, 2, 0).value) == BARRIER,
		"all staged operations leave the source untouched")
	var committed: DrawingResult = session.commit()
	_check(committed.ok and committed.delta != null and
		committed.delta.after.size() == 14,
		"combined gesture commits one correct delta")
	_check(int(committed.delta.before.get("1,1", -1)) == ORIGINAL and
		int(committed.delta.after.get("1,1", -1)) == LATE,
		"published mixed-command delta keeps canonical before and final after")
	var after_ok: bool = true
	for y: int in range(3):
		for x: int in range(5):
			var expected: int = BARRIER if Vector2i(x, y) == Vector2i(2, 0) else FILL
			if x == 1 and y == 1:
				expected = LATE
			after_ok = after_ok and int(doc.read_pixel(layer, x, y).value) == expected
	_check(after_ok and int(doc.read_pixel(layer, 5, 0).value) == 0,
		"all final pixels, barrier and blank exterior remain exact")
	_check(doc.undo().ok and int(doc.read_pixel(layer, 1, 1).value) == ORIGINAL and
		int(doc.read_pixel(layer, 2, 0).value) == BARRIER,
		"undo restores hidden RGB and obstacle in a single operation")
	_check(doc.redo().ok and int(doc.read_pixel(layer, 1, 1).value) == LATE and
		int(doc.read_pixel(layer, 0, 2).value) == FILL,
		"redo reconstructs both staged changes")

	# Repeated fills in a single session must use the immutable source, not
	# each other's detached preview, even across a signed tile boundary.
	var far: DrawingDocument = DrawingDocument.new("signed-staged-source", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var anchor: int = 9007199254740993
	var seed: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(seed.fill_rect(Rect2i(-1, 0, 3, 1), ORIGINAL).ok and seed.commit().ok,
		"seed hidden-RGB pixels at far positive/negative 64-bit coordinates")
	var shifted: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-1, 0, 2, 1), true)
	_check(shifted.flood_fill(Vector2i.ZERO, EARLY, mask, 64).ok and
		shifted.change_count() == 2, "masked fill stages two pixels across signed seam")
	_check(shifted.flood_fill(Vector2i(1, 0), FILL, null, 64).ok and
		shifted.change_count() == 3, "second fill reuses original source snapshot")
	_check(int(shifted._before.get("%d,%d" % [anchor, -anchor], -1)) == ORIGINAL and
		int(shifted._after.get("%d,%d" % [anchor, -anchor], -1)) == FILL,
		"second fill replaces earlier preview without losing source before-bytes")
	_check(shifted.commit().ok and
		int(far.read_pixel(far_layer, anchor + 1, -anchor).value) == FILL,
		"publish three exact far-world pixels in one transaction")
	_check(far.undo().ok and
		int(far.read_pixel(far_layer, anchor - 1, -anchor).value) == ORIGINAL and
		int(far.read_pixel(far_layer, anchor + 1, -anchor).value) == ORIGINAL,
		"far-world undo restores all hidden RGB exactly")

	# A provider can change a document revision during a detached session.
	# The verified source shortcut must not bypass publication's final guard.
	var stale: DrawingDocument = DrawingDocument.new("stale-verified", 16)
	var stale_layer: String = String(stale.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var stale_seed: DrawingEditSession = stale.begin_edit(stale_layer, stale.revision).value
	_check(stale_seed.fill_rect(Rect2i(0, 0, 2, 2), ORIGINAL).ok and
		stale_seed.commit().ok, "seed publication-race fixture")
	var stale_edit: DrawingEditSession = stale.begin_edit(stale_layer, stale.revision).value
	_check(stale_edit.flood_fill(Vector2i.ZERO, FILL, null, 32).ok and
		stale_edit.change_count() == 4,
		"stage verified source bytes without mutating document")
	_check(stale.create_layer(DrawingLayerNode.RASTER, "Concurrent").ok,
		"simulate concurrent publication after staging")
	var stale_commit: DrawingResult = stale_edit.commit()
	_check(not stale_commit.ok and stale_commit.code == "STALE_REVISION",
		"verified source cannot bypass optimistic revision guard")
	_check(int(stale.read_pixel(stale_layer, 0, 0).value) == ORIGINAL and
		int(stale.read_pixel(stale_layer, 1, 1).value) == ORIGINAL,
		"stale transaction publishes no partial replacement")

	print("T068_VERIFIED_STAGE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
