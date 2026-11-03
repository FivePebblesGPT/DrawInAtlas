extends SceneTree
## T-080 UI-independent transaction tests; same planner will serve floating hosts.
const LAYOUT: Script = preload("res://addons/drawing/dock_layout.gd")
const DRAG: Script = preload("res://addons/drawing/dock_drag.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T080_MODEL_FAILED: " + detail)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: DrawingDockLayout = LAYOUT.new() as DrawingDockLayout
	for name: String in ["colors", "swatches", "gradients", "layers", "history"]:
		check(layout.register_panel(name), "register " + name)
	check(layout.create_container("right"), "create dock")
	check(layout.attach_panel("colors", "right", "color"), "attach Colors")
	check(layout.attach_panel("layers", "right", "layers"), "attach Layers")
	check(layout.attach_panel("history", "right", "history"), "attach History")
	check(layout.attach_panel("swatches", "right", "swatches"), "attach Swatches")
	check(layout.attach_panel("gradients", "right", "gradients"), "attach Gradients")
	check(layout.merge_groups("swatches", "color", 1), "join swatches")
	check(layout.merge_groups("gradients", "color", 2), "join gradients")
	var drag: DrawingDockDrag = DRAG.new(layout) as DrawingDockDrag
	var original: Dictionary = layout.snapshot()
	check(drag.begin_panel("gradients"), "start panel drag")
	check(drag.preview({"kind": "tab_slot", "group": "color", "index": 0}), "valid front slot")
	check(layout.snapshot() == original, "preview does not mutate model")
	drag.cancel()
	check(layout.snapshot() == original, "Esc cancellation is bit-exact")
	check(drag.begin_panel("gradients"), "start reorder")
	check(drag.preview({"kind": "tab_slot", "group": "color", "index": 0}), "front preview")
	check(drag.commit(), "commit front reorder")
	check(layout.group_info("color")["panels"] == ["gradients", "colors", "swatches"], "front order")
	check(drag.begin_panel("gradients"), "start end reorder")
	check(drag.preview({"kind": "tab_slot", "group": "color", "index": 3}), "end preview")
	check(drag.commit(), "commit end reorder")
	check(layout.group_info("color")["panels"] == ["colors", "swatches", "gradients"], "end order")
	check(drag.begin_panel("gradients"), "start split")
	check(drag.preview({"kind": "group_slot", "container": "right", "index": 0}), "top group insertion")
	check(drag.commit(), "commit split")
	check(layout.group_of("gradients") == "split-1", "new unique group id")
	check(layout.container_info("right")["groups"][0]["id"] == "split-1", "top group location")
	check(drag.begin_panel("gradients"), "start remerge")
	check(drag.preview({"kind": "tab_slot", "group": "color", "index": 1}), "merge target")
	check(drag.commit(), "remerge tab")
	check(layout.group_info("split-1").is_empty(), "empty split group removed")
	check(layout.group_info("color")["panels"] == ["colors", "gradients", "swatches"], "merge insertion precise")
	check(layout.rail_icons("right")[1]["panel"] == "gradients" and not layout.rail_icons("right")[1]["separator_before"], "rail mirrors order")
	var before: Dictionary = layout.snapshot()
	check(drag.begin_group("color"), "start group move")
	check(drag.preview({"kind": "group_slot", "container": "right", "index": 3}), "bottom group target")
	check(layout.snapshot() == before, "group preview leaves original")
	check(drag.commit(), "commit group move")
	check(layout.container_info("right")["groups"][2]["id"] == "color", "group at end")
	check(layout.set_group_collapsed("color", true), "collapse group")
	check(layout.select_panel("swatches"), "select tab")
	before = layout.snapshot()
	check(drag.begin_group("color"), "begin failed group attempt")
	check(not drag.preview({"kind": "merge_group", "group": "unknown", "index": 0}), "invalid merge rejected")
	check(not drag.commit(), "invalid attempt cannot commit")
	check(layout.snapshot() == before, "invalid target exact rollback")
	check(drag.begin_panel("swatches"), "begin failed panel attempt")
	check(not drag.preview({"kind": "tab_slot", "group": "history", "index": 99}), "bad slot rejected")
	drag.cancel()
	check(layout.snapshot() == before, "failed and cancel keep all fields")
	check(drag.begin_group("color"), "start full group merge")
	check(drag.preview({"kind": "merge_group", "group": "layers", "index": 1}), "full group merge valid")
	check(drag.commit(), "whole group merges")
	check(layout.group_info("layers")["panels"] == ["layers", "colors", "gradients", "swatches"], "whole-group relative order retained")
	var all_icons: Array[Dictionary] = layout.rail_icons("right")
	check(all_icons.size() == 5 and all_icons[1]["panel"] == "colors" and not all_icons[1]["separator_before"], "all panels unique and rail joined")
	check(drag.begin_panel("history"), "begin concurrent mutation test")
	check(drag.preview({"kind": "group_slot", "container": "right", "index": 0}), "candidate accepted")
	check(layout.select_panel("swatches"), "external model change")
	before = layout.snapshot()
	check(not drag.commit(), "stale drag refuses to overwrite")
	check(layout.snapshot() == before, "stale drag leaves newer model intact")
	print("T080_DOCK_DRAG_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T080_DOCK_DRAG_MODEL_PASSED")
	quit(1 if failures else 0)
