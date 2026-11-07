extends SceneTree
## T-086: bounded frame-local preview stamps, including signed-seam parity and
## safe fallback for dense/corrupt and extreme source-tile footprints.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_PREVIEW_INDEX_FAILED: " + description)


func compare_stamps(session: DrawingEditSession, viewport: Rect2i,
		display_stride: int, max_entries: int = 40000) -> void:
	var result: Dictionary = session.preview_stamps_for_display_tiles(
		viewport, display_stride, max_entries)
	var indexed: bool = bool(result.get("indexed", false))
	var stamps: Dictionary = result["stamps"] as Dictionary
	if indexed:
		check(stamps.size() <= max_entries, "bounded index entries")
	else:
		check(stamps.is_empty(), "unbounded index returned no partial stamps")
	for y: int in range(viewport.position.y, viewport.end.y):
		for x: int in range(viewport.position.x, viewport.end.x):
			var region: Rect2i = Rect2i(x * display_stride, y * display_stride,
				display_stride, display_stride)
			var expected: int = session.preview_stamp_for_area(region)
			var actual: int = int(stamps.get("%d,%d" % [x, y], 0)) \
				if indexed else session.preview_stamp_for_area(region)
			check(actual == expected, "stamp parity at %d,%d stride %d" %
				[x, y, session.document.tile_stride])


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for stride: int in [1, 16, 128, 256, 513, 2048]:
		var doc: DrawingDocument = DrawingDocument.new("preview-index-%d" % stride, stride)
		var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
		var draft: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
		check(bool(draft.preview_stamps_for_display_tiles(Rect2i(-4, -3, 8, 6), 128)["indexed"]),
			"empty draft supports a blank index")
		# Populate generations directly to stress the indexing geometry. Actual
		# pixels/transactional behavior are tested by the real brush below.
		for tile: Vector2i in [Vector2i(-3, -3), Vector2i(-2, 0), Vector2i(-1, -1),
				Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, -2), Vector2i(8, 9)]:
			draft._preview_epoch += 1
			draft._preview_tile_versions["%d,%d" % [tile.x, tile.y]] = draft._preview_epoch
		compare_stamps(draft, Rect2i(-5, -5, 11, 11), 128)
		compare_stamps(draft, Rect2i(-4, -4, 7, 7), 128, 3)
		check(not bool(draft.preview_stamps_for_display_tiles(Rect2i(-2, -2, 4, 4),
				128, 0)["indexed"]), "zero memory budget fails to legacy lookup")
		check(not bool(draft.preview_stamps_for_display_tiles(Rect2i(-2, -2, 4, 4),
				0)["indexed"]), "invalid display tile size fails to legacy lookup")
		draft.cancel()
		check((draft.preview_stamps_for_display_tiles(Rect2i(-3, -3, 6, 6),
				128)["stamps"] as Dictionary).is_empty(),
			"cancelled session cannot publish stale index stamps")

	# Real live edits: overlapping edits to the same source tile must preserve
	# its latest version, including when rollback clears a draft pixel.
	var doc: DrawingDocument = DrawingDocument.new("preview-index-live", 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var session: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(session.paint_path(PackedVector2Array([Vector2(-0.5, -0.5)]),
		0xff334455, 3.0).ok, "stage negative seam brush")
	var first: int = session.preview_stamp_for_area(Rect2i(-128, -128, 128, 128))
	check(first > 0, "real held-button dab has a nonzero display generation")
	check(session.paint_path(PackedVector2Array([Vector2(-1.5, -1.5)]),
		0xff334455, 3.0).ok, "stage overlapping second dab")
	check(session.preview_stamp_for_area(Rect2i(-128, -128, 128, 128)) > first,
		"same-tile stroke increases generation")
	compare_stamps(session, Rect2i(-3, -3, 7, 7), 128)
	var before_cancel: int = doc.revision
	session.cancel()
	check(doc.revision == before_cancel and session.preview_stamp_for_area(
		Rect2i(-128, -128, 128, 128)) == 0, "cancel preserves committed revision")

	# The full 2048-byte source tile spans 256 display tiles; an intentionally
	# tiny cap must trigger the exact old per-area path, never a partial index.
	var large: DrawingDocument = DrawingDocument.new("preview-large", 2048)
	var large_layer: String = String(large.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var large_edit: DrawingEditSession = large.begin_edit(large_layer,
		large.revision).value as DrawingEditSession
	large_edit._preview_tile_versions["0,0"] = 5
	check(not bool(large_edit.preview_stamps_for_display_tiles(
		Rect2i(0, 0, 16, 16), 128, 20)["indexed"]),
		"bounded fallback for one large storage tile")
	compare_stamps(large_edit, Rect2i(0, 0, 16, 16), 128, 20)
	large_edit._preview_tile_versions["999999999999999999,0"] = 6
	check(not bool(large_edit.preview_stamps_for_display_tiles(
		Rect2i(0, 0, 16, 16), 128)["indexed"]),
		"64-bit world multiplication overflow fails closed to exact path")
	large_edit._preview_tile_versions.erase("999999999999999999,0")
	large_edit._preview_tile_versions["-9223372036854775808,0"] = 7
	check(not bool(large_edit.preview_stamps_for_display_tiles(
		Rect2i(0, 0, 16, 16), 128)["indexed"]),
		"minimum signed int coordinate cannot bypass overflow guard")
	large_edit.cancel()

	# One 25%-style viewport can expose thousands of source display tiles.
	# No fixed timing assertion on CI: verify parity separately and record the
	# relative overhead for a repeatable synthetic long-stroke change set.
	var perf: DrawingDocument = DrawingDocument.new("preview-index-bench", 1)
	var perf_layer: String = String(perf.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var perf_edit: DrawingEditSession = perf.begin_edit(perf_layer,
		perf.revision).value as DrawingEditSession
	for i: int in range(240):
		var x: int = (i * 117) % 1900 - 950
		var y: int = (i * 199) % 1100 - 550
		perf_edit._preview_tile_versions["%d,%d" % [x, y]] = i + 1
	var viewport: Rect2i = Rect2i(-16, -12, 32, 24)
	compare_stamps(perf_edit, viewport, 128)
	check(not bool(perf_edit.preview_stamps_for_display_tiles(viewport, 128,
		80)["indexed"]), "bounded work counts repeated storage keys in same display tile")
	var indexed_times: Array[int] = []
	var original_times: Array[int] = []
	for trial: int in range(5):
		var start: int = Time.get_ticks_usec()
		var table: Dictionary = perf_edit.preview_stamps_for_display_tiles(viewport, 128)
		var generations: Dictionary = table["stamps"] as Dictionary
		var index_accum: int = 0
		for y: int in range(viewport.position.y, viewport.end.y):
			for x: int in range(viewport.position.x, viewport.end.x):
				index_accum += int(generations.get("%d,%d" % [x, y], 0))
		indexed_times.append(Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		var old_accum: int = 0
		for y: int in range(viewport.position.y, viewport.end.y):
			for x: int in range(viewport.position.x, viewport.end.x):
				old_accum += perf_edit.preview_stamp_for_area(
					Rect2i(x * 128, y * 128, 128, 128))
		original_times.append(Time.get_ticks_usec() - start)
		check(index_accum == old_accum and bool(table["indexed"]),
			"benchmarked path matches source generations")
	indexed_times.sort()
	original_times.sort()
	print(("T086_PREVIEW_INDEX_TIMING median_index_us=%d median_legacy_us=%d runs=5 "
		+ "visible_tiles=%d changed_storage_tiles=%d") % [indexed_times[2],
		original_times[2], viewport.size.x * viewport.size.y,
		perf_edit._preview_tile_versions.size()])

	print("T086_PREVIEW_INDEX: %d checks; %d failed" % [checks, failures])
	print("T086_PREVIEW_INDEX_PASSED" if failures == 0 else "T086_PREVIEW_INDEX_FAILED")
	quit(0 if failures == 0 else 1)
