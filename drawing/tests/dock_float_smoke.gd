extends SceneTree
## T-081: floating-host ownership checks, independent of any native window.
const LAYOUT: Script = preload("res://addons/drawing/dock_layout.gd")
const DRAG: Script = preload("res://addons/drawing/dock_drag.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T081_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: DrawingDockLayout = LAYOUT.new() as DrawingDockLayout
	var drag: DrawingDockDrag = DRAG.new(layout) as DrawingDockDrag
	check(layout.create_container("right"), "create attached dock")
	for panel_id: String in ["colors", "swatches", "gradients", "layers", "history", "effects"]:
		check(layout.register_panel(panel_id), "register " + panel_id)
		check(layout.attach_panel(panel_id, "right", panel_id), "attach " + panel_id)
	check(layout.merge_groups("swatches", "colors", 1), "group swatches")
	check(layout.merge_groups("gradients", "colors", 2), "group gradients")
	check(layout.select_panel("swatches"), "preserve active color tab")
	check(layout.set_group_collapsed("colors", true), "preserve collapsed state")
	check(layout.create_container("float-1", DrawingDockLayout.FLOATING), "floating host created")
	check(layout.container_info("float-1")["kind"] == DrawingDockLayout.FLOATING, "host type")
	var snapshot: Dictionary = layout.snapshot()
	check(drag.begin_group("colors"), "begin transfer")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-1", "index": 0}), "preview detach")
	check(layout.snapshot() == snapshot, "preview does not change icon ownership")
	drag.cancel()
	check(layout.snapshot() == snapshot, "cancellation leaves ownership exact")
	check(drag.begin_group("colors"), "begin committed transfer")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-1", "index": 0}), "validate detachment")
	check(drag.commit(), "commit float")
	check(layout.owner_of("colors") == "float-1" and layout.owner_of("swatches") == "float-1" and
		layout.owner_of("gradients") == "float-1", "all members transfer together")
	check(layout.group_info("colors")["active"] == "swatches" and layout.group_info("colors")["collapsed"],
		"selection and collapse survive detachment")
	check(layout.rail_icons("right").size() == 3, "only attached icons remain in right dock")
	check(layout.rail_icons("float-1").size() == 3 and not layout.rail_icons("float-1")[1]["separator_before"],
		"float owns a grouped icon per member")
	check(not layout.remove_empty_container("float-1"), "cannot destroy nonempty host")
	var single_group_snapshot: Dictionary = layout.snapshot()
	check(not layout.move_group("layers", "float-1", 1), "cannot stack a second floating group")
	check(layout.snapshot() == single_group_snapshot, "rejected stack is fully atomic")
	check(layout.container_info("float-1")["groups"].size() == 1, "one group per floating container")
	check(layout.rail_icons("float-1").size() == 3, "float has no second-group separator")
	check(layout.group_info("colors")["collapsed"], "collapsed state retained")
	check(layout.select_panel("gradients"), "select another floating tab")
	check(layout.group_info("colors")["active"] == "gradients", "floating active panel tracked in model")
	snapshot = layout.snapshot()
	check(drag.begin_panel("gradients"), "begin floating reorder")
	check(drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "colors", "index": 0}), "valid float insertion")
	check(layout.snapshot() == snapshot, "reorder preview exact no-op")
	check(drag.commit(), "commit floating reorder")
	check(layout.group_info("colors")["panels"] == ["gradients", "colors", "swatches"], "floating order updated")
	check(layout.rail_icons("float-1")[0]["panel"] == "gradients", "host order reflected")
	snapshot = layout.snapshot()
	check(drag.begin_panel("swatches"), "begin invalid destination")
	check(not drag.preview({"kind": DrawingDockDrag.TAB_SLOT, "group": "ghost", "index": 0}), "invalid float target rejected")
	check(not drag.commit(), "invalid commit rejected")
	check(layout.snapshot() == snapshot, "invalid destination exact no-op")
	check(drag.begin_group("colors"), "begin stale floating reorder")
	check(drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "right", "index": 1}), "preview redock")
	check(layout.select_panel("colors"), "intervening panel selection")
	snapshot = layout.snapshot()
	check(not drag.commit() and layout.snapshot() == snapshot, "stale transaction cannot overwrite state")
	check(layout.create_container("float-empty", DrawingDockLayout.FLOATING), "create candidate empty float")
	check(layout.remove_empty_container("float-empty"), "remove abandoned empty float")
	check(layout.container_info("float-empty").is_empty(), "removed container not in registry")
	check(not layout.remove_empty_container("right"), "live dock cannot disappear while populated")
	check(layout.create_container("float-2", DrawingDockLayout.FLOATING), "second independent host")
	check(layout.move_group("history", "float-2", 0), "transfer history to other float")
	check(layout.owner_of("history") == "float-2" and layout.owner_of("effects") == "right", "independent ownership remains unique")
	check(layout.snapshot()["containers"].size() == 3, "exact live container count")
	check(layout.restore(layout.snapshot()), "floating state round trip")
	var ids: Dictionary = {}
	for info: Dictionary in layout.snapshot()["containers"]:
		for group: Dictionary in info["groups"]:
			for panel_id: String in group["panels"]:
				ids[panel_id] = ids.get(panel_id, 0) + 1
	check(ids.size() == 6 and ids.values().all(func(count: int) -> bool: return count == 1), "each panel exists in exactly one container")
	check(layout.create_container("empty-dock", DrawingDockLayout.DOCK), "create additional empty dock")
	check(not layout.remove_empty_container("empty-dock"), "empty required dock cannot be discarded as float cleanup")
	print("T081_FLOAT_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T081_FLOAT_MODEL_PASSED")
	quit(1 if failures else 0)
