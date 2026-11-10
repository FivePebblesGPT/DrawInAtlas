extends SceneTree
## T-095: exact pixels and transaction semantics for tile-local deferred Brush
## staging, against the old canonical-key implementation on a separate document.

const ORIGIN: Vector2i = Vector2i(2147483691, -2147483749)
const AREA: Rect2i = Rect2i(-70, -70, 140, 140)
const INK: int = 0x9052acd3
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_BRUSH_DEFERRED_FAILED: " + label)

func make_target(stride: int) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("deferred-%d" % stride, stride)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Paint", "root").value)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
	var rgba: PackedByteArray = PackedByteArray()
	for i: int in range(19 * 19):
		rgba.append_array(PackedByteArray([i % 256, 91, 152,
			0 if i % 5 == 0 else 111]))
	check(seed.apply_region(Rect2i(-9, -9, 19, 19), rgba).ok and seed.commit().ok,
		"seed source with hidden RGB")
	return {"document": doc, "layer": layer}

func begin(target: Dictionary, deferred: bool) -> DrawingEditSession:
	var doc: DrawingDocument = target["document"]
	var edit: DrawingEditSession = doc.begin_edit(target["layer"], doc.revision,
		Transform2D.IDENTITY, ORIGIN.x, ORIGIN.y).value
	edit._brush_tile_publish = deferred
	return edit

func snapshot(target: Dictionary, edit: DrawingEditSession = null) -> PackedByteArray:
	var result: DrawingResult = DrawingRenderer.render(target["document"], AREA,
		ORIGIN.x, ORIGIN.y, AREA.size.x * AREA.size.y, edit)
	check(result.ok, "render succeeds")
	return result.value.get_data() if result.ok else PackedByteArray()

func comparison(stride: int, erase: bool, mixed: bool) -> void:
	var a: Dictionary = make_target(stride)
	var b: Dictionary = make_target(stride)
	var fast: DrawingEditSession = begin(a, true)
	var old: DrawingEditSession = begin(b, false)
	var baseline: PackedByteArray = snapshot(a)
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(-68, -68, 136, 136), true)
	check(mask.combine_rectangle(Rect2i(-3, -3, 8, 9), "Subtract"), "selection hole")
	var paths: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-47.5, -41.5), Vector2(32.875, 19.25)]),
		PackedVector2Array([Vector2(-49.25, 34.5), Vector2(51.5, -29.75)]),
		PackedVector2Array([Vector2(52.5, 11.5), Vector2(-12.25, 46.75)])]
	for path: PackedVector2Array in paths:
		var fa: DrawingResult = fast.paint_path(path, INK, 60.0, erase, mask)
		var ob: DrawingResult = old.paint_path(path, INK, 60.0, erase, mask)
		check(fa.ok and ob.ok, "Brush/Eraser batch stages")
		check(fast.change_count() == old.change_count(), "change count after batch")
		check(snapshot(a, fast) == snapshot(b, old), "byte-exact intermediate preview")
	check(fast._brush_deferred and fast._before.is_empty() and fast._after.is_empty(),
		"Brush-only path avoids canonical string key allocation")
	if mixed:
		check(fast.fill_rect(Rect2i(24, -11, 3, 3), 0x70873ad9).ok and
			old.fill_rect(Rect2i(24, -11, 3, 3), 0x70873ad9).ok,
			"mixed fill stages")
		check(not fast._brush_deferred and not fast._brush_tile_publish and
			fast._before == old._before and fast._after == old._after,
			"mixed API materializes canonical global deltas")
		var extra: PackedVector2Array = PackedVector2Array([Vector2(5.5, 52.5)])
		check(fast.paint_path(extra, INK, 9.0).ok and old.paint_path(extra, INK, 9.0).ok,
			"later Brush uses canonical fallback")
	var preview: PackedByteArray = snapshot(a, fast)
	check(preview == snapshot(b, old) and snapshot(a) == baseline,
		"unpublished document matches independent reference")
	var result: DrawingResult = fast.commit()
	var expected: DrawingResult = old.commit()
	check(result.ok and expected.ok, "single atomic commit")
	if result.ok and expected.ok:
		check(result.delta.before == expected.delta.before and
			result.delta.after == expected.delta.after, "canonical history bytes match")
	check(snapshot(a) == preview and snapshot(a) == snapshot(b),
		"commit exactly equals preview")
	check(a["document"].undo().ok and b["document"].undo().ok and
		snapshot(a) == baseline and snapshot(a) == snapshot(b), "Undo parity")
	check(a["document"].redo().ok and b["document"].redo().ok and
		snapshot(a) == preview and snapshot(a) == snapshot(b), "Redo parity")

func failed_batch_then_retry() -> void:
	var a: Dictionary = make_target(16)
	var b: Dictionary = make_target(16)
	var fast: DrawingEditSession = begin(a, true)
	var reference: DrawingEditSession = begin(b, false)
	var initial: PackedVector2Array = PackedVector2Array([Vector2(-6.5, -3.5)])
	check(fast.paint_path(initial, INK, 5.0).ok and
		reference.paint_path(initial, INK, 5.0).ok, "first batch succeeds")
	var previous_count: int = fast.change_count()
	var previous_patches: Dictionary = fast._preview_tiles.duplicate(true)
	var doc: DrawingDocument = a["document"]
	# Force the second batch to fail *after* accepting pixels in earlier tiles.
	var bad_cx: int = DrawingDocument.TILES.floor_div(ORIGIN.x + 22, 16)
	var bad_cy: int = DrawingDocument.TILES.floor_div(ORIGIN.y - 3, 16)
	var bad_key: String = "%d,%d" % [bad_cx, bad_cy]
	check(doc.register_lazy_chunk(a["layer"], bad_cx, bad_cy,
		"unavailable", "0".repeat(64), Callable()).ok, "missing lazy tile registered")
	var second: PackedVector2Array = PackedVector2Array([Vector2(35.5, -3.5)])
	var failed: DrawingResult = fast.paint_path(second, INK, 5.0)
	check(not failed.ok and failed.code == "MISSING_TILE", "late lazy read fails")
	check(fast.change_count() == previous_count and
		fast._preview_tiles == previous_patches, "only failing batch rolled back")
	check(fast._after.is_empty() and fast._before.is_empty(),
		"failed batch never builds global source deltas")
	# Clear only the deliberately introduced test fixture, then retry.
	doc._pending_tiles.erase(a["layer"] + ":" + bad_key)
	check(fast.paint_path(second, INK, 5.0).ok and
		reference.paint_path(second, INK, 5.0).ok, "same batch retry succeeds")
	check(snapshot(a, fast) == snapshot(b, reference), "retry preview equals old publisher")
	var fa: DrawingResult = fast.commit()
	var rb: DrawingResult = reference.commit()
	check(fa.ok and rb.ok and fa.delta.after == rb.delta.after and
		fa.delta.before == rb.delta.before, "retry committed exact history")
	check(snapshot(a) == snapshot(b), "retry committed bytes match")

func preverified_source_identity() -> void:
	var target: Dictionary = make_target(64)
	var doc: DrawingDocument = target["document"]
	var x: int = 22
	var y: int = -18
	var key: String = DrawingDocument.TILES.tile_key64(ORIGIN.x + x,
		ORIGIN.y + y, doc.tile_stride)
	var read: DrawingResult = doc.read_pixel(target["layer"], ORIGIN.x + x, ORIGIN.y + y)
	check(read.ok, "preverified source lookup succeeds")
	var edit: DrawingEditSession = begin(target, true)
	check(edit._stage(x, y, INK, null, true, true, int(read.value), true).ok,
		"internal preverified Brush stage succeeds")
	check(edit._source_tiles.has(key),
		"preverified source also records authoritative tile identity")
	var preview: PackedByteArray = snapshot(target, edit)
	check(edit.commit().ok and snapshot(target) == preview,
		"preverified source publishes identical preview pixels")
	var stale: DrawingEditSession = begin(target, true)
	check(stale._stage(x + 1, y, INK, null, true, true, 0, true).ok,
		"preverified test stages another tile-local pixel")
	var source: DrawingRasterTile = doc._nodes[target["layer"]].tiles[key]
	doc._nodes[target["layer"]].tiles[key] = source.detached_copy()
	var current_revision: int = doc.revision
	var failed: DrawingResult = stale.commit()
	check(not failed.ok and failed.code == "STALE_PIXEL" and
		doc.revision == current_revision, "preverified source identity prevents stale publication")

func run() -> void:
	for stride: int in [16, 30, 64, 256]:
		for erase: bool in [false, true]:
			comparison(stride, erase, false)
		comparison(stride, false, true)
	failed_batch_then_retry()
	preverified_source_identity()
	if failures == 0:
		print("T095_BRUSH_DEFERRED_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T095_BRUSH_DEFERRED_FAILED checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _initialize() -> void:
	call_deferred("run")
