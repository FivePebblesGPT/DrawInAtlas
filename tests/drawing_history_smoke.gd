extends SceneTree
## T-054: one Drawing-local history and one Atlas global cross-map timeline.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T-054 FAILED: " + description)


func _run() -> void:
	_local_history()
	_atlas_history()
	_transfer()
	_mixed_timeline()
	_sequential_drawing_history()
	_transfer_with_later_edit()
	_save_as_binding()
	_camera()
	print("DRAWING_HISTORY_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _context(map_id: String, document: DrawingDocument, layer_id: String,
		mode: String = "surface_paint") -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = map_id
	result.floor_group_id = "floor-1"
	result.detail_group_id = "D0"
	result.document_id = document.id
	result.selected_layer_ids.append(layer_id)
	result.editor_mode = mode
	result.has_focus = true
	result.focus_bounds = Rect2(1000.0, 3000.0, 10.0, 10.0)
	return result


func _paint(document: DrawingDocument, layer_id: String, color: int = 0x00224466,
		pixel: Vector2i = Vector2i(1, 1)) -> DrawingResult:
	var started: DrawingResult = document.begin_edit(layer_id, document.revision)
	if not started.ok:
		return started
	var gesture: DrawingEditSession = started.value as DrawingEditSession
	var staged: DrawingResult = gesture.fill_rect(Rect2i(pixel, Vector2i.ONE), color)
	if not staged.ok:
		return staged
	return gesture.commit()


func _local_history() -> void:
	var doc: DrawingDocument = DrawingDocument.new("local", 16)
	var a: String = String(doc.create_layer(DrawingLayerNode.RASTER, "A").value)
	var b: String = String(doc.create_layer(DrawingLayerNode.RASTER, "B").value)
	_check(doc.is_dirty(), "metadata changes dirty an unsaved local document")
	_check(doc.mark_published(doc.revision, {}).ok and not doc.is_dirty(), "savepoint clears metadata dirtiness")
	var select_a: DrawingHistoryContext = _context("", doc, a)
	var select_b: DrawingHistoryContext = _context("", doc, b)
	_check(not doc.record_selection_change(select_a, select_b), "selection-only history defaults OFF")
	var drawn: DrawingResult = _paint(doc, a)
	_check(drawn.ok and doc.history_length() == 1 and doc.can_undo(), "one gesture produces one local entry")
	_check(doc.read_pixel(a, 1, 1).value == 0x00224466, "transparent hidden RGB is exact")
	_check(doc.undo().ok and doc.read_pixel(a, 1, 1).value == 0, "local content undo")
	_check(doc.redo().ok and doc.read_pixel(a, 1, 1).value == 0x00224466, "local content redo")
	var saved: String = OS.get_cache_dir().path_join("t054-local-%d.drawing" % Time.get_ticks_usec())
	_check(DrawingFileIO.save(doc, saved).ok and not doc.is_dirty(), "physical local savepoint")
	doc.record_selection_history = true
	_check(doc.record_selection_change(select_a, select_b), "selection-only operation now tracked")
	_check(doc.history_length() == 2 and not doc.is_dirty(), "selection is one entry and not dirty")
	var selection_undo: DrawingResult = doc.undo()
	_check(selection_undo.ok and selection_undo.value is DrawingHistoryContext
		and (selection_undo.value as DrawingHistoryContext).selected_layer_ids == [a], "undo selection restores A")
	_check(not doc.is_dirty(), "selection undo preserves saved state")
	var selection_redo: DrawingResult = doc.redo()
	_check(selection_redo.ok and (selection_redo.value as DrawingHistoryContext).selected_layer_ids == [b],
		"redo selection restores B")
	_check(not doc.is_dirty(), "selection redo also clean")
	_check(doc.undo().ok and doc.undo().ok and doc.is_dirty(), "undo content after selection is dirty")
	_check(doc.redo().ok and doc.redo().ok and not doc.is_dirty(), "redo through content and selection reaches savepoint")
	doc.record_selection_history = false
	_check(doc.undo().ok and doc.can_redo(), "toggle does not erase earlier selection records")
	var select_many: DrawingHistoryContext = select_b.detached_copy()
	select_many.selected_layer_ids.append("third")
	select_many.selected_layer_ids.append("fourth")
	doc.record_selection_history = true
	_check(doc.record_selection_change(select_a, select_many) and doc.history_length() == 2,
		"one multi-select commit replaces redo branch with one selection entry")
	_check(not doc.can_redo() and not doc.is_dirty(), "selection branch does not dirty or preserve stale redo")
	var bad_session: DrawingResult = doc.begin_edit(a, doc.revision - 1)
	_check(not bad_session.ok and not doc.is_dirty(), "rejected stale gesture never dirties")
	var returned: DrawingResult = doc.undo()
	_check(returned.ok and (returned.value as DrawingHistoryContext).selected_layer_ids == [a],
		"marquee undo restores its one before-context")
	_check(DirAccess.remove_absolute(saved) == OK, "remove scratch Drawing file")


func _atlas_history() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var global: AtlasEditHistory = AtlasEditHistory.new(campaign)
	global.active_map_id = "world"
	var document: DrawingDocument = DrawingDocument.new("shared", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Shared").value)
	_check(document.set_external_history(true).ok, "Atlas claims document history once")
	var source: DrawingHistoryContext = _context("world", document, layer, "object_placement")
	source.asset_id = "asset-shared"
	var destination: DrawingHistoryContext = source.detached_copy()
	destination.map_id = "greyhaven"
	destination.editor_mode = "surface_paint"
	var replayed: Array[DrawingHistoryContext] = []
	var notices: Array[String] = []
	var attempted_reentrant: Array[bool] = []
	global.restoration_warning.connect(func(note: String) -> void: notices.append(note))
	global.context_restorer = func(context: DrawingHistoryContext,
			_regions: Array[DrawingDirtyRegion]) -> bool:
		replayed.append(context.detached_copy())
		attempted_reentrant.append(global.record_selection_change(source, destination))
		return true
	var begin: DrawingResult = document.begin_edit(layer, document.revision)
	var edit: DrawingEditSession = begin.value as DrawingEditSession
	_check(edit.fill_rect(Rect2i(1, 1, 2, 2), 0x00ffeedd).ok, "stage gesture")
	global.active_map_id = "greyhaven"  # User navigated mid-stroke; origin stays pinned.
	var committed: DrawingResult = global.commit_drawing(edit, source, destination)
	_check(committed.ok and committed.regions.size() == 1, "commit records dirty bounds")
	_check(global.can_undo() and not document.can_undo(), "only Atlas owns embedded history")
	_check((global.get_undo_command() as AtlasDrawingEdit).asset_id == "asset-shared",
		"stable reusable asset ID is distinct from Drawing document ID")
	_check(document.read_pixel(layer, 1, 1).value == 0x00ffeedd, "shared asset committed canonically once")
	global.active_map_id = "greyhaven"
	_check(global.undo() and document.read_pixel(layer, 1, 1).value == 0,
		"cross-map undo reverts shared content while viewing B")
	_check(replayed.size() == 1 and replayed[0].map_id == "world" and replayed[0].editor_mode == "object_placement",
		"history returns to originating map and placement mode")
	_check(not attempted_reentrant[0] and not global.can_undo(), "restoration cannot recursively add history")
	_check(global.redo() and document.read_pixel(layer, 1, 1).value == 0x00ffeedd,
		"redo restores shared canonical content")
	_check(replayed.size() == 2 and replayed[1].document_id == "shared" \
		and replayed[1].map_id == "greyhaven" and replayed[1].editor_mode == "surface_paint",
		"redo restores destination map and after-mode")
	_check(notices.is_empty(), "no spurious missing-target notice")
	var old_revision: int = document.revision
	var bad: DrawingResult = document.begin_edit(layer, old_revision - 1)
	_check(not bad.ok and document.revision == old_revision,
		"rejected stale editing session has no dirty revision")
	global.mark_saved()
	_check(not global.is_dirty(), "global content savepoint")
	var selected_after: DrawingHistoryContext = destination.detached_copy()
	selected_after.selected_layer_ids = ["another"]
	_check(not global.record_selection_change(destination, selected_after), "Atlas selection preference defaults OFF")
	var only_mode: DrawingHistoryContext = destination.detached_copy()
	only_mode.editor_mode = "object_source_edit"
	global.record_selection_history = true
	_check(not global.record_selection_change(destination, only_mode),
		"mode-only changes do not enter opt-in selection history")
	global.record_selection_history = true
	_check(global.record_selection_change(destination, selected_after), "opt-in Atlas selection event recorded")
	_check(not global.is_dirty(), "selection entry does not dirty Atlas campaign")
	_check(global.undo() and not global.is_dirty() and replayed.back().selected_layer_ids == [layer],
		"selection undo restores previous selection without dirty")
	_check(global.redo() and not global.is_dirty() and replayed.back().selected_layer_ids == ["another"],
		"selection redo restores next selection without dirty")
	global.context_restorer = func(_context: DrawingHistoryContext,
			_regions: Array[DrawingDirtyRegion]) -> bool: return false
	_check(global.undo(), "selection still reverses with unavailable target")
	_check(not notices.is_empty() and global.last_playback_warning.contains("unavailable"),
		"missing context displays notification without rolling back artwork")
	var detached: DrawingDocument = DrawingDocument.new("separate", 16)
	var copied: String = String(detached.create_layer(DrawingLayerNode.RASTER, "copy").value)
	_check(_paint(detached, copied, 0x33445566).ok and document.read_pixel(layer, 1, 1).value == 0x00ffeedd,
		"editing independent copied content cannot mutate original source")
	var tamper: DrawingResult = _paint(document, layer, 0x01020304, Vector2i(99, 99))
	_check(tamper.ok, "simulate an out-of-band edit as stale history target")
	var cursor_was: bool = global.can_redo()
	_check(not global.undo() and global.can_redo() == cursor_was,
		"unexpected external revision blocks stale global replay without cursor mutation")


func _transfer() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	var a: DrawingDocument = DrawingDocument.new("origin", 16)
	var b: DrawingDocument = DrawingDocument.new("destination", 16)
	var keeper: String = String(a.create_layer(DrawingLayerNode.RASTER, "Keep").value)
	var movable: String = String(a.create_layer(DrawingLayerNode.RASTER, "Moving").value)
	var owned_a: DrawingResult = a.set_external_history(true)
	var owned_b: DrawingResult = b.set_external_history(true)
	var saved: DrawingResult = _paint(a, movable, 0x00331122)
	_check(saved.ok and owned_a.ok and owned_b.ok,
		"cross-document transfer starts with independent Atlas-owned documents")
	var before: DrawingHistoryContext = _context("world", a, movable, "surface_paint")
	var after: DrawingHistoryContext = _context("greyhaven", b, movable, "surface_paint")
	var move: AtlasDrawingTransfer = AtlasDrawingTransfer.new(a, b, movable,
		DrawingDocument.ROOT_ID, false, before, after)
	_check(timeline.execute_drawing_transfer(move), "one Atlas command moves raster source to destination")
	_check(not a.has_node(movable) and b.has_node(movable), "move keeps stable layer ID and removes source")
	_check(b.read_pixel(movable, 1, 1).value == 0x00331122, "moved data is pixel-identical")
	_check(timeline.undo(), "one undo reverses the cross-document move")
	_check(a.has_node(movable) and not b.has_node(movable), "undo restores source and removes destination")
	_check(a.list_children() == [keeper, movable], "undo restores sibling ordering")
	_check(timeline.redo() and b.has_node(movable) and not a.has_node(movable),
		"redo moves the same stable ID without regenerating nodes")
	_check(not timeline.can_redo() and timeline.undo(), "one global history entry, no hidden child steps")
	var copied_context: DrawingHistoryContext = _context("world", b, "copied")
	var copy: AtlasDrawingTransfer = AtlasDrawingTransfer.new(a, b, movable,
		DrawingDocument.ROOT_ID, true, before, copied_context)
	_check(timeline.execute_drawing_transfer(copy), "copy is an independent global content action")
	var copy_id: String = copy.target_node_id
	_check(a.has_node(movable) and copy_id != movable and b.has_node(copy_id),
		"copy leaves source intact and gives target a fresh ID")
	_check(timeline.undo() and a.has_node(movable) and not b.has_node(copy_id),
		"copy undo removes only destination")
	_check(timeline.redo() and b.has_node(copy_id), "copy redo reuses original copied ID")
	_check(not timeline.execute_drawing_transfer(AtlasDrawingTransfer.new(a, a, movable,
		DrawingDocument.ROOT_ID, false, before, before)), "self-transfer rejected safely")
	var mismatch: DrawingDocument = DrawingDocument.new("different-density", 16, 2, 1)
	_check(mismatch.set_external_history(true).ok, "different density destination configured")
	_check(not timeline.execute_drawing_transfer(AtlasDrawingTransfer.new(a, mismatch,
		movable, DrawingDocument.ROOT_ID, false, before,
		_context("world", mismatch, movable))), "cross-density move requires explicit resampling")


func _mixed_timeline() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	timeline.active_map_id = "world"
	var document: DrawingDocument = DrawingDocument.new("mixed", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "one").value)
	_check(document.set_external_history(true).ok, "mixed history document is exclusively Atlas-owned")
	var origin: DrawingHistoryContext = _context("world", document, layer)
	var edit: DrawingEditSession = document.begin_edit(layer, document.revision).value as DrawingEditSession
	_check(edit.fill_rect(Rect2i(3, 4, 1, 1), 0x77112233).ok \
		and timeline.commit_drawing(edit, origin, origin).ok, "first chronological entry is Drawing")
	var map: AtlasMapDocument = campaign.get_map("world")
	var changed: AtlasGrid = map.grid.copy()
	changed.cell_size += 4.0
	_check(timeline.execute(AtlasGridEdit.new("world", map.grid, changed)),
		"legacy Atlas grid command joins same timeline")
	_check(timeline.undo() and document.read_pixel(layer, 3, 4).value == 0x77112233,
		"first undo reverts only later Atlas grid command")
	_check(timeline.undo() and document.read_pixel(layer, 3, 4).value == 0,
		"second undo reverts Drawing without independent branch")
	_check(timeline.redo() and timeline.redo() \
		and document.read_pixel(layer, 3, 4).value == 0x77112233 \
		and map.grid.same_as(changed), "redo preserves mixed Atlas/Drawing chronological order")


func _sequential_drawing_history() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign)
	var doc: DrawingDocument = DrawingDocument.new("sequential", 16)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "paint").value)
	_check(doc.set_external_history(true).ok, "sequential gestures use the global owner")
	var context: DrawingHistoryContext = _context("world", doc, layer)
	for x: int in range(3):
		var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value as DrawingEditSession
		var staged: DrawingResult = edit.fill_rect(Rect2i(x, 0, 1, 1), 0x22334455 + x)
		_check(staged.ok and timeline.commit_drawing(edit, context, context).ok,
			"consecutive Drawing gesture %d entered global timeline" % x)
	_check(timeline.can_undo() and doc.read_pixel(layer, 2, 0).value == 0x22334457,
		"all three Drawing edits published canonically")
	for x: int in range(2, -1, -1):
		_check(timeline.undo() and doc.read_pixel(layer, x, 0).value == 0,
			"undo earlier Drawing command %d despite revision advancement" % x)
	_check(not timeline.can_undo(), "all three Drawing edits share one chronological cursor")
	for x: int in range(3):
		_check(timeline.redo() and doc.read_pixel(layer, x, 0).value == 0x22334455 + x,
			"redo earlier Drawing command %d after intervening replay" % x)
	_check(not timeline.can_redo(), "redo branch consumed without duplicated edits")
	var stale: DrawingResult = _paint(doc, layer, 0x11223344, Vector2i(10, 10))
	_check(stale.ok and not timeline.undo(),
		"out-of-band gesture invalidates revision ledger; history cursor stays intact")


func _transfer_with_later_edit() -> void:
	var timeline: AtlasEditHistory = AtlasEditHistory.new(AtlasCampaign.sample())
	var source: DrawingDocument = DrawingDocument.new("transfer-chain-a", 16)
	var target: DrawingDocument = DrawingDocument.new("transfer-chain-b", 16)
	var layer: String = String(source.create_layer(DrawingLayerNode.RASTER, "move me").value)
	_check(source.set_external_history(true).ok and target.set_external_history(true).ok,
		"two transfer chain documents have external history")
	var original: DrawingHistoryContext = _context("world", source, layer)
	var moved: DrawingHistoryContext = _context("world", target, layer)
	var transfer: AtlasDrawingTransfer = AtlasDrawingTransfer.new(source, target, layer,
		DrawingDocument.ROOT_ID, false, original, moved)
	_check(timeline.execute_drawing_transfer(transfer), "transfer is one global operation")
	var edit: DrawingEditSession = target.begin_edit(layer, target.revision).value as DrawingEditSession
	_check(edit.fill_rect(Rect2i(5, 7, 1, 1), 0x55667788).ok \
		and timeline.commit_drawing(edit, moved, moved).ok, "paint into transferred layer")
	_check(timeline.undo() and target.read_pixel(layer, 5, 7).value == 0,
		"first undo removes paint, not the transfer")
	_check(timeline.undo() and source.has_node(layer) and not target.has_node(layer),
		"second undo reverses transfer despite destination revision change")
	_check(timeline.redo() and target.has_node(layer) and not source.has_node(layer),
		"redo reuses the transferred layer identity")
	_check(timeline.redo() and target.read_pixel(layer, 5, 7).value == 0x55667788,
		"redo paint after layer restored with same stable ID")


func _save_as_binding() -> void:
	var timeline: AtlasEditHistory = AtlasEditHistory.new(AtlasCampaign.sample())
	timeline.active_map_id = "world"
	timeline.mark_saved()
	var instances: Dictionary = {"A": {"generation": "instance-v1", "source_id": "original"},
		"sibling": {"generation": "instance-v1", "source_id": "original"}}
	var assets: Dictionary = {"original": true}
	var look: Callable = func(identifier: String) -> Variant:
		return instances.get(identifier, {})
	var exists: Callable = func(identifier: String) -> bool:
		return assets.has(identifier)
	var publish: Callable = func(instance: String, generation: String,
			original: String, variant: String) -> bool:
		if instances[instance]["generation"] != generation or instances[instance]["source_id"] != original:
			return false
		assets[variant] = true
		instances[instance]["source_id"] = variant
		return true
	var bind: Callable = func(instance: String, generation: String,
			previous: String, next: String) -> bool:
		if not instances.has(instance) or instances[instance]["generation"] != generation \
				or instances[instance]["source_id"] != previous:
			return false
		instances[instance]["source_id"] = next
		return true
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = "world"
	context.floor_group_id = "floor-one"
	context.selected_instance_id = "A"
	context.selected_instance_generation = "instance-v1"
	context.editor_mode = "object_source_edit"
	var saved: AtlasAssetRebind = AtlasAssetRebind.new("A", "instance-v1", "original", "variant-B",
		context, context, look, exists, publish, bind)
	_check(timeline.execute_asset_rebind(saved), "Save As publishes B and rebinds only originating instance")
	_check(instances["sibling"]["source_id"] == "original" and instances["A"]["source_id"] == "variant-B",
		"sibling linked instances keep original source")
	_check(timeline.undo() and instances["A"]["source_id"] == "original" and assets.has("variant-B"),
		"undo rebind keeps durable Variant B in library")
	_check(timeline.is_dirty(), "retained B keeps project dirty even at pre-Save-As history cursor")
	_check(timeline.redo() and instances["A"]["source_id"] == "variant-B",
		"redo rebinds to same B without creating a new variant")
	_check(timeline.undo(), "undo again restores old binding")
	assets.erase("variant-B")
	_check(not timeline.redo() and instances["A"]["source_id"] == "original" \
		and timeline.can_redo(), "redo rejects manually deleted B without recreating it")
	var original_generation: String = instances["A"]["generation"]
	instances["A"]["generation"] = "reused-id-v2"
	_check(not timeline.redo() and instances["A"]["generation"] != original_generation,
		"same ID with new instance generation does not receive stale binding")


func _camera() -> void:
	var current: Vector2 = Vector2(50, 50)
	var size: Vector2 = Vector2(100, 100)
	var partially_visible: Rect2 = Rect2(99, 99, 20, 20)
	_check(AtlasHistoryCamera.pan_if_hidden(current, 1.0, size, partially_visible) == current,
		"partly visible bounds never pan")
	var hidden: Rect2 = Rect2(200, 300, 4, 4)
	_check(AtlasHistoryCamera.pan_if_hidden(current, 1.0, size, hidden) == Vector2(202, 302),
		"hidden geometry pans to center, never adjusts zoom")
	_check(AtlasHistoryCamera.pan_if_hidden(current, 2.0, size,
		Rect2(75, 70, 5, 5)) == current, "zoomed viewport still respects partial visibility")
