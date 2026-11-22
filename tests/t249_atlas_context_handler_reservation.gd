extends SceneTree
## T-249: history callbacks cannot replace the handler used by their own operation.

var checks: int = 0
var failures: int = 0


class Probe:
	extends RefCounted
	var history: AtlasEditHistory
	var reflect: bool = false
	var replacement: bool = false
	var provider_calls: int = 0
	var restorer_calls: int = 0
	var changed_calls: int = 0
	var original_provider: Callable
	var original_restorer: Callable
	var attempted: bool = false
	var rejected: bool = false

	func attempt() -> void:
		attempted = true
		var before_provider: Callable = history.context_provider
		var before_restorer: Callable = history.context_restorer
		if reflect:
			history.set("context_provider", Callable(self, "replacement_context"))
			history.set("context_restorer", Callable(self, "replacement_restore"))
		else:
			history.context_provider = Callable(self, "replacement_context")
			history.context_restorer = Callable(self, "replacement_restore")
		rejected = history.context_provider == before_provider and \
			history.context_restorer == before_restorer

	func provide_context() -> DrawingHistoryContext:
		provider_calls += 1
		if not attempted:
			attempt()
		var value: DrawingHistoryContext = DrawingHistoryContext.new()
		value.selected_layer_ids.append("original")
		return value

	func replacement_context() -> DrawingHistoryContext:
		replacement = true
		var value: DrawingHistoryContext = DrawingHistoryContext.new()
		value.selected_layer_ids.append("replaced")
		return value

	func restore_context(_context: DrawingHistoryContext, _regions: Array) -> bool:
		restorer_calls += 1
		if not attempted:
			attempt()
		return true

	func replacement_restore(_context: DrawingHistoryContext, _regions: Array) -> bool:
		replacement = true
		return true

	func on_changed() -> void:
		changed_calls += 1
		if not attempted:
			attempt()


class FailingCommand:
	extends AtlasEditCommand
	var probe: Probe

	func _init(callback: Probe) -> void:
		map_id = "world"
		probe = callback

	func apply(_campaign: AtlasCampaign) -> bool:
		probe.attempt()
		return false


class CallbackCommand:
	extends AtlasGridEdit
	var probe: Probe

	func _init(target: String, before: AtlasGrid, after: AtlasGrid, listener: Probe) -> void:
		super._init(target, before, after)
		probe = listener

	func apply(campaign: AtlasCampaign) -> bool:
		probe.attempt()
		return super.apply(campaign)


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T249_CONTEXT_OWNER_FAILED: " + label)


func setup_probe(history: AtlasEditHistory, reflected: bool) -> Probe:
	var value: Probe = Probe.new()
	value.history = history
	value.reflect = reflected
	value.original_provider = Callable(value, "provide_context")
	value.original_restorer = Callable(value, "restore_context")
	history.context_provider = value.original_provider
	history.context_restorer = value.original_restorer
	return value


func scenario(stage: String, reflected: bool) -> void:
	var label: String = stage + ("/reflect" if reflected else "/direct")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var before_grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var after_grid: AtlasGrid = before_grid.copy()
	after_grid.cell_size += 5.0
	var probe: Probe = setup_probe(timeline, reflected)
	if stage == "signal":
		timeline.changed.connect(probe.on_changed)
	var command: AtlasEditCommand = CallbackCommand.new("world", before_grid, after_grid, probe) \
		if stage == "apply" else AtlasGridEdit.new("world", before_grid, after_grid)
	check(timeline.execute(command), label + ": command applied")
	check(probe.attempted and probe.rejected and not probe.replacement,
		label + ": in-flight handler replacement rejected")
	check(timeline.context_provider == probe.original_provider and
		timeline.context_restorer == probe.original_restorer,
		label + ": existing handlers retained after commit")
	check(timeline._contexts_before[0].selected_layer_ids == ["original"] and
		timeline._contexts_after[0].selected_layer_ids == ["original"],
		label + ": before/after capture uses one provider")
	check(probe.provider_calls == 2 and timeline._cursor == 1,
		label + ": command remains chronological")
	if stage == "signal":
		timeline.changed.disconnect(probe.on_changed)
	check(timeline.undo() and campaign.get_map("world").grid.same_as(before_grid) and
		timeline.redo() and campaign.get_map("world").grid.same_as(after_grid),
		label + ": Undo/Redo and restoration remain valid")
	check(probe.restorer_calls == 2 and not probe.replacement,
		label + ": original restoration handler remained installed")
	# Ordinary UI replacement between commands remains supported.
	timeline.context_provider = Callable(probe, "replacement_context")
	timeline.context_restorer = Callable(probe, "replacement_restore")
	check(timeline.context_provider != probe.original_provider and
		timeline.context_restorer != probe.original_restorer,
		label + ": idle handler configuration remains editable")
	check(timeline.undo() and probe.replacement,
		label + ": new restorer becomes active only after idle configuration")


func replay_scenario(reflected: bool) -> void:
	var label: String = "restore" + ("/reflect" if reflected else "/direct")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var before_grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var after_grid: AtlasGrid = before_grid.copy()
	after_grid.cell_size += 7.0
	check(timeline.execute(AtlasGridEdit.new("world", before_grid, after_grid)),
		label + ": initial command")
	var probe: Probe = setup_probe(timeline, reflected)
	check(timeline.undo() and probe.attempted and probe.rejected and not probe.replacement,
		label + ": Undo restorer could not change callback pair")
	check(timeline.redo() and probe.restorer_calls == 2 and not probe.replacement,
		label + ": Redo uses the original restoration handler")
	check(timeline.context_provider == probe.original_provider and
		timeline.context_restorer == probe.original_restorer,
		label + ": both callbacks are still unchanged")
	timeline.context_provider = Callable(probe, "replacement_context")
	timeline.context_restorer = Callable(probe, "replacement_restore")
	check(timeline.undo() and probe.replacement,
		label + ": idle replacement works after replay")


func failed_command_scenario(reflected: bool) -> void:
	var label: String = "failed-command" + ("/reflect" if reflected else "/direct")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var probe: Probe = setup_probe(timeline, reflected)
	check(not timeline.execute(FailingCommand.new(probe)), label + ": outer command refused")
	check(probe.attempted and probe.rejected and not probe.replacement,
		label + ": failed apply cannot rebind callbacks")
	check(timeline._cursor == 0 and timeline._commands.is_empty() and
		timeline.context_provider == probe.original_provider,
		label + ": failure leaves command and handler intact")
	timeline.context_provider = Callable(probe, "replacement_context")
	check(timeline.context_provider != probe.original_provider,
		label + ": failed command releases callback reservation")


func native_drawing_scenario(reflected: bool) -> void:
	var label: String = "native-drawing" + ("/reflect" if reflected else "/direct")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok,
		label + ": Atlas Drawing registry attached")
	var doc_result: DrawingResult = registry.document_at("world", "ground", 1, true)
	if not doc_result.ok:
		check(false, label + ": detail available")
		return
	var doc: DrawingDocument = doc_result.value
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var probe: Probe = setup_probe(timeline, reflected)
	timeline.changed.connect(probe.on_changed)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not started.ok:
		check(false, label + ": session available")
		return
	var session: DrawingEditSession = started.value
	check(session.fill_rect(Rect2i(-1, 0, 1, 1), 0x00335577).ok,
		label + ": hidden-RGB edit staged")
	var pinned: DrawingHistoryContext = DrawingHistoryContext.new()
	pinned.map_id = "world"
	pinned.floor_group_id = "ground"
	pinned.document_id = doc.id
	pinned.selected_layer_ids.append(layer)
	var committed: DrawingResult = timeline.commit_drawing(session, pinned, pinned)
	check(committed.ok and committed.delta.native_history_token > 0,
		label + ": host publishes native RGBA8 history")
	check(probe.changed_calls == 1 and probe.attempted and probe.rejected and
		timeline.context_restorer == probe.original_restorer,
		label + ": publication observer cannot replace handlers")
	timeline.changed.disconnect(probe.on_changed)
	check(timeline.undo() and int(doc.read_pixel(layer, -1, 0).value) == 0 and
		timeline.redo() and int(doc.read_pixel(layer, -1, 0).value) == 0x00335577,
		label + ": Atlas native Undo/Redo retains hidden RGB")
	check(not probe.replacement and probe.restorer_calls == 2,
		label + ": native history restores using original handler")


func run() -> void:
	for reflected: bool in [false, true]:
		for stage: String in ["context", "apply", "signal"]:
			scenario(stage, reflected)
		replay_scenario(reflected)
		failed_command_scenario(reflected)
		native_drawing_scenario(reflected)
	if failures == 0:
		print("T249_CONTEXT_OWNER_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T249_CONTEXT_OWNER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
