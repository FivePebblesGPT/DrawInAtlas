extends SceneTree
## T-062: published/hidden Object Editor drafts, Atlas instance origin and history.

var checks: int = 0
var failures: int = 0
var directory: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OBJECT_EDITOR_FAILED: " + description)


func _paint(doc: DrawingDocument, layer: String, rgba: int, point: Vector2i) -> bool:
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begun.ok:
		return false
	var edit: DrawingEditSession = begun.value
	if not edit.apply_region(Rect2i(point, Vector2i.ONE), PackedByteArray([
			rgba & 255, (rgba >> 8) & 255, (rgba >> 16) & 255,
			(rgba >> 24) & 255])).ok:
		return false
	return edit.commit().ok


func _pixel(library: AtlasObjectLibrary, instance_id: String, point: Vector2i) -> int:
	var result: DrawingResult = library.render_instance(instance_id, Rect2i(point, Vector2i.ONE))
	if not result.ok or result.value.get("status") != "linked":
		return -1
	return (result.value["image"] as Image).get_data().decode_u32(0)


func _context(instance_id: String, asset_id: String) -> DrawingHistoryContext:
	var result: DrawingHistoryContext = DrawingHistoryContext.new()
	result.map_id = "world"
	result.floor_group_id = "ground"
	result.detail_group_id = "D0"
	result.selected_instance_id = instance_id
	result.asset_id = asset_id
	result.editor_mode = "ObjectSelection"
	return result


func _delete_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for folder: String in dir.get_directories():
		_delete_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _run() -> void:
	directory = OS.get_cache_dir().path_join("t062-editor-" + DrawingDocument.new_id())
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(directory.path_join("Campaign.scn"))
	var source: DrawingDocument = DrawingDocument.new("source-document", 32)
	var group: String = String(source.create_layer(DrawingLayerNode.GROUP, "Objects").value)
	var layer: String = String(source.create_layer(DrawingLayerNode.RASTER, "Art", group).value)
	_check(_paint(source, layer, 0x00332211, Vector2i(-7, -8)), "source supports exact alpha-zero RGB")
	var source_id: String = String(library.create_asset(source, "Standing stone").value)
	var a: String = String(library.place(source_id, "world", "ground", "D0").value)
	var b: String = String(library.place(source_id, "world", "ground", "D0",
		Transform2D(1.0, Vector2(100, 100))).value)
	_check(library.instance_ids().size() == 2, "two independent Atlas placements")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "world"
	var state: Dictionary = {"context": _context(a, source_id)}
	var get_context: Callable = func() -> DrawingHistoryContext: return state["context"]
	var bridge: AtlasObjectEditorBridge = AtlasObjectEditorBridge.new(library, history, get_context)
	var opened: DrawingResult = bridge.open_from_instance(a)
	_check(opened.ok, "captured source/instance edit context opens")
	if not opened.ok:
		quit(1)
		return
	var tab: DrawingObjectEditorSession = opened.value
	_check(tab.origin_instance_id == a and tab.origin_map_id == "world" and
		tab.source_id == source_id and tab.source_revision == 1, "tab identifies source and origin")
	_check(not tab.is_dirty(), "opening a published source creates a clean private draft")
	var edit_layer: String = String(tab.document.list_children(tab.document.list_children()[0])[0])
	_check(_paint(tab.document, edit_layer, 0xffabcdef, Vector2i(2, 3)), "paint in private draft")
	_check(tab.is_dirty() and _pixel(library, a, Vector2i(2, 3)) == 0 and
		_pixel(library, b, Vector2i(2, 3)) == 0, "unsaved preview never leaks to either instance")
	_check(tab.document.undo().ok and tab.document.redo().ok, "draft uses local Drawing undo")
	_check(tab.set_name("Standing stone updated").ok and tab.is_dirty(), "modified name marks dirty")
	_check(tab.set_frame(Vector2i(-12, 16), Rect2i(-30, -20, 64, 96)).ok,
		"source supports signed object-local anchor and explicit bounds")
	_check(not tab.set_frame(Vector2i(0, 0), Rect2i(0, 0, -1, 100)).ok,
		"invalid local bounds are rejected without changing the draft")
	var saved: DrawingResult = tab.save()
	_check(saved.ok and tab.source_revision == 2 and not tab.is_dirty(), "Save publishes immutable revision and resets savepoint")
	_check(library.asset_info(source_id)["name"] == "Standing stone updated" and
		library.asset_handle(source_id).origin == Vector2i(-12, 16) and
		library.asset_handle(source_id).bounds == Rect2i(-30, -20, 64, 96) and
		_pixel(library, a, Vector2i(2, 3)) == 0xffabcdef and
		_pixel(library, b, Vector2i(2, 3)) == 0xffabcdef, "Save refreshes all linked placements")
	var published_doc: DrawingDocument = library.begin_draft(source_id).value.document
	var published_layer: String = String(published_doc.list_children(published_doc.list_children()[0])[0])
	_check(published_doc.read_pixel(published_layer, -7, -8).value == 0x00332211,
		"source storage retains hidden RGB bytes and signed coordinates (transparent compositing shows zero)")
	edit_layer = String(tab.document.list_children(tab.document.list_children()[0])[0])
	_check(_paint(tab.document, edit_layer, 0xff998877, Vector2i(4, 5)), "prepare variant-only artwork")
	_check(_pixel(library, a, Vector2i(4, 5)) == 0 and _pixel(library, b, Vector2i(4, 5)) == 0,
		"variant remains invisible until Save As")
	var variant: DrawingResult = tab.save_as()
	_check(variant.ok, "Save As atomically publishes B and retargets captured instance A")
	if not variant.ok:
		print("T062 SAVE_AS: ", variant.code, " / ", variant.message)
		quit(1)
		return
	var variant_id: String = tab.source_id
	_check(variant_id != source_id and tab.origin_instance_id.is_empty() and not tab.is_dirty(),
		"new independent variant gets a separate source and clean editor tab")
	_check(library.asset_handle(variant_id).origin == Vector2i(-12, 16) and
		library.asset_handle(variant_id).bounds == Rect2i(-30, -20, 64, 96),
		"Save As preserves Object Asset-local frame independently of raster")
	_check(library.instance_info(a)["source_id"] == variant_id and
		library.instance_info(b)["source_id"] == source_id and
		_pixel(library, a, Vector2i(4, 5)) == 0xff998877 and
		_pixel(library, b, Vector2i(4, 5)) == 0,
		"Save As changes A only; original and B placement remain unchanged")
	_check(history.can_undo() and history.undo(), "global history undoes the one rebind")
	_check(library.instance_info(a)["source_id"] == source_id and library.asset_exists(variant_id),
		"undo retains the independent saved B source")
	_check(history.redo() and library.instance_info(a)["source_id"] == variant_id,
		"redo binds the exact existing Variant B")
	var index: Dictionary = library.export_index()
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(directory.path_join("Campaign.scn"))
	_check(reloaded.load().ok and reloaded.asset_exists(variant_id) and
		reloaded.instance_info(b)["source_id"] == source_id and
		reloaded.asset_handle(variant_id).origin == Vector2i(-12, 16) and
		reloaded.asset_handle(variant_id).bounds == Rect2i(-30, -20, 64, 96),
		"reloaded registry retains asset, frame and correct sibling placement")
	var independent: DrawingResult = bridge.open_source(source_id)
	_check(independent.ok and independent.value.origin_instance_id.is_empty(),
		"independent Object Editor opens without captured instance")
	var standalone: DrawingObjectEditorSession = independent.value
	var independent_id: String = String(standalone.save_as().value)
	_check(independent_id != source_id and independent_id != variant_id and
		library.instance_info(a)["source_id"] == variant_id and
		library.instance_info(b)["source_id"] == source_id and
		library.asset_ids().size() == 3,
		"standalone Save As deep-copies without rebinding any placement")
	var copied: DrawingResult = library.begin_draft(independent_id)
	_check(copied.ok and copied.value.document.id != source.id and
		copied.value.document.list_children()[0] != group,
		"copied asset receives fresh document and subtree IDs")
	bridge.release(standalone)
	_check(not standalone.save().ok, "released editor cannot publish later")
	# Failed/stale publication keeps the tab dirty and registry unchanged.
	var stale_origin: DrawingResult = bridge.open_from_instance(a) # still selected old source -> reject
	_check(not stale_origin.ok, "origin context mismatch is rejected")
	state["context"] = _context(b, source_id)
	var broken: DrawingResult = bridge.open_from_instance(b)
	_check(broken.ok, "new origin selection opens independently")
	if broken.ok:
		var stale: DrawingObjectEditorSession = broken.value
		var stale_layer: String = String(stale.document.list_children(stale.document.list_children()[0])[0])
		_check(_paint(stale.document, stale_layer, 0xff557799, Vector2i(8, 9)), "prepare private stale draft")
		var earlier: Dictionary = library.export_index()
		state["context"] = _context(a, variant_id)
		_check(not stale.save_as().ok and stale.is_dirty() and library.export_index() == earlier,
			"selection/map mode switch blocks stale instance publication")
		state["context"] = _context(b, source_id)
		library.publication_guard = func() -> bool: return false
		_check(not stale.save_as().ok and stale.is_dirty() and library.export_index() == earlier,
			"failed atomic index publication preserves draft and all bindings")
		library.publication_guard = Callable()
		var placement: Dictionary = library.instance_info(b)
		_check(library.transform_instance(b, placement["revision"],
			Transform2D(1.0, Vector2(102, 100))).ok, "external transform changes generation revision")
		_check(not stale.save_as().ok and library.export_index()["assets"].size() == 3,
			"changed instance revision rejects Save As without creating a variant")
		bridge.release(stale)
	# Mount the same shared Drawing workspace in Atlas, no engine fork.
	var window: AtlasObjectEditorWindow = AtlasObjectEditorWindow.new()
	root.add_child(window)
	window.configure(library, history, get_context)
	await process_frame
	_check(window.workspace != null and not window.workspace.start_blank_document and
		window.workspace.tabs.is_empty(), "Atlas host opens clean dedicated Object Editor tabs")
	var mounted: DrawingResult = window.open_source(source_id)
	_check(mounted.ok and window.workspace.tabs.size() == 1 and
		window.workspace.current_object() == mounted.value and
		window.workspace.current_document() == mounted.value.document,
		"Atlas opens Drawing-owned editor UI with the captured source")
	_check(window.workspace.status.text.contains(source_id) and
		window.workspace.status.text.contains("Standing stone"), "Object tab shows stable source identity")
	window.workspace._request_close_current()
	_check(window.workspace.tabs.is_empty(), "clean tab closes without publishing")
	state["context"] = _context(a, variant_id)
	var mounted_instance: DrawingResult = window.open_instance(a)
	_check(mounted_instance.ok and window.workspace.status.text.contains(a) and
		window.workspace.status.text.contains("world"), "Atlas-launched instance tab shows origin identity")
	if mounted_instance.ok:
		var instance_session: DrawingObjectEditorSession = mounted_instance.value
		var instance_layer: String = window.workspace.current_layer()
		_check(_paint(instance_session.document, instance_layer, 0xff114488, Vector2i(14, 15)),
			"hosted editor paints with shared Drawing core")
		window.workspace._after_edit()
		var old_b: String = String(library.instance_info(a)["source_id"])
		window.workspace._ask_save()
		_check(window.workspace.variant_dialog.visible,
			"Atlas-hosted Save As asks for the new asset's display name and shows target Objects path")
		window.workspace.variant_name.text = "Standing stone variant gold"
		window.workspace.variant_dialog.hide()
		window.workspace._save_as_named_object()
		_check(library.asset_info(String(library.instance_info(a)["source_id"]))["name"] ==
			"Standing stone variant gold", "Save As uses the chosen label without renaming original")
		_check(library.instance_info(a)["source_id"] != old_b and
			library.instance_info(b)["source_id"] == source_id and
			window.workspace.current_object().source_id == library.instance_info(a)["source_id"] and
			window.workspace.current_object().origin_instance_id.is_empty(),
			"host UI Save As publishes variant and rebinds exactly A")
		window.workspace._request_close_current()
		_check(window.workspace.tabs.is_empty(), "saved variant tab closes without prompt")
	window.queue_free()
	bridge.release(tab)
	_delete_tree(directory)
	print("OBJECT_EDITOR_PASSED (%d checks; %d failed)" % [checks, failures])
	quit(0 if failures == 0 else 1)
