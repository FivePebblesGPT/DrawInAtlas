extends SceneTree
## T-068: stage a verified fill-source pixel without reading its tile twice.
## Mixed commands retain immutable before-bytes across native publication and Undo/Redo.

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


func _read_region(document: DrawingDocument, layer: String,
		bounds: Rect2i) -> Dictionary[Vector2i, int]:
	var pixels: Dictionary[Vector2i, int] = {}
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var pixel: DrawingResult = document.read_pixel(layer, x, y)
			if not pixel.ok:
				return {}
			pixels[Vector2i(x, y)] = int(pixel.value)
	return pixels


func _read_far_row(document: DrawingDocument, layer: String,
		anchor: int) -> Array[int]:
	var pixels: Array[int] = []
	for dx: int in range(-2, 3):
		var pixel: DrawingResult = document.read_pixel(layer, anchor + dx, -anchor)
		if not pixel.ok:
			return []
		pixels.append(int(pixel.value))
	return pixels


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
	var region: Rect2i = Rect2i(-1, -1, 7, 5)
	var source_pixels: Dictionary[Vector2i, int] = _read_region(doc, layer, region)
	_check(source_pixels.size() == region.get_area() and
		source_pixels[Vector2i(1, 1)] == ORIGINAL and
		source_pixels[Vector2i(2, 0)] == BARRIER and
		source_pixels[Vector2i(-1, 0)] == 0,
		"record full source region including hidden RGB and blank guards")
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
	_check(doc.revision == revision and
		_read_region(doc, layer, region) == source_pixels,
		"mixed detached commands leave every source and guard pixel unchanged")
	var expected_pixels: Dictionary[Vector2i, int] = source_pixels.duplicate()
	for y: int in range(3):
		for x: int in range(5):
			if x == 2 and y == 0:
				continue
			expected_pixels[Vector2i(x, y)] = LATE if x == 1 and y == 1 else FILL
	var committed: DrawingResult = session.commit()
	_check(committed.ok and doc.revision == revision + 1,
		"combined gesture publishes exactly one native revision")
	_check(_read_region(doc, layer, region) == expected_pixels,
		"published mixed gesture matches every canonical RGBA8 and guard pixel")
	_check(doc.undo().ok and _read_region(doc, layer, region) == source_pixels,
		"one Undo restores the entire source including hidden RGB and obstacle")
	_check(doc.redo().ok and _read_region(doc, layer, region) == expected_pixels,
		"one Redo restores the entire late-edit and fill result")

	# Repeated fills in a single session must use the immutable source, not
	# each other's detached preview, even across a signed tile boundary.
	var far: DrawingDocument = DrawingDocument.new("signed-staged-source", 16)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	# The native publication projection is bounded even though public edits
	# accept larger 64-bit coordinates. A tile-aligned signed anchor keeps the
	# -1/0 seam exact and avoids 32-bit Vector2i for absolute world pixels.
	var anchor: int = 1125899906842624
	var far_revision: int = far.revision
	var seed: DrawingEditSession = far.begin_edit(far_layer, far_revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	_check(seed.fill_rect(Rect2i(-1, 0, 3, 1), ORIGINAL).ok and seed.commit().ok,
		"seed transparent hidden-RGB pixels at a valid large signed tile seam")
	var far_source: Array[int] = [0, ORIGINAL, ORIGINAL, ORIGINAL, 0]
	_check(_read_far_row(far, far_layer, anchor) == far_source,
		"far source contains exactly three original pixels and two clear guards")
	var before_far_revision: int = far.revision
	var shifted: DrawingEditSession = far.begin_edit(far_layer, before_far_revision,
		Transform2D.IDENTITY, anchor, -anchor).value
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-1, 0, 2, 1), true)
	_check(shifted.flood_fill(Vector2i.ZERO, EARLY, mask, 64).ok and
		shifted.change_count() == 2, "masked fill stages two pixels across signed seam")
	_check(shifted.flood_fill(Vector2i(1, 0), FILL, null, 64).ok and
		shifted.change_count() == 3, "second fill reuses immutable original source")
	_check(int(shifted._before.get("%d,%d" % [anchor, -anchor], -1)) == ORIGINAL and
		int(shifted._after.get("%d,%d" % [anchor, -anchor], -1)) == FILL,
		"second fill supersedes preview while retaining canonical source bytes")
	_check(far.revision == before_far_revision and
		_read_far_row(far, far_layer, anchor) == far_source,
		"both detached far-world fills leave source and clear guards untouched")
	var far_published: Array[int] = [0, FILL, FILL, FILL, 0]
	_check(shifted.commit().ok and far.revision == before_far_revision + 1,
		"two far-world fills publish as a single native history transaction")
	_check(_read_far_row(far, far_layer, anchor) == far_published,
		"far-world publication matches entire signed seam and clear guards")
	_check(far.undo().ok and _read_far_row(far, far_layer, anchor) == far_source,
		"far-world Undo restores entire region and hidden RGB")
	_check(far.redo().ok and _read_far_row(far, far_layer, anchor) == far_published,
		"far-world Redo restores the exact final fill pixels and guards")

	# Stage stays public at >2^53 but native tile publication must fail closed.
	var unsafe_anchor: int = 9007199254740993
	var unsafe_revision: int = far.revision
	var unsafe: DrawingEditSession = far.begin_edit(far_layer, unsafe_revision,
		Transform2D.IDENTITY, unsafe_anchor, -unsafe_anchor).value
	_check(unsafe.fill_rect(Rect2i(-1, 0, 3, 1), ORIGINAL).ok and
		unsafe.change_count() == 3,
		"wide signed public edit can stage three candidate source pixels")
	var unsafe_result: DrawingResult = unsafe.commit()
	var unsafe_cleared: bool = true
	for dx: int in range(-2, 3):
		var unsafe_pixel: DrawingResult = far.read_pixel(far_layer,
			unsafe_anchor + dx, -unsafe_anchor)
		unsafe_cleared = unsafe_cleared and unsafe_pixel.ok and int(unsafe_pixel.value) == 0
	_check(not unsafe_result.ok and far.revision == unsafe_revision and
		unsafe_cleared and _read_far_row(far, far_layer, anchor) == far_published,
		"unsafe native publication cannot mutate revision, source or valid pixels")
	unsafe.cancel()

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
