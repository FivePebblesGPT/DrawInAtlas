extends SceneTree
## T-246: callback reentrancy must not reorder ordinary Atlas command history.

var checks: int = 0
var failures: int = 0


class CallbackProbe:
	extends RefCounted
	var history: AtlasEditHistory
	var campaign: AtlasCampaign
	var mode: String = ""
	var calls: int = 0
	var nested_result: bool = false
	var initial_saved: int = 0
	var initial_external: int = 0
	var context: DrawingHistoryContext

	func attempt() -> void:
		if calls != 0:
			return
		calls = 1
		match mode:
			"execute":
				var before: AtlasGrid = campaign.get_map("world").grid.copy()
				var after: AtlasGrid = before.copy()
				after.cell_size += 9.0
				nested_result = history.execute(AtlasGridEdit.new("world", before, after))
			"undo":
				nested_result = history.undo()
			"redo":
				nested_result = history.redo()
			"reset":
				history.reset(campaign)
			"saved":
				history.mark_saved()
			"external":
				history.mark_external_change()
			"selection":
				var after: DrawingHistoryContext = context.detached_copy()
				after.selected_layer_ids.append("changed")
				nested_result = history.record_selection_change(context, after)

	func provide_context() -> DrawingHistoryContext:
		attempt()
		return context

	func on_changed() -> void:
		attempt()


class CallbackCommand:
	extends AtlasGridEdit
	var probe: CallbackProbe

	func _init(target: String, before: AtlasGrid, after: AtlasGrid,
			callback: CallbackProbe) -> void:
		super._init(target, before, after)
		probe = callback

	func apply(campaign: AtlasCampaign) -> bool:
		probe.attempt()
		return super.apply(campaign)


class RejectedCommand:
	extends AtlasEditCommand

	func _init() -> void:
		map_id = "world"

	func apply(_campaign: AtlasCampaign) -> bool:
		return false


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T246_ATLAS_COMMAND_FAILED: " + label)


func scenario(stage: String, mode: String) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	history.record_selection_history = true
	var grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 2.0
	check(history.execute(AtlasGridEdit.new("world", grid, changed)),
		stage + "/" + mode + ": baseline command accepted")
	if mode == "redo":
		check(history.undo(), stage + "/redo: baseline command undone")
	var original_cursor: int = history._cursor
	var original_external: int = history._external_revision
	var original_saved: int = history._saved_state
	var initial_grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var next_grid: AtlasGrid = initial_grid.copy()
	next_grid.cell_size += 4.0
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = "world"
	context.floor_group_id = "ground"
	var probe: CallbackProbe = CallbackProbe.new()
	probe.history = history
	probe.campaign = campaign
	probe.mode = mode
	probe.context = context
	probe.initial_saved = original_saved
	probe.initial_external = original_external
	if stage == "context":
		history.context_provider = Callable(probe, "provide_context")
	elif stage == "signal":
		history.changed.connect(probe.on_changed)
	var command: AtlasEditCommand = CallbackCommand.new("world", initial_grid, next_grid, probe) \
		if stage == "apply" else AtlasGridEdit.new("world", initial_grid, next_grid)
	check(history.execute(command), stage + "/" + mode + ": outer command accepted")
	check(probe.calls == 1, stage + "/" + mode + ": callback ran once")
	check(not probe.nested_result, stage + "/" + mode + ": nested history operation rejected")
	check(history._cursor == original_cursor + 1 and
		history._commands.size() == original_cursor + 1,
		stage + "/" + mode + ": exactly one timeline command recorded")
	check(history._external_revision == original_external and
		history._saved_state == original_saved,
		stage + "/" + mode + ": dirty and save markers unchanged")
	check(campaign.get_map("world").grid.same_as(next_grid),
		stage + "/" + mode + ": outer grid change remains canonical")
	# Remove callbacks before checking ordinary replay and guard release.
	history.context_provider = Callable()
	if stage == "signal":
		history.changed.disconnect(probe.on_changed)
	check(history.undo() and campaign.get_map("world").grid.same_as(initial_grid),
		stage + "/" + mode + ": Undo restores original grid")
	check(history.redo() and campaign.get_map("world").grid.same_as(next_grid),
		stage + "/" + mode + ": Redo replays outer command")


func failed_command_release() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	check(not history.execute(RejectedCommand.new()) and not history.can_undo(),
		"rejected command does not consume a history slot")
	var before: AtlasGrid = campaign.get_map("world").grid.copy()
	var after: AtlasGrid = before.copy()
	after.cell_size += 3.0
	check(history.execute(AtlasGridEdit.new("world", before, after)),
		"rejected command releases reservation for later command")
	check(history.undo() and history.redo(), "later ordinary Undo and Redo available")


class CallbackTransfer:
	extends AtlasDrawingTransfer
	var probe: CallbackProbe

	func _init(source: DrawingDocument, target: DrawingDocument, node: String,
			parent: String, before: DrawingHistoryContext, after: DrawingHistoryContext,
			callback: CallbackProbe) -> void:
		super._init(source, target, node, parent, true, before, after)
		probe = callback

	func apply(campaign: AtlasCampaign) -> bool:
		probe.attempt()
		return super.apply(campaign)


func asset_rebind_callbacks() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var before: DrawingHistoryContext = DrawingHistoryContext.new()
	before.map_id = "world"
	before.floor_group_id = "ground"
	var instance: Dictionary = {"generation": "v1", "source_id": "A"}
	var assets: Dictionary = {"A": true}
	var probe: CallbackProbe = CallbackProbe.new()
	probe.history = history
	probe.campaign = campaign
	probe.mode = "execute"
	probe.context = before
	var look: Callable = func(_id: String) -> Variant:
		return instance.duplicate()
	var exists: Callable = func(id: String) -> bool:
		return assets.has(id)
	var publish: Callable = func(_id: String, _generation: String,
			_original: String, variant: String) -> bool:
		probe.attempt()
		assets[variant] = true
		instance["source_id"] = variant
		return true
	var bind: Callable = func(_id: String, _generation: String,
			_previous: String, replacement: String) -> bool:
		instance["source_id"] = replacement
		return true
	var command: AtlasAssetRebind = AtlasAssetRebind.new("editor", "v1", "A", "B",
		before, before, look, exists, publish, bind)
	check(history.execute_asset_rebind(command), "asset: Save As rebind committed")
	check(probe.calls == 1 and not probe.nested_result,
		"asset: publish callback cannot nest an Atlas grid command")
	check(history._commands.size() == 1 and history._cursor == 1 and
		instance["source_id"] == "B" and assets.has("B"),
		"asset: only the rebind command is recorded")
	check(history.undo() and instance["source_id"] == "A" and assets.has("B"),
		"asset: Undo restores binding but keeps durable asset")
	check(history.redo() and instance["source_id"] == "B",
		"asset: Redo reuses the bound asset")


func transfer_callbacks() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var source: DrawingDocument = DrawingDocument.new("t246-source", 64)
	var target: DrawingDocument = DrawingDocument.new("t246-target", 64)
	var layer: String = str(source.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(source.set_external_history(true).ok and target.set_external_history(true).ok,
		"transfer: both documents use Atlas history")
	var before: DrawingHistoryContext = DrawingHistoryContext.new()
	before.map_id = "world"
	before.floor_group_id = "ground"
	before.document_id = source.id
	var after: DrawingHistoryContext = before.detached_copy()
	after.document_id = target.id
	var probe: CallbackProbe = CallbackProbe.new()
	probe.history = history
	probe.campaign = campaign
	probe.mode = "execute"
	probe.context = before
	var transfer: AtlasDrawingTransfer = CallbackTransfer.new(source, target, layer,
		"root", before, after, probe)
	check(history.execute_drawing_transfer(transfer), "transfer: single-panel copy committed")
	check(probe.calls == 1 and not probe.nested_result,
		"transfer: apply callback cannot nest a grid command")
	check(history._commands.size() == 1 and history._cursor == 1 and
		source.has_node(layer) and target.has_node(transfer.target_node_id),
		"transfer: only the copy command is recorded")
	check(history.undo() and source.has_node(layer) and not target.has_node(transfer.target_node_id),
		"transfer: Undo leaves source and removes target")
	check(history.redo() and target.has_node(transfer.target_node_id),
		"transfer: Redo restores the target")


func run() -> void:
	for stage: String in ["context", "apply", "signal"]:
		for mode: String in ["execute", "undo", "redo", "reset", "saved", "external", "selection"]:
			scenario(stage, mode)
	failed_command_release()
	asset_rebind_callbacks()
	transfer_callbacks()
	if failures == 0:
		print("T246_ATLAS_COMMAND_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T246_ATLAS_COMMAND_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
