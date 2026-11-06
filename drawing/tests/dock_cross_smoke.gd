extends SceneTree
## T-082 headless cross-container transaction and ownership witness.
const LAYOUT: Script = preload("res://addons/drawing/dock_layout.gd")
const DRAG: Script = preload("res://addons/drawing/dock_drag.gd")
var assertions: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("T082_MODEL_FAILED: " + label)

func perform(planner: DrawingDockDrag, kind: String, id: String, target: Dictionary) -> bool:
	var started: bool = planner.begin_panel(id) if kind == DrawingDockDrag.PANEL else planner.begin_group(id)
	if not started or not planner.preview(target):
		planner.cancel()
		return false
	return planner.commit()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: DrawingDockLayout = LAYOUT.new() as DrawingDockLayout
	var drag: DrawingDockDrag = DRAG.new(layout) as DrawingDockDrag
	check(layout.create_container("right"), "dock initialized")
	for id: String in ["colors", "layers", "history", "swatches", "gradients", "effects"]:
		check(layout.register_panel(id) and layout.attach_panel(id, "right", id), "panel registered " + id)
	check(layout.merge_groups("layers", "colors", 1), "colors/layers grouped")
	check(layout.create_container("float-1", DrawingDockLayout.FLOATING), "first host")
	check(layout.create_container("float-2", DrawingDockLayout.FLOATING), "second host")
	check(layout.select_panel("layers"), "active tab selection before transfer")
	check(layout.set_group_collapsed("colors", true), "collapse state before transfer")
	var original: Dictionary = layout.snapshot()
	check(drag.begin_group("colors"), "begin group detach")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-1", "index": 0}), "valid whole group detach preview")
	check(layout.snapshot() == original, "preview leaves ownership and state exact")
	drag.cancel()
	check(layout.snapshot() == original, "cancel returns exact pre-drag state")
	check(perform(drag, DrawingDockDrag.GROUP, "colors", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-1", "index": 0}), "commit atomic detach")
	check(layout.owner_of("layers") == "float-1" and layout.owner_of("colors") == "float-1", "both icons detach")
	check(layout.rail_icons("right").map(func(e: Dictionary) -> String: return e["panel"]) == ["history", "swatches", "gradients", "effects"], "only detached icons disappear")
	check(not layout.rail_icons("float-1")[1]["separator_before"], "joined group has no internal separator")
	check(layout.group_info("colors")["active"] == "layers" and layout.group_info("colors")["collapsed"], "active and collapsed state survive transfer")
	check(perform(drag, DrawingDockDrag.PANEL, "layers", {"kind": DrawingDockDrag.TAB_SLOT, "group": "colors", "index": 0}), "reorder tabs while floated")
	check(layout.group_info("colors")["panels"] == ["layers", "colors"], "floating relative tab order")
	check(perform(drag, DrawingDockDrag.GROUP, "colors", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 1}), "group insertion between existing groups")
	var rail: Array[Dictionary] = layout.rail_icons("right")
	check(rail.map(func(e: Dictionary) -> String: return e["panel"]) == ["history", "layers", "colors", "swatches", "gradients", "effects"], "exact group slot rail order")
	check(rail[1]["separator_before"] and not rail[2]["separator_before"] and rail[3]["separator_before"], "separators exactly at group boundaries")
	check(layout.group_info("colors")["active"] == "layers" and layout.group_info("colors")["collapsed"], "redock keeps group state")
	check(layout.remove_empty_container("float-1"), "empty floating host removed")
	check(not layout.remove_empty_container("right"), "required dock never deleted")
	check(layout.move_group("history", "float-2", 0), "history creates other host")
	var snapshot: Dictionary = layout.snapshot()
	check(drag.begin_panel("colors"), "begin single-panel transfer")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "history", "index": 1}), "cross-container tab merge preview")
	check(layout.snapshot() == snapshot, "single-panel preview does not relocate view")
	check(drag.commit(), "cross-container tab merge commit")
	check(layout.group_info("history")["panels"] == ["history", "colors"], "one tab merged without moving full source")
	check(layout.owner_of("layers") == "right" and layout.owner_of("colors") == "float-2", "source group still in dock")
	check(layout.rail_icons("float-2").size() == 2 and not layout.rail_icons("float-2")[1]["separator_before"], "single-panel merge icons adjacent")
	check(perform(drag, DrawingDockDrag.PANEL, "colors", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 2}), "single-panel split target in dock")
	check(layout.group_of("colors") != "history" and layout.owner_of("colors") == "right", "split creates new right group")
	check(layout.rail_icons("float-2").size() == 1, "float keeps its remaining tab")
	var split_group: String = layout.group_of("colors")
	check(perform(drag, DrawingDockDrag.GROUP, split_group, {"kind": DrawingDockDrag.MERGE_GROUP, "group": "swatches", "index": 0}), "group-merge across right groups")
	check(layout.group_info("swatches")["panels"] == ["colors", "swatches"], "merge insertion at specified tab index")
	check(layout.owner_of("swatches") == "right" and layout.owner_of("colors") == "right", "merge retains unique ownership")
	snapshot = layout.snapshot()
	check(drag.begin_group("swatches"), "begin invalid group destination")
	check(not drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "destroyed", "index": 0}), "destroyed destination rejected")
	check(not drag.commit() and snapshot == layout.snapshot(), "invalid target cannot replay older valid target")
	check(drag.begin_panel("colors"), "begin invalid tab destination")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "history", "index": 1}), "initial valid target")
	check(not drag.preview({}), "leaving targets invalidates previous preview")
	check(not drag.commit() and snapshot == layout.snapshot(), "invalid release doesn't apply last preview")
	check(drag.begin_group("swatches"), "begin invalid stacked-host transaction")
	check(not drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-2", "index": 1}), "second floating group rejected")
	check(not drag.commit(), "stacking cannot commit")
	check(drag.begin_group("swatches"), "begin stale transaction")
	check(drag.preview({"kind": DrawingDockDrag.MERGE_GROUP, "group": "history", "index": 1}), "preview explicit group merge")
	check(layout.set_group_collapsed("swatches", true), "intervening state mutation")
	snapshot = layout.snapshot()
	check(not drag.commit() and snapshot == layout.snapshot(), "stale transaction leaves intervening state exact")
	check(perform(drag, DrawingDockDrag.GROUP, "swatches", {"kind": DrawingDockDrag.MERGE_GROUP, "group": "history", "index": 1}), "merge group into existing floating tabs")
	check(layout.container_info("float-2")["groups"].size() == 1 and layout.group_info("swatches").is_empty(), "merge maintains one host group")
	check(layout.group_info("history")["panels"] == ["history", "colors", "swatches"], "merged panels retain identities and order")
	check(not layout.rail_icons("float-2")[1]["separator_before"], "one floating group has no separators")
	check(perform(drag, DrawingDockDrag.GROUP, "history", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 1}), "redock merged group")
	check(perform(drag, DrawingDockDrag.GROUP, "history", {"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-2", "index": 0}), "repeat detach to empty host")
	check(layout.restore(layout.snapshot()), "mixed floating/dock snapshot round-trip valid")
	var seen: Dictionary = {}
	for container: Dictionary in layout.snapshot()["containers"]:
		for group: Dictionary in container["groups"]:
			for id: String in group["panels"]:
				seen[id] = int(seen.get(id, 0)) + 1
	check(seen.size() == 6 and seen.values().all(func(n: int) -> bool: return n == 1), "no duplicate/lost panels after cross-host cycles")
	check(layout.snapshot()["containers"].size() == 2, "only populated dock and host remain")
	print("T082_CROSS_MODEL: %d checks; %d failed" % [assertions, failures])
	if failures == 0:
		print("T082_CROSS_MODEL_PASSED")
	quit(1 if failures else 0)
