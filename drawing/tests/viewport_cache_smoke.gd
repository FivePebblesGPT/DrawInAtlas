extends SceneTree
## T-086: source-revision display invalidations and independent preview tile stamps.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_MODEL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t086-model", 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.display_changes_since(0)["full"], "untracked creation forces full invalidation")
	var revision: int = doc.revision
	var source: DrawingEditSession = doc.begin_edit(layer, revision).value as DrawingEditSession
	check(source.paint_path(PackedVector2Array([Vector2(-1.5, -1.5)]), 0xff4466ee, 2.0).ok,
		"signed-seam preview stage")
	check(source.preview_stamp_for_area(Rect2i(-128, -128, 128, 128)) > 0,
		"negative display tile sees unsigned storage-tile draft")
	check(source.preview_stamp_for_area(Rect2i(128, 128, 128, 128)) == 0,
		"unrelated display tile does not see preview")
	var first_stamp: int = source.preview_stamp_for_area(Rect2i(-128, -128, 128, 128))
	check(source.paint_path(PackedVector2Array([Vector2(-2.5, -2.5)]), 0xff4466ee, 2.0).ok,
		"second sample within same storage tile")
	check(source.preview_stamp_for_area(Rect2i(-128, -128, 128, 128)) > first_stamp,
		"in-progress same-tile redraw invalidated")
	check(source.commit().ok, "commit seam stroke")
	var changes: Dictionary = doc.display_changes_since(revision)
	check(not changes["full"] and (changes["regions"] as Array).size() == 1,
		"single atomic raster edit publishes one bounded dirty region")
	var dirty: DrawingDirtyRegion = changes["regions"][0]
	check(dirty.x < 0 and dirty.y < 0 and dirty.width < 16 and dirty.height < 16,
		"dirty region preserves local signed bounds")
	check(doc.display_changes_since(doc.revision)["regions"].is_empty(),
		"no-op view sync requires no recomposition")
	var before_undo: int = doc.revision
	check(doc.undo().ok, "one-step seam undo")
	check(not doc.display_changes_since(before_undo)["full"],
		"undo emits selective raster invalidation")
	var before_redo: int = doc.revision
	check(doc.redo().ok, "one-step seam redo")
	check(not doc.display_changes_since(before_redo)["full"],
		"redo emits selective raster invalidation")
	var before_visibility: int = doc.revision
	check(doc.set_visibility(layer, false).ok and doc.display_changes_since(before_visibility)["full"],
		"visibility invalidates composited layers globally")
	check(doc.set_visibility(layer, true).ok, "restore visible layer")
	check(doc.display_changes_since(before_visibility)["full"],
		"missing revision cannot be skipped by a later raster publication")
	var after_layer: int = doc.revision
	var next: DrawingEditSession = doc.begin_edit(layer, after_layer).value as DrawingEditSession
	check(next.paint_path(PackedVector2Array([Vector2(3.5, 4.5)]), 0xffaabbcc).ok
		and next.commit().ok, "new content after structural changes")
	check(not doc.display_changes_since(after_layer)["full"],
		"recent content-only change permits selective reuse")
	check(doc.display_changes_since(-1)["full"] and doc.display_changes_since(doc.revision + 1)["full"],
		"unknown cache versions fail closed")
	# The change log is bounded and cannot promise selective changes to a stale
	# client after many transactions.
	var old_revision: int = doc.revision
	for i: int in range(DrawingDocument.DISPLAY_CHANGE_LIMIT + 2):
		var step: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
		if not step.paint_path(PackedVector2Array([Vector2(float(20 + i), 6.5)]), 0xff112233).ok \
				or not step.commit().ok:
			check(false, "bounded-journal setup commit %d" % i)
			break
	check(doc.display_changes_since(old_revision)["full"],
		"evicted journal history forces conservative recomposition")
	check(not doc.display_changes_since(doc.revision - 1)["full"],
		"latest revision remains selectively accessible after eviction")

	var detached: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	check(detached.paint_path(PackedVector2Array([Vector2(220.5, 220.5)]), 0xffaabbcc).ok,
		"draft can touch second storage tile")
	check(detached.preview_stamp_for_area(Rect2i(128, 128, 128, 128)) > 0 and
		detached.preview_stamp_for_area(Rect2i(-128, -128, 128, 128)) == 0,
		"draft stamp uses tile-accurate source intersection")
	detached.cancel()
	check(detached.preview_stamp_for_area(Rect2i(128, 128, 128, 128)) == 0,
		"cancel clears draft generation without publication")

	# Lazy source registration has no content revision, but adds a previously
	# published source tile to the viewport and must invalidate occupancy.
	var lazy_doc: DrawingDocument = DrawingDocument.new("t086-lazy", 16)
	var lazy_layer: String = String(lazy_doc.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	var lazy_bytes: PackedByteArray = PackedByteArray()
	lazy_bytes.resize(16 * 16 * 4)
	var before_register: int = lazy_doc.revision
	var lazy_fetch: Callable = func(_reference: String) -> PackedByteArray: return lazy_bytes
	check(lazy_doc.register_lazy_chunk(lazy_layer, 1, 0, "blob",
		DrawingRasterTile.digest_rgba8(lazy_bytes, 16), lazy_fetch).ok,
		"register published source with valid independent tile digest")
	check(lazy_doc.revision == before_register and lazy_doc.display_source_epoch == 1,
		"lazy source registration increments display epoch without changing document revision")

	print("T086_MODEL: %d checks; %d failed" % [checks, failures])
	print("T086_MODEL_PASSED" if failures == 0 else "T086_MODEL_FAILED")
	quit(0 if failures == 0 else 1)
