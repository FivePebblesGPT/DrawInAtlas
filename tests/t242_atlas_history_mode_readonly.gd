extends SceneTree
## T-242: Atlas's global timeline must survive rejected property-level handoffs.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const PAINT: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T242_ATLAS_MODE_FAILED: " + label)


func context(doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.document_id = doc.id
	result.selected_layer_ids.append(layer)
	return result


func commit_tile(doc: DrawingDocument, layer: String,
		history: AtlasEditHistory, where: Vector2i, pigment: int) -> DrawingResult:
	var begin: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begin.ok:
		return begin
	var session: DrawingEditSession = begin.value as DrawingEditSession
	var painted: DrawingResult = session.fill_rect(Rect2i(where, Vector2i.ONE), pigment)
	if not painted.ok:
		session.cancel()
		return painted
	var source: DrawingHistoryContext = context(doc, layer)
	return history.commit_drawing(session, source, source)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native store available in Atlas")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok and
		registry.ensure_detail("world", "ground", 1, 2, 1, STRIDE).ok,
		"registry attaches a host-owned Drawing detail")
	var selected: DrawingResult = registry.document_at("world", "ground", 1, true)
	check(selected.ok, "Atlas detail can be selected")
	if not selected.ok:
		quit(1)
		return
	var doc: DrawingDocument = selected.value
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(doc.external_history and not layer.is_empty(),
		"registry selected external history before editing")
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var first: DrawingResult = commit_tile(doc, layer, history, Vector2i(-1, 4), HIDDEN)
	check(first.ok and first.delta.native_history_token > 0,
		"first Atlas edit commits a real native history token")
	var map: AtlasMapDocument = campaign.get_map("world")
	var grid: AtlasGrid = map.grid.copy()
	var updated: AtlasGrid = grid.copy()
	updated.cell_size += 4.0
	check(history.execute(AtlasGridEdit.new("world", grid, updated)),
		"non-Drawing Atlas command joins chronological timeline")
	var second: DrawingResult = commit_tile(doc, layer, history, Vector2i(64, 0), PAINT)
	check(second.ok and second.delta.native_history_token > 0,
		"second Atlas edit joins the native history timeline")
	var store: Object = doc._native_raster_store
	var old_stats: Dictionary = store.call("stats")
	var old_revision: int = doc.revision
	doc.external_history = false
	doc.set("external_history", false)
	doc.set_indexed(NodePath("external_history"), false)
	check(doc.external_history and doc.history_length() == 0,
		"direct and reflective writes cannot take over Atlas history")
	check(not doc.set_external_history(false).ok,
		"checked handoff still refuses host-owned command timeline")
	check(doc._native_raster_store == store and doc.revision == old_revision and
		store.call("stats") == old_stats,
		"attempts leave native store, revisions and tokens untouched")
	check(history.can_undo() and not doc.can_undo(),
		"only global history owns the undo cursor")
	check(history.undo() and int(doc.read_pixel(layer, 64, 0).value) == 0,
		"global Undo reverses latest native tile")
	check(history.undo() and map.grid.same_as(grid),
		"global Undo reverses intervening Atlas metadata")
	check(history.undo() and int(doc.read_pixel(layer, -1, 4).value) == 0,
		"global Undo reverses original native tile")
	check(history.redo() and int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"global Redo restores hidden RGB")
	check(history.redo() and map.grid.same_as(updated),
		"global Redo restores Atlas metadata")
	check(history.redo() and int(doc.read_pixel(layer, 64, 0).value) == PAINT,
		"global Redo restores latest native pigment")
	check(doc.external_history and doc.history_length() == 0 and
		doc._native_raster_store == store,
		"native owner and global-only history persist through full playback")
	if failures == 0:
		print("T242_ATLAS_MODE_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T242_ATLAS_MODE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
