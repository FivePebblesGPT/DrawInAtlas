extends SceneTree
## T-086 bounded, focal-point-aware dense viewport texture retention.
## Pure headless model: deliberately does not imply GPU or physical latency.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T086_FOCUS_FAILED: " + label)


func seed_view(canvas: Control, visible: Rect2i, focus: Vector2) -> int:
	var evictions: int = 0
	for y: int in range(visible.position.y, visible.end.y):
		for x: int in range(visible.position.x, visible.end.x):
			var key: String = "%d,%d" % [x, y]
			if canvas._display_tiles.has(key):
				continue
			var before: int = canvas._display_tiles.size()
			var retain: bool = canvas._reserve_display_slot(visible, Vector2i(x, y), focus)
			if retain:
				if before == canvas.MAX_DISPLAY_TILES:
					evictions += 1
				canvas._display_tiles[key] = {
					"area": Rect2i(x * 128, y * 128, 128, 128), "last_used": 1}
	return evictions


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var visible: Rect2i = Rect2i(-8, -6, 16, 12)
	check(visible.get_area() == 192 and canvas.MAX_DISPLAY_TILES == 144,
		"dense test contains 48 more tiles than retained budget")
	check(seed_view(canvas, visible, Vector2.ZERO) > 0,
		"first center-focused pass displaces scan-order edge entries")
	check(canvas._display_tiles.size() == canvas.MAX_DISPLAY_TILES,
		"retained textures remain strictly bounded")
	check(canvas._display_tiles.has("0,0") and canvas._display_tiles.has("-1,-1"),
		"center source tiles survive first fill")
	check(not canvas._display_tiles.has("-8,-6") and
		not canvas._display_tiles.has("7,5"),
		"opposite corner tiles remain transient")
	var original_keys: Array = canvas._display_tiles.keys()
	check(seed_view(canvas, visible, Vector2.ZERO) == 0 and
		canvas._display_tiles.size() == canvas.MAX_DISPLAY_TILES,
		"repeat with unchanged center does not reallocate retained entries")
	var original_count: int = 0
	for key: String in original_keys:
		if canvas._display_tiles.has(key):
			original_count += 1
	check(original_count == canvas.MAX_DISPLAY_TILES,
		"stable center uses exactly the same cache keys")
	check(seed_view(canvas, visible, Vector2(-7.5, -5.5)) > 0,
		"focus relocation replaces less relevant visible textures")
	check(canvas._display_tiles.has("-8,-6") and
		not canvas._display_tiles.has("7,5"),
		"relocated focus retains target corner")
	check(seed_view(canvas, visible, Vector2(-7.5, -5.5)) == 0,
		"repeat after pointer focus shift is stable")
	canvas.size = Vector2(256, 256)
	canvas.zoom = 0.5
	canvas.camera = Vector2(256, -128)
	canvas.pointer_known = false
	check(canvas._display_cache_focus().distance_to(Vector2(2, -1)) < 0.001,
		"absent pointer uses viewport source center")
	canvas.pointer_known = true
	canvas.last_pointer_position = Vector2(0, 0)
	check(canvas._display_cache_focus().distance_to(Vector2(0, -3)) < 0.001,
		"visible pointer focus uses signed source-space transform")
	canvas.last_pointer_position = Vector2(-1, 0)
	check(canvas._display_cache_focus().distance_to(Vector2(2, -1)) < 0.001,
		"outside pointer falls back to viewport center")
	canvas._display_tiles.clear()
	seed_view(canvas, visible, Vector2.ZERO)
	var replace_key: String = String(canvas._display_tiles.keys()[0])
	canvas._display_tiles["-50,-50"] = (canvas._display_tiles[replace_key] as Dictionary).duplicate()
	canvas._display_tiles["-50,-50"]["area"] = Rect2i(-6400, -6400, 128, 128)
	canvas._display_tiles.erase(replace_key)
	check(canvas._reserve_display_slot(visible, Vector2i(-8, -5), Vector2.ZERO)
		and not canvas._display_tiles.has("-50,-50"),
		"offscreen texture evicted before any visible texture")
	check(canvas._display_tiles.size() == canvas.MAX_DISPLAY_TILES - 1,
		"reservation itself only evicts and leaves insertion to caller")
	print("T086_FOCUS: %d checks; %d failed" % [checks, failures])
	print("T086_FOCUS_PASSED" if failures == 0 else "T086_FOCUS_FAILED")
	quit(0 if failures == 0 else 1)
