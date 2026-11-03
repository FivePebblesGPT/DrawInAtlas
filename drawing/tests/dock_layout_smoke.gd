extends SceneTree
## T-078: pure dock ownership/group operations, snapshots and shell integration.

const LAYOUT_SCRIPT: Script = preload("res://addons/drawing/dock_layout.gd")
const WORKSPACE_SCRIPT: Script = preload("res://addons/drawing/workspace.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("DOCK MODEL FAILED: " + description)


func _run() -> void:
	var layout: DrawingDockLayout = LAYOUT_SCRIPT.new() as DrawingDockLayout
	_check(layout.register_panel("colors"), "register colors")
	_check(layout.register_panel("layers"), "register layers")
	_check(layout.register_panel("history"), "register history")
	_check(not layout.register_panel("colors"), "reject duplicate stable panel ID")
	_check(not layout.register_panel(""), "reject empty panel ID")
	_check(layout.create_container("right"), "create right dock")
	_check(layout.create_container("float-a", DrawingDockLayout.FLOATING), "create floating host")
	_check(not layout.create_container("right"), "reject duplicate host")
	_check(not layout.create_container("bad", "window"), "reject unsupported host kind")
	_check(layout.attach_panel("colors", "right", "color-group"), "attach Colors")
	_check(layout.attach_panel("layers", "right", "layer-group"), "attach Layers")
	_check(layout.attach_panel("history", "right", "history-group"), "attach History")
	_check(not layout.attach_panel("colors", "float-a", "other"), "prevent duplicated ownership")
	_check(layout.rail_icons("right").size() == 3, "three initial rail icons")
	_check(bool(layout.rail_icons("right")[1]["separator_before"]), "singleton groups separated")
	_check(layout.owner_of("colors") == "right", "attached owner query")
	_check(layout.merge_groups("layer-group", "color-group", 1), "merge Colors and Layers")
	_check(layout.rail_icons("right").size() == 3, "merge leaves same number of icons")
	_check(not bool(layout.rail_icons("right")[1]["separator_before"]), "merged tabs have no separator")
	_check(bool(layout.rail_icons("right")[2]["separator_before"]), "History still separated")
	_check(layout.group_info("color-group")["panels"] == ["colors", "layers"], "ordered merged tabs")
	_check(layout.group_of("layers") == "color-group", "single group owner")
	_check(layout.set_minimized("right", true), "minimize dock without detaching contents")
	_check(not layout.set_minimized("float-a", true), "floating host cannot minimize like dock")
	_check(layout.activate_from_rail("right", "layers"), "select Layers in group flyout")
	_check(layout.group_info("color-group")["active"] == "layers", "flyout selects requested tab")
	_check(layout.container_info("right")["flyout_group"] == "color-group", "shared flyout is group-scoped")
	_check(layout.activate_from_rail("right", "colors"), "same group switches tab")
	_check(layout.container_info("right")["flyout_group"] == "color-group", "same group reuses flyout")
	_check(layout.activate_from_rail("right", "colors"), "click same active icon closes flyout")
	_check(layout.container_info("right")["flyout_group"] == "", "flyout closes without hiding tabs")
	_check(layout.set_group_collapsed("history-group", true), "collapse History independently")
	_check(bool(layout.group_info("history-group")["collapsed"]), "History collapse remembered")
	_check(not bool(layout.group_info("color-group")["collapsed"]), "other group stays expanded")
	_check(layout.move_panel("layers", "color-group", 0), "reorder tabs within shared group")
	_check(layout.group_info("color-group")["panels"] == ["layers", "colors"], "tab order updated")
	_check(layout.split_panel("colors", "new-color", "right", 1), "split Colors into own group")
	_check(layout.group_of("colors") == "new-color", "new group owns split panel")
	_check(layout.move_group("new-color", "float-a", 0), "detach group to floating host")
	_check(layout.owner_of("colors") == "float-a", "panel moved to floating host")
	_check(layout.rail_icons("right").size() == 2, "detached panel icon removed from old rail")
	_check(layout.rail_icons("float-a").size() == 1, "floating tab remains available")
	_check(layout.move_group("new-color", "right", 0), "redock group at cursor insertion index")
	_check(layout.rail_icons("right")[0]["panel"] == "colors", "redocking honors target index")
	_check(layout.owner_of("colors") == "right", "panel owner restored to dock")
	_check(layout.merge_groups("new-color", "color-group", 1), "merge reordered group back into tabs")
	_check(layout.group_info("color-group")["panels"] == ["layers", "colors"], "member insertion order preserved")
	_check(layout.move_group("color-group", "float-a", 0), "detach multi-tab group")
	_check(layout.group_info("color-group")["panels"] == ["layers", "colors"], "whole group retains member order")
	_check(layout.move_group("color-group", "right", 1), "redock entire ordered tab group")
	_check(layout.group_info("color-group")["panels"] == ["layers", "colors"], "redock retains relative order")
	var prior: Dictionary = layout.snapshot()
	_check(not layout.move_group("color-group", "missing", 0), "reject nonexistent host")
	_check(not layout.move_panel("colors", "history-group", 88), "reject invalid tab index")
	_check(not layout.split_panel("colors", "history-group", "right", 0), "reject duplicate group ID")
	_check(not layout.merge_groups("color-group", "color-group", 0), "reject self merge")
	_check(not layout.move_group("color-group", "right", -3), "reject invalid group index")
	_check(layout.snapshot() == prior, "invalid moves are transactional")
	_check(layout.set_panel_visible("layers", false), "hide panel separately from ownership")
	_check(layout.owner_of("layers") == "right", "hidden panel retains owner")
	_check(layout.rail_icons("right").size() == 2, "hidden panel absent from rail")
	_check(not layout.select_panel("layers"), "hidden panel cannot become active through click")
	_check(layout.set_panel_visible("layers", true), "recover panel through menu")
	_check(layout.select_panel("layers"), "active tab is independently selectable")
	var saved: Dictionary = layout.snapshot()
	var loaded: DrawingDockLayout = LAYOUT_SCRIPT.new() as DrawingDockLayout
	for panel_id: String in ["colors", "layers", "history"]:
		_check(loaded.register_panel(panel_id), "register restored known panel " + panel_id)
	_check(loaded.restore(saved), "versioned layout roundtrip")
	_check(loaded.snapshot() == saved, "roundtrip preserves all independent state")
	var rejected: Dictionary = saved.duplicate(true)
	rejected["version"] = 999
	_check(not loaded.restore(rejected), "reject incompatible snapshot version")
	_check(loaded.snapshot() == saved, "failed snapshot leaves model unchanged")
	rejected = saved.duplicate(true)
	rejected["containers"][0]["groups"][0]["panels"].append("missing-panel")
	_check(not loaded.restore(rejected), "reject unknown panel IDs")
	_check(loaded.snapshot() == saved, "unknown-ID snapshot rolls back")
	rejected = saved.duplicate(true)
	rejected["containers"][0]["groups"][0]["panels"].append("history")
	_check(not loaded.restore(rejected), "reject duplicate ownership in snapshot")
	_check(loaded.snapshot() == saved, "duplicate-ID snapshot rolls back")
	_check(layout.close_flyout("right"), "explicit flyout close")
	_check(layout.set_minimized("right", false), "restore expanded dock")
	_check(not bool(layout.container_info("right")["minimized"]), "expanded dock state retained")
	# The existing workspace uses this model while rendering the same T-063 shell.
	var workspace: Control = WORKSPACE_SCRIPT.new() as Control
	workspace.layout_persistence_enabled = false
	workspace.set("start_blank_document", false)
	root.add_child(workspace)
	for frame: int in range(3):
		await process_frame
	var shell_layout: DrawingDockLayout = workspace.get("dock_layout") as DrawingDockLayout
	_check(shell_layout != null, "standalone workspace installs shared dock model")
	if shell_layout != null:
		_check(shell_layout.rail_icons("right").size() == 3, "shell registers three actual dock panels")
		_check(shell_layout.group_of("layers") == "layers", "Layers initially separate in T-063 layout")
		_check(workspace.get("dock_views").has("layers"), "live control mapping retained")
	_check(workspace.find_child("PanelDock", true, false) != null, "existing dock remains unchanged")
	root.remove_child(workspace)
	workspace.free()
	print("DRAWING_DOCK_MODEL_%s (%d checks, %d failures)" % ["PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
