extends SceneTree
## Focal-retention selection for an over-budget, complete detached preview.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T138_FOCAL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	var document: DrawingDocument = DrawingDocument.new("t138-focal", 128)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	canvas.document = document
	canvas.layer_id = layer
	var window: Rect2i = Rect2i(-120, -20, 240, 40)
	var focus: Vector2 = Vector2(95.0, 0.0)
	for x: int in range(-90, 90):
		canvas._occupied_display_tiles["%d,0" % x] = true
	check(canvas._focal_retention_plan(window, focus).size() == canvas.MAX_DISPLAY_TILES,
		"committed over-budget view retains a bounded focal plan")
	var draft: DrawingEditSession = document.begin_edit(layer, document.revision).value as DrawingEditSession
	canvas.session = draft
	var stamps: Dictionary = {"95,0": 3, "-100,-2": 4}
	check(canvas._focal_retention_plan(window, focus).is_empty(),
		"unknown active preview keeps conservative retention")
	var planned: Dictionary = canvas._focal_retention_plan(window, focus, stamps, true)
	check(planned.size() == canvas.MAX_DISPLAY_TILES,
		"complete over-budget preview receives exactly the bounded retention slots")
	check(planned.has("95,0"), "nearest preview-only tile is retained")
	check(planned.has("89,0") and planned.has("88,0"),
		"near committed tiles share focus with preview-only tiles")
	check(not planned.has("-100,-2") and not planned.has("-90,0"),
		"distant preview and committed tiles remain transient")
	var repeated: Dictionary = canvas._focal_retention_plan(window, focus, stamps, true)
	check(repeated == planned, "fixed focus and index have deterministic selection")
	check(canvas._focal_retention_plan(window, Vector2(-100.0, -2.0), stamps, true).has("-100,-2"),
		"moving focus selects a distant preview-only tile")
	check(canvas._focal_retention_plan(window, focus, stamps, false).is_empty(),
		"incomplete preview cannot authorize focal plan")
	for malformed: Dictionary in [{"junk": 3}, {"00,0": 3}, {"1,0": 0}, {"1,0": -1}, {"1,0": "3"}, {"1,0,0": 3}]:
		check(canvas._focal_retention_plan(window, focus, malformed, true).is_empty(),
			"malformed or noncanonical preview metadata disables preselection: %s" % malformed)
	canvas._occupancy_unknown = true
	check(canvas._focal_retention_plan(window, focus, stamps, true).is_empty(),
		"unknown committed occupancy disables preview plan")
	canvas._occupancy_unknown = false
	var huge: Dictionary = {}
	for x: int in range(4100):
		huge["%d,3" % x] = 1
	check(canvas._focal_retention_plan(window, focus, huge, true).is_empty(),
		"over-limit preview metadata falls back without unbounded sorting")
	canvas.session = null
	canvas._move_preview = draft
	check(canvas._focal_retention_plan(window, focus, stamps, true).has("95,0"),
		"complete detached Move preview uses the same bounded focal plan")
	canvas._move_preview = null
	draft.cancel()
	check(canvas._focal_retention_plan(window, focus).size() == canvas.MAX_DISPLAY_TILES,
		"committed focal plan remains unchanged after cancellation")
	print("T138_FOCAL_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
