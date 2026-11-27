extends SceneTree
## Structural replay is not a new native raster branch.

const INK: int = 0x00123456
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T325_FAILED: " + label)

func context(doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.document_id = doc.id
	ctx.map_id = "world"
	ctx.selected_layer_ids.append(layer)
	return ctx

func paint(doc: DrawingDocument, timeline: AtlasEditHistory, layer: String, x: int) -> int:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(opened.ok, "begin paint")
	if not opened.ok:
		return 0
	var session: DrawingEditSession = opened.value as DrawingEditSession
	var staged: DrawingResult = session.fill_rect(Rect2i(x, 1, 1, 1), INK)
	check(staged.ok, "stage signed hidden RGB")
	if not staged.ok:
		session.cancel()
		return 0
	var ctx: DrawingHistoryContext = context(doc, layer)
	var result: DrawingResult = timeline.commit_drawing(session, ctx, ctx)
	check(result.ok and result.delta != null and result.delta.native_history_token > 0, "publish paint")
	return result.delta.native_history_token if result.ok and result.delta != null else 0

func retained(doc: DrawingDocument, token: int) -> bool:
	return bool(doc._native_raster_store.call("has_retained_history_token", token))

func exercise(copied: bool, semantic: bool) -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var source: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	var target: DrawingDocument = DrawingDocument.new(DrawingDocument.new_id(), 64)
	check(source.create_layer(DrawingLayerNode.GROUP, "Transfer", "root", "group").ok, "create group")
	if not semantic:
		check(source.create_layer(DrawingLayerNode.RASTER, "Moving", "group", "moving").ok, "moving raster")
	else:
		check(source.create_layer(DrawingLayerNode.OBJECTS, "Semantic", "group", "objects").ok, "moving semantic layer")
	check(source.create_layer(DrawingLayerNode.RASTER, "Keeper", "root", "keeper").ok and
		target.create_layer(DrawingLayerNode.RASTER, "Keeper", "root", "keeper").ok, "resident layers")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "external owners")
	if not semantic:
		check(paint(source, timeline, "moving", -11) > 0, "moving layer has bytes")
	var older_source: int = paint(source, timeline, "keeper", -1)
	var older_target: int = paint(target, timeline, "keeper", -2)
	var command: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, "group", "root", copied,
		context(source, "group"), context(target, "group"))
	check(timeline.execute_drawing_transfer(command), "apply transfer")
	if not command._applied:
		return
	var future_source: int = paint(source, timeline, "keeper", -65)
	var future_target: int = paint(target, timeline, "keeper", -66)
	check(timeline.undo() and timeline.undo(), "undo future raster commands")
	check(retained(source, future_source) and retained(target, future_target), "future tokens live before transfer replay")
	var target_revision: int = target.revision
	var source_revision: int = source.revision
	var busy: Dictionary = target._native_raster_store.call("begin_edit", "keeper", target_revision, false)
	check(bool(busy.get("ok", false)), "reserve target native edit")
	check(not timeline.undo(), "busy target rejects transfer Undo")
	check(source.revision == source_revision and target.revision == target_revision and command._applied,
		"rejected Undo does not mutate either document")
	check(bool(target._native_raster_store.call("discard_edit", int(busy.get("transaction", 0)))), "cancel reservation")
	check(timeline.undo(), "undo transfer")
	check(source.has_node("group") and not target.has_node(command.target_node_id), "restore tree")
	check(retained(source, future_source) and retained(target, future_target), "transfer Undo preserves unrelated future tokens")
	check(retained(source, older_source) and retained(target, older_target), "transfer Undo preserves applied tokens")
	check(timeline.redo(), "redo transfer")
	check(source.has_node("group") == copied and target.has_node(command.target_node_id), "replay transfer tree")
	check(retained(source, future_source) and retained(target, future_target), "transfer Redo preserves unrelated future tokens")
	check(timeline.redo() and timeline.redo(), "redo future raster commands")
	check(int(source.read_pixel("keeper", -65, 1).value) == INK and
		int(target.read_pixel("keeper", -66, 1).value) == INK, "exact future hidden RGB restored")
	check(source._native_save_projection_matches() and target._native_save_projection_matches(), "native projections match")
	check(timeline.undo() and timeline.undo() and timeline.undo(), "rewind transfer and future commands")
	check(retained(source, future_source) and retained(target, future_target), "tokens still retained before real branch")
	var grid: AtlasGrid = campaign.get_map("world").grid.copy()
	var changed: AtlasGrid = grid.copy()
	changed.cell_size += 4.0
	check(timeline.execute(AtlasGridEdit.new("world", grid, changed)), "actual host branch")
	check(not retained(source, future_source) and not retained(target, future_target) and not timeline.can_redo(), "actual branch releases abandoned tokens")
	check(retained(source, older_source) and retained(target, older_target), "branch retains applied tokens")

func new_transfer_branch() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var source: DrawingDocument = DrawingDocument.new("t325-branch-source", 64)
	var target: DrawingDocument = DrawingDocument.new("t325-branch-target", 64)
	check(source.create_layer(DrawingLayerNode.GROUP, "Empty", "root", "group").ok and
		source.create_layer(DrawingLayerNode.RASTER, "Keep", "root", "keeper").ok and
		target.create_layer(DrawingLayerNode.RASTER, "Keep", "root", "keeper").ok, "branch fixture")
	check(source.set_external_history(true).ok and target.set_external_history(true).ok, "branch owners")
	var prior: int = paint(source, timeline, "keeper", -1)
	var later_source: int = paint(source, timeline, "keeper", -2)
	var later_target: int = paint(target, timeline, "keeper", -3)
	check(timeline.undo() and timeline.undo(), "branch fixture future tokens")
	var command: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, "group", "root", false,
		context(source, "group"), context(target, "group"))
	var rev_s: int = source.revision
	var rev_t: int = target.revision
	var active: Dictionary = source._native_raster_store.call("begin_edit", "keeper", rev_s, false)
	check(bool(active.get("ok", false)), "busy semantic source")
	check(not timeline.execute_drawing_transfer(command) and source.revision == rev_s and
		target.revision == rev_t and timeline.can_redo(), "reject busy semantic Move before destination mutation")
	check(retained(source, later_source) and retained(target, later_target), "rejected branch retains future tokens")
	check(bool(source._native_raster_store.call("discard_edit", int(active.get("transaction", 0)))), "release busy source")
	check(timeline.execute_drawing_transfer(command), "successful Move branches timeline")
	check(not retained(source, later_source) and not retained(target, later_target) and
		retained(source, prior) and not timeline.can_redo(), "timeline alone drops abandoned tokens")
	check(timeline.undo(), "new branch remains reversible")
	check(source.has_node("group") and not target.has_node(command.target_node_id), "undo branch restores original group")
	check(timeline.redo(), "new branch Redo")
	var stale_s: int = source.revision
	var stale_t: int = target.revision
	check(bool(target._native_raster_store.call("advance_metadata_revision", stale_t, false)), "inject stale semantic target")
	check(not timeline.undo() and source.revision == stale_s and target.revision == stale_t and
		command._applied and target.has_node(command.target_node_id), "stale target fails before restoring source")

func local_guard() -> void:
	var doc: DrawingDocument = DrawingDocument.new("t325-local", 64)
	check(doc.create_layer(DrawingLayerNode.GROUP, "Group", "root", "group").ok and
		doc.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink").ok, "local fixture")
	var snapshot: DrawingResult = doc.export_subtree("group")
	var rev: int = doc.revision
	check(snapshot.ok and not doc.import_subtree(snapshot.value, "root", false, true).ok and
		not doc.remove_subtree("group", false, true).ok and not doc.reorder("group", "root", 1, false, true).ok and
		doc.revision == rev and doc.has_node("group"), "local caller cannot opt out of branch ownership")
	var edit: DrawingResult = doc.begin_edit("ink", rev)
	check(edit.ok and not doc.preflight_unrecorded_subtree_removal("group").ok, "pending script edit prevents semantic transfer without native owner")
	if edit.ok:
		(edit.value as DrawingEditSession).cancel()
	check(doc.preflight_unrecorded_subtree_removal("group").ok, "cancel restores transfer eligibility")
	check(doc.set_external_history(true).ok, "external owner without native store")
	edit = doc.begin_edit("ink", rev)
	check(edit.ok and not doc.import_subtree(snapshot.value, "root", false, true).ok and
		not doc.remove_subtree("group", false, true).ok and not doc.reorder("group", "root", 1, false, true).ok and
		doc.revision == rev and doc.has_node("group"), "pending script edit prevents host structural mutations")
	if edit.ok:
		(edit.value as DrawingEditSession).cancel()

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native extension present")
	for copied: bool in [false, true]:
		for semantic: bool in [false, true]:
			exercise(copied, semantic)
	new_transfer_branch()
	local_guard()
	print("T325 checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T325_TRANSFER_REDO_OWNERSHIP_PASSED")
	quit(1 if failures else 0)
