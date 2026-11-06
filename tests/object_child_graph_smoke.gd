extends SceneTree
## T-064 first milestone: transactional child source references and safe reload.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("T064_CHILD_GRAPH_FAILED: " + description)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in directory.get_directories():
		_erase_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _child(source_id: String, id: String) -> Dictionary:
	return {"id": id, "generation": "generation-" + id,
		"source_id": source_id, "transform": [1, 0, 0, 1, -12, 32],
		"visible": true, "placeholder": false, "revision": 0, "metadata": {}}


func _graph_record(id: String, children: Array = []) -> Dictionary:
	return {"id": id, "children": children}


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t064-graph-" + DrawingDocument.new_id())
	var campaign: String = folder.path_join("Campaign.scn")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	var source: DrawingDocument = DrawingDocument.new("t064-pixels", 16)
	var group: DrawingResult = source.create_layer(DrawingLayerNode.GROUP, "Group")
	_check(group.ok, "prepare reusable Drawing source")
	var a: DrawingResult = library.create_asset(source, "Parent A")
	var b: DrawingResult = library.create_asset(source, "Child B")
	var c: DrawingResult = library.create_asset(source, "Grandchild C")
	_check(a.ok and b.ok and c.ok, "publish three independent source documents")
	if not a.ok or not b.ok or not c.ok:
		quit(1)
		return
	var aid: String = str(a.value)
	var bid: String = str(b.value)
	var cid: String = str(c.value)
	_check(library.children_for_asset(aid).is_empty() and library.children_revision(aid) == 0,
		"old flat source has empty child list without migration")
	var ab: DrawingResult = library.attach_child(aid, 0, bid,
		Transform2D(0.5, Vector2(-11, 13)))
	_check(ab.ok, "attach reusable source under parent without rasterizing")
	var bc: DrawingResult = library.attach_child(bid, 0, cid)
	_check(bc.ok, "attach grandchild into second parent")
	var parents_of_c: Array[String] = [aid, bid]
	parents_of_c.sort()
	var child_id: String = str(ab.value)
	var items: Array[Dictionary] = library.children_for_asset(aid)
	_check(items.size() == 1 and items[0]["id"] == child_id \
		and items[0]["status"] == "linked", "stable child identity is visible")
	_check(is_equal_approx(float(items[0]["transform"][0]), cos(0.5)) and \
		is_equal_approx(float(items[0]["transform"][1]), sin(0.5)) and \
		items[0]["transform"][4] == -11.0 and items[0]["transform"][5] == 13.0,
		"parent-local transform is serialized exactly")
	_check(library.children_revision(aid) == 1 and library.asset_info(aid)["revision"] == 1,
		"graph edits advance separate optimistic revision without mutating source pixels")
	_check(library.dependent_sources(cid) == parents_of_c,
		"reverse dependencies propagate from a grandchild to both ancestors")
	_check(library.dependent_sources(bid) == [aid], "direct reverse dependency")
	_check(library.dependent_sources(aid).is_empty(), "root has no dependents")
	var copy: Array[Dictionary] = library.children_for_asset(aid)
	copy[0]["transform"][4] = 1234
	_check(library.children_for_asset(aid)[0]["transform"][4] == -11.0,
		"child data returned to editor is detached from registry")
	var opened: DrawingResult = library.begin_draft(aid)
	_check(opened.ok, "open existing source with nested references in independent draft")
	var draft: AtlasObjectDraft = opened.value
	var original_children: Array[Dictionary] = library.children_for_asset(aid)
	var saved_pixels: DrawingResult = library.save_draft(draft)
	_check(saved_pixels.ok and library.asset_info(aid)["revision"] == 2,
		"publishing pixels advances immutable source revision")
	_check(library.children_for_asset(aid) == original_children and library.children_revision(aid) == 1,
		"pixel Save preserves the exact nested child graph and its revision")
	_check(not library.save_as(draft).ok and not library.export_portable_source(aid,
		folder.path_join("unsupported-nested.drawing")).ok,
		"unfinished Save As/export child-copy policies refuse loss of nested references")
	_check(not FileAccess.file_exists(folder.path_join("unsupported-nested.drawing")),
		"failed nested export creates no silently flattened portable file")
	var before: Dictionary = library.export_index()
	var ca: DrawingResult = library.attach_child(cid, 0, aid)
	_check(not ca.ok and ca.code == "CHILD_CYCLE" and library.export_index() == before,
		"indirect source cycle is rejected atomically")
	var self_edge: DrawingResult = library.attach_child(cid, 0, cid)
	_check(not self_edge.ok and self_edge.code == "CHILD_CYCLE",
		"self reference is rejected")
	_check(not library.attach_child(aid, 0, cid).ok,
		"stale parent graph revision cannot add a second child")
	_check(not library.attach_child(cid, 0, "absent-id").ok,
		"new child must name a currently published source")
	_check(not library.attach_child(cid, 0, aid,
		Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)).ok,
		"singular child transform is not accepted")
	var same: DrawingResult = library.attach_child(aid, 1, bid)
	_check(same.ok and library.children_for_asset(aid).size() == 2,
		"a source may occur twice under the same parent as distinct instances")
	var second_id: String = str(same.value)
	_check(second_id != child_id and library.children_for_asset(aid)[1]["generation"] \
		!= library.children_for_asset(aid)[0]["generation"],
		"two references have independent immutable IDs/generations")
	var moved: DrawingResult = library.transform_child(aid, child_id, 2,
		Transform2D(1.25, Vector2(200, -45)))
	_check(moved.ok and library.children_revision(aid) == 3,
		"transform child transaction advances parent graph revision")
	items = library.children_for_asset(aid)
	_check(items[0]["revision"] == 1 and items[0]["transform"][4] == 200.0 \
		and items[1]["revision"] == 0,
		"transform edit preserves sibling revision and identity")
	_check(not library.transform_child(aid, child_id, 2, Transform2D.IDENTITY).ok,
		"stale child transform update is refused")
	var stale_reader: AtlasObjectLibrary = AtlasObjectLibrary.new(campaign)
	_check(stale_reader.load().ok and stale_reader.children_revision(aid) == 3,
		"new library reloads versioned nested references")
	var removed: DrawingResult = library.detach_child(aid, second_id, 3)
	_check(removed.ok and library.children_for_asset(aid).size() == 1,
		"removing one instance retains other same-source child")
	_check(not stale_reader.attach_child(aid, 3, cid).ok and \
		stale_reader.children_for_asset(aid).size() == 2,
		"optimistic index lease prevents a stale library committing")
	var frozen: Dictionary = library.export_index()
	library.publication_guard = func() -> bool: return false
	var denied: DrawingResult = library.attach_child(aid, 4, cid)
	_check(not denied.ok and denied.code == "PUBLISH" and library.export_index() == frozen,
		"a rejected index replacement leaves the graph and revisions untouched")
	library.publication_guard = Callable()
	var after: Dictionary = library.export_index()
	var relocated: String = folder + "-moved"
	_check(DirAccess.rename_absolute(folder, relocated) == OK,
		"portable campaign relocation succeeds")
	var portable: AtlasObjectLibrary = AtlasObjectLibrary.new(relocated.path_join("Campaign.scn"))
	_check(portable.load().ok and portable.children_for_asset(aid).size() == 1,
		"child graph resolves by stable IDs after directory relocation")
	_check(portable.dependent_sources(cid) == parents_of_c,
		"reverse edges survive saved-file reload")
	var invalid: Dictionary = after.duplicate(true)
	for asset: Dictionary in invalid["assets"]:
		if asset["id"] == cid:
			asset["children"] = [_child(aid, "cycle-new")]
	var original: Dictionary = portable.export_index()
	var broken: DrawingResult = portable.load_snapshot(invalid)
	_check(not broken.ok and broken.code == "CHILD_CYCLE",
		"corrupted cyclic snapshot is rejected before replacing loaded state")
	_check(portable.export_index() == original,
		"rejected snapshot does not mutate loaded sources or references")
	var bad_id: Dictionary = original.duplicate(true)
	for asset: Dictionary in bad_id["assets"]:
		if asset["id"] == bid:
			asset["children"] = [_child(cid, child_id)]
	_check(not portable.load_snapshot(bad_id).ok,
		"child IDs are globally unique, including across parents")
	var invalid_transform: Dictionary = original.duplicate(true)
	for asset: Dictionary in invalid_transform["assets"]:
		if asset["id"] == aid:
			asset["children"][0]["transform"] = [1, 0, 0, 0, 0, 0]
	_check(not portable.load_snapshot(invalid_transform).ok,
		"noninvertible nested transform cannot be loaded")
	var stale_delete: DrawingResult = portable.preview_delete_asset(bid)
	_check(stale_delete.ok and stale_delete.value["child_bindings"].size() == 1,
		"destructive preview captures the parent-child binding")
	var child_changed: DrawingResult = portable.transform_child(aid, child_id,
		portable.children_revision(aid), Transform2D(0.75, Vector2(-3, 6)))
	_check(child_changed.ok, "nested transform can change after confirmation opened")
	var stale_policy: DrawingResult = portable.delete_asset(bid, "remove", stale_delete.value)
	_check(not stale_policy.ok and stale_policy.code == "STALE_SOURCE" and portable.asset_exists(bid),
		"stale nested delete confirmation is rejected with no lost child binding")
	var delete_preview: DrawingResult = portable.preview_delete_asset(cid)
	_check(delete_preview.ok and delete_preview.value["child_bindings"].size() == 1,
		"delete preview counts nested child references alongside map placements")
	_check(portable.delete_asset(cid, "cancel", delete_preview.value).ok and portable.asset_exists(cid),
		"explicit Cancel never modifies nested child bindings")
	var missing: DrawingResult = portable.delete_asset(cid, "null", delete_preview.value)
	_check(missing.ok, "NULL deletion retains nested child as a placeholder")
	_check(portable.children_for_asset(bid)[0]["status"] == "NULL",
		"dangling child reference stays inspectable as a NULL proxy")
	_check(portable.children_for_asset(aid)[0]["status"] == "linked",
		"other unrelated parent child remains linked")
	var reload_missing: AtlasObjectLibrary = AtlasObjectLibrary.new(relocated.path_join("Campaign.scn"))
	_check(reload_missing.load().ok and reload_missing.children_for_asset(bid)[0]["status"] == "NULL",
		"NULL child remains nonrecursive and safe after reload")
	_check(reload_missing.children_for_asset(bid)[0]["placeholder"] and \
		reload_missing.children_for_asset(bid)[0]["revision"] == 1,
		"NULL deletion advances the child revision without changing stable identity")
	var removal_preview: DrawingResult = reload_missing.preview_delete_asset(bid)
	_check(removal_preview.ok and removal_preview.value["child_bindings"].size() == 1,
		"second source deletion previews parent-owned nested bindings")
	var removed_source: DrawingResult = reload_missing.delete_asset(bid, "remove", removal_preview.value)
	_check(removed_source.ok and reload_missing.children_for_asset(aid).is_empty(),
		"Remove policy deletes references from other parents atomically")
	var removed_reopened: AtlasObjectLibrary = AtlasObjectLibrary.new(relocated.path_join("Campaign.scn"))
	_check(removed_reopened.load().ok and removed_reopened.children_for_asset(aid).is_empty(),
		"nested remove persists without resurrecting references on reload")
	# Pure graph stress cases: exact depth limit, cyclic loads, malformed child
	# arrays and caps are all checked without generating thousands of files.
	var graph: Dictionary = {}
	for index: int in range(18):
		var name: String = "chain-%02d" % index
		graph[name] = _graph_record(name, [_child("chain-%02d" % (index + 1),
			"link-%02d" % index)] if index < 17 else [])
	_check(not AtlasObjectChildGraph.validate(graph).ok,
		"17 nested edges exceed the provisional 16-level render budget")
	graph["chain-16"]["children"] = []
	_check(AtlasObjectChildGraph.validate(graph).ok,
		"depth of 16 edges is permitted without recursive stack use")
	graph["chain-16"]["children"] = [_child("chain-01", "cycle-short")]
	_check(not AtlasObjectChildGraph.validate(graph).ok,
		"a cycle in an otherwise bounded graph is rejected")
	var oversized: Dictionary = {"parent": _graph_record("parent", [])}
	for index: int in range(65):
		oversized["parent"]["children"].append(_child("missing-source", "oversized-%d" % index))
	_check(not AtlasObjectChildGraph.validate(oversized).ok,
		"per-parent child cap rejects pathological nested lists")
	var malformed: Dictionary = {"parent": _graph_record("parent", [_child("missing", "x")])}
	malformed["parent"]["children"][0]["metadata"] = {"invalid": Vector2.ONE}
	_check(not AtlasObjectChildGraph.validate(malformed).ok,
		"nonportable child metadata is refused")
	print("T064_CHILD_GRAPH_PASSED (%d checks; %d failed)" % [checks, failures])
	if failures == 0:
		_erase_tree(relocated)
	quit(0 if failures == 0 else 1)
