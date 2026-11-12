extends SceneTree
## T-103: over-budget focal retention is selected once per frame, not by
## repeated mutation of the live LRU while the draw list is traversed.

var checks: int = 0
var failures: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T103_MODEL_FAILED: " + description)

func occupancy(canvas: Control, window: Rect2i) -> void:
	canvas._occupied_display_tiles.clear()
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			canvas._occupied_display_tiles["%d,%d" % [x, y]] = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	check(canvas.has_method("_focal_retention_plan"), "focal retention planner is available")
	if not canvas.has_method("_focal_retention_plan"):
		print("T103_MODEL: %d checks; %d failed" % [checks, failures])
		quit(1)
		return
	var window: Rect2i = Rect2i(-8, -6, 16, 12)
	occupancy(canvas, window)
	var plan: Dictionary = canvas._focal_retention_plan(window, Vector2.ZERO)
	check(plan.size() == canvas.MAX_DISPLAY_TILES, "192 occupied tiles select exactly 144 retainable keys")
	check(plan.has("-1,-1") and plan.has("0,0") and not plan.has("-8,-6")
		and not plan.has("7,5"), "nearest signed content wins over raster iteration order")
	check(canvas._focal_retention_plan(window, Vector2.ZERO) == plan,
		"fixed focus deterministically selects the same retained tiles")
	var corner: Dictionary = canvas._focal_retention_plan(window, Vector2(-7.5, -5.5))
	check(corner.size() == canvas.MAX_DISPLAY_TILES and corner.has("-8,-6")
		and not corner.has("7,5"), "focus relocation changes chosen working set")
	var sparse: Rect2i = Rect2i(-50, -50, 100, 100)
	check(canvas._focal_retention_plan(sparse, Vector2.ZERO).size() == 144,
		"large sparse view enumerates bounded known occupancy")
	canvas._occupied_display_tiles.erase("-8,-6")
	check(not canvas._focal_retention_plan(window, Vector2(-7.5, -5.5)).has("-8,-6"),
		"retired occupancy is excluded from the plan")
	canvas._occupancy_unknown = true
	check(canvas._focal_retention_plan(window, Vector2.ZERO).is_empty(),
		"unknown occupancy retains conservative fallback")
	canvas._occupancy_unknown = false
	occupancy(canvas, Rect2i(-2, -2, 4, 4))
	check(canvas._focal_retention_plan(Rect2i(-2, -2, 4, 4), Vector2.ZERO).is_empty(),
		"small view does not pay focal planning overhead")
	occupancy(canvas, window)
	check(canvas._focal_retention_plan(Rect2i(-1000, -1000, 2000, 2000), Vector2.ZERO).is_empty(),
		"extreme viewport dimensions use bounded conservative fallback")
	var doc: DrawingDocument = DrawingDocument.new("t103-preview")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "layer").value)
	var edit_result: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(edit_result.ok, "create preview for fallback guard")
	if edit_result.ok:
		canvas._move_preview = edit_result.value as DrawingEditSession
		check(canvas._focal_retention_plan(window, Vector2.ZERO).is_empty(),
			"live detached preview retains conservative path")
		canvas._move_preview.cancel()
		canvas._move_preview = null
	check(canvas._focal_retention_plan(window, Vector2.ZERO).size() == 144,
		"closed preview restores focal planning")
	print("T103_MODEL: %d checks; %d failed" % [checks, failures])
	print("T103_MODEL_PASSED" if failures == 0 else "T103_MODEL_FAILED")
	quit(0 if failures == 0 else 1)
