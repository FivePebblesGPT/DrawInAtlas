extends SceneTree
## Outline cache continuity across an over-budget in-window focus change.
var checks: int = 0
var failures: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T142_OUTLINE_FAILED: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	check(canvas.has_method("_sync_mask_outline_cache"),
		"canvas exposes bounded contour cache reconciliation")
	if failures > 0:
		print("T142_OUTLINE_NEGATIVE checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	var footprint: Rect2i = Rect2i(-2880, -1600, 5760, 3200)
	var mask: DrawingSelection = DrawingSelection.new()
	mask.set_rectangle(footprint)
	mask.set_mask({Vector2i(960 + 8, 8): true})
	check(mask.combine_rectangle(Rect2i(10000, 10000, 1, 1), "Subtract"),
		"compound mask setup exercises conservative over-capacity path")
	canvas.set_selection_mask(mask, false)
	var before: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	var window: Rect2i = Rect2i(-45, -25, 90, 50)
	check(before.size() == canvas.MAX_MASK_OUTLINE_CACHE, "before plan is saturated")
	canvas._mask_outline_window = window
	canvas._mask_outline_focus = Vector2i.ZERO
	for tile: Vector2i in before:
		canvas._mask_outline_cache[tile] = PackedVector2Array([Vector2(tile), Vector2(tile + Vector2i.ONE)])
	var original_count: int = canvas._mask_outline_cache.size()
	canvas.camera = Vector2(64, 0)
	var after: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	check(after.size() == canvas.MAX_MASK_OUTLINE_CACHE, "after plan is saturated")
	var expected_overlap: int = 0
	for tile: Vector2i in after:
		if canvas._mask_outline_cache.has(tile):
			expected_overlap += 1
	check(expected_overlap > 3500 and expected_overlap <= original_count,
		"one-cell pan retains thousands of eligible outline tiles")
	canvas._sync_mask_outline_cache(window, Vector2i(1, 0), after)
	check(canvas._mask_outline_cache.size() == expected_overlap,
		"focus pan removes only contours no longer in the current plan")
	check(canvas._mask_outline_focus == Vector2i(1, 0), "focal identity is updated")
	var all_eligible: bool = true
	for tile: Vector2i in canvas._mask_outline_cache:
		if not after.has(tile):
			all_eligible = false
			break
	check(all_eligible, "no stale/out-of-plan tiles retained")
	var preserved: bool = true
	for tile: Vector2i in after:
		if before.has(tile) and not canvas._mask_outline_cache.has(tile):
			preserved = false
			break
	check(preserved, "all overlapping tiles retain their cached contour data")
	check(canvas._mask_outline_cache.size() <= canvas.MAX_MASK_OUTLINE_CACHE,
		"hard 4096-cache budget is unchanged")
	# A different selection/visible window must still drop cached contours.
	canvas._sync_mask_outline_cache(Rect2i(-40, -20, 80, 40), Vector2i(2, 0), after)
	check(canvas._mask_outline_cache.is_empty(), "changed tile window invalidates all old contours")
	canvas._mask_outline_cache[Vector2i(0, 0)] = PackedVector2Array()
	var small_plan: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ONE]
	canvas._sync_mask_outline_cache(Rect2i(-40, -20, 80, 40), Vector2i(3, 0), small_plan)
	check(canvas._mask_outline_cache.size() == 1,
		"below-cap selection retains valid contours through focus changes")
	check(mask.allows(Vector2i(968, 8)) and not mask.allows(Vector2i(0, 0)),
		"mask authorization is not changed by cache planning")
	print("T142_OUTLINE_METRICS " + JSON.stringify({"overlap": expected_overlap,
		"new_candidates": after.size() - expected_overlap}))
	print("T142_OUTLINE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
