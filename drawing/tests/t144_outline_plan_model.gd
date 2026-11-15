extends SceneTree
## Repeated four-tile contour redraws must reuse a bounded exact candidate plan.
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("T144_MODEL_FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(1680, 960)
	canvas.zoom = 0.25
	var selection: DrawingSelection = DrawingSelection.new()
	selection.set_rectangle(Rect2i(-4096, -4096, 8192, 8192))
	var pixels: Dictionary[Vector2i, bool] = {}
	for ty: int in range(-31, 32):
		for tx: int in range(-51, 52):
			pixels[Vector2i(tx * 64 + 8, ty * 64 + 8)] = true
			if pixels.size() >= 4300:
				break
		if pixels.size() >= 4300:
			break
	selection.set_mask(pixels)
	canvas.set_selection_mask(selection, false)
	var footprint: Rect2i = Rect2i(-4096, -4096, 8192, 8192)
	var initial: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	check(initial.size() == 4096, "4300 occupied tiles cap at the 4096-entry contour plan")
	check(canvas.get("_mask_outline_plan_build_count") == 1, "first plan builds once")
	var warm_samples: Array[int] = []
	for index: int in range(24):
		var start_us: int = Time.get_ticks_usec()
		var repeated: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
		warm_samples.append(Time.get_ticks_usec() - start_us)
		if index == 0:
			check(repeated == initial, "stable plan preserves exact focal ordering")
	check(canvas.get("_mask_outline_plan_build_count") == 1,
		"24 stable redraws do not reindex 4300 source-mask entries")
	var changed: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	changed.remove_at(0)
	check(canvas._mask_outline_tile_candidates(footprint) == initial,
		"caller modifications cannot poison the cached candidate list")
	canvas.camera = Vector2(64, 0)
	var panned: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	check(panned.size() == 4096 and panned != initial,
		"camera focus move recomputes nearest occupied tiles")
	check(canvas.get("_mask_outline_plan_build_count") == 2, "changed focal tile rebuilds once")
	var clipped: Rect2i = Rect2i(-4095, -4096, 8191, 8192)
	canvas._mask_outline_tile_candidates(clipped)
	check(canvas.get("_mask_outline_plan_build_count") == 3,
		"sub-tile clipped footprint changes invalidate cached plan")
	canvas._mask_outline_cache[Vector2i.ZERO] = PackedVector2Array()
	pixels[Vector2i(3500, 3500)] = true
	canvas.selection_mask.set_mask(pixels)
	canvas._mask_outline_tile_candidates(clipped)
	check(canvas.get("_mask_outline_plan_build_count") == 4,
		"in-place mask setter increments its plan generation")
	check(canvas._mask_outline_cache.is_empty(),
		"in-place source-mask change also invalidates traced contours")
	canvas.selection_mask.inverted = true
	var inverted_plan: Array[Vector2i] = canvas._mask_outline_tile_candidates(clipped)
	check(canvas.get("_mask_outline_plan_build_count") == 5,
		"direct inversion invalidates a previously indexed explicit plan")
	check(inverted_plan.size() == 4096 and inverted_plan != panned,
		"inverted mask switches to the conservative focal fallback")
	canvas.selection_mask.inverted = false
	canvas._mask_outline_tile_candidates(clipped)
	check(canvas.get("_mask_outline_plan_build_count") == 6,
		"restoring non-inverted mask rebuilds exact occupied candidates")
	var replacement: DrawingSelection = canvas.selection_mask.detached_copy()
	replacement.set_rectangle(Rect2i(-10, -10, 20, 20))
	canvas.set_selection_mask(replacement, false)
	var rectangle: Array[Vector2i] = canvas._mask_outline_tile_candidates(Rect2i(-10, -10, 20, 20))
	check(rectangle.size() == 4 and canvas.get("_mask_outline_plan_build_count") == 7,
		"new selection replaces the bounded plan and uses rectangle fallback")
	var oversized: DrawingSelection = DrawingSelection.new()
	oversized.set_rectangle(Rect2i(-4096, -4096, 8192, 8192))
	var dense_pixels: Dictionary[Vector2i, bool] = {}
	for y: int in range(100):
		for x: int in range(100):
			dense_pixels[Vector2i(x, y)] = true
	oversized.set_mask(dense_pixels)
	canvas.set_selection_mask(oversized, false)
	var fallback: Array[Vector2i] = canvas._mask_outline_tile_candidates(footprint)
	check(fallback.size() == 4096, "oversized selection still uses bounded fallback")
	canvas._mask_outline_tile_candidates(footprint)
	check(canvas.get("_mask_outline_plan_build_count") == 8,
		"fallback candidate plan is also reused when its context is stable")
	warm_samples.sort()
	print("T144_MODEL_METRICS " + JSON.stringify({"warm_median_us": warm_samples[12],
		"warm_p95_us": warm_samples[22], "occupied_tiles": pixels.size(),
		"builds": canvas.get("_mask_outline_plan_build_count")}))
	print("T144_MODEL_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
