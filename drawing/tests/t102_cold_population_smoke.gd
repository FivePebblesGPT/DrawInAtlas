extends SceneTree
## T-102 deterministic scheduling oracle; no GPU timing is inferred here.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T102_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func fill_occupancy(canvas: Control, window: Rect2i) -> void:
	canvas._occupied_display_tiles.clear()
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			canvas._occupied_display_tiles["%d,%d" % [x, y]] = true

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var window := Rect2i(-3, -3, 6, 6)
	fill_occupancy(canvas, window)
	var selected: Dictionary = canvas._cold_population_targets(window, Vector2(-1.5, -1.5))
	check(canvas.MAX_COLD_TILES_PER_DRAW == 4 and selected.size() == 4,
		"cold population selects a bounded batch from 36 signed tiles")
	check(selected.has("-2,-2") and selected.has("-1,-2")
		and selected.has("-2,-1") and selected.has("-2,-3"),
		"selection prioritizes nearest signed tiles, not raster scan order")
	check(not selected.has("-3,-3") and not selected.has("2,2"),
		"far signed tiles remain pending while center becomes visible")
	var one: String = "-2,-2"
	canvas._display_tiles[one] = {"dirty": false, "preview_stamp": 0, "preview_owner": null}
	var after_hit: Dictionary = canvas._cold_population_targets(window, Vector2(-1.5, -1.5))
	check(not after_hit.has(one) and after_hit.size() == 4,
		"cached unchanged tile is not rescheduled")
	canvas._display_tiles[one]["dirty"] = true
	check(canvas._cold_population_targets(window, Vector2(-1.5, -1.5)).has(one),
		"dirty source invalidation requires a repaint")
	canvas._display_tiles[one]["dirty"] = false
	canvas._display_tiles[one]["preview_stamp"] = 3
	check(canvas._cold_population_targets(window, Vector2(-1.5, -1.5)).has(one),
		"stale detached preview cannot be reused after cancel")
	canvas._display_tiles[one]["preview_stamp"] = 0
	canvas._display_tiles[one]["preview_owner"] = RefCounted.new()
	check(canvas._cold_population_targets(window, Vector2(-1.5, -1.5)).has(one),
		"preview owner identity is included in invalidation")
	canvas._display_tiles[one]["preview_owner"] = null
	canvas._display_tiles.clear()
	fill_occupancy(canvas, Rect2i(-1, -1, 2, 2))
	check(canvas._cold_population_targets(Rect2i(-1, -1, 2, 2), Vector2.ZERO).is_empty(),
		"tiny visible footprint remains single-frame")
	fill_occupancy(canvas, Rect2i(-9, -8, 16, 10))
	check(canvas._cold_population_targets(Rect2i(-9, -8, 16, 10), Vector2.ZERO).is_empty(),
		"160-tile viewport uses full-frame transient fallback")
	fill_occupancy(canvas, window)
	canvas._occupancy_unknown = true
	check(canvas._cold_population_targets(window, Vector2.ZERO).is_empty(),
		"unknown occupancy never skips potentially visible content")
	canvas._occupancy_unknown = false
	var doc := DrawingDocument.new("t102-preview-guard")
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "pixels").value)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "create an authentic detached session for gating")
	if started.ok:
		canvas._move_preview = started.value as DrawingEditSession
		check(canvas._cold_population_targets(window, Vector2.ZERO).is_empty(),
			"a live detached preview is always rendered without cold throttling")
		canvas._move_preview.cancel()
		canvas._move_preview = null
	check(canvas._cold_population_targets(window, Vector2.ZERO).size() == 4,
		"closed preview restores the bounded source-only scheduler")
	print("T102_MODEL: %d checks; %d failed" % [checks, failures])
	print("T102_MODEL_PASSED" if failures == 0 else "T102_MODEL_FAILED")
	quit(0 if failures == 0 else 1)
