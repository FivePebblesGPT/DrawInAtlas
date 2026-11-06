extends SceneTree
## T-064: a complete portable project copy preserves old generations, retained
## nested source revisions and sparse Drawing bytes, publishing all-or-nothing.

var checks: int = 0
var failures: int = 0
var folder: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T064_CAMPAIGN_COPY_FAILED: " + name)


func _source(label: String, color: int) -> DrawingDocument:
	var doc: DrawingDocument = DrawingDocument.new(label, 16)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Pixels").value)
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	if edit.fill_rect(Rect2i(0, 0, 1, 1), color).ok:
		edit.commit()
	return doc


func _paint(doc: DrawingDocument, layer: String, position: Vector2i,
		bytes: PackedByteArray) -> bool:
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision,
		Transform2D.IDENTITY, position.x, position.y)
	return begun.ok and begun.value.apply_region(Rect2i(0, 0, 1, 1), bytes).ok \
		and begun.value.commit().ok


func _copy_files_count(source: String, target: String) -> int:
	var result: DrawingResult = AtlasCampaignStore.copy_portable(source, target)
	_check(result.ok, "copy fully published, verified project: " + result.code + " " + result.message)
	return int(result.value.get("files", 0)) if result.ok else 0


func _run() -> void:
	folder = OS.get_cache_dir().path_join("t064-campaign-copy-" + DrawingDocument.new_id())
	var original: String = folder.path_join("original")
	var source_path: String = original.path_join("World.scn")
	var destination: String = folder.path_join("travelled")
	var dest_path: String = destination.path_join("NewWorld.scn")
	_check(DirAccess.make_dir_recursive_absolute(original) == OK,
		"create fresh source project folder")
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	_check(registry.attach_campaign(campaign).ok, "attach sparse campaign registry")
	var doc: DrawingDocument = registry.document_at("world", "ground", 0, true).value
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Far pixels").value)
	_check(_paint(doc, layer, Vector2i(-511, 1023), PackedByteArray([12, 34, 56, 0])),
		"record signed sparse pixel including hidden RGB")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(source_path)
	var p: DrawingResult = library.create_asset(_source("nested parent", 0xff0000ff), "Parent")
	var c: DrawingResult = library.create_asset(_source("nested child", 0xff00ff00), "Child")
	var l: DrawingResult = library.create_asset(_source("nested leaf", 0xffff0000), "Leaf")
	_check(p.ok and c.ok and l.ok, "publish independent parent/child/grandchild sources")
	if not p.ok or not c.ok or not l.ok:
		quit(1)
		return
	var parent_id: String = str(p.value)
	var child_id: String = str(c.value)
	var leaf_id: String = str(l.value)
	var grandchild: DrawingResult = library.attach_child(child_id, 0, leaf_id,
		Transform2D(0.0, Vector2(4.0, -5.0)))
	_check(grandchild.ok, "publish second-level nested dependency")
	var attached: DrawingResult = library.attach_child(parent_id, 0, child_id,
		Transform2D(0.0, Vector2(-3.0, 4.0)))
	var placed: DrawingResult = library.place(parent_id, "world", "ground", "D0",
		Transform2D(0.0, Vector2(20.0, -6.0)))
	_check(attached.ok and placed.ok, "publish linked child and top-level placement")
	var first: DrawingResult = AtlasCampaignBundle.save(campaign, registry, library, source_path)
	_check(first.ok, "first complete generation published: " + first.message)
	if not first.ok:
		quit(1)
		return
	var first_generation: String = str(first.value["generation"])
	var draft_result: DrawingResult = library.begin_draft(child_id)
	_check(draft_result.ok, "open detached child source draft")
	var draft: AtlasObjectDraft = draft_result.value
	var source_layer: String = draft.document.list_children()[0]
	var edit: DrawingEditSession = draft.document.begin_edit(source_layer, draft.document.revision).value
	_check(edit.fill_rect(Rect2i(1, 0, 1, 1), 0xffffffff).ok and edit.commit().ok,
		"edit child without changing source identity")
	_check(library.save_draft(draft).ok, "publish new child source revision")
	_check(_paint(doc, layer, Vector2i(2051, -3000), PackedByteArray([99, 101, 103, 255])),
		"add second sparse pixel in another chunk")
	var second: DrawingResult = AtlasCampaignBundle.save(campaign, registry, library, source_path)
	_check(second.ok, "second generation publishes current Object and Drawing revisions")
	if not second.ok:
		quit(1)
		return
	var source_root: String = AtlasCampaignBundle.root_path(source_path)
	var source_hash: String = FileAccess.get_sha256(source_root)
	_check(AtlasCampaignBundle.load(source_path).error == OK,
		"original current generation is independently readable")
	_check(FileAccess.file_exists(original.path_join("Objects/%s/v000001.drawing" % child_id)) and \
		FileAccess.file_exists(original.path_join("Objects/%s/v000002.drawing" % child_id)),
		"both old and new immutable Object revisions are retained")
	var files_count: int = _copy_files_count(source_path, dest_path)
	_check(files_count >= 10 and FileAccess.file_exists(AtlasCampaignBundle.root_path(dest_path)),
		"project published only after copying source and recovery metadata")
	_check(not DirAccess.dir_exists_absolute(folder.path_join(".atlas-copy-exposed")),
		"copy does not reserve predictable public staging names")
	var clone: AtlasStoreResult = AtlasCampaignBundle.load(dest_path)
	_check(clone.error == OK and clone.generation == str(second.value["generation"]) and not clone.recovered,
		"renamed portable copy loads its current generation without recovery")
	if clone.error != OK:
		quit(1)
		return
	_check(clone.library.asset_exists(parent_id) and clone.library.asset_exists(child_id) and \
		clone.library.asset_exists(leaf_id),
		"copied registry resolves verified parent, child and grandchild sources")
	_check(clone.library.children_for_asset(parent_id)[0]["id"] == str(attached.value) and \
		clone.library.children_for_asset(parent_id)[0]["source_id"] == child_id,
		"nested child identity and source binding preserved")
	_check(clone.library.children_for_asset(child_id)[0]["id"] == str(grandchild.value) and \
		clone.library.children_for_asset(child_id)[0]["source_id"] == leaf_id,
		"grandchild identity, reference and sibling placement survive project copy")
	_check(clone.library.instance_info(str(placed.value))["source_id"] == parent_id,
		"map placement ID and binding preserved")
	_check(FileAccess.file_exists(destination.path_join("Objects/%s/v000001.drawing" % child_id)) and \
		FileAccess.file_exists(destination.path_join("Objects/%s/v000002.drawing" % child_id)),
		"retained preexisting Object source revisions copied, not just current revision")
	_check(FileAccess.file_exists(destination.path_join("Objects/NewWorld.scn.atlas-object-index.json")) and \
		not FileAccess.file_exists(destination.path_join("Objects/World.scn.atlas-object-index.json")),
		"transitional Objects index retargeted to new campaign filename")
	var cloned_document: DrawingResult = clone.registry.document_at("world", "ground", 0)
	_check(cloned_document.ok and cloned_document.value.read_pixel(layer, -511, 1023).value == 0x0038220c and \
		cloned_document.value.read_pixel(layer, 2051, -3000).value == 0xff676563,
		"portable copy restores signed sparse pixels and exact hidden RGB")
	var nested_pixel: DrawingResult = clone.library.render_source_tree(parent_id,
		Rect2i(Vector2i(-2, 4), Vector2i.ONE))
	_check(nested_pixel.ok and (nested_pixel.value as Image).get_pixel(0, 0).a > 0.9,
		"copied parent composition sees current child source revision")
	var deep_pixel: DrawingResult = clone.library.render_source_tree(parent_id,
		Rect2i(Vector2i(1, -1), Vector2i.ONE))
	_check(deep_pixel.ok and (deep_pixel.value as Image).get_pixel(0, 0).b > 0.9,
		"grandchild pixels compose transitively from the cloned registry")
	var hit: DrawingResult = clone.library.hit_test_path(str(placed.value), Vector2(21.5, -6.5))
	_check(hit.ok and hit.value["path"] == PackedStringArray([str(attached.value),
		str(grandchild.value)]), "grandchild hit path survives full project clone")
	var copy_backup: String = AtlasCampaignBundle.backup_path(dest_path)
	_check(FileAccess.file_exists(copy_backup) and \
		AtlasCampaignBundle._load_one(dest_path, copy_backup, AtlasStoreIO.new()).error == OK,
		"copy retains independently verified previous-generation recovery pointer")
	var cloned_child: DrawingResult = clone.library.begin_draft(child_id)
	_check(cloned_child.ok, "copied Object source opens as independent draft")
	if cloned_child.ok:
		var copied_draft: AtlasObjectDraft = cloned_child.value
		_check(clone.library.save_draft(copied_draft).ok and clone.library.asset_info(child_id)["revision"] == 3,
			"copied Object registry publishes third revision independently")
		_check(library.asset_info(child_id)["revision"] == 2 and \
			FileAccess.get_sha256(source_root) == source_hash,
			"mutating copy does not touch original campaign files")
	_check(AtlasCampaignBundle.save(clone.campaign, clone.registry, clone.library, dest_path).ok,
		"copied campaign saves a new validated generation")
	_check(AtlasCampaignBundle.load(dest_path).error == OK and \
		AtlasCampaignBundle.load(source_path).error == OK,
		"copy and source reload independently after clone publication")
	var again: DrawingResult = AtlasCampaignCopy.copy_portable(source_path, dest_path)
	_check(not again.ok and again.code == "COPY_EXISTS" and \
		AtlasCampaignBundle.load(dest_path).error == OK,
		"preexisting project is not replaced or modified")
	_check(not AtlasCampaignCopy.copy_portable(source_path,
			original.path_join("nested/Copy.scn")).ok,
		"destination inside source project is forbidden")
	_check(not AtlasCampaignCopy.copy_portable(source_path,
			folder.path_join("missing-parent/Other/Copy.scn")).ok,
		"copy never creates unapproved destination parents")
	var halted: String = folder.path_join("stopped/Cancelled.scn")
	var copied_paths: Array[String] = []
	var gate: Callable = func(source_file: String, _dest_file: String) -> bool:
		copied_paths.append(source_file)
		return copied_paths.size() < 3
	var stopped: DrawingResult = AtlasCampaignCopy.copy_portable(source_path, halted, gate)
	_check(not stopped.ok and stopped.code == "COPY_CANCELLED" and \
			not DirAccess.dir_exists_absolute(halted.get_base_dir()),
		"mid-copy fault rejects all staged components, without exposing destination")
	var symlink_dir: String = original.path_join("Drawings/user-controlled-link")
	var drawing_directory: DirAccess = DirAccess.open(original.path_join("Drawings"))
	var linked: Error = drawing_directory.create_link(original, symlink_dir)
	_check(linked == OK, "prepare symlink escape in source Drawings tree")
	if linked == OK:
		var escaped: DrawingResult = AtlasCampaignCopy.copy_portable(source_path,
			folder.path_join("linked/Unsafe.scn"))
		_check(not escaped.ok and escaped.code == "COPY_LINK" and \
				not DirAccess.dir_exists_absolute(folder.path_join("linked")),
			"linked component is rejected and staging folder cleaned")
		DirAccess.remove_absolute(symlink_dir)
	var root_corruption: String = folder.path_join("corrupt/Copy.scn")
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_root)
	var changed: FileAccess = FileAccess.open(source_root, FileAccess.WRITE)
	changed.store_string("{not valid JSON")
	changed.close()
	var corrupt: DrawingResult = AtlasCampaignCopy.copy_portable(source_path, root_corruption)
	_check(not corrupt.ok and corrupt.code == "COPY_SOURCE" and \
			not DirAccess.dir_exists_absolute(root_corruption.get_base_dir()),
		"invalid source root is not rescued by valid backup during project copy")
	var restore: FileAccess = FileAccess.open(source_root, FileAccess.WRITE)
	restore.store_buffer(source_bytes)
	restore.close()
	_check(FileAccess.get_sha256(source_root) == source_hash,
		"source generation restored after corruption fixture")
	var unsaved_draft: DrawingResult = library.begin_draft(child_id)
	_check(unsaved_draft.ok and library.save_draft(unsaved_draft.value).ok,
		"publish an Object source revision without checkpointing campaign root")
	var mismatched: DrawingResult = AtlasCampaignCopy.copy_portable(source_path,
		folder.path_join("uncheckpointed/Copy.scn"))
	_check(not mismatched.ok and mismatched.code == "STALE_OBJECTS" and \
			not DirAccess.dir_exists_absolute(folder.path_join("uncheckpointed")),
		"uncheckpointed Object registry cannot masquerade as saved campaign contents")
	_check(AtlasCampaignBundle.save(campaign, registry, library, source_path).ok,
		"newly published Object source can be checkpointed explicitly")
	_check(AtlasCampaignCopy.copy_portable(source_path,
		folder.path_join("checkpointed/Copy.scn")).ok and \
		AtlasCampaignBundle.load(folder.path_join("checkpointed/Copy.scn")).error == OK,
		"a completed checkpoint enables safe independent project copying")
	var expected: String = "T064_CAMPAIGN_COPY_PASSED (%d checks; %d failed)" % [checks, failures]
	print(expected)
	quit(0 if failures == 0 else 1)
