extends SceneTree
## T-064: an independent campaign Objects copy must retain nested IDs, pixels,
## transforms, placements and NULL records without mutating the source campaign.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_PROJECT_COPY_FAILED: " + label)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(filename))
	for folder: String in directory.get_directories():
		_erase_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)


func _source(name: String, rgba: int) -> DrawingDocument:
	var source: DrawingDocument = DrawingDocument.new(name, 16)
	var layer: DrawingResult = source.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not layer.ok:
		push_error("T064_PROJECT_COPY_FAILED: source layer")
		return source
	var edit: DrawingEditSession = source.begin_edit(str(layer.value), source.revision).value
	if not edit.fill_rect(Rect2i(0, 0, 1, 1), rgba).ok or not edit.commit().ok:
		push_error("T064_PROJECT_COPY_FAILED: source pixel")
	return source


func _pixel_at(library: AtlasObjectLibrary, parent_id: String, point: Vector2i) -> Color:
	var region: Rect2i = Rect2i(point, Vector2i.ONE)
	var rendered: DrawingResult = library.render_source_tree(parent_id, region)
	if not rendered.ok:
		return Color.TRANSPARENT
	return (rendered.value as Image).get_pixel(0, 0)


func _run() -> void:
	var root: String = OS.get_cache_dir().path_join("t064-project-copy-" + DrawingDocument.new_id())
	var original_dir: String = root.path_join("source")
	var clone_dir: String = root.path_join("copied")
	var collision_dir: String = root.path_join("collision")
	var stale_dir: String = root.path_join("stale")
	_check(DirAccess.make_dir_recursive_absolute(original_dir) == OK and \
		DirAccess.make_dir_recursive_absolute(clone_dir) == OK and \
		DirAccess.make_dir_recursive_absolute(collision_dir) == OK and \
		DirAccess.make_dir_recursive_absolute(stale_dir) == OK, "prepare independent project directories")
	var original: AtlasObjectLibrary = AtlasObjectLibrary.new(original_dir.path_join("Campaign.scn"))
	var parent: DrawingResult = original.create_asset(_source("parent", 0xff0000ff), "Parent")
	var child: DrawingResult = original.create_asset(_source("child", 0xff00ff00), "Child")
	var leaf: DrawingResult = original.create_asset(_source("leaf", 0xffff0000), "Leaf")
	_check(parent.ok and child.ok and leaf.ok, "publish three independently versioned sources")
	if not parent.ok or not child.ok or not leaf.ok:
		quit(1)
		return
	var aid: String = str(parent.value)
	var bid: String = str(child.value)
	var cid: String = str(leaf.value)
	var ab: DrawingResult = original.attach_child(aid, 0, bid,
		Transform2D(0.0, Vector2(5, -3)))
	var bc: DrawingResult = original.attach_child(bid, 0, cid,
		Transform2D(0.0, Vector2(-2, 4)))
	var ac: DrawingResult = original.attach_child(aid, 1, cid,
		Transform2D(0.0, Vector2(-11, 8)))
	_check(ab.ok and bc.ok and ac.ok, "publish a branching, reusable nested graph")
	var placement: DrawingResult = original.place(aid, "world", "ground", "D0",
		Transform2D(0.0, Vector2(20, 10)))
	_check(placement.ok, "publish independent Atlas map placement")
	var initial: Dictionary = original.export_index()
	_check(_pixel_at(original, aid, Vector2i(3, 1)).b > 0.9 and \
		_pixel_at(original, aid, Vector2i(5, -3)).g > 0.9,
		"source graph composes shared child/grandchild with signed offsets")
	var result: DrawingResult = original.copy_objects_to(clone_dir.path_join("Campaign.scn"))
	_check(result.ok and result.value is Dictionary and result.value.get("sources") == 3 \
		and result.value.get("placements") == 1, "publish a complete independent Objects copy")
	_check(original.export_index() == initial, "copy does not mutate original registry")
	var copy: AtlasObjectLibrary = AtlasObjectLibrary.new(clone_dir.path_join("Campaign.scn"))
	_check(copy.load().ok, "load clone using destination campaign-relative registry path")
	_check(FileAccess.get_sha256(original_dir.path_join("Objects/Campaign.scn.atlas-object-index.json")) ==
		FileAccess.get_sha256(clone_dir.path_join("Objects/Campaign.scn.atlas-object-index.json")),
		"copy preserves the exact canonical index bytes, references and IDs")
	_check(copy.children_revision(aid) == 2 and copy.children_revision(bid) == 1 and \
		copy.children_for_asset(aid).size() == 2, "parent child revisions and sibling order survive copy")
	_check(copy.children_for_asset(aid)[0]["id"] == str(ab.value) and \
		copy.children_for_asset(aid)[1]["id"] == str(ac.value) and \
		copy.children_for_asset(bid)[0]["id"] == str(bc.value),
		"each child instance ID and its ordering survive copy")
	var expected_dependents: Array[String] = [aid, bid]
	expected_dependents.sort()
	_check(copy.dependent_sources(cid) == expected_dependents,
		"reverse references remain valid across shared parents")
	_check(copy.instance_info(str(placement.value)) == original.instance_info(str(placement.value)),
		"map placement retains ID, generation, world transform and source binding")
	_check(_pixel_at(copy, aid, Vector2i(3, 1)).b > 0.9 and \
		_pixel_at(copy, aid, Vector2i(5, -3)).g > 0.9 and \
		_pixel_at(copy, aid, Vector2i(-11, 8)).b > 0.9,
		"copied project renders nested source pixels at identical positions")
	var hit: DrawingResult = copy.hit_test_path(str(placement.value), Vector2(23.5, 11.5))
	_check(hit.ok and hit.value is Dictionary and \
		hit.value["path"] == PackedStringArray([str(ab.value), str(bc.value)]),
		"copied project resolves the same stable grandchild hit path")
	var copy_info: Dictionary = copy.asset_info(cid)
	_check(copy.asset_exists(cid) and FileAccess.file_exists(clone_dir.path_join(str(copy_info["path"]))) \
		and FileAccess.get_sha256(clone_dir.path_join(str(copy_info["path"]))) == str(copy_info["sha256"]),
		"copied immutable revision has the exact published digest")
	var draft_result: DrawingResult = copy.begin_draft(cid)
	_check(draft_result.ok, "clone opens its own detached source draft")
	var draft: AtlasObjectDraft = draft_result.value
	var raster_id: String = draft.document.list_children()[0]
	var edit: DrawingEditSession = draft.document.begin_edit(raster_id, draft.document.revision).value
	_check(edit.fill_rect(Rect2i(1, 0, 1, 1), 0xffffffff).ok and edit.commit().ok,
		"edit pixels in cloned child source")
	_check(copy.save_draft(draft).ok and copy.asset_info(cid)["revision"] == 2,
		"clone publishes a new immutable child source revision")
	_check(_pixel_at(copy, aid, Vector2i(4, 1)).a > 0.9 and \
		_pixel_at(original, aid, Vector2i(4, 1)).a == 0.0,
		"clone edits propagate to cloned ancestors only")
	_check(original.asset_info(cid)["revision"] == 1 and original.export_index() == initial,
		"original source revision and nested graph remain untouched")
	var reloaded: AtlasObjectLibrary = AtlasObjectLibrary.new(clone_dir.path_join("Campaign.scn"))
	_check(reloaded.load().ok and reloaded.asset_info(cid)["revision"] == 2,
		"copied project remains independent after fresh process-style reload")
	_check(_pixel_at(reloaded, aid, Vector2i(4, 1)).a > 0.9,
		"reloaded graph resolves the latest cloned child pixels")
	var duplicate: DrawingResult = original.copy_objects_to(clone_dir.path_join("Campaign.scn"))
	_check(not duplicate.ok and duplicate.code == "COPY_EXISTS" and \
		reloaded.asset_info(cid)["revision"] == copy.asset_info(cid)["revision"],
		"existing destination is rejected without overwriting its edits")
	_check(not original.copy_objects_to(original_dir.path_join("Other.scn")).ok,
		"source project cannot overwrite its own Objects component")
	_check(not original.copy_objects_to(original_dir.path_join("Objects/inside/Campaign.scn")).ok,
		"cannot place destination within source Object data")
	_check(not original.copy_objects_to(root.path_join("missing/Campaign.scn")).ok and \
		not DirAccess.dir_exists_absolute(root.path_join("missing")),
		"missing destination directory is rejected without creating it")
	_check(DirAccess.make_dir_absolute(collision_dir.path_join("Objects")) == OK,
		"reserve preexisting destination Objects directory")
	_check(not original.copy_objects_to(collision_dir.path_join("Campaign.scn")).ok and \
		not FileAccess.file_exists(collision_dir.path_join("Objects/Campaign.scn.atlas-object-index.json")),
		"preexisting Objects directory is never adopted or modified")
	var removed: DrawingResult = copy.delete_asset(cid, "null")
	_check(removed.ok and copy.children_for_asset(aid)[1]["status"] == "NULL" and \
		copy.children_for_asset(bid)[0]["status"] == "NULL",
		"copy preserves existing Remove/NULL semantics independently")
	_check(AtlasObjectLibrary.new(clone_dir.path_join("Campaign.scn")).load().ok and \
		original.children_for_asset(bid)[0]["status"] == "linked",
		"clone NULL records do not rewrite source project child links")
	var corrupt_dir: String = root.path_join("corrupted")
	_check(DirAccess.make_dir_absolute(corrupt_dir) == OK,
		"prepare destination for rejected checksum copy")
	var copied_child_path: String = clone_dir.path_join(str(copy.asset_info(bid)["path"]))
	var copied_child: FileAccess = FileAccess.open(copied_child_path, FileAccess.READ_WRITE)
	_check(copied_child != null, "open isolated copied source for corruption test")
	if copied_child != null:
		copied_child.store_8(0)
		copied_child.close()
	var corrupted_copy: DrawingResult = copy.copy_objects_to(corrupt_dir.path_join("Campaign.scn"))
	_check(not corrupted_copy.ok and corrupted_copy.code == "MISSING_SOURCE" and \
		not DirAccess.dir_exists_absolute(corrupt_dir.path_join("Objects")),
		"modified published bytes are never adopted by a second project copy")
	_check(original.asset_exists(bid), "copy corruption never alters source project bytes")
	var source_index: String = original_dir.path_join("Objects/Campaign.scn.atlas-object-index.json")
	var before_hash: String = FileAccess.get_sha256(source_index)
	var index_file: FileAccess = FileAccess.open(source_index, FileAccess.WRITE)
	index_file.store_string("malformed index external update")
	index_file.close()
	var stale_copy: DrawingResult = original.copy_objects_to(stale_dir.path_join("Campaign.scn"))
	_check(not stale_copy.ok and stale_copy.code == "STALE_INDEX" and \
		not DirAccess.dir_exists_absolute(stale_dir.path_join("Objects")),
		"stale/corrupt registry refuses copy with no destination published")
	_check(FileAccess.get_sha256(source_index) != before_hash,
		"stale rejection is based on changed registry bytes")
	var output: String = "T064_PROJECT_COPY_PASSED (%d checks; %d failed)" % [checks, failures]
	if failures == 0:
		_erase_tree(root)
	print(output)
	quit(0 if failures == 0 else 1)
