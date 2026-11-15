extends SceneTree
## Sparse over-budget explicit masks must spend their bounded tile plan on truth.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T141_OUTLINE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var mask: DrawingSelection = DrawingSelection.new()
	var area: Rect2i = Rect2i(-4096, -2304, 8192, 4608)
	mask.set_rectangle(area)
	var chosen: Dictionary[Vector2i, bool] = {}
	# More than 4096 occupied tiles, with most entries away from camera focus.
	for radius: int in range(50, -1, -1):
		for y: int in range(-27, 28):
			for x: int in range(-50, 51):
				if maxi(absi(x), absi(y)) != radius:
					continue
				chosen[Vector2i(x * 64 + 8, y * 64 + 8)] = true
				if chosen.size() >= 4250:
					break
			if chosen.size() >= 4250:
				break
		if chosen.size() >= 4250:
			break
	# Explicit interior islands that the former empty-cell ring cap misses.
	chosen[Vector2i(38 * 64 + 8, 8)] = true
	chosen[Vector2i(0, 0)] = true
	chosen[Vector2i(-38 * 64 + 8, 8)] = true
	mask.set_mask(chosen)
	canvas.set_selection_mask(mask, false)
	var started_us: int = Time.get_ticks_usec()
	var tiles: Array[Vector2i] = canvas._mask_outline_tile_candidates(area)
	var elapsed_us: int = Time.get_ticks_usec() - started_us
	print("T141_MODEL_METRICS " + JSON.stringify({"plan_cpu_us": elapsed_us, "input_entries": chosen.size()}))
	check(chosen.size() > canvas.MAX_MASK_OUTLINE_CACHE, "explicit sparse index exceeds budget")
	check(tiles.size() == canvas.MAX_MASK_OUTLINE_CACHE, "candidate plan is bounded")
	check(tiles.has(Vector2i(38, 0)) and tiles.has(Vector2i(-38, 0)),
		"far-but-occupied islands remain eligible")
	var all_occupied: bool = true
	for tile: Vector2i in tiles:
		if not chosen.has(tile * 64 + Vector2i(8, 8)) and tile != Vector2i.ZERO:
			all_occupied = false
			break
	check(all_occupied, "no empty tiles consume the selected-pixel budget")
	check(tiles[0] == Vector2i.ZERO, "overflow prioritizes occupied focal tile")
	var repeated: Array[Vector2i] = canvas._mask_outline_tile_candidates(area)
	check(tiles == repeated, "candidate ordering is stable")
	var duplicate_check: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in tiles:
		duplicate_check[tile] = true
	check(duplicate_check.size() == tiles.size(), "candidate tiles are unique")
	canvas.camera = Vector2(38 * 64, 0)
	var panned: Array[Vector2i] = canvas._mask_outline_tile_candidates(area)
	check(panned[0] == Vector2i(38, 0), "pan reprioritizes actual occupied tile")
	# A small mask retains its historical row-major exact candidate order.
	var tiny: DrawingSelection = DrawingSelection.new()
	tiny.set_rectangle(area)
	tiny.set_mask({Vector2i(320, 192): true, Vector2i(-320, -192): true, Vector2i(320, 128): false})
	canvas.set_selection_mask(tiny, false)
	check(canvas._mask_outline_tile_candidates(area) == [Vector2i(-5, -3), Vector2i(5, 3)],
		"small sparse mask remains exact and row-major")
	# More than the explicit indexing memory cap stays on the conservative path.
	var huge: Dictionary[Vector2i, bool] = {}
	for i: int in range(10000):
		huge[Vector2i((i % 128 - 64) * 64 + 8, (i / 128 - 40) * 64 + 8)] = true
	mask.set_mask(huge)
	canvas.set_selection_mask(mask, false)
	canvas.camera = Vector2.ZERO
	var fallback: Array[Vector2i] = canvas._mask_outline_tile_candidates(area)
	check(fallback.size() == canvas.MAX_MASK_OUTLINE_CACHE, "oversized index uses bounded fallback")
	check(fallback[0] == Vector2i.ZERO, "conservative fallback stays focal")
	check(mask.allows(Vector2i(38 * 64 + 8, 8)), "selection authorization stays independent")
	print("T141_OUTLINE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
