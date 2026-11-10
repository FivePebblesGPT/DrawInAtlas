extends SceneTree
## T-091: one floating tab group, transactional rejection and legacy migration.
const LAYOUT: Script = preload("res://addons/drawing/dock_layout.gd")
const DRAG: Script = preload("res://addons/drawing/dock_drag.gd")
const PERSIST: Script = preload("res://addons/drawing/dock_persistence.gd")
const HOST: Script = preload("res://addons/drawing/floating_host.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T091_MODEL_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: DrawingDockLayout = LAYOUT.new()
	var drag: DrawingDockDrag = DRAG.new(layout)
	check(layout.create_container("right"), "dock registered")
	for id: String in ["colors", "swatches", "layers", "history", "effects"]:
		check(layout.register_panel(id) and layout.attach_panel(id, "right", id), "panel " + id)
	check(layout.merge_groups("swatches", "colors", 1), "tab group attached")
	check(layout.select_panel("swatches"), "secondary active panel")
	check(layout.create_container("float-1", DrawingDockLayout.FLOATING), "floating host registered")
	check(layout.create_container("float-2", DrawingDockLayout.FLOATING), "second floating host")
	check(layout.move_group("colors", "float-1", 0), "float two-tab group")
	check(layout.move_group("history", "float-2", 0), "float other group")
	var before: Dictionary = layout.snapshot()
	check(not layout.move_group("layers", "float-1", 1), "second group rejected by model")
	check(layout.snapshot() == before, "rejected move cannot lose a group")
	check(not layout.split_panel("swatches", "split-extra", "float-1", 1), "floating in-place split rejected")
	check(layout.snapshot() == before, "rejected split is atomic")
	check(drag.begin_group("layers"), "begin group transfer")
	check(not drag.preview({"kind": DrawingDockDrag.GROUP_SLOT, "container": "float-1", "index": 1}), "invalid preview rejected")
	check(not drag.commit() and layout.snapshot() == before, "invalid commit exact rollback")
	check(drag.begin_group("layers"), "begin explicit merge")
	check(drag.preview({"kind": DrawingDockDrag.MERGE_GROUP, "group": "colors", "index": 2}), "single-host merge preview")
	check(layout.snapshot() == before, "merge preview does not mutate")
	check(drag.commit(), "merged group into floating tabs")
	check(layout.container_info("float-1")["groups"].size() == 1, "one group after merge")
	check(layout.group_info("colors")["panels"] == ["colors", "swatches", "layers"], "stable panel order across merge")
	check(layout.group_info("layers").is_empty(), "source group retired")
	check(layout.rail_icons("float-1").size() == 3 and not layout.rail_icons("float-1")[2]["separator_before"], "no internal group delimiter")
	check(layout.restore(layout.snapshot()), "new snapshot validates")
	var stacked: Dictionary = layout.snapshot()
	for container: Dictionary in stacked["containers"]:
		if container["id"] == "float-1":
			container["groups"].append({"id": "obsolete-stack", "panels": ["effects"], "active": "effects", "collapsed": true})
		else:
			for group: Dictionary in container["groups"]:
				group["panels"].erase("effects")
			container["groups"] = container["groups"].filter(func(group: Dictionary) -> bool: return not group["panels"].is_empty())
	check(not layout.restore(stacked), "raw legacy multi-group snapshot no longer accepted")
	check(layout.container_info("float-1")["groups"].size() == 1, "invalid restore leaves layout unchanged")
	var legacy: Dictionary = {"schema": 1, "layout": stacked, "dock_width": 347,
		"dock_scroll": 37, "hosts": [
			{"id": "float-1", "visible": false, "rect": [120.0, 90.0, 350.0, 280.0], "client": [1200.0, 800.0]},
			{"id": "float-2", "visible": true, "rect": [300.0, 120.0, 300.0, 300.0], "client": [1200.0, 800.0]}]}
	var migrated: Dictionary = DrawingDockPersistence.recover(legacy, layout)
	check(not migrated.is_empty() and migrated.get("recovered", false), "legacy stack migrated")
	if not migrated.is_empty():
		var witness: DrawingDockLayout = LAYOUT.new()
		witness.create_container("right")
		for id: String in ["colors", "swatches", "layers", "history", "effects"]:
			witness.register_panel(id)
		check(witness.restore(migrated["layout"]), "migrated layout validates")
		check(witness.owner_of("effects") != "right" and witness.owner_of("effects") != "float-1", "legacy extra group gains its own host")
		check(witness.group_of("effects") == "obsolete-stack", "group ID preserved")
		check(witness.group_info("colors")["panels"] == ["colors", "swatches", "layers"], "original tabs preserved")
		check(witness.container_info("float-1")["groups"].size() == 1, "first host owns one group")
		check(migrated["hosts"].size() == 3, "each floating group has geometry")
		check(migrated["hosts"].any(func(entry: Dictionary) -> bool:
			return entry["id"] == witness.owner_of("effects") and not entry["visible"]), "migrated host inherits hidden state")
		check(migrated["dock_width"] == 347 and migrated["dock_scroll"] == 37, "width and scroll retained")
		check(not DrawingDockPersistence.recover({"schema": 8}, layout).size(), "unsupported preferences rejected")
		var corrupt: Dictionary = legacy.duplicate(true)
		corrupt["layout"]["containers"][-1]["groups"].append(corrupt["layout"]["containers"][-1]["groups"][0].duplicate(true))
		check(DrawingDockPersistence.recover(corrupt, layout).is_empty(), "duplicate group rejects corrupt settings")
		var translated: Rect2 = DrawingDockPersistence.restore_rect(migrated["hosts"][0], Vector2(600, 400))
		check(translated.size.x > 0.0 and translated.size.y > 0.0, "geometry remains usable across resolution")
	# Dragged edge must stop at the client border without moving its opposite
	# anchor. Clamping the whole oversized Rect2 would silently shift that edge.
	var client: Control = Control.new()
	client.size = Vector2(1280, 800)
	root.add_child(client)
	var host: DrawingFloatingHost = HOST.new()
	client.add_child(host)
	var frame: Rect2 = Rect2(290, 175, 325, 270)
	var boundaries: Array[Dictionary] = [
		{"name": "left", "sides": Vector4i(1, 0, 0, 0), "delta": Vector2(-700, 0),
			"anchor": Vector2(615, 175), "moving": Vector2(5, 445)},
		{"name": "right", "sides": Vector4i(0, 0, 1, 0), "delta": Vector2(2000, 0),
			"anchor": Vector2(290, 175), "moving": Vector2(1275, 445)},
		{"name": "top", "sides": Vector4i(0, 1, 0, 0), "delta": Vector2(0, -700),
			"anchor": Vector2(290, 445), "moving": Vector2(615, 5)},
		{"name": "bottom", "sides": Vector4i(0, 0, 0, 1), "delta": Vector2(0, 2000),
			"anchor": Vector2(290, 175), "moving": Vector2(615, 795)},
		{"name": "top-left", "sides": Vector4i(1, 1, 0, 0), "delta": Vector2(-700, -700),
			"anchor": Vector2(615, 445), "moving": Vector2(5, 5)},
		{"name": "bottom-right", "sides": Vector4i(0, 0, 1, 1), "delta": Vector2(2000, 2000),
			"anchor": Vector2(290, 175), "moving": Vector2(1275, 795)}]
	for boundary: Dictionary in boundaries:
		host.set_host_rect(frame)
		host._frame_start = Rect2(host.position, host.size)
		host._resize_sides = boundary["sides"]
		host._resize_from_pointer(boundary["delta"])
		var actual: Rect2 = Rect2(host.position, host.size)
		var anchor: Vector2 = boundary["anchor"]
		var moving: Vector2 = boundary["moving"]
		var horizontal_anchor: float = actual.end.x if host._resize_sides.x else actual.position.x
		var vertical_anchor: float = actual.end.y if host._resize_sides.y else actual.position.y
		var horizontal_moving: float = actual.position.x if host._resize_sides.x else actual.end.x
		var vertical_moving: float = actual.position.y if host._resize_sides.y else actual.end.y
		check(is_equal_approx(horizontal_anchor, anchor.x) and is_equal_approx(vertical_anchor, anchor.y),
			"boundary resize preserves fixed anchors: " + boundary["name"])
		check(is_equal_approx(horizontal_moving, moving.x) and is_equal_approx(vertical_moving, moving.y),
			"boundary resize clamps only dragged edges: " + boundary["name"])
	host.queue_free()
	client.queue_free()
	print("T091_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T091_MODEL_PASSED")
	quit(1 if failures else 0)
