extends SceneTree
## Focal-first bounded fallback for over-capacity irregular outline windows.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T140_OUTLINE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var span: Rect2i = Rect2i(-4000, -2600, 8000, 5200)
	var mask: DrawingSelection = DrawingSelection.new()
	mask.set_rectangle(span)
	var many: Dictionary[Vector2i, bool] = {}
	for y: int in range(-30, 31):
		for x: int in range(-54, 55):
			many[Vector2i(x * 64 + 8, y * 64 + 8)] = true
			if many.size() > canvas.MAX_MASK_OUTLINE_CACHE + 64:
				break
		if many.size() > canvas.MAX_MASK_OUTLINE_CACHE + 64:
			break
	many[Vector2i(8, 8)] = true
	mask.set_mask(many)
	canvas.set_selection_mask(mask, false)
	var candidates: Array[Vector2i] = canvas._mask_outline_tile_candidates(span)
	check(candidates.size() == canvas.MAX_MASK_OUTLINE_CACHE, "fallback respects 4096-tile ceiling")
	check(candidates[0] == Vector2i.ZERO, "first fallback tile is the camera focal cell")
	check(candidates.has(Vector2i.ZERO), "large sparse mask retains central outline")
	check(not candidates.has(Vector2i(-63, -41)), "top-left scan no longer preempts focal outline")
	var unique: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in candidates:
		unique[tile] = true
	check(unique.size() == candidates.size(), "focal traversal has no duplicate tile visits")
	check(candidates == canvas._mask_outline_tile_candidates(span), "fallback order is deterministic")
	canvas.camera = Vector2(-2560, 1408)
	var moved: Array[Vector2i] = canvas._mask_outline_tile_candidates(span)
	check(moved[0] == Vector2i(-40, 22), "camera move changes the prioritized focal cell")
	check(moved.size() == canvas.MAX_MASK_OUTLINE_CACHE, "moved camera retains hard tile cap")
	canvas.camera = Vector2(200000, 200000)
	moved = canvas._mask_outline_tile_candidates(span)
	check(moved[0] == Vector2i(62, 40), "outside camera is clamped to footprint")
	var skinny: Rect2i = Rect2i(-32, -180000, 32, 360000)
	var inverted: DrawingSelection = mask.detached_copy()
	inverted.inverted = true
	canvas.set_selection_mask(inverted, false)
	canvas.camera = Vector2.ZERO
	moved = canvas._mask_outline_tile_candidates(skinny)
	check(moved.size() == canvas.MAX_MASK_OUTLINE_CACHE, "very tall narrow footprint still bounded")
	check(moved[0] == Vector2i(-1, 0), "narrow footprint clamps the focus horizontally")
	# Below-cap positive explicit masks must stay precise and not visit empty cells.
	var tiny: DrawingSelection = DrawingSelection.new()
	tiny.set_rectangle(span)
	tiny.set_mask({Vector2i(-2800, -1400): true, Vector2i(2900, 1500): true})
	canvas.set_selection_mask(tiny, false)
	var precise: Array[Vector2i] = canvas._mask_outline_tile_candidates(span)
	check(precise.size() == 2, "small sparse mask still indexes only actual occupied tiles")
	check(precise.has(Vector2i(-44, -22)) and precise.has(Vector2i(45, 23)),
		"both distant sparse-mask islands are preserved")
	# Composite and inverted masks retain conservative full-tile evaluation.
	var compound: DrawingSelection = tiny.detached_copy()
	check(compound.combine_rectangle(Rect2i(0, 0, 24, 24), "Add"), "compound mask setup")
	canvas.set_selection_mask(compound, false)
	check(canvas._mask_outline_tile_candidates(span)[0] == Vector2i.ZERO,
		"compound fallback prioritizes the camera without assuming sparse truth")
	compound = tiny.detached_copy()
	compound.inverted = true
	canvas.set_selection_mask(compound, false)
	check(canvas._mask_outline_tile_candidates(span)[0] == Vector2i.ZERO,
		"inverted fallback prioritizes the camera without changing authorization")
	check(tiny.allows(Vector2i(2900, 1500)) and not tiny.allows(Vector2i.ZERO),
		"selection authorization remains unchanged")
	print("T140_OUTLINE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
