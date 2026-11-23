extends SceneTree
## Atlas host history is reserved even while its GDScript EditSession is pending.

const HIDDEN: int = 0x00335577
const PAINT: int = 0xff3366aa
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T244_ATLAS_PENDING_FAILED: " + label)


func context(doc: DrawingDocument, layer: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.document_id = doc.id
	result.selected_layer_ids.append(layer)
	return result


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "native tile ABI loaded for Atlas")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok,
		"Atlas registry accepts campaign")
	var allocated: DrawingResult = registry.ensure_detail("world", "ground", 1, 2, 1, 64)
	check(allocated.ok, "Atlas registers a detail to receive a loaded document")
	var loaded: DrawingDocument = DrawingDocument.new(str(allocated.value), 64, 2, 1)
	var layer: String = str(loaded.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	check(not layer.is_empty() and registry.attach_loaded_document(
		"world", "ground", 1, loaded).ok,
		"Atlas adopts a pre-existing raster layer before any host command")
	var selected: DrawingResult = registry.document_at("world", "ground", 1, true)
	check(selected.ok and selected.value == loaded,
		"Atlas returns the attached document")
	if not selected.ok:
		quit(1)
		return
	var doc: DrawingDocument = selected.value
	check(doc.external_history and doc._native_raster_store == null and
		doc.revision == doc._external_history_anchor_revision,
		"Atlas owns a pristine command timeline with an existing raster layer")
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var started: DrawingResult = doc.begin_edit(layer, doc.revision)
	check(started.ok, "Atlas opens first Drawing edit")
	var session: DrawingEditSession = started.value
	check(not doc.set_external_history(false).ok and doc.external_history,
		"unpainted session reserves host timeline before native attachment")
	check(session.fill_rect(Rect2i(-1, 4, 1, 1), HIDDEN).ok,
		"Atlas paints hidden-RGB signed pixel in detached staging")
	check(doc._native_raster_store == null and not doc.set_external_history(false).ok,
		"staged session cannot hand off Atlas ownership")
	var source: DrawingHistoryContext = context(doc, layer)
	var committed: DrawingResult = history.commit_drawing(session, source, source)
	check(committed.ok and committed.delta.native_history_token > 0 and
		doc._native_raster_store != null, "Atlas commit acquires Rust source and history token")
	check(doc.external_history and doc.history_length() == 0 and history.can_undo(),
		"global history holds command and local timeline is empty")
	check(history.undo() and int(doc.read_pixel(layer, -1, 4).value) == 0,
		"Atlas Undo restores zero pixel")
	check(history.redo() and int(doc.read_pixel(layer, -1, 4).value) == HIDDEN,
		"Atlas Redo restores alpha-zero hidden RGB")
	var prior_store: Object = doc._native_raster_store
	var next: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(next.fill_rect(Rect2i(64, 0, 1, 1), PAINT).ok,
		"second Atlas session opens with retained Rust source")
	check(not doc.set_external_history(false).ok and doc._native_raster_store == prior_store,
		"host owner stays fixed during subsequent pending session")
	next.cancel()
	check(next._closed and doc.external_history, "cancellation leaves host ownership intact")
	check(history.can_undo() and int(doc.read_pixel(layer, 64, 0).value) == 0,
		"cancelled edit neither publishes bytes nor creates Atlas command")
	if failures == 0:
		print("T244_ATLAS_PENDING_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T244_ATLAS_PENDING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
