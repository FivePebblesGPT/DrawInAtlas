extends SceneTree
## Bounded sparse explicit-mask outline traversal; no rendering required.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T139_OUTLINE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var mask: DrawingSelection = DrawingSelection.new()
	var span: Rect2i = Rect2i(-4000, -2600, 8000, 5200)
	mask.set_rectangle(span)
	var points: Dictionary[Vector2i, bool] = {
		Vector2i(-2800, -1400): true,
		Vector2i(2900, 1500): true,
		Vector2i(10, 0): false,
		Vector2i(4200, 10): true}
	mask.set_mask(points)
	canvas.set_selection_mask(mask, false)
	var tiles: Array[Vector2i] = canvas._mask_outline_tile_candidates(span)
	check(tiles.size() == 2, "sparse explicit mask visits only two occupied outline tiles")
	check(tiles.has(Vector2i(-44, -22)), "negative selected island retains contour tile")
	check(tiles.has(Vector2i(45, 23)), "far positive selected island is not dropped")
	check(not tiles.has(Vector2i(0, 0)), "false mask entries do not create contour tiles")
	check(not tiles.has(Vector2i(65, 0)), "keys outside base bounds cannot authorize tiles")
	check(tiles == canvas._mask_outline_tile_candidates(span), "candidate ordering is deterministic")
	var local: Array[Vector2i] = canvas._mask_outline_tile_candidates(Rect2i(2700, 1300, 400, 400))
	check(local.size() == 1 and local[0] == Vector2i(45, 23),
		"viewport clipping excludes the offscreen negative island")
	var copied: DrawingSelection = mask.detached_copy()
	copied.inverted = true
	canvas.set_selection_mask(copied, false)
	check(canvas._mask_outline_tile_candidates(span).size() == canvas.MAX_MASK_OUTLINE_CACHE,
		"inverted explicit masks keep the bounded conservative scan")
	copied = mask.detached_copy()
	check(copied.combine_rectangle(Rect2i(0, 0, 24, 24), "Add"), "compound mask accepted")
	canvas.set_selection_mask(copied, false)
	check(canvas._mask_outline_tile_candidates(span).size() == canvas.MAX_MASK_OUTLINE_CACHE,
		"compound explicit masks keep the bounded conservative scan")
	canvas.set_selection_mask(mask, false)
	var empty: Rect2i = Rect2i(5000, 0, 50, 50)
	check(canvas._mask_outline_tile_candidates(empty).is_empty(), "offscreen sparse selection is empty")
	var many: Dictionary[Vector2i, bool] = {}
	for y: int in range(65):
		for x: int in range(64):
			many[Vector2i(-4000 + x * 64, -2600 + y * 64)] = true
	var large: DrawingSelection = DrawingSelection.new()
	large.set_rectangle(span)
	large.set_mask(many)
	canvas.set_selection_mask(large, false)
	check(canvas._mask_outline_tile_candidates(span).size() == canvas.MAX_MASK_OUTLINE_CACHE,
		"over-capacity explicit indexes keep bounded tile allocation")
	check(canvas._mask_outline_tile_candidates(Rect2i()).is_empty(),
		"empty footprint creates no traversal")
	check(mask.allows(Vector2i(2900, 1500)) and not mask.allows(Vector2i(10, 0)),
		"selected pixel truth is unchanged")
	print("T139_OUTLINE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
