extends SceneTree
## T-095: a failed shape/fill after deferred Brush staging must preserve the
## earlier valid stroke and remain retryable. Compare against the canonical
## (non-deferred) publisher on an independent document.

const ORIGIN = Vector2i(2147483648, -2147483648)
const VIEW = Rect2i(-12, -8, 105, 24)
const SAFE_VIEW = Rect2i(-12, -8, 23, 20)
const BRUSH_RGBA: int = 0x9052acd3
const SEED_RGBA: int = 0xff3a6b7c
const FILL_RGBA: int = 0xb0c59441
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T095_MIXED_ROLLBACK_FAILED: " + label)

func make_target(stride: int, flood: bool) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("mixed-rollback-%d" % stride, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	if flood:
		var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
			Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
		check(seed.fill_rect(Rect2i(stride + 2, 0, stride - 2, 1), SEED_RGBA).ok,
			"seed contiguous flood source")
		check(seed.commit().ok, "commit flood source")
	return {"document": doc, "layer": layer}

func begin(target: Dictionary, deferred: bool) -> DrawingEditSession:
	var doc: DrawingDocument = target["document"]
	var edit: DrawingEditSession = doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
	edit._brush_tile_publish = deferred
	return edit

func pixels(target: Dictionary, draft: DrawingEditSession = null,
		area: Rect2i = VIEW) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(target["document"], area,
		ORIGIN.x, ORIGIN.y, area.size.x * area.size.y, draft)
	check(result.ok, "render source/preview")
	return result.value.get_data() if result.ok else PackedByteArray()

func operation(edit: DrawingEditSession, kind: String, stride: int) -> DrawingResult:
	var left: int = stride
	var width: int = stride + 4
	match kind:
		"rect":
			return edit.fill_rect(Rect2i(left, 0, width, 1), FILL_RGBA)
		"region":
			var bytes: PackedByteArray = PackedByteArray()
			for i: int in range(width):
				bytes.append_array(PackedByteArray([65, 148, 197, 176]))
			return edit.apply_region(Rect2i(left, 0, width, 1), bytes)
		"polygon":
			return edit.paint_polygon(PackedVector2Array([
				Vector2(left, 0), Vector2(left + width, 0),
				Vector2(left + width, 2), Vector2(left, 2)]), FILL_RGBA)
		"flood":
			return edit.flood_fill(Vector2i(stride + 2, 0), FILL_RGBA, null, 1000)
	return DrawingResult.failure("TEST", "Unknown operation")

func scenario(kind: String, stride: int, retry: bool) -> void:
	var fast_target: Dictionary = make_target(stride, kind == "flood")
	var slow_target: Dictionary = make_target(stride, kind == "flood")
	var fast: DrawingEditSession = begin(fast_target, true)
	var slow: DrawingEditSession = begin(slow_target, false)
	var baseline: PackedByteArray = pixels(fast_target)
	var dab: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.5)])
	check(fast.paint_path(dab, BRUSH_RGBA, 5.0).ok and
		slow.paint_path(dab, BRUSH_RGBA, 5.0).ok,
		"initial deferred and original Brush strokes")
	check(fast._brush_deferred and fast._before.is_empty(),
		"Brush-only input is deferred before mixed API")
	var original_full_preview: PackedByteArray = pixels(slow_target, slow)
	var expected_preview: PackedByteArray = pixels(slow_target, slow, SAFE_VIEW)
	check(pixels(fast_target, fast, SAFE_VIEW) == expected_preview, "initial preview parity")
	var before_count: int = fast.change_count()
	var doc_fast: DrawingDocument = fast_target["document"]
	var doc_slow: DrawingDocument = slow_target["document"]
	var bad_x: int = DrawingDocument.TILES.floor_div(ORIGIN.x + 2 * stride, stride)
	var bad_y: int = DrawingDocument.TILES.floor_div(ORIGIN.y, stride)
	var tile_key: String = "%d,%d" % [bad_x, bad_y]
	check(doc_fast.register_lazy_chunk(fast_target["layer"], bad_x, bad_y,
		"unavailable", "0".repeat(64), Callable()).ok, "fast bad late tile")
	check(doc_slow.register_lazy_chunk(slow_target["layer"], bad_x, bad_y,
		"unavailable", "0".repeat(64), Callable()).ok, "reference bad late tile")
	var failed_fast: DrawingResult = operation(fast, kind, stride)
	var failed_slow: DrawingResult = operation(slow, kind, stride)
	check(not failed_fast.ok and not failed_slow.ok and
		failed_fast.code == failed_slow.code, "late mixed failure matches reference")
	check(fast.change_count() == before_count, "earlier Brush edit survives failed mixed operation")
	check(pixels(fast_target, fast, SAFE_VIEW) == expected_preview and
		pixels(slow_target, slow, SAFE_VIEW) == expected_preview,
		"failed mixed operation restores exact Brush preview")
	check(doc_fast.revision == doc_slow.revision and
		pixels(fast_target, null, SAFE_VIEW) == pixels(slow_target, null, SAFE_VIEW),
		"failed attempt published no document pixels")
	# The same operation must be retryable after the lazy-source error is fixed.
	doc_fast._pending_tiles.erase(String(fast_target["layer"]) + ":" + tile_key)
	doc_slow._pending_tiles.erase(String(slow_target["layer"]) + ":" + tile_key)
	if not retry:
		var commit_fast: DrawingResult = fast.commit()
		var commit_slow: DrawingResult = slow.commit()
		check(commit_fast.ok and commit_slow.ok, "valid Brush commits after mixed failure")
		if commit_fast.ok and commit_slow.ok:
			check(commit_fast.delta.before == commit_slow.delta.before and
				commit_fast.delta.after == commit_slow.delta.after,
				"failed mixed operation leaves identical Brush-only history")
		check(pixels(fast_target) == original_full_preview and
			pixels(slow_target) == original_full_preview,
			"failed mixed operation commits only the original Brush")
		check(doc_fast.undo().ok and doc_slow.undo().ok and
			pixels(fast_target) == baseline and pixels(slow_target) == baseline,
			"failure-only Undo restores original source")
		check(doc_fast.redo().ok and doc_slow.redo().ok and
			pixels(fast_target) == original_full_preview and
			pixels(slow_target) == original_full_preview,
			"failure-only Redo restores original Brush")
		return
	var retried_fast: DrawingResult = operation(fast, kind, stride)
	var retried_slow: DrawingResult = operation(slow, kind, stride)
	check(retried_fast.ok and retried_slow.ok, "retry mixed operation succeeds")
	check(pixels(fast_target, fast) == pixels(slow_target, slow),
		"retry preview byte-exact with canonical publisher")
	var committed: PackedByteArray = pixels(slow_target, slow)
	var result_fast: DrawingResult = fast.commit()
	var result_slow: DrawingResult = slow.commit()
	check(result_fast.ok and result_slow.ok, "one atomic commit")
	if result_fast.ok and result_slow.ok:
		check(result_fast.delta.before == result_slow.delta.before and
			result_fast.delta.after == result_slow.delta.after,
			"canonical history bytes equal")
	check(pixels(fast_target) == committed and pixels(slow_target) == committed,
		"committed bytes equal retry preview")
	check(doc_fast.undo().ok and doc_slow.undo().ok and
		pixels(fast_target) == baseline and pixels(slow_target) == baseline,
		"Undo restores original source")
	check(doc_fast.redo().ok and doc_slow.redo().ok and
		pixels(fast_target) == committed and pixels(slow_target) == committed,
		"Redo restores committed bytes")

func run() -> void:
	for stride: int in [16, 32]:
		for kind: String in ["rect", "region", "polygon", "flood"]:
			scenario(kind, stride, true)
			scenario(kind, stride, false)
	if failures == 0:
		print("T095_MIXED_ROLLBACK_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T095_MIXED_ROLLBACK_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
