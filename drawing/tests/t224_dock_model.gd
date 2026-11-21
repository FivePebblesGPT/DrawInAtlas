extends SceneTree
## T-224 planner: precise icon membership and bit-exact transactional rollback.

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T224_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: DrawingDockLayout = DrawingDockLayout.new()
	for id: String in ["colors", "swatches", "layers", "history", "brushes"]:
		check(layout.register_panel(id), "register " + id)
	check(layout.create_container("right"), "dock container")
	check(layout.create_container("float-1", DrawingDockLayout.FLOATING), "float container")
	check(layout.attach_panel("colors", "right", "colors"), "colors singleton")
	check(layout.attach_panel("layers", "right", "layers"), "layers singleton")
	check(layout.attach_panel("history", "right", "history"), "history singleton")
	check(layout.attach_panel("swatches", "float-1", "swatches"), "floating singleton")
	check(layout.attach_panel("brushes", "right", "brushes"), "brush singleton")
	check(layout.set_group_collapsed("colors", true), "persist collapsed source")
	check(layout.select_panel("history"), "history active")
	var drag: DrawingDockDrag = DrawingDockDrag.new(layout)
	var initial: Dictionary = layout.snapshot()
	check(drag.begin_panel("colors"), "begin icon-only transaction")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "layers", "index": 0}), "merge at first exact slot")
	check(layout.snapshot() == initial, "preview untouched all state including float and collapse")
	drag.cancel()
	check(layout.snapshot() == initial, "Escape exact rollback")
	check(drag.begin_panel("colors"), "restart merge")
	check(not drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "layers", "index": 99}), "reject invalid tab index")
	check(not drag.commit() and layout.snapshot() == initial, "invalid drop exact rollback")
	check(drag.begin_panel("colors"), "restart for valid merge")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "layers", "index": 1}) and drag.commit(), "commit explicit icon proximity")
	check(layout.group_of("colors") == "layers" and layout.group_info("colors").is_empty(), "remove empty source group")
	check(layout.group_info("layers")["panels"] == ["layers", "colors"], "insert index preserved")
	check(drag.begin_panel("colors"), "begin same-group reorder")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "layers", "index": 0}) and drag.commit(), "reorder to front")
	check(layout.group_info("layers")["panels"] == ["colors", "layers"], "no duplicate on same-group reorder")
	check(drag.begin_panel("colors"), "begin singleton split")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 0}), "preview group gap")
	var before_split: Dictionary = layout.snapshot()
	check(drag.commit() and layout.group_of("colors") == "split-1", "split into numbered group")
	check(layout.group_info("split-1")["panels"] == ["colors"] and layout.group_info("layers")["panels"] == ["layers"], "only dragged icon moves")
	check(drag.begin_panel("colors"), "begin floating transfer")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "swatches", "index": 0}), "only append to existing host group")
	check(drag.commit(), "float transfer commit")
	check(layout.container_info("float-1")["groups"].size() == 1 and
		layout.group_info("swatches")["panels"] == ["colors", "swatches"], "floating host remains single-group")
	var prior: Dictionary = layout.snapshot()
	check(drag.begin_panel("colors"), "attempt second floating group")
	check(not drag.preview({"kind": DrawingDockDrag.GROUP_SLOT,
		"container": "float-1", "index": 1}), "reject second group during preview")
	check(not drag.commit() and layout.snapshot() == prior, "reject invalid second group in float atomically")
	check(drag.begin_group("swatches"), "begin marker whole-group gesture")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 0}) and drag.commit(),
		"whole-group marker restores all members together")
	check(layout.group_info("swatches")["panels"] == ["colors", "swatches"], "group marker is not single icon")
	check(layout.snapshot()["panels"].size() == 5, "panel identity count unchanged")
	check(drag.begin_panel("history") and drag.preview({"kind": DrawingDockDrag.TAB_SLOT,
		"group": "layers", "index": 1}), "start concurrent source transaction")
	check(layout.select_panel("colors"), "external state mutation")
	prior = layout.snapshot()
	check(not drag.commit() and layout.snapshot() == prior, "stale target refuses overwrite")
	var restored: DrawingDockLayout = DrawingDockLayout.new()
	for id: String in ["colors", "swatches", "layers", "history", "brushes"]:
		check(restored.register_panel(id), "restore panel " + id)
	check(restored.restore(prior) and restored.snapshot() == prior, "persisted layout restores bit-exact")
	print("T224_DOCK_MODEL: %d checks; %d failed" % [checks, failures])
	quit(1 if failures else 0)
