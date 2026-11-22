extends SceneTree
## T-248: synchronous host-history callbacks cannot rebind the edit target.

var checks: int = 0
var failures: int = 0


class Probe:
	extends RefCounted
	var history: AtlasEditHistory
	var reflected: bool = false
	var calls: int = 0
	var origin: String = ""
	var observed_reserved: bool = false
	var unchanged: bool = false

	func attempt() -> void:
		calls += 1
		origin = history.active_map_id
		observed_reserved = history._timeline_reserved() or history._replaying
		if reflected:
			history.set("active_map_id", "other")
		else:
			history.active_map_id = "other"
		unchanged = history.active_map_id == origin

	func provide_context() -> DrawingHistoryContext:
		attempt()
		return DrawingHistoryContext.new()

	func on_changed() -> void:
		attempt()

	func restore_context(_context: DrawingHistoryContext, _regions: Array) -> bool:
		attempt()
		return true


class CallbackCommand:
	extends AtlasGridEdit
	var probe: Probe

	func _init(target: String, before: AtlasGrid, after: AtlasGrid, callback: Probe) -> void:
		super._init(target, before, after)
		probe = callback

	func apply(campaign: AtlasCampaign) -> bool:
		probe.attempt()
		return super.apply(campaign)


class ReentrantDocument:
	extends DrawingDocument
	var probe: Probe
	var publishing: bool = false

	func _publish_edit(layer_id: String, expected: int,
			before: Dictionary[String, int], after: Dictionary[String, int],
			record_history: bool = true, track_unrecorded: bool = true) -> DrawingResult:
		publishing = true
		var result: DrawingResult = super._publish_edit(layer_id, expected, before,
			after, record_history, track_unrecorded)
		publishing = false
		return result

	func _resolve_chunk(layer_id: String, tile_key: String) -> DrawingResult:
		if publishing and probe != null and probe.calls == 0:
			probe.attempt()
		return super._resolve_chunk(layer_id, tile_key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T248_ACTIVE_MAP_FAILED: " + label)


func scenario(stage: String, reflected: bool) -> void:
	var key: String = "%s/%s" % [stage, "reflective" if reflected else "direct"]
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var before: AtlasGrid = campaign.get_map("world").grid.copy()
	var after: AtlasGrid = before.copy()
	after.cell_size += 3.0
	var probe: Probe = Probe.new()
	probe.history = history
	probe.reflected = reflected
	if stage == "context":
		history.context_provider = Callable(probe, "provide_context")
	elif stage == "changed":
		history.changed.connect(probe.on_changed)
	var command: AtlasEditCommand = CallbackCommand.new("world", before, after, probe) \
		if stage == "apply" else AtlasGridEdit.new("world", before, after)
	check(history.execute(command), key + ": outer command succeeds")
	check(probe.calls == (2 if stage == "context" else 1) and probe.observed_reserved,
		key + ": callback runs in reservation")
	check(probe.unchanged and history.active_map_id == "world", key + ": target is unchanged")
	check(history._commands.size() == 1 and history._cursor == 1 and
		campaign.get_map("world").grid.same_as(after), key + ": command remains atomic")
	history.context_provider = Callable()
	if stage == "changed":
		history.changed.disconnect(probe.on_changed)
	check(history.undo() and history.redo(), key + ": replay works")
	history.active_map_id = "other"
	check(history.active_map_id == "other", key + ": idle navigation still works")
	history.active_map_id = "world"
	check(history.active_map_id == "world", key + ": idle return still works")


func replay_scenario(reflected: bool) -> void:
	var key: String = "restore/%s" % ["reflective" if reflected else "direct"]
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var before: AtlasGrid = campaign.get_map("world").grid.copy()
	var after: AtlasGrid = before.copy()
	after.cell_size += 3.0
	check(history.execute(AtlasGridEdit.new("world", before, after)), key + ": command")
	var probe: Probe = Probe.new()
	probe.history = history
	probe.reflected = reflected
	history.context_restorer = Callable(probe, "restore_context")
	check(history.undo(), key + ": undo")
	check(probe.calls == 1 and probe.observed_reserved and probe.unchanged and
		history.active_map_id == "world", key + ": Undo callback cannot rebind map")
	check(history.redo(), key + ": redo")
	check(probe.calls == 2 and probe.unchanged and history.active_map_id == "world",
		key + ": Redo callback cannot rebind map")
	check(campaign.get_map("world").grid.same_as(after), key + ": exact grid replay")


func reset_scenario(reflected: bool) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var probe: Probe = Probe.new()
	probe.history = history
	probe.reflected = reflected
	history.changed.connect(probe.on_changed)
	history.reset(campaign)
	check(probe.calls == 1 and probe.unchanged and history.active_map_id.is_empty(),
		"reset: changed observer cannot pick new active map")
	history.changed.disconnect(probe.on_changed)
	history.active_map_id = "world"
	check(history.active_map_id == "world", "reset: subsequent idle selection allowed")


func drawing_scenario(reflected: bool) -> void:
	var key: String = "drawing/%s" % ["reflective" if reflected else "direct"]
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var doc: ReentrantDocument = ReentrantDocument.new("t248-drawing", 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.set_external_history(true).ok, key + ": Atlas history owns raster")
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, key + ": raster edit starts")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value
	check(session.fill_rect(Rect2i(-1, 4, 1, 1), 0x00335577).ok,
		key + ": hidden-RGB pixel staged")
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = "world"
	context.floor_group_id = "ground"
	context.document_id = doc.id
	var probe: Probe = Probe.new()
	probe.history = history
	probe.reflected = reflected
	doc.probe = probe
	var committed: DrawingResult = history.commit_drawing(session, context, context)
	check(committed.ok and committed.delta != null and committed.delta.native_history_token > 0,
		key + ": host records native raster delta")
	check(probe.calls == 1 and probe.observed_reserved and probe.unchanged and
		history.active_map_id == "world", key + ": provider cannot rebind map")
	check(history.undo() and int(doc.read_pixel(layer, -1, 4).value) == 0 and
		history.redo() and int(doc.read_pixel(layer, -1, 4).value) == 0x00335577,
		key + ": history preserves signed hidden-RGB pixel")


func run() -> void:
	for reflected: bool in [false, true]:
		for stage: String in ["context", "apply", "changed"]:
			scenario(stage, reflected)
		replay_scenario(reflected)
		reset_scenario(reflected)
		drawing_scenario(reflected)
	if failures == 0:
		print("T248_ATLAS_ACTIVE_MAP_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T248_ATLAS_ACTIVE_MAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
