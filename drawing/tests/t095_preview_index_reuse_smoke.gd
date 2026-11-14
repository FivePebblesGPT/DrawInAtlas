extends SceneTree
## Canvas-owned preview index must be reused for cursor-only redraws and
## invalidated by every change that can alter the visible generation stamps.

var checks: int = 0
var failures: int = 0


func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T095_PREVIEW_REUSE_FAILED: " + detail)


func expect_index(canvas: Control, edit: DrawingEditSession, window: Rect2i,
		reused: bool, label: String) -> void:
	var expected: Dictionary = edit.preview_stamps_for_display_tiles(window, 128)
	var actual: Dictionary = canvas._preview_index_for_draw(edit, window)
	check(actual == expected, label + " matches uncached source index")
	check(bool(canvas._preview_index_reused) == reused,
		label + " cache reuse matches expected state")
	if bool(actual.get("indexed", false)):
		var stamps: Dictionary = actual["stamps"]
		for y: int in range(window.position.y, window.end.y):
			for x: int in range(window.position.x, window.end.x):
				var tile: Rect2i = Rect2i(x * 128, y * 128, 128, 128)
				var expected_version: int = edit.preview_stamp_for_area(tile)
				check(int(stamps.get("%d,%d" % [x, y], 0)) == expected_version,
					label + " exact area stamp %d,%d" % [x, y])


func settled() -> void:
	await process_frame
	await process_frame
	await process_frame


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("preview-cache", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit != null, "first detached edit opened")
	if edit == null:
		quit(1)
		return
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(360, 300)
	canvas.document = doc
	canvas.layer_id = layer
	canvas.zoom = 4.0
	root.add_child(canvas)
	await settled()

	var window: Rect2i = Rect2i(-3, -3, 7, 7)
	check(edit.paint_path(PackedVector2Array([Vector2(-1.5, -1.5)]),
		0xff4875a6, 9.0).ok, "initial signed-seam Brush staged")
	expect_index(canvas, edit, window, false, "initial projection")
	expect_index(canvas, edit, window, true, "unchanged cursor redraw")
	expect_index(canvas, edit, Rect2i(-4, -3, 7, 7), false, "viewport pan")
	expect_index(canvas, edit, window, false, "return to original viewport")
	check(edit.paint_path(PackedVector2Array([Vector2(20.5, -20.5)]),
		0xff4875a6, 9.0).ok, "new pixel batch staged")
	expect_index(canvas, edit, window, false, "preview mutation")
	expect_index(canvas, edit, window, true, "new preview stable")

	# A session swap must not reuse the same epoch and window by coincidence.
	edit.cancel()
	expect_index(canvas, edit, window, false, "cancelled edit")
	check((canvas._preview_index_for_draw(null, window) as Dictionary).is_empty(),
		"clearing an inactive preview frees its retained projection")
	check(canvas._preview_index_owner == null, "no cancelled session remains retained")
	var replacement: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(replacement.paint_path(PackedVector2Array([Vector2(50.5, 15.5)]),
		0xffb75b26, 11.0).ok, "replacement session staged")
	expect_index(canvas, replacement, window, false, "new session same revision")
	expect_index(canvas, replacement, window, true, "replacement session stable")

	# A committed change from outside the detached transaction makes its
	# revision invalid even when the epoch and viewport are unchanged.
	var other: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(other._stage(3, 3, 0xffaabbcc).ok and other.commit().ok,
		"independent source commit advances revision")
	expect_index(canvas, replacement, window, false, "stale source revision")
	check((canvas._preview_index_for_draw(replacement, window)["stamps"] as Dictionary).is_empty(),
		"stale edit cannot resurrect draft stamps")
	replacement.cancel()

	# Exercise the actual Canvas draw path: consecutive cursor-only redraws
	# reuse an unchanged preview but real paint forces recomputation.
	canvas.brush_width = 7.0
	canvas.color_rgba = 0xff00ff99
	canvas.start_gesture(canvas.pixel_to_position(Vector2(1.5, 1.5)))
	await settled()
	var visible_edit: DrawingEditSession = canvas.session
	check(visible_edit != null and visible_edit._preview_epoch > 0,
		"real renderer preview created via pointer-down")
	check(int(canvas.last_frame_metrics.get("preview_index_built", 0)) == 1,
		"actual Canvas draw builds visible preview index")
	canvas.queue_redraw()
	await settled()
	check(int(canvas.last_frame_metrics.get("preview_index_cache_hit", 0)) == 1,
		"actual cursor redraw reuses index")
	canvas.paint_to(Vector2i(11, 10))
	canvas._drain_segments(256)
	check(visible_edit._preview_epoch > 0, "actual preview stages a second input")
	canvas.queue_redraw()
	await settled()
	check(int(canvas.last_frame_metrics.get("preview_index_cache_hit", 1)) == 0,
		"actual Canvas draw invalidates index after new paint")
	canvas.cancel_gesture()
	await settled()
	check(canvas.session == null and canvas._preview_index_owner == null,
		"cancelled gesture releases cached preview on next draw")
	canvas.queue_free()
	await settled()

	# Synthetic longer stroke: many changed storage tiles and a stable
	# viewport. Timings deliberately carry no CI threshold or device claim.
	var perf_doc: DrawingDocument = DrawingDocument.new("preview-cache-bench", 1)
	var perf_layer: String = String(perf_doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var perf: DrawingEditSession = perf_doc.begin_edit(perf_layer, perf_doc.revision).value
	for i: int in range(240):
		perf._preview_epoch += 1
		perf._preview_tile_versions["%d,%d" % [(i * 117) % 1900 - 950,
			(i * 199) % 1100 - 550]] = perf._preview_epoch
	var perf_window: Rect2i = Rect2i(-16, -12, 32, 24)
	var perf_canvas: Control = Control.new()
	perf_canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var cold: Dictionary = perf_canvas._preview_index_for_draw(perf, perf_window)
	var reference: Dictionary = perf.preview_stamps_for_display_tiles(perf_window, 128)
	check(cold == reference, "large synthetic index matches independent recalculation")
	var start_uncached: int = Time.get_ticks_usec()
	for i: int in range(80):
		perf.preview_stamps_for_display_tiles(perf_window, 128)
	var uncached_us: int = Time.get_ticks_usec() - start_uncached
	var start_cached: int = Time.get_ticks_usec()
	for i: int in range(80):
		perf_canvas._preview_index_for_draw(perf, perf_window)
	var cached_us: int = Time.get_ticks_usec() - start_cached
	check(bool(perf_canvas._preview_index_reused) and \
		perf_canvas._preview_index_result == reference, "large index reused without stamp drift")
	print("T095_PREVIEW_REUSE_TIMING uncached_us=%d cached_us=%d repeats=80 keys=%d" % [
		uncached_us, cached_us, perf._preview_tile_versions.size()])
	perf_canvas.free()

	# The cached result must preserve a bounded failure, never retain the
	# partial index when a source tile overlaps more than 40,000 display keys.
	var huge_doc: DrawingDocument = DrawingDocument.new("preview-cache-large", 2048)
	var huge_layer: String = String(huge_doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var huge: DrawingEditSession = huge_doc.begin_edit(huge_layer, huge_doc.revision).value
	for i: int in range(170):
		huge._preview_epoch += 1
		huge._preview_tile_versions["%d,%d" % [i % 16, i / 16]] = huge._preview_epoch
	var huge_canvas: Control = Control.new()
	huge_canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var huge_window: Rect2i = Rect2i(0, 0, 256, 256)
	var huge_first: Dictionary = huge_canvas._preview_index_for_draw(huge, huge_window)
	check(not bool(huge_first["indexed"]) and 		(huge_first["stamps"] as Dictionary).is_empty(),
		"over-budget index fails closed to per-area fallback")
	var huge_second: Dictionary = huge_canvas._preview_index_for_draw(huge, huge_window)
	check(bool(huge_canvas._preview_index_reused) and huge_second == huge_first,
		"bounded fallback can be reused for a stable preview")
	huge._preview_epoch += 1
	huge._preview_tile_versions["-9223372036854775808,0"] = huge._preview_epoch
	var huge_third: Dictionary = huge_canvas._preview_index_for_draw(huge, huge_window)
	check(not bool(huge_canvas._preview_index_reused) and 		(not bool(huge_third["indexed"])) and 		(huge_third["stamps"] as Dictionary).is_empty(),
		"changed unsafe 64-bit tile invalidates cached fallback")
	huge_canvas.free()

	print("T095_PREVIEW_REUSE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T095_PREVIEW_REUSE_PASSED")
	quit(1 if failures else 0)


func _initialize() -> void:
	call_deferred("run")
