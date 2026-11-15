extends SceneTree
## A complete detached index may schedule a retainable cold preview over frames.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T137_COLD_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var doc: DrawingDocument = DrawingDocument.new("t137-scheduler", 256)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	canvas.document = doc
	canvas.layer_id = layer
	var draft: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
	canvas.session = draft
	var window: Rect2i = Rect2i(-12, -8, 24, 16)
	var focus: Vector2 = Vector2.ZERO
	for x: int in range(-5, 5):
		canvas._occupied_display_tiles["%d,0" % x] = true
	var stamps: Dictionary = {"-9,3": 4, "3,2": 6}
	var rows: Dictionary = canvas._sparse_visible_draw_rows(window, true, stamps, true)
	check(bool(rows["indexed"]) and int(rows["count"]) == 12,
		"complete detached preview supplies committed and preview-only rows")
	var selected: Dictionary = canvas._cold_population_targets(window, focus, draft, stamps, rows)
	check(selected.size() == 4,
		"complete retainable preview gets four bounded cold tiles")
	check(selected.has("-1,0") and selected.has("0,0"),
		"focal-near committed tiles retain cold priority")
	check(not selected.has("-9,3"),
		"distant preview tile waits behind near tiles")
	var preview_focus: Vector2 = Vector2(3, 2)
	check(canvas._cold_population_targets(window, preview_focus,
		draft, stamps, rows).has("3,2"),
		"closest preview-only tile receives cold priority")
	canvas._display_tiles["3,2"] = {"dirty": false, "preview_stamp": 6,
		"preview_owner": draft}
	check(not canvas._cold_population_targets(window, preview_focus,
		draft, stamps, rows).has("3,2"),
		"unchanged draft texture is a cache hit")
	canvas._display_tiles["3,2"]["preview_owner"] = null
	check(canvas._cold_population_targets(window, preview_focus,
		draft, stamps, rows).has("3,2"),
		"different preview owner requires refresh")
	canvas._display_tiles["3,2"]["preview_owner"] = draft
	canvas._display_tiles["3,2"]["preview_stamp"] = 5
	check(canvas._cold_population_targets(window, preview_focus,
		draft, stamps, rows).has("3,2"),
		"changed draft generation requires refresh")
	canvas._display_tiles.erase("3,2")
	check(canvas._cold_population_targets(window, focus, draft, stamps, {}).is_empty(),
		"incomplete preview index must use conservative traversal")
	canvas._occupancy_unknown = true
	check(canvas._cold_population_targets(window, focus, draft, stamps, rows).is_empty(),
		"unknown committed occupancy disables preview cold scheduling")
	canvas._occupancy_unknown = false
	check(canvas._cold_population_targets(window, focus, draft, {"junk": 9},
		canvas._sparse_visible_draw_rows(window, true, {"junk": 9}, true)).is_empty(),
		"malformed preview key cannot authorize scheduling")
	check(canvas._cold_population_targets(window, focus, draft, {"00,0": 9},
		canvas._sparse_visible_draw_rows(window, true, {"00,0": 9}, true)).is_empty(),
		"noncanonical preview alias must fall back")
	check(canvas._cold_population_targets(window, focus, draft, {"1,1": 0},
		canvas._sparse_visible_draw_rows(window, true, {"1,1": 0}, true)).is_empty(),
		"invalid generation must fall back")
	for x: int in range(10, 150):
		canvas._occupied_display_tiles["%d,0" % x] = true
	var over: Dictionary = canvas._sparse_visible_draw_rows(Rect2i(-12, -8, 200, 16),
		true, stamps, true)
	check(canvas._cold_population_targets(Rect2i(-12, -8, 200, 16), focus,
		draft, stamps, over).is_empty(), "over-144 tile preview retains full traversal")
	check(canvas._cold_population_targets(window, focus).is_empty(),
		"live preview without supplied complete index remains conservative")
	draft.cancel()
	print("T137_COLD_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
