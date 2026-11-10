extends SceneTree
## T-095: current-tile source/patch references are a fast path only. Compare
## exact pixels and one-step history to an independent canonical-key painter;
## exercise signed tile transitions, null source, failed lazy reads and rollback.

const ORIGIN: Vector2i = Vector2i(-1099511627873, 1099511627929)
const VIEW: Rect2i = Rect2i(-48, -43, 97, 89)
const COLOR: int = 0x8f3ca9d1
const STRIDES: Array[int] = [3, 16, 30, 64, 255]

class FaultDocument:
	extends DrawingDocument
	var reject_key: String = ""
	var reject_once: bool = true
	var failed_count: int = 0
	func _resolve_chunk(layer: String, key: String) -> DrawingResult:
		if not reject_key.is_empty() and key == reject_key and reject_once:
			reject_once = false
			failed_count += 1
			return DrawingResult.failure("INJECTED_TILE", "Injected failed tile resolution")
		return super._resolve_chunk(layer, key)

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_BRUSH_TILE_REFERENCE_FAILED: " + label)

func make_target(stride: int, faultable: bool) -> Dictionary:
	var doc: DrawingDocument = FaultDocument.new("cache-source-%d" % stride, stride) \
		if faultable else DrawingDocument.new("canonical-source-%d" % stride, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
	for item: Vector3i in [Vector3i(-30, -25, 0), Vector3i(5, 3, 1), Vector3i(31, 25, 2)]:
		var rgba: int = [0x0038ab42, 0x7e9ed265, 0xff6c3f92][item.z]
		check(edit._stage(item.x, item.y, rgba).ok, "seed RGBA8 tile")
	check(edit.commit().ok, "seed commit")
	return {"doc": doc, "layer": layer}

func begin(target: Dictionary, tile_fast: bool) -> DrawingEditSession:
	var doc: DrawingDocument = target["doc"]
	var edit: DrawingEditSession = doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
	edit._brush_tile_publish = tile_fast
	return edit

func pixels(target: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var rendered: DrawingResult = DrawingRenderer.render(target["doc"], VIEW,
		ORIGIN.x, ORIGIN.y, VIEW.size.x * VIEW.size.y, edit)
	check(rendered.ok, "render source or preview")
	return rendered.value.get_data() if rendered.ok else PackedByteArray()

func equivalent(fast: Dictionary, reference: Dictionary,
		cached: DrawingEditSession, canonical: DrawingEditSession, label: String) -> void:
	check(cached.change_count() == canonical.change_count(), label + " change_count")
	check(pixels(fast, cached) == pixels(reference, canonical),
		label + " preview RGBA8")
	# Even a transparent source tile must be recorded as successfully resolved.
	check(cached._brush_cached_source_ready, label + " authoritative source cached")
	if cached._preview_tiles.has(cached._brush_cached_tile_key):
		check(cached._brush_cached_patch == cached._preview_tiles[cached._brush_cached_tile_key],
			label + " current patch reference matches published preview")

func commit_equivalent(fast: Dictionary, reference: Dictionary,
		cached: DrawingEditSession, canonical: DrawingEditSession, original: PackedByteArray,
		label: String) -> void:
	var preview: PackedByteArray = pixels(fast, cached)
	var a: DrawingResult = cached.commit()
	var b: DrawingResult = canonical.commit()
	check(a.ok and b.ok, label + " both commits")
	if a.ok and b.ok:
		check(a.delta.before == b.delta.before and a.delta.after == b.delta.after,
			label + " canonical before/after history")
	check(pixels(fast) == preview and pixels(fast) == pixels(reference),
		label + " published matches draft/reference")
	var fast_doc: DrawingDocument = fast["doc"]
	var reference_doc: DrawingDocument = reference["doc"]
	check(fast_doc.undo().ok and reference_doc.undo().ok and
		pixels(fast) == original and pixels(fast) == pixels(reference),
		label + " exact Undo")
	check(fast_doc.redo().ok and reference_doc.redo().ok and
		pixels(fast) == preview and pixels(fast) == pixels(reference),
		label + " exact Redo")

func case_signed_tiles(stride: int, erase: bool) -> void:
	var fast: Dictionary = make_target(stride, true)
	var reference: Dictionary = make_target(stride, false)
	var original: PackedByteArray = pixels(fast)
	var cached: DrawingEditSession = begin(fast, true)
	var canonical: DrawingEditSession = begin(reference, false)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-45, -40, 91, 81), true)
	check(mask.combine_rectangle(Rect2i(-6, -8, 14, 16), "Subtract"),
		"selection hole")
	var parts: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-31.25, -27.5), Vector2(32.25, 26.5)]),
		PackedVector2Array([Vector2(36.5, -14.5), Vector2(-39.5, 18.5)]),
		PackedVector2Array([Vector2(-27.5, 21.5)]),
		PackedVector2Array([Vector2(17.5, -35.5), Vector2(-28.5, -21.5)])]
	for i: int in range(parts.size()):
		var a: DrawingResult = cached.paint_path(parts[i], COLOR, 20.0,
			erase, mask, 6000, VIEW)
		var b: DrawingResult = canonical.paint_path(parts[i], COLOR, 20.0,
			erase, mask, 6000, VIEW)
		check(a.ok and b.ok, "path stage stride=%d erase=%s batch=%d" % [stride, erase, i])
		equivalent(fast, reference, cached, canonical,
			"stride=%d erase=%s batch=%d" % [stride, erase, i])
	commit_equivalent(fast, reference, cached, canonical, original,
		"stride=%d erase=%s" % [stride, erase])

func case_rejected_source(retry: bool) -> void:
	var fast: Dictionary = make_target(16, true)
	var reference: Dictionary = make_target(16, false)
	var doc: FaultDocument = fast["doc"] as FaultDocument
	var original: PackedByteArray = pixels(fast)
	var cached: DrawingEditSession = begin(fast, true)
	var canonical: DrawingEditSession = begin(reference, false)
	var first: PackedVector2Array = PackedVector2Array([Vector2(-28.5, -22.5)])
	check(cached.paint_path(first, COLOR, 3.0).ok and
		canonical.paint_path(first, COLOR, 3.0).ok, "first batch success")
	var before_failure: PackedByteArray = pixels(fast, cached)
	var previous_count: int = cached.change_count()
	var last: Vector2 = cached._last
	var next: PackedVector2Array = PackedVector2Array([Vector2(31.5, 29.5)])
	var target_key: String = DrawingDocument.TILES.tile_key64(ORIGIN.x + 31,
		ORIGIN.y + 29, 16)
	# The intervening sweep may encounter earlier tiles before this failure.
	doc.reject_key = target_key
	var rejected: DrawingResult = cached.paint_path(next, COLOR, 3.0, false,
		null, 8000, VIEW)
	check(not rejected.ok and rejected.code == "INJECTED_TILE" and
		doc.failed_count == 1, "late source read injected")
	check(cached._brush_cached_tile_key.is_empty() and
		not cached._brush_cached_source_ready and cached._brush_cached_patch.is_empty(),
		"failed batch invalidates all current-tile references")
	check(cached.change_count() == previous_count and cached._last == last and
		pixels(fast, cached) == before_failure,
		"failed batch restores state and detached preview")
	if retry:
		check(cached.paint_path(next, COLOR, 3.0, false, null, 8000, VIEW).ok and
			canonical.paint_path(next, COLOR, 3.0, false, null, 8000, VIEW).ok,
			"same batch retry")
	else:
		var skipped: PackedVector2Array = PackedVector2Array([Vector2(-24.5, 25.5)])
		check(cached.paint_path(skipped, COLOR, 3.0, false, null, 8000, VIEW).ok and
			canonical.paint_path(skipped, COLOR, 3.0, false, null, 8000, VIEW).ok,
			"new batch after reject")
	equivalent(fast, reference, cached, canonical, "post-reject")
	commit_equivalent(fast, reference, cached, canonical, original,
		"failure %s" % ("retry" if retry else "skip"))

func case_direct_retry() -> void:
	var fast: Dictionary = make_target(30, true)
	var reference: Dictionary = make_target(30, false)
	var original: PackedByteArray = pixels(fast)
	var doc: FaultDocument = fast["doc"] as FaultDocument
	var cached: DrawingEditSession = begin(fast, true)
	var canonical: DrawingEditSession = begin(reference, false)
	check(cached._stage(-32, -32, COLOR, null, true, true, -1, true).ok and
		canonical._stage(-32, -32, COLOR, null, true, true).ok,
		"initial source tile resolved")
	var x: int = 36
	var y: int = 32
	var key: String = DrawingDocument.TILES.tile_key64(ORIGIN.x + x, ORIGIN.y + y, 30)
	doc.reject_key = key
	var rejected: DrawingResult = cached._stage(x, y, COLOR, null, true, true, -1, true)
	check(not rejected.ok and rejected.code == "INJECTED_TILE", "direct lazy read fails")
	check(cached._brush_cached_tile_key == key and
		not cached._brush_cached_source_ready,
		"same key remains unresolved after failure")
	check(cached._stage(x, y, COLOR, null, true, true, -1, true).ok and
		canonical._stage(x, y, COLOR, null, true, true).ok,
		"retry does not cache the failed read as an empty source tile")
	equivalent(fast, reference, cached, canonical, "direct retry")
	commit_equivalent(fast, reference, cached, canonical, original, "direct retry")

func run() -> void:
	for stride: int in STRIDES:
		for erase: bool in [false, true]:
			case_signed_tiles(stride, erase)
	case_rejected_source(true)
	case_rejected_source(false)
	case_direct_retry()
	print("T095_BRUSH_TILE_REFERENCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_BRUSH_TILE_REFERENCE_PASSED")
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
