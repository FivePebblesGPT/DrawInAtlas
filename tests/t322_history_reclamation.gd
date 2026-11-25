extends SceneTree
## Native history must follow the command owner's lifetime, not only raster revisions.

const INK: int = 0x00335577
var checks: int = 0
var failures: int = 0


class ReentrantDocument:
	extends DrawingDocument
	var owner: AtlasEditHistory
	var reentered: bool = false
	var release_calls: int = 0

	func _release_discarded_history_delta(delta: DrawingDelta, applied: bool) -> void:
		release_calls += 1
		reentered = owner.undo() or owner.redo() or reentered
		owner.reset(null)
		super._release_discarded_history_delta(delta, applied)


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T322_FAILED: " + label)


func document(external: bool) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok, "create raster")
	check(doc.set_external_history(external).ok, "set history owner")
	return doc


func context(doc: DrawingDocument) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.document_id = doc.id
	ctx.map_id = "world"
	ctx.selected_layer_ids.append("ink")
	return ctx


func paint(doc: DrawingDocument, history: AtlasEditHistory, x: int) -> int:
	var opened: DrawingResult = doc.begin_edit("ink", doc.revision)
	check(opened.ok, "open edit")
	if not opened.ok:
		return 0
	var session: DrawingEditSession = opened.value as DrawingEditSession
	var staged: DrawingResult = session.fill_rect(Rect2i(x, 1, 1, 1), INK)
	check(staged.ok, "stage hidden RGB")
	if not staged.ok:
		session.cancel()
		return 0
	var ctx: DrawingHistoryContext = context(doc)
	var result: DrawingResult = history.commit_drawing(session, ctx, ctx) if history != null else session.commit()
	check(result.ok and result.delta != null and result.delta.native_history_token > 0, "commit native history")
	return result.delta.native_history_token if result.ok and result.delta != null else 0


func retained(doc: DrawingDocument, token: int) -> bool:
	return bool(doc._native_raster_store.call("has_retained_history_token", token))


func used(doc: DrawingDocument) -> int:
	return int(doc._native_raster_store.call("stats").get("bytes_used", -1))


func test_host(mode: String) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	timeline.record_selection_history = true
	var a: DrawingDocument = document(true)
	var b: DrawingDocument = document(true)
	var first: int = paint(a, timeline, -1)
	var second: int = paint(b, timeline, -2)
	var third: int = paint(a, timeline, -3)
	if mini(first, mini(second, third)) <= 0:
		return
	check(timeline.undo() and timeline.undo(), mode + ": undo across two native stores")
	check(retained(a, third) and retained(b, second) and retained(a, first), "tokens retained before branch")
	var rev_a: int = a.revision
	var rev_b: int = b.revision
	var mem_a: int = used(a)
	var mem_b: int = used(b)
	# A rejected command must not discard either future token.
	var grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 4.0
	check(not timeline.execute(AtlasGridEdit.new("missing", grid, changed)) and timeline.can_redo() and
		retained(a, third) and retained(b, second), "rejected branch preserves both tokens")
	if mode == "grid":
		check(timeline.execute(AtlasGridEdit.new("world", grid, changed)), "grid branch")
	elif mode == "selection":
		var before: DrawingHistoryContext = context(a)
		var after: DrawingHistoryContext = before.detached_copy()
		after.selected_layer_ids.clear()
		check(timeline.record_selection_change(before, after), "selection branch")
	elif mode == "external":
		timeline.mark_external_change()
	else:
		timeline.reset(campaign)
	check(not timeline.can_redo() and not retained(a, third) and not retained(b, second), mode + ": abandoned native tokens reclaimed")
	check(used(a) < mem_a and used(b) < mem_b, mode + ": both stores release history memory")
	check(a.revision == rev_a and b.revision == rev_b and a._native_save_projection_matches() and
		b._native_save_projection_matches(), mode + ": native revisions and canonical projections unchanged")
	check(int(a.read_pixel("ink", -1, 1).value) == INK and int(a.read_pixel("ink", -3, 1).value) == 0 and
		int(b.read_pixel("ink", -2, 1).value) == 0, "exact signed pixels unchanged")
	if mode == "reset":
		check(not retained(a, first) and not timeline.can_undo(), "reset releases applied command token too")
		check(paint(a, timeline, 1) > 0 and timeline.undo() and timeline.redo(), "new timeline reuses live native owner")
	else:
		check(retained(a, first), "prior applied token preserved")
		if mode != "external":
			check(timeline.undo(), "undo non-raster branch")
		check(timeline.undo() and int(a.read_pixel("ink", -1, 1).value) == 0 and
			timeline.redo() and int(a.read_pixel("ink", -1, 1).value) == INK, "earlier native Undo/Redo still works")


func test_local() -> void:
	var doc: DrawingDocument = document(false)
	var first: int = paint(doc, null, -1)
	var second: int = paint(doc, null, -2)
	if mini(first, second) <= 0:
		return
	check(doc.undo().ok, "local Undo")
	var rev: int = doc.revision
	var memory: int = used(doc)
	var native: Object = doc._native_raster_store
	var active: Dictionary = native.call("begin_edit", "ink", rev, false)
	check(bool(active.get("ok", false)), "begin independent pending edit")
	doc.record_selection_history = true
	var before: DrawingHistoryContext = context(doc)
	var after: DrawingHistoryContext = before.detached_copy()
	after.selected_layer_ids.clear()
	check(doc.record_selection_change(before, after), "local selection-only branch")
	check(not doc.can_redo() and not retained(doc, second) and retained(doc, first) and used(doc) < memory,
		"local selection abandons only native Redo")
	check(bool(native.call("has_active_edit")) and doc.revision == rev and doc._native_save_projection_matches(),
		"reclamation preserves unrelated active edit and revision")
	check(bool(native.call("discard_edit", int(active.get("transaction", 0)))), "cancel retained edit")
	check(doc.undo().ok and doc.undo().ok and doc.redo().ok and int(doc.read_pixel("ink", -1, 1).value) == INK,
		"local prior Undo/Redo survives")


func test_host_reentrancy(mode: String) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	timeline.record_selection_history = true
	var doc: ReentrantDocument = ReentrantDocument.new(DrawingDocument.new_id(), 64)
	doc.owner = timeline
	check(doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok and
		doc.set_external_history(true).ok, "reentrancy fixture")
	var token: int = paint(doc, timeline, -1)
	if token <= 0:
		return
	check(timeline.undo(), "reentrancy fixture undone")
	if mode == "selection":
		var before: DrawingHistoryContext = context(doc)
		var after: DrawingHistoryContext = before.detached_copy()
		after.selected_layer_ids.clear()
		check(timeline.record_selection_change(before, after), "guard selection cleanup")
	elif mode == "external":
		timeline.mark_external_change()
	else:
		timeline.reset(campaign)
	check(doc.release_calls == 1 and not doc.reentered and not retained(doc, token),
		mode + ": cleanup callbacks cannot replay commands")
	check(timeline._campaign == campaign, mode + ": nested reset rejected")
	doc.owner = null


func test_stale_owner() -> void:
	var doc: DrawingDocument = document(false)
	var token: int = paint(doc, null, -1)
	if token <= 0:
		return
	check(doc.undo().ok, "stale owner fixture undone")
	var native: Object = doc._native_raster_store
	var rev: int = doc.revision
	check(bool(native.call("advance_metadata_revision", rev, false)), "inject ahead native revision")
	var memory: int = used(doc)
	doc.record_selection_history = true
	var before: DrawingHistoryContext = context(doc)
	var after: DrawingHistoryContext = before.detached_copy()
	after.selected_layer_ids.clear()
	check(doc.record_selection_change(before, after), "selection can abandon host snapshot with stale owner")
	check(retained(doc, token) and used(doc) == memory and doc.revision == rev and
		int(native.call("stats").get("revision")) == rev + 1, "stale native history is untouched")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native extension")
	for mode: String in ["grid", "selection", "external", "reset"]:
		test_host(mode)
	test_local()
	for mode: String in ["selection", "external", "reset"]:
		test_host_reentrancy(mode)
	test_stale_owner()
	print("T322_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T322_HISTORY_RECLAMATION_PASSED")
	quit(0 if failures == 0 else 1)
