extends SceneTree
## T-247: every Atlas history changed notification is a read-only timeline boundary.

var checks: int = 0
var failures: int = 0


class CallbackProbe:
	extends RefCounted
	var history: AtlasEditHistory
	var campaign: AtlasCampaign
	var action: String
	var notifications: int = 0
	var reserved: bool = false
	var unchanged: bool = false
	var rejected: bool = true

	func snapshot() -> Dictionary:
		return {
			"cursor": history._cursor,
			"commands": history._commands.size(),
			"states": history._states.duplicate(),
			"before": history._contexts_before.size(),
			"after": history._contexts_after.size(),
			"saved": history._saved_state,
			"external": history._external_revision,
			"saved_external": history._saved_external_revision,
			"map_id": history.active_map_id,
			"grid": campaign.get_map("world").grid.cell_size,
		}

	func on_changed() -> void:
		notifications += 1
		if notifications != 1:
			return
		reserved = history._timeline_reserved()
		var before: Dictionary = snapshot()
		match action:
			"execute":
				var grid: AtlasGrid = campaign.get_map("world").grid.copy()
				var altered: AtlasGrid = grid.copy()
				altered.cell_size += 11.0
				rejected = not history.execute(AtlasGridEdit.new("world", grid, altered))
			"undo":
				rejected = not history.undo()
			"redo":
				rejected = not history.redo()
			"reset":
				history.reset(campaign)
			"saved":
				history.mark_saved()
			"external":
				history.mark_external_change()
			"selection":
				var original: DrawingHistoryContext = DrawingHistoryContext.new()
				original.map_id = "world"
				var selected: DrawingHistoryContext = original.detached_copy()
				selected.selected_layer_ids.append("nested")
				rejected = not history.record_selection_change(original, selected)
		unchanged = snapshot() == before


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T247_ATLAS_NOTIFICATION_FAILED: " + name)


func scenario(event: String, action: String) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	history.record_selection_history = true
	var original: AtlasGrid = campaign.get_map("world").grid.copy()
	var painted: AtlasGrid = original.copy()
	painted.cell_size += 3.0
	check(history.execute(AtlasGridEdit.new("world", original, painted)),
		event + "/" + action + ": baseline command")
	if event == "redo":
		check(history.undo(), event + "/" + action + ": prepare redo")
	elif event == "saved":
		history.mark_external_change()
	elif event == "external":
		history.mark_saved()
	var probe: CallbackProbe = CallbackProbe.new()
	probe.history = history
	probe.campaign = campaign
	probe.action = action
	history.changed.connect(probe.on_changed)
	var completed: bool = true
	match event:
		"undo":
			completed = history.undo()
		"redo":
			completed = history.redo()
		"selection":
			var before: DrawingHistoryContext = DrawingHistoryContext.new()
			before.map_id = "world"
			var after: DrawingHistoryContext = before.detached_copy()
			after.selected_layer_ids.append("chosen")
			completed = history.record_selection_change(before, after)
		"saved":
			history.mark_saved()
		"external":
			history.mark_external_change()
		"reset":
			history.reset(campaign)
	check(completed, event + "/" + action + ": outer operation succeeded")
	check(probe.notifications == 1, event + "/" + action + ": exactly one notification")
	check(probe.reserved, event + "/" + action + ": callback sees reserved timeline")
	check(probe.rejected and probe.unchanged,
		event + "/" + action + ": attempted nested mutation did not change history")
	history.changed.disconnect(probe.on_changed)
	match event:
		"undo":
			check(history.can_redo() and history.redo() and
				campaign.get_map("world").grid.same_as(painted),
				event + "/" + action + ": chronological redo resumes")
		"redo":
			check(history.can_undo() and history.undo() and
				campaign.get_map("world").grid.same_as(original),
				event + "/" + action + ": chronological undo resumes")
		"selection":
			check(history._commands.size() == 2 and history.undo() and history.redo(),
				event + "/" + action + ": selection remains one undoable entry")
		"saved":
			check(not history.is_dirty(), event + "/" + action + ": save marker remains clean")
		"external":
			check(history.is_dirty(), event + "/" + action + ": external change remains dirty")
		"reset":
			history.active_map_id = "world"
			var grid: AtlasGrid = campaign.get_map("world").grid.copy()
			var altered: AtlasGrid = grid.copy()
			altered.cell_size += 7.0
			check(not history.can_undo() and
				history.execute(AtlasGridEdit.new("world", grid, altered)) and history.undo(),
				event + "/" + action + ": reset releases boundary for future commands")


func run() -> void:
	for event: String in ["undo", "redo", "selection", "saved", "external", "reset"]:
		for action: String in ["execute", "undo", "redo", "reset", "saved", "external", "selection"]:
			scenario(event, action)
	if failures == 0:
		print("T247_ATLAS_NOTIFICATION_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T247_ATLAS_NOTIFICATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
