extends SceneTree
## T-245: Atlas must not accept nested timeline mutations during a lazy Drawing commit.

const HIDDEN: int = 0x00335577
var checks: int = 0
var failures: int = 0


class ReentrantDocument:
	extends DrawingDocument
	var owner: AtlasEditHistory
	var campaign: AtlasCampaign
	var edit: DrawingEditSession
	var context: DrawingHistoryContext
	var mode: String = ""
	var calls: int = 0
	var in_publish: bool = false
	var nested_ok: bool = false
	var nested_code: String = ""
	var mutation_ok: bool = false

	func _publish_edit(layer_id: String, expected: int,
			before: Dictionary[String, int], after: Dictionary[String, int],
			record_history: bool = true, track_unrecorded: bool = true) -> DrawingResult:
		in_publish = true
		var published: DrawingResult = super._publish_edit(layer_id, expected, before,
			after, record_history, track_unrecorded)
		in_publish = false
		return published

	func _resolve_chunk(layer_id: String, tile_key: String) -> DrawingResult:
		if in_publish and calls == 0:
			calls = 1
			match mode:
				"nested":
					var nested: DrawingResult = owner.commit_drawing(edit, context, context)
					nested_ok = nested.ok
					nested_code = nested.code
				"execute":
					var grid: AtlasGrid = campaign.get_map("world").grid
					var changed: AtlasGrid = grid.copy()
					changed.cell_size += 3.0
					mutation_ok = owner.execute(AtlasGridEdit.new("world", grid, changed))
				"selection":
					var after: DrawingHistoryContext = context.detached_copy()
					after.selected_layer_ids.append("other")
					mutation_ok = owner.record_selection_change(context, after)
				"undo":
					mutation_ok = owner.undo()
				"redo":
					mutation_ok = owner.redo()
				"external":
					owner.mark_external_change()
				"saved":
					owner.mark_saved()
				"reset":
					owner.reset(campaign)
		return super._resolve_chunk(layer_id, tile_key)


class FailedDocument:
	extends DrawingDocument

	func _publish_edit(_layer_id: String, _expected: int,
			_before: Dictionary[String, int], _after: Dictionary[String, int],
			_record_history: bool = true, _track_unrecorded: bool = true) -> DrawingResult:
		return DrawingResult.failure("REJECTED", "Synthetic source failure")


class ChangedObserver:
	extends RefCounted
	var history: AtlasEditHistory
	var calls: int = 0

	func on_change() -> void:
		calls += 1
		if calls == 1:
			history.mark_external_change()


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T245_ATLAS_COMMIT_FAILED: " + label)


func scenario(mode: String) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var doc: ReentrantDocument = ReentrantDocument.new("t245-" + mode, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var owner_result: DrawingResult = doc.set_external_history(true)
	check(owner_result.ok, mode + ": document switches to Atlas history before edits")
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	history.record_selection_history = true
	var grid: AtlasGrid = campaign.get_map("world").grid
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 2.0
	check(history.execute(AtlasGridEdit.new("world", grid, changed)),
		mode + ": baseline Atlas command created")
	if mode == "redo":
		check(history.undo(), mode + ": baseline command moved to Redo")
	var observer: ChangedObserver
	if mode == "signal":
		observer = ChangedObserver.new()
		observer.history = history
		history.changed.connect(observer.on_change)
	var initial_cursor: int = history._cursor
	var initial_size: int = history._commands.size()
	var initial_external: int = history._external_revision
	var initial_saved: int = history._saved_state
	var initial_cell: float = campaign.get_map("world").grid.cell_size
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = "world"
	context.floor_group_id = "ground"
	context.document_id = doc.id
	context.selected_layer_ids.append(layer)
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, mode + ": opens pending native-capable edit")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value
	check(session.fill_rect(Rect2i(-1, 4, 1, 1), HIDDEN).ok,
		mode + ": stages signed hidden-RGB pixel")
	doc.owner = history
	doc.campaign = campaign
	doc.edit = session
	doc.context = context
	doc.mode = mode
	var result: DrawingResult = history.commit_drawing(session, context, context)
	check(doc.calls == 1, mode + ": publication resolves its source")
	if observer != null:
		check(observer.calls == 1, "signal: synchronous changed observer runs once")
	check(result.ok and result.delta != null and result.delta.native_history_token > 0,
		mode + ": outer commit succeeds with native history")
	if not result.ok:
		return
	check(not doc.nested_ok and not doc.mutation_ok and
		(mode != "nested" or doc.nested_code == "HISTORY_CONTEXT"),
		mode + ": nested command rejected by the host reservation")
	check(history._commands.size() == initial_cursor + 1 and
		history._cursor == initial_cursor + 1 and history.active_map_id == "world",
		mode + ": exactly one Drawing command appended to original timeline")
	check(history._external_revision == initial_external and
		history._saved_state == initial_saved and
		campaign.get_map("world").grid.cell_size == initial_cell,
		mode + ": global history, save state and map grid remain unchanged")
	check(int(doc.read_pixel(layer, -1, 4).value) == HIDDEN and
		doc._native_raster_store != null, mode + ": canonical hidden RGB exists in Rust")
	check(history.undo() and int(doc.read_pixel(layer, -1, 4).value) == 0,
		mode + ": undo restores pixel")
	check(history.redo() and int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		mode + ": redo restores hidden RGB")
	check(history._commands.size() == initial_cursor + 1 and
		initial_size >= initial_cursor,
		mode + ": timeline remains well formed after playback")


func rejected_commit_releases_guard() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var doc: FailedDocument = FailedDocument.new("t245-rejected", 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.set_external_history(true).ok, "failure: Atlas owns document")
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = "world"
	context.document_id = doc.id
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "failure: edit opens")
	if not started.ok:
		return
	var session: DrawingEditSession = started.value
	check(session.fill_rect(Rect2i(0, 0, 1, 1), HIDDEN).ok,
		"failure: edit stages")
	var rejected: DrawingResult = history.commit_drawing(session, context, context)
	check(not rejected.ok and rejected.code == "REJECTED" and not history.can_undo(),
		"failure: publication rejects without an Atlas command")
	var grid: AtlasGrid = campaign.get_map("world").grid
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 2.0
	check(history.execute(AtlasGridEdit.new("world", grid, changed)),
		"failure: later Atlas command executes after reservation release")
	check(history.undo() and history.redo(),
		"failure: ordinary history playback resumes")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native ABI available")
	for mode: String in ["nested", "execute", "selection", "undo", "redo",
			"external", "saved", "reset", "signal"]:
		scenario(mode)
	rejected_commit_releases_guard()
	if failures == 0:
		print("T245_ATLAS_COMMIT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T245_ATLAS_COMMIT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
