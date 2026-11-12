extends SceneTree
## T-108: opt-in nested Save As policies; default editor behavior stays gated.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T108_POLICY_FAILED: " + description)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in directory.get_directories():
		_erase_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _source(label: String, rgba: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(label, 16)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if layer.ok:
		var begun: DrawingResult = doc.begin_edit(str(layer.value), doc.revision)
		if begun.ok:
			var edit: DrawingEditSession = begun.value
			if edit.fill_rect(Rect2i(-2, 3, 1, 1), rgba).ok:
				edit.commit()
	return doc


func _context(instance_id: String, source_id: String) -> DrawingHistoryContext:
	var ctx: DrawingHistoryContext = DrawingHistoryContext.new()
	ctx.map_id = "world"
	ctx.floor_group_id = "ground"
	ctx.detail_group_id = "D0"
	ctx.selected_instance_id = instance_id
	ctx.asset_id = source_id
	ctx.editor_mode = "object_source_edit"
	return ctx


func _pixel(library: AtlasObjectLibrary, id: String, point: Vector2i) -> Color:
	var pixels: DrawingResult = library.render_source_tree(id, Rect2i(point, Vector2i.ONE))
	if not pixels.ok:
		return Color.TRANSPARENT
	return (pixels.value as Image).get_pixel(0, 0)


func _run() -> void:
	var root: String = OS.get_cache_dir().path_join("t108-policy-" + DrawingDocument.new_id())
	var dest: String = root.path_join("portable")
	_check(DirAccess.make_dir_recursive_absolute(dest) == OK, "prepare portable-copy directory")
	_check(DirAccess.make_dir_recursive_absolute(root.path_join("source")) == OK,
		"prepare independent source directory")
	var campaign: String = root.path_join("source/Campaign.scn")
	var lib: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	var a: DrawingResult = lib.create_asset(_source("Parent", 0xff0000ff), "Parent")
	var b: DrawingResult = lib.create_asset(_source("Child", 0x00aa44ff), "Child")
	var c: DrawingResult = lib.create_asset(_source("Shared", 0xff00ff00), "Shared")
	_check(a.ok and b.ok and c.ok, "publish signed, hidden-RGB and opaque assets")
	if not (a.ok and b.ok and c.ok):
		quit(1)
		return
	var aid: String = str(a.value)
	var bid: String = str(b.value)
	var cid: String = str(c.value)
	var ab: DrawingResult = lib.attach_child(aid, 0, bid,
		Transform2D(0.0, Vector2(4, -1)))
	var bc: DrawingResult = lib.attach_child(bid, 0, cid,
		Transform2D(0.0, Vector2(-1, 2)))
	var ac: DrawingResult = lib.attach_child(aid, 1, cid,
		Transform2D(0.0, Vector2(-7, 1)))
	_check(ab.ok and bc.ok and ac.ok, "prepare shared grandchild DAG with signed transforms")
	_check(not lib.attach_child(cid, lib.children_revision(cid), aid).ok,
		"indirect A→B→C→A cycle is rejected without corrupting the published graph")
	var i1: DrawingResult = lib.place(aid, "world", "ground", "D0")
	var i2: DrawingResult = lib.place(aid, "other", "ground", "D0")
	_check(i1.ok and i2.ok, "prepare independent map placements")
	var null_source: DrawingResult = lib.create_asset(_source("Lost", 0xff123456), "Lost")
	_check(null_source.ok, "create source for explicit NULL tombstone")
	var null_id: String = str(null_source.value)
	var tombstone: DrawingResult = lib.attach_child(aid, lib.children_revision(aid), null_id)
	_check(tombstone.ok and lib.delete_asset(null_id, "null").ok and
		lib.children_for_asset(aid)[2]["status"] == "NULL",
		"published parent retains a deleted child's NULL identity")
	var refused_export: DrawingResult = lib.export_portable_source(aid,
		root.path_join("source/nested.drawing"), int(lib.asset_info(aid)["revision"]))
	_check(not refused_export.ok and refused_export.code == "NESTED_EXPORT" and
		not FileAccess.file_exists(root.path_join("source/nested.drawing")),
		"single-file nested export remains blocked; full portable component copy is separate")
	var source_index: Dictionary = lib.export_index()
	var default_draft: AtlasObjectDraft = lib.begin_draft(aid).value
	var impact: DrawingResult = lib.nested_save_as_impact(default_draft)
	_check(impact.ok and impact.value["deep_copy_new_sources"] == 3 and
		impact.value["links_new_sources"] == 1 and impact.value["child_instances"] == 4 and
		impact.value["null_instances"] == 1,
		"read-only impact distinguishes one linked copy from three deep source copies")
	_check(lib.export_index() == source_index, "preview has no disk/index/placement side effects")
	var blocked: DrawingResult = lib.save_as(default_draft)
	_check(not blocked.ok and blocked.code == "NESTED_SAVE_AS" and
		lib.export_index() == source_index, "normal Save As refuses undecided nested policy")
	var wrong: DrawingResult = lib.save_as(default_draft, null, null, null, "", "guess")
	_check(not wrong.ok and wrong.code == "NESTED_POLICY", "unknown policy is rejected")
	var linked: DrawingResult = lib.save_as(default_draft, null, null, null,
		"Linked Variant", "links")
	_check(linked.ok and lib.asset_ids().size() == 4, "explicit links creates only one new asset")
	if not linked.ok:
		quit(1)
		return
	var lid: String = str(linked.value)
	var linked_children: Array[Dictionary] = lib.children_for_asset(lid)
	_check(linked_children.size() == 3 and linked_children[0]["source_id"] == bid and
		linked_children[1]["source_id"] == cid and
		linked_children[0]["id"] != str(ab.value) and
		linked_children[0]["generation"] != lib.children_for_asset(aid)[0]["generation"],
		"linked policy preserves source IDs, but creates distinct child placement identities")
	_check(linked_children[2]["placeholder"] and
		linked_children[2]["source_id"] == null_id and
		linked_children[2]["id"] != str(tombstone.value),
		"linked copy preserves explicit NULL without adopting a missing source")
	_check(lib.children_for_asset(aid)[0]["id"] == str(ab.value) and
		lib.instance_info(str(i1.value))["source_id"] == aid,
		"independent Save As does not mutate original graph or Atlas bindings")
	var deep_draft: AtlasObjectDraft = lib.begin_draft(aid, str(i1.value)).value
	var timeline: AtlasEditHistory = AtlasEditHistory.new(AtlasCampaign.sample())
	timeline.active_map_id = "world"
	timeline.context_restorer = func(_context_arg: DrawingHistoryContext,
			_dirty_regions: Array[DrawingDirtyRegion]) -> bool:
		return true
	var deep: DrawingResult = lib.save_as(deep_draft, timeline,
		_context(str(i1.value), aid), _context(str(i1.value), "new"),
		"Independent Family", "deep_copy")
	_check(deep.ok and lib.asset_ids().size() == 7, "explicit deep-copy publishes 3 additional sources atomically")
	if not deep.ok:
		quit(1)
		return
	var did: String = str(deep.value)
	var family: Array[Dictionary] = lib.children_for_asset(did)
	var bcopy: String = str(family[0]["source_id"])
	var ccopy: String = str(family[1]["source_id"])
	_check(bcopy != bid and ccopy != cid and bcopy != ccopy and
		lib.children_for_asset(bcopy)[0]["source_id"] == ccopy,
		"deep-copy preserves shared descendant exactly once with fresh stable IDs")
	_check(lib.dependent_sources(ccopy).has(bcopy) and
		lib.dependent_sources(ccopy).has(did) and
		not lib.dependent_sources(ccopy).has(aid),
		"copied leaf invalidates only the detached deep-copy ancestry")
	var hidden_source: AtlasObjectDraft = lib.begin_draft(bid).value
	var hidden_copy: AtlasObjectDraft = lib.begin_draft(bcopy).value
	var hidden_source_layer: String = hidden_source.document.list_children()[0]
	var hidden_copy_layer: String = hidden_copy.document.list_children()[0]
	_check(hidden_source.document.read_pixel(hidden_source_layer, -2, 3).value == 0x00aa44ff and
		hidden_copy.document.read_pixel(hidden_copy_layer, -2, 3).value == 0x00aa44ff,
		"deep copy preserves exact hidden RGB with zero alpha")
	_check(family[2]["placeholder"] and family[2]["source_id"] == null_id and
		family[2]["id"] != str(tombstone.value),
		"deep copy retains missing-child tombstone without manufacturing an asset")
	_check(family[0]["id"] != str(ab.value) and family[0]["revision"] == 0 and
		family[0]["transform"] == lib.children_for_asset(aid)[0]["transform"],
		"copied nested placement has new ID and original signed geometry")
	_check(lib.instance_info(str(i1.value))["source_id"] == did and
		lib.instance_info(str(i2.value))["source_id"] == aid,
		"atomic deep Save As rebinds only selected Atlas origin")
	var deep_hit: DrawingResult = lib.hit_test_path(str(i1.value), Vector2(-8.5, 4.5))
	var original_hit: DrawingResult = lib.hit_test_path(str(i2.value), Vector2(-8.5, 4.5))
	_check(deep_hit.ok and original_hit.ok and deep_hit.value is Dictionary and
		original_hit.value is Dictionary and
		deep_hit.value.get("path") == PackedStringArray([str(family[1]["id"])]) and
		original_hit.value.get("path") == PackedStringArray([str(ac.value)]),
		"nested hit paths select the independent direct child in each parent family")
	_check(timeline.can_undo() and timeline.undo() and
		lib.instance_info(str(i1.value))["source_id"] == aid and lib.asset_exists(did),
		"Undo restores A, retaining independent nested B family in library")
	_check(timeline.redo() and lib.instance_info(str(i1.value))["source_id"] == did and
		lib.asset_ids().size() == 7, "Redo reuses retained nested copy without duplicating it")
	_check(lib.asset_info(cid).get("revision", -1) == 1,
		"original published leaf revision remains unchanged")
	var before_child: Color = _pixel(lib, lid, Vector2i(-9, 4))
	var child_draft: AtlasObjectDraft = lib.begin_draft(cid).value
	var raster: String = child_draft.document.list_children()[0]
	var edit: DrawingEditSession = child_draft.document.begin_edit(raster, child_draft.document.revision).value
	_check(edit.fill_rect(Rect2i(0, 0, 1, 1), 0xffee3311).ok and edit.commit().ok and
		lib.save_draft(child_draft).ok, "update original shared leaf after variants exist")
	_check(_pixel(lib, lid, Vector2i(-7, 1)).a > 0.99 and
		_pixel(lib, did, Vector2i(-7, 1)).a < 0.9,
		"original updates propagate through links but not into deep-copy descendants")
	_check(before_child.a > 0.0, "signed-position shared original rendered before update")
	var copy_draft: AtlasObjectDraft = lib.begin_draft(ccopy).value
	var clone_layer: String = copy_draft.document.list_children()[0]
	var clone_edit: DrawingEditSession = copy_draft.document.begin_edit(
		clone_layer, copy_draft.document.revision).value
	_check(clone_edit.fill_rect(Rect2i(0, 0, 1, 1), 0xff456789).ok and
		clone_edit.commit().ok and lib.save_draft(copy_draft).ok,
		"deep-copy leaf can publish an independent revision")
	_check(_pixel(lib, did, Vector2i(-7, 1)).a > 0.0 and
		_pixel(lib, aid, Vector2i(-7, 1)).a > 0.0,
		"independent and original parent previews resolve their respective leaves")
	var copy_result: DrawingResult = lib.copy_objects_to(dest.path_join("Campaign.scn"))
	_check(copy_result.ok, "portable project copy includes new nested family: %s %s" %
		[copy_result.code, copy_result.message])
	if not copy_result.ok:
		print("T108_PORTABLE_COPY_ERROR: ", copy_result.code, " ", copy_result.message)
		quit(1)
		return
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(dest.path_join("Campaign.scn"))
	_check(reloaded.load().ok and reloaded.asset_ids().size() == 7 and
		reloaded.children_for_asset(bcopy)[0]["source_id"] == ccopy,
		"portable reload preserves copied IDs, shared descendant and hierarchy")
	_check(reloaded.instance_info(str(i1.value))["source_id"] == did and
		reloaded.instance_info(str(i2.value))["source_id"] == aid,
		"portable reload preserves both independent Atlas bindings")
	var before_failure: Dictionary = lib.export_index()
	var index_file: String = root.path_join("source/Objects/Campaign.scn.atlas-object-index.json")
	var original_sha: String = FileAccess.get_sha256(index_file)
	var directory: DirAccess = DirAccess.open(root.path_join("source/Objects"))
	var before_dirs: PackedStringArray = directory.get_directories()
	before_dirs.sort()
	lib.publication_guard = func() -> bool: return false
	var rejected: DrawingResult = lib.save_as(lib.begin_draft(aid).value,
		null, null, null, "Rejected", "deep_copy")
	_check(not rejected.ok and rejected.code == "PUBLISH" and
		lib.export_index() == before_failure and FileAccess.get_sha256(index_file) == original_sha,
		"late index rejection leaves no partially published nested family")
	var after_dirs: PackedStringArray = directory.get_directories()
	after_dirs.sort()
	_check(before_dirs == after_dirs,
		"failed multi-source publication cleans staged revision directories")
	lib.publication_guard = Callable()
	var stale: AtlasObjectDraft = lib.begin_draft(aid).value
	var attached_again: DrawingResult = lib.attach_child(aid,
		lib.children_revision(aid), bid)
	_check(attached_again.ok and not lib.save_as(stale, null, null, null, "Stale", "links").ok,
		"child graph change invalidates stale nested Save As draft")
	var recovery: DrawingResult = lib.save_as(lib.begin_draft(aid).value,
		null, null, null, "Retry", "links")
	_check(recovery.ok and lib.asset_ids().size() == 8,
		"fresh draft retries safely after failed publication and graph conflict")
	var missing_before: Dictionary = lib.export_index()
	var leaf_path: String = root.path_join("source").path_join(str(lib.asset_info(cid)["path"]))
	_check(DirAccess.remove_absolute(leaf_path) == OK,
		"simulate lost published child revision")
	var missing: DrawingResult = lib.save_as(lib.begin_draft(aid).value,
		null, null, null, "Unsafe", "deep_copy")
	_check(not missing.ok and missing.code == "MISSING_SOURCE" and
		lib.export_index() == missing_before,
		"missing published child rejects deep copy with no partial registry mutation")
	var output: String = "T108_POLICY_PASSED (%d checks; %d failed)" % [checks, failures]
	if failures == 0:
		_erase_tree(root)
	print(output)
	quit(0 if failures == 0 else 1)
