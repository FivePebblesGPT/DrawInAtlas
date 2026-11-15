extends SceneTree
## Cache reconciliation across an actual visible-tile-window translation.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T145_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(1680, 960)
	canvas.zoom = 0.25
	var selection: DrawingSelection = DrawingSelection.new()
	selection.set_rectangle(Rect2i(-6000, -3000, 12000, 6000))
	var pixels: Dictionary[Vector2i, bool] = {Vector2i(960 + 8, 8): true}
	selection.set_mask(pixels)
	check(selection.combine_rectangle(Rect2i(20000, 20000, 1, 1), "Subtract"),
		"compound mask uses conservative bounded ring plan")
	canvas.set_selection_mask(selection, false)
	var original_clip: Rect2i = Rect2i(-3360, -1920, 6720, 3840)
	var moved_clip: Rect2i = Rect2i(-3296, -1920, 6720, 3840)
	var old_window: Rect2i = Rect2i(-53, -30, 106, 60)
	var new_window: Rect2i = Rect2i(-52, -30, 106, 60)
	var old_plan: Array[Vector2i] = canvas._mask_outline_tile_candidates(original_clip)
	check(old_plan.size() == 4096, "old visible window saturates bounded contour plan")
	canvas._sync_mask_outline_cache(old_window, Vector2i.ZERO, old_plan, original_clip)
	for tile: Vector2i in old_plan:
		canvas._mask_outline_cache[tile] = PackedVector2Array([
			Vector2(tile * 64), Vector2(tile * 64 + Vector2i(1, 1))])
	var sentinel: Vector2i = Vector2i(15, 0)
	check(old_plan.has(sentinel), "target contour is in original plan")
	var sentinel_edges: PackedVector2Array = canvas._mask_outline_cache[sentinel].duplicate()
	canvas.camera = Vector2(64, 0)
	var new_plan: Array[Vector2i] = canvas._mask_outline_tile_candidates(moved_clip)
	check(new_plan.size() == 4096 and new_plan.has(sentinel),
		"new visible window is saturated and includes target")
	var common: int = 0
	for tile: Vector2i in new_plan:
		if canvas._mask_outline_cache.has(tile):
			common += 1
	check(common > 3500 and common < 4096, "camera pan shares thousands but not all tiles")
	canvas._sync_mask_outline_cache(new_window, Vector2i(1, 0), new_plan, moved_clip)
	check(canvas._mask_outline_window == new_window, "new visible tile window recorded")
	check(canvas._mask_outline_cache.size() == common,
		"window translation evicts only contours no longer eligible")
	check(canvas._mask_outline_cache.has(sentinel) and canvas._mask_outline_cache[sentinel] == sentinel_edges,
		"target cached edges survive translation without recompositing")
	var eligible: bool = true
	for tile: Vector2i in canvas._mask_outline_cache:
		if not new_plan.has(tile):
			eligible = false
			break
	check(eligible, "no obsolete cached contour lies outside new plan")
	check(canvas._mask_outline_cache.size() <= canvas.MAX_MASK_OUTLINE_CACHE,
		"hard 4096 contour-cache budget is preserved")
	var remaining: int = canvas._mask_outline_cache.size()
	canvas._sync_mask_outline_cache(new_window, Vector2i(1, 0), new_plan, moved_clip)
	check(canvas._mask_outline_cache.size() == remaining,
		"stable window reuses contours without further eviction")
	# A genuinely replaced selection must still invalidate every old contour.
	# Public in-place mask changes must not preserve stale outlines.
	var changed_pixels: Dictionary[Vector2i, bool] = {Vector2i(100, 100): true}
	canvas.selection_mask.set_mask(changed_pixels)
	canvas._mask_outline_tile_candidates(moved_clip)
	check(canvas._mask_outline_cache.is_empty(),
		"in-place public mask change invalidates cached contours")
	var replacement: DrawingSelection = selection.detached_copy()
	replacement.set_mask({Vector2i(-200, -200): true})
	canvas.set_selection_mask(replacement, false)
	check(canvas._mask_outline_cache.is_empty(), "selection replacement invalidates all old contours")
	check(selection.allows(Vector2i(968, 8)) and not selection.allows(Vector2i(0, 0)),
		"view-only optimization cannot change source-mask authorization")
	print("T145_MODEL_METRICS " + JSON.stringify({"shared": common, "retained": remaining}))
	print("T145_MODEL_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
