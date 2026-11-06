extends SceneTree
## T-060: real filesystem, two-map instance linkage, private Save and atomic Save As.

var checks: int = 0
var failed: int = 0
var working_dir: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error("OBJECT_ASSETS_FAILED: " + description)


func _paint(doc: DrawingDocument, layer: String, rgba: int,
		point: Vector2i = Vector2i(2, 3)) -> DrawingResult:
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begun.ok:
		return begun
	var session: DrawingEditSession = begun.value as DrawingEditSession
	var staged: DrawingResult = session.fill_rect(Rect2i(point, Vector2i.ONE), rgba)
	return session.commit() if staged.ok else staged


func _at(library: AtlasObjectLibrary, instance_id: String, point: Vector2i) -> int:
	var render: DrawingResult = library.render_instance(instance_id, Rect2i(point, Vector2i.ONE))
	if not render.ok or render.value.get("status", "") != "linked":
		return -1
	return (render.value["image"] as Image).get_data().decode_u32(0)


func _context(map_id: String, instance_id: String, asset_id: String) -> DrawingHistoryContext:
	var context: DrawingHistoryContext = DrawingHistoryContext.new()
	context.map_id = map_id
	context.floor_group_id = "ground"
	context.detail_group_id = "D0"
	context.selected_instance_id = instance_id
	context.asset_id = asset_id
	context.editor_mode = "object_source_edit"
	return context


func _save_json(path: String, content: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(content))
	file.close()


func _remove_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for name: String in directory.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func _run() -> void:
	working_dir = OS.get_cache_dir().path_join("drawinatlas-objects-%s" % DrawingDocument.new_id())
	var campaign: String = working_dir.path_join("Campaign.scn")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	var source: DrawingDocument = DrawingDocument.new("castle-document", 16)
	var group: String = String(source.create_layer(DrawingLayerNode.GROUP, "Buildings").value)
	var layer: String = String(source.create_layer(DrawingLayerNode.RASTER, "Castle", group).value)
	var text_layer: String = String(source.create_layer(DrawingLayerNode.TEXT, "Banner", group).value)
	var object_layer: String = String(source.create_layer(DrawingLayerNode.OBJECTS, "Decorations", group).value)
	_check(source.set_text(text_layer, "North tower — café 🏰").ok,
		"source has authored semantic text")
	_check(source.add_object(object_layer, {"position": Vector2(-3.5, 2.75),
		"tint": Color(0.25, 0.5, 0.75), "shape": "flag"}).ok,
		"source has typed semantic vector and color metadata")
	_check(_paint(source, layer, 0x00ff7788).ok, "prepare source with nonzero transparent RGB")
	_check(not library.load().ok, "missing index is visible, not silently treated as empty")
	var created: DrawingResult = library.create_asset(source, "Castle")
	_check(created.ok and library.asset_ids().size() == 1, "publish independent source")
	if not created.ok:
		quit(1)
		return
	var a_id: String = String(created.value)
	var path_a: String = library.asset_info(a_id)["path"]
	_check(path_a.begins_with("Objects/") and not path_a.contains(".."), "canonical portable asset path")
	_check(library.asset_exists(a_id), "immutable published asset file exists")
	var asset_handle: AtlasObjectAsset = library.asset_handle(a_id)
	_check(asset_handle.id == a_id and asset_handle.revision == 1 and \
		asset_handle.relative_path == path_a, "detached asset handle exposes stable source identity")
	asset_handle.name = "modified local handle"
	_check(library.asset_info(a_id)["name"] == "Castle", "asset handle cannot mutate registry state")
	var typed_source: DrawingDocument = library.begin_draft(a_id).value.document
	var loaded_children: Array[String] = typed_source.list_children(typed_source.list_children()[0])
	_check(typed_source.inspect_node(loaded_children[1]).text_value == "North tower — café 🏰",
		"portable Object source preserves Unicode text layers")
	var loaded_symbols: DrawingLayerNode = typed_source.inspect_node(loaded_children[2])
	var loaded_symbol: Dictionary = loaded_symbols.objects.values()[0]
	_check(loaded_symbol["position"] is Vector2 and loaded_symbol["position"] == Vector2(-3.5, 2.75) \
		and loaded_symbol["tint"] is Color,
		"portable source preserves typed semantic Vector2 and Color without lossy JSON strings")
	var semantic: DrawingResult = DrawingFileIO.encode(typed_source)
	var tampered: Dictionary = (semantic.value as Dictionary).duplicate(true)
	for record: Dictionary in tampered["document"]["layers"]:
		if record.has("objects_variant64"):
			record["objects_sha256"] = "faked-digest"
	_check(not DrawingFileIO.decode(tampered).ok,
		"tampered typed semantic payload is rejected before Variant decoding")
	_check(source.read_pixel(layer, 2, 3).value == 0x00ff7788,
		"source document stays detached from registered copy")
	var tr: Transform2D = Transform2D(0.25, Vector2(120, 70))
	var placed_a: DrawingResult = library.place(a_id, "world", "ground", "D0", tr)
	var placed_b: DrawingResult = library.place(a_id, "greyhaven", "upper", "D1",
		Transform2D(0.6, Vector2(8, -9)))
	_check(placed_a.ok and placed_b.ok, "placements on distinct maps")
	var ia: String = String(placed_a.value)
	var ib: String = String(placed_b.value)
	_check(ia != ib and library.instance_info(ia)["generation"] != library.instance_info(ib)["generation"],
		"instances and generations have distinct identity")
	_check(library.instances_for_asset(a_id) == [ia, ib] or library.instances_for_asset(a_id) == [ib, ia],
		"one source resolves multiple map placements")
	_check(library.instance_info(ia)["source_id"] == a_id and library.instance_info(ia)["map_id"] == "world",
		"origin placement persists context")
	_check(library.select_at("world", "ground", "D0", tr * Vector2(2.5, 3.5)).value.is_empty(),
		"alpha-zero source is not selected by map hit testing")
	var first: DrawingResult = library.render_instance(ia, Rect2i(2, 3, 1, 1))
	_check(first.ok and first.value["asset_revision"] == 1, "read-only render uses published source")
	_check(library.begin_draft(a_id).value.document.read_pixel(
		String(library.begin_draft(a_id).value.document.list_children(
			library.begin_draft(a_id).value.document.list_children()[0])[0]), 2, 3).value == 0x00ff7788,
		"saved document preserves exact RGBA8 hidden RGB")
	_check(library.hit_test(ia, tr * Vector2(2.5, 3.5)).ok,
		"native hit test accepts transformed world coordinate")
	_check(library.hit_test(ia, tr * Vector2(2.5, 3.5)).value == false,
		"fully transparent source is not a painted hit")
	var transparent_draft: DrawingResult = library.begin_draft(a_id)
	_check(transparent_draft.ok and transparent_draft.value is AtlasObjectDraft,
		"private draft opens with no Atlas dependency")
	var draft: AtlasObjectDraft = transparent_draft.value
	var clone_layer: String = String(draft.document.list_children(draft.document.list_children()[0])[0])
	_check(_paint(draft.document, clone_layer, 0xff123456).ok, "draft receives private painting")
	_check(_at(library, ia, Vector2i(2, 3)) == 0 \
		and _at(library, ib, Vector2i(2, 3)) == 0, "neither instance previews unsaved edits")
	var saved: DrawingResult = library.save_draft(draft)
	_check(saved.ok and saved.value == 2, "Save publishes next immutable revision")
	_check(_at(library, ia, Vector2i(2, 3)) == 0xff123456 \
		and _at(library, ib, Vector2i(2, 3)) == 0xff123456, "both maps resolve new source immediately")
	_check(library.asset_info(a_id)["revision"] == 2 and FileAccess.file_exists(working_dir.path_join(path_a)),
		"old revision retained for history")
	var moved: Dictionary = library.instance_info(ib)
	var new_tr: Transform2D = Transform2D(1.4, Vector2(-3, 22))
	_check(library.transform_instance(ib, moved["revision"], new_tr).ok,
		"per-instance rotation/position changes independently")
	_check(not library.transform_instance(ib, moved["revision"], tr).ok, "stale transform rejected")
	_check(library.instance_info(ia)["transform"] != library.instance_info(ib)["transform"],
		"transform change does not affect sibling")
	_check(library.asset_info(a_id)["revision"] == 2, "transforms never edit the asset")
	var metadata_info: Dictionary = library.instance_info(ib)
	_check(library.set_instance_metadata(ib, metadata_info["revision"], {"tag": "boss", "level": 4}).ok,
		"per-instance metadata is stored separately")
	_check(library.instance_info(ib)["metadata"]["tag"] == "boss" and \
		library.instance_info(ia)["metadata"].is_empty(), "metadata does not leak to sibling")
	_check(not library.set_instance_metadata(ib, library.instance_info(ib)["revision"], \
		{"raster_override": Vector2(3, 4)}).ok, "unsafe non-primitive overrides rejected")
	var visibility: Dictionary = library.instance_info(ib)
	_check(library.set_instance_visibility(ib, visibility["revision"], false).ok and \
		library.render_instance(ib, Rect2i(2, 3, 1, 1)).value["status"] == "hidden",
		"instance-only visibility controls rendering")
	visibility = library.instance_info(ib)
	_check(library.set_instance_visibility(ib, visibility["revision"], true).ok,
		"visibility can be restored without source edit")
	var opened_a: DrawingResult = library.begin_draft(a_id, ia)
	_check(opened_a.ok, "open Object Editor through originating instance A")
	var variant_draft: AtlasObjectDraft = opened_a.value
	var variant_layer: String = String(variant_draft.document.list_children(variant_draft.document.list_children()[0])[0])
	_check(_paint(variant_draft.document, variant_layer, 0xff998877, Vector2i(4, 5)).ok,
		"private Variant B changes remain unpublished")
	var campaign_model: AtlasCampaign = AtlasCampaign.sample()
	var timeline: AtlasEditHistory = AtlasEditHistory.new(campaign_model)
	timeline.active_map_id = "world"
	var restored: Array[DrawingHistoryContext] = []
	timeline.context_restorer = func(context: DrawingHistoryContext, _regions: Array[DrawingDirtyRegion]) -> bool:
		restored.append(context.detached_copy())
		return true
	var before: DrawingHistoryContext = _context("world", ia, a_id)
	var after: DrawingHistoryContext = _context("world", ia, "variant")
	var as_result: DrawingResult = library.save_as(variant_draft, timeline, before, after)
	_check(as_result.ok, "Save As through A publishes asset and binding in one Atlas history command")
	if not as_result.ok:
		print("OBJECT SAVE AS ERROR ", as_result.code, ": ", as_result.message)
		quit(1)
		return
	var b_id: String = String(as_result.value)
	_check(b_id != a_id and library.asset_ids().size() == 2, "Variant B independent stable asset ID")
	_check(library.instance_info(ia)["source_id"] == b_id and library.instance_info(ib)["source_id"] == a_id,
		"Save As rebinds only originating instance")
	_check(library.asset_info(b_id)["revision"] == 1 and _at(library, ia, Vector2i(4, 5)) == 0xff998877,
		"Variant B content saved and presented")
	_check(_at(library, ib, Vector2i(4, 5)) == 0, "original source unaffected by Save As")
	_check(timeline.can_undo() and timeline.is_dirty(), "global history includes one durable Save As")
	_check(timeline.undo(), "undo restores original instance binding")
	_check(library.instance_info(ia)["source_id"] == a_id and library.asset_ids().size() == 2,
		"undo retains reopenable B with no references")
	_check(timeline.is_dirty() and not restored.is_empty() and restored.back().selected_instance_id == ia,
		"undo preserves dirty retained variant and selected origin")
	_check(timeline.redo() and library.instance_info(ia)["source_id"] == b_id,
		"redo rebinds original saved B without duplication")
	_check(not restored.is_empty() and restored.back().asset_id == b_id and \
		restored.back().editor_mode == "object_source_edit",
		"redo context restores actual new asset ID, selected instance and editor mode")
	_check(timeline.undo() and library.asset_ids().size() == 2,
		"repeated undo never removes B")
	_check(library.instances_for_asset(b_id).is_empty(), "orphaned B remains in asset browser/library")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	var reopened_index: DrawingResult = reloaded.load()
	if not reopened_index.ok:
		print("RELOAD ERROR: ", reopened_index.code, " ", reopened_index.message)
	_check(reopened_index.ok and reloaded.asset_ids().size() == 2,
		"reopening after undo retains B and exact source linkage")
	if not reopened_index.ok:
		quit(1)
		return
	_check(reloaded.instance_info(ia)["source_id"] == a_id,
		"reloading after undo restores original binding")
	var unrelated: AtlasObjectLibrary = AtlasObjectLibrary.new(working_dir.path_join("OtherCampaign.scn"))
	_check(not unrelated.load().ok,
		"separate campaigns sharing an Objects folder do not inherit each other's registry")
	var free_draft: DrawingResult = reloaded.begin_draft(a_id)
	var independent: DrawingResult = reloaded.save_as(free_draft.value)
	_check(independent.ok and reloaded.asset_ids().size() == 3,
		"independent Save As saves a third asset")
	_check(reloaded.instance_info(ia)["source_id"] == a_id and reloaded.instance_info(ib)["source_id"] == a_id,
		"independent Save As touches no Atlas placement")
	var independent_asset: String = String(independent.value)
	_check(reloaded.asset_info(independent_asset)["id"] != a_id and independent_asset != b_id,
		"new independent copy has distinct identity")
	var independent_draft: AtlasObjectDraft = free_draft.value
	var standalone_layer: String = String(independent_draft.document.list_children(
		independent_draft.document.list_children()[0])[0])
	_check(_paint(independent_draft.document, standalone_layer, 0xff1144dd,
		Vector2i(-7, -8)).ok, "independent Save As keeps an editable private draft")
	var published_independent: DrawingResult = reloaded.begin_draft(independent_asset)
	var published_layer: String = String(published_independent.value.document.list_children(
		published_independent.value.document.list_children()[0])[0])
	_check(published_independent.value.document.read_pixel(published_layer, -7, -8).value == 0,
		"unsaved modifications to independent Save As never leak into library source")
	_check(reloaded.save_draft(independent_draft).ok and reloaded.asset_info(independent_asset)["revision"] == 2,
		"independent copy can be saved without modifying original source")
	_check(reloaded.begin_draft(independent_asset).value.document.read_pixel(published_layer, -7, -8).value == 0xff1144dd,
		"published independent copy contains new signed-negative raster content")
	_check(reloaded.begin_draft(a_id).value.document.read_pixel(
			String(reloaded.begin_draft(a_id).value.document.list_children(
				reloaded.begin_draft(a_id).value.document.list_children()[0])[0]), -7, -8).value == 0,
		"independent copy never aliases original pixels")
	var another_edit: DrawingResult = reloaded.begin_draft(a_id)
	var stale_edit: DrawingResult = reloaded.begin_draft(a_id)
	_check(reloaded.save_draft(another_edit.value).ok,
		"concurrent source publisher may save its revision")
	_check(not reloaded.save_draft(stale_edit.value).ok,
		"older draft cannot clobber a newer source")
	var competitor: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	_check(competitor.load().ok, "independent writer can read current index")
	var stale_origin: DrawingResult = reloaded.begin_draft(a_id, ia)
	var origin: Dictionary = reloaded.instance_info(ia)
	_check(reloaded.transform_instance(ia, origin["revision"], tr.translated(Vector2(1, 0))).ok,
		"concurrent placement edit changes binding revision")
	_check(not competitor.place(b_id, "world", "ground", "D0").ok,
		"stale second writer cannot overwrite published registry")
	_check(competitor.load().ok and competitor.place(b_id, "world", "ground", "D0").ok,
		"second writer can retry after explicitly reloading")
	_check(not reloaded.place(b_id, "world", "ground", "D0").ok and reloaded.load().ok,
		"first writer detects concurrent change and reloads before continuing")
	var new_timeline: AtlasEditHistory = AtlasEditHistory.new(campaign_model)
	new_timeline.active_map_id = "world"
	var before_index: Dictionary = reloaded.export_index()
	_check(not reloaded.save_as(stale_origin.value, new_timeline, before, after).ok \
		and reloaded.export_index() == before_index,
		"stale instance Save As rejects with zero registry/placement changes")
	var fresh: DrawingResult = reloaded.begin_draft(a_id, ia)
	reloaded.publication_guard = func() -> bool: return false
	before_index = reloaded.export_index()
	_check(not reloaded.save_as(fresh.value, new_timeline, before, after).ok \
		and reloaded.export_index() == before_index,
		"fault-injected index publication never half-rebinds an instance")
	reloaded.publication_guard = Callable()
	_check(reloaded.instance_info(ia)["generation"] == origin["generation"],
		"failed Save As never replaces instance generation")
	var retry: DrawingResult = reloaded.save_as(fresh.value, new_timeline, before, after)
	_check(retry.ok and reloaded.instance_info(ia)["source_id"] == retry.value,
		"retry after failed registry publication succeeds without an orphan-file collision")
	_check(new_timeline.undo() and reloaded.instance_info(ia)["source_id"] == a_id,
		"retry variant can be undone to original binding")
	_check(reloaded.delete_asset(String(retry.value), "remove").ok,
		"explicit deletion removes unreferenced variant registry identity")
	var state_before_redo: Dictionary = reloaded.export_index()
	_check(not new_timeline.redo() and reloaded.export_index() == state_before_redo,
		"redo refuses explicitly deleted B rather than recreating it")
	var old_transform: Array = reloaded.instance_info(ib)["transform"]
	var removed: DrawingResult = reloaded.delete_asset(a_id, "cancel")
	_check(removed.ok and reloaded.asset_ids().size() == 3, "cancel deletion is a no-op")
	removed = reloaded.delete_asset(a_id, "null")
	_check(removed.ok and not reloaded.asset_info(a_id), "NULL deletion removes published registry entry")
	_check(reloaded.instance_info(ib)["status"] == "NULL" and \
		reloaded.instance_info(ib)["transform"] == old_transform and \
		reloaded.instance_info(ib)["source_id"] == a_id,
		"NULL preserves asset key and exact instance transform")
	_check(reloaded.render_instance(ib, Rect2i(2, 3, 1, 1)).value["status"] == "NULL",
		"NULL renderer never asks nonexistent DrawingDocument for pixels")
	_check(reloaded.hit_test(ib, new_tr.origin).value["selectable"] == true,
		"missing-object placeholder remains selectable near its placement")
	_check(reloaded.hit_test(ib, new_tr.origin + Vector2(1000, 1000)).value["selectable"] == false,
		"missing-object placeholder does not capture clicks across entire map")
	_check(reloaded.select_at("greyhaven", "upper", "D1", new_tr.origin).value.has(ib),
		"NULL placement remains selectable within its map/floor/detail")
	_check(reloaded.load().ok and reloaded.instance_info(ib)["status"] == "NULL",
		"NULL placeholders and IDs survive a fresh reload")
	# Move the whole project folder and prove links are relative and portable.
	var renamed: String = working_dir + "-moved"
	_check(DirAccess.rename_absolute(working_dir, renamed) == OK, "move project directory")
	var portable: AtlasObjectLibrary = AtlasObjectLibrary.new(renamed.path_join("Campaign.scn"))
	_check(portable.load().ok and portable.asset_exists(b_id), "asset survives entire-directory relocation")
	_check(portable.instance_info(ib)["status"] == "NULL", "missing placeholder survives relocation")
	# Same-name file replacement must not silently rebind a source.
	var asset_b_path: String = renamed.path_join(portable.asset_info(b_id)["path"])
	# A symlink with a canonical filename is still an external path escape.
	var backup_path: String = asset_b_path + ".safe-test"
	_check(DirAccess.rename_absolute(asset_b_path, backup_path) == OK,
		"stage Object source for symlink-escape test")
	var asset_directory: DirAccess = DirAccess.open(asset_b_path.get_base_dir())
	var link_status: Error = asset_directory.create_link(backup_path, asset_b_path)
	_check(link_status == OK, "create candidate symlink in Object source directory")
	if link_status == OK:
		_check(not portable.asset_exists(b_id),
			"canonical path cannot use a symlink to a different asset file")
		_check(DirAccess.remove_absolute(asset_b_path) == OK,
			"remove object symlink after rejection")
	_check(DirAccess.rename_absolute(backup_path, asset_b_path) == OK,
		"restore source file after symlink test")
	var stolen: FileAccess = FileAccess.open(asset_b_path, FileAccess.WRITE)
	stolen.store_string("an unrelated file")
	stolen.close()
	_check(portable.instance_info(b_id).is_empty() and not portable.asset_exists(b_id),
		"replacement source rejected by saved digest")
	# Forged traversal path is rejected without reading outside Objects/.
	var index_path: String = renamed.path_join("Objects/Campaign.scn.atlas-object-index.json")
	var forged: Dictionary = portable.export_index()
	forged["assets"][0]["path"] = "Objects/../secret.drawing"
	_save_json(index_path, forged)
	var suspicious: AtlasObjectLibrary = AtlasObjectLibrary.new(renamed.path_join("Campaign.scn"))
	_check(not suspicious.load().ok, "malicious relative-path traversal rejected")
	print("OBJECT_ASSETS_PASSED (%d checks; %d failed)" % [checks, failed])
	if failed == 0:
		_remove_tree(renamed)
	quit(0 if failed == 0 else 1)
