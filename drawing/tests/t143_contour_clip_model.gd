extends SceneTree
## Reconcile a saturated selection-outline cache when exact viewport clipping
## changes inside the same 64px tile window and camera focal tile.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T143_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(1680, 960)
	canvas.zoom = 0.25
	var selection: DrawingSelection = DrawingSelection.new()
	selection.set_rectangle(Rect2i(-3500, -2000, 7000, 4000))
	var pixels: Dictionary[Vector2i, bool] = {}
	for ty: int in range(-26, 27):
		for tx: int in range(-39, 40):
			if pixels.size() >= 4095:
				break
			pixels[Vector2i(tx * 64 + 8, ty * 64 + 8)] = true
		if pixels.size() >= 4095:
			break
	var old_tile: Vector2i = Vector2i(-53, 0)
	var new_tile: Vector2i = Vector2i(52, 0)
	pixels[Vector2i(-3355, 12)] = true
	pixels[Vector2i(3364, 12)] = true
	selection.set_mask(pixels)
	canvas.set_selection_mask(selection, false)
	check(pixels.size() == 4097, "exactly 4095 shared and two edge-island pixel entries")
	var before_clip: Rect2i = Rect2i(-3361, -1921, 6722, 3842).intersection(selection.bounds)
	var after_clip: Rect2i = Rect2i(-3353, -1921, 6722, 3842).intersection(selection.bounds)
	var before: Array[Vector2i] = canvas._mask_outline_tile_candidates(before_clip)
	check(before.size() == 4096, "old clipped plan saturates cache")
	check(before.has(old_tile) and not before.has(new_tile), "old edge is visible, new edge is not")
	var window: Rect2i = Rect2i(-53, -31, 106, 62)
	var focus: Vector2i = Vector2i.ZERO
	canvas._sync_mask_outline_cache(window, focus, before, before_clip)
	for tile: Vector2i in before:
		canvas._mask_outline_cache[tile] = PackedVector2Array()
	canvas.camera = Vector2(8, 0)
	var after: Array[Vector2i] = canvas._mask_outline_tile_candidates(after_clip)
	check(after.size() == 4096, "new clipped plan is also saturated")
	check(after.has(new_tile) and not after.has(old_tile), "edge islands exchange visibility")
	check(canvas._mask_outline_window == window and canvas._mask_outline_focus == focus,
		"camera's sub-tile pan retains window and focal tile")
	canvas._sync_mask_outline_cache(window, focus, after, after_clip)
	check(canvas._mask_outline_cache.size() == 4095, "only stale edge tile evicted")
	check(not canvas._mask_outline_cache.has(old_tile), "old off-screen contour removed")
	check(not canvas._mask_outline_cache.has(new_tile), "new contour has a free cache slot")
	var all_shared: bool = true
	for tile: Vector2i in after:
		if tile != new_tile and not canvas._mask_outline_cache.has(tile):
			all_shared = false
			break
	check(all_shared, "all 4095 shared contours remain cached")
	check(canvas._mask_outline_cache.size() <= canvas.MAX_MASK_OUTLINE_CACHE,
		"hard contour cache ceiling is unchanged")
	# A second identical clipped footprint must not evict cached contents.
	canvas._mask_outline_cache[new_tile] = PackedVector2Array()
	canvas._sync_mask_outline_cache(window, focus, after, after_clip)
	check(canvas._mask_outline_cache.size() == 4096,
		"stable plan reuses the complete cache without clearing it")
	canvas._sync_mask_outline_cache(Rect2i(-52, -31, 105, 62), focus, after, after_clip)
	check(canvas._mask_outline_cache.size() == 4096,
		"different tile windows retain unchanged shared eligible contours")
	check(selection.allows(Vector2i(3364, 12)) and selection.allows(Vector2i(-3355, 12)),
		"outline reconciliation does not change pixel authorization")
	print("T143_MODEL_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
