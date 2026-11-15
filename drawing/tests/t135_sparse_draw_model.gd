extends SceneTree
## Deterministic source-tile enumeration model. No graphics/device latency claim.

var checks: int = 0
var failures: int = 0


func check(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("T135_SPARSE_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var window: Rect2i = Rect2i(-500, -300, 1000, 600)
	for key: String in ["2,3", "-1,-1", "0,0", "-500,-300", "499,299", "500,299", "0,300"]:
		canvas._occupied_display_tiles[key] = true
	var sparse: Dictionary = canvas._sparse_visible_draw_rows(window, false)
	check(bool(sparse.get("indexed", false)), "sparse committed view uses occupancy index")
	check(int(sparse.get("count", -1)) == 5, "only five signed occupied display tiles intersect window")
	check((sparse["ys"] as Array) == [-300, -1, 0, 3, 299], "rows are visited in original signed raster order")
	check((sparse["rows"] as Dictionary).get(-300, []) == [-500], "negative corner is included")
	check((sparse["rows"] as Dictionary).get(299, []) == [499], "positive inclusive corner is included")
	check(not (sparse["rows"] as Dictionary).has(300), "exclusive positive Y edge is omitted")
	check((sparse["rows"] as Dictionary).get(0, []) == [0], "positive/negative signed coordinates do not alias")
	canvas._occupied_display_tiles["-10,-20"] = true
	canvas._occupied_display_tiles["10,-20"] = true
	canvas._occupied_display_tiles["-2,-20"] = true
	sparse = canvas._sparse_visible_draw_rows(window, false)
	check((sparse["rows"] as Dictionary).get(-20, []) == [-10, -2, 10],
		"columns remain sorted in the original left-to-right draw order")
	check(not bool(canvas._sparse_visible_draw_rows(window, true)["indexed"]),
		"any detached preview keeps the conservative full draw")
	canvas._occupancy_unknown = true
	check(not bool(canvas._sparse_visible_draw_rows(window, false)["indexed"]),
		"unknown or incomplete occupancy cannot cull content")
	canvas._occupancy_unknown = false
	check(not bool(canvas._sparse_visible_draw_rows(Rect2i(-1, -1, 2, 2), false)["indexed"]),
		"small dense region keeps the ordinary row-major scan")
	canvas._occupied_display_tiles["broken"] = true
	check(not bool(canvas._sparse_visible_draw_rows(window, false)["indexed"]),
		"malformed index fails closed to full scan")
	canvas._occupied_display_tiles.erase("broken")
	canvas._occupied_display_tiles["oops,1"] = true
	check(not bool(canvas._sparse_visible_draw_rows(window, false)["indexed"]),
		"nonnumeric tile coordinates also fail closed to a full scan")
	canvas._occupied_display_tiles.erase("oops,1")
	canvas._occupied_display_tiles["01,0"] = true
	check(not bool(canvas._sparse_visible_draw_rows(window, false)["indexed"]),
		"noncanonical duplicate-prone coordinates cannot authorize sparse enumeration")
	canvas._occupied_display_tiles.clear()
	sparse = canvas._sparse_visible_draw_rows(window, false)
	check(bool(sparse["indexed"]) and int(sparse["count"]) == 0 and
		(sparse["ys"] as Array).is_empty(),
		"fully empty sparse documents do not traverse the full viewport")
	canvas._occupied_display_tiles["0,0"] = true
	check(not bool(canvas._sparse_visible_draw_rows(Rect2i(0, 0, 1, 1), false)["indexed"]),
		"one occupied display cell does not allocate a sparse plan")
	print("T135_SPARSE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
