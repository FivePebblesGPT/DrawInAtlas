extends SceneTree
## Source/preview sparse enumeration must never drop detached or committed tiles.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T136_UNION_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var view: Rect2i = Rect2i(-100, -100, 200, 200)
	canvas._occupied_display_tiles["-2,-3"] = true
	canvas._occupied_display_tiles["0,0"] = true
	var changed: Dictionary = {"-2,-3": 3, "4,5": 9, "-4,6": 2}
	var old: Dictionary = canvas._sparse_visible_draw_rows(view, true)
	check(not bool(old["indexed"]), "unindexed detached preview must fall back")
	var indexed: Dictionary = canvas._sparse_visible_draw_rows(view, true, changed, true)
	check(bool(indexed["indexed"]), "complete detached preview enables bounded sparse union")
	check(int(indexed["count"]) == 4, "overlapping committed/preview tile included exactly once")
	check((indexed["ys"] as Array) == [-3, 0, 5, 6], "signed rows preserve painter's order")
	check((indexed["rows"] as Dictionary).get(-3, []) == [-2], "negative committed tile preserved")
	check((indexed["rows"] as Dictionary).get(5, []) == [4], "preview-only tile is included")
	check((indexed["rows"] as Dictionary).get(6, []) == [-4], "negative preview-only tile is included")
	var moved: Dictionary = canvas._sparse_visible_draw_rows(view, true, {"9,9": 20}, true)
	check(bool(moved["indexed"]) and int(moved["count"]) == 3 and
		not (moved["rows"] as Dictionary).has(5), "new preview generation cannot reuse stale rows")
	check(not bool(canvas._sparse_visible_draw_rows(view, true, changed, false)["indexed"]),
		"incomplete preview index always falls back")
	check(not bool(canvas._sparse_visible_draw_rows(view, true, {}, false)["indexed"]),
		"missing preview index always falls back")
	canvas._occupancy_unknown = true
	check(not bool(canvas._sparse_visible_draw_rows(view, true, changed, true)["indexed"]),
		"unknown committed occupancy always falls back")
	canvas._occupancy_unknown = false
	check(not bool(canvas._sparse_visible_draw_rows(Rect2i(-2, -3, 1, 1), true,
			changed, true)["indexed"]), "small view retains original row traversal")
	check(not bool(canvas._sparse_visible_draw_rows(view, true, {"broken": 1}, true)["indexed"]),
		"malformed preview key cannot authorize culling")
	check(not bool(canvas._sparse_visible_draw_rows(view, true, {"01,0": 1}, true)["indexed"]),
		"noncanonical preview key cannot alias committed tile")
	canvas._occupied_display_tiles["garbage"] = true
	check(not bool(canvas._sparse_visible_draw_rows(view, true, changed, true)["indexed"]),
		"malformed committed key still causes conservative fallback")
	canvas._occupied_display_tiles.erase("garbage")
	check(not bool(canvas._sparse_visible_draw_rows(view, true,
			{"2,2": 0}, true)["indexed"]), "invalid zero preview generation fails closed")
	canvas._occupied_display_tiles.clear()
	var blank: Dictionary = canvas._sparse_visible_draw_rows(view, true, {}, true)
	check(bool(blank["indexed"]) and int(blank["count"]) == 0,
		"empty complete preview and empty committed index omit all tiles")
	canvas._occupied_display_tiles["0,0"] = true
	check(bool(canvas._sparse_visible_draw_rows(view, false)["indexed"]),
		"ordinary committed sparse traversal unchanged")
	print("T136_UNION_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
