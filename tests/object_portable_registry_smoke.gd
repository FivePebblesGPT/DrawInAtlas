extends SceneTree
## T-065: portable source import/export through the Atlas-owned registry.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T065_PORTABLE_FAILED: " + label)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child: String in directory.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var folder: String = OS.get_cache_dir().path_join("t065-portable-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "create temporary campaign folder")
	var outside: String = folder.path_join("incoming")
	check(DirAccess.make_dir_recursive_absolute(outside) == OK, "create separate import directory")
	var source_file: String = outside.path_join("portable.drawing")
	var doc: DrawingDocument = DrawingDocument.new("portable-stable-id", 16)
	var group: DrawingResult = doc.create_layer(DrawingLayerNode.GROUP, "Art")
	check(group.ok, "create source group")
	var source: DrawingResult = DrawingObjectEditorFile.save(doc, source_file,
		"Amber lamp", Vector2i(-4, 8), Rect2i(-2, 7, 30, 24), 9)
	check(source.ok, "save portable source with revision and explicit local frame")
	var library: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	var imported: DrawingResult = library.import_portable_source(source_file)
	check(imported.ok and imported.value == doc.id, "import preserves embedded source identity")
	if not imported.ok:
		print("T065_PORTABLE_FAILED setup import: " + imported.message)
		_erase_tree(folder)
		quit(1)
		return
	var info: Dictionary = library.asset_info(doc.id)
	check(info["name"] == "Amber lamp" and info["revision"] == 1 and
		info["origin"] == [-4, 8] and info["bounds"] == [-2, 7, 30, 24],
		"campaign starts at revision one and retains portable name/frame")
	check(info["path"] == "Objects/portable-stable-id/v000001.drawing" and
		library.asset_exists(doc.id), "registered revision is a canonical campaign-relative Object")
	check(library.asset_ids() == [doc.id] and library.instance_ids().is_empty(),
		"import registers source without creating an Atlas placement")
	check(not library.import_portable_source(source_file).ok, "duplicate source ID fails closed")
	check(not library.import_portable_source(library._absolute(String(info["path"]))).ok,
		"cannot import a campaign revision from its own Objects directory")
	var placed: DrawingResult = library.place(doc.id, "world", "first", "D0")
	check(placed.ok and library.source_usage(doc.id)["linked"] == 1,
		"imported asset can be placed as an Atlas-linked instance")
	var path: String = outside.path_join("export.drawing")
	var exported: DrawingResult = library.export_portable_source(doc.id, path, 1)
	check(exported.ok and FileAccess.file_exists(path), "export writes a new portable file")
	var reopened: DrawingResult = DrawingObjectEditorFile.open(path)
	check(reopened.ok and reopened.value["source_id"] == doc.id and
		reopened.value["source_revision"] == 1 and reopened.value["name"] == "Amber lamp" and
		reopened.value["origin"] == Vector2i(-4, 8) and
		reopened.value["bounds"] == Rect2i(-2, 7, 30, 24),
		"export reconstructs stable portable metadata and local frame")
	check(reopened.ok and reopened.value["document"].id == doc.id,
		"export keeps document source identity")
	check(not library.export_portable_source(doc.id, path, 1).ok,
		"export never overwrites an existing file")
	check(not library.export_portable_source(doc.id, outside.path_join("no.drawing"), 2).ok,
		"stale expected revision is rejected before writing")
	check(not library.export_portable_source(doc.id, library.root_path.path_join("unsafe.drawing")).ok,
		"export cannot pollute campaign-managed Objects directory")
	var stale_handle: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	check(stale_handle.load().ok, "second library loads published registry")
	var other: DrawingDocument = DrawingDocument.new("fresh-object", 16)
	var another_path: String = outside.path_join("another.drawing")
	check(DrawingObjectEditorFile.save(other, another_path, "Another", Vector2i.ZERO,
		Rect2i(), 1).ok, "create second portable source")
	check(library.import_portable_source(another_path).ok, "second source publication succeeds")
	var stale_import: DrawingResult = stale_handle.import_portable_source(source_file)
	check(not stale_import.ok and stale_import.code == "STALE_INDEX",
		"stale library cannot import after concurrent registry publication")
	check(not stale_handle.export_portable_source(doc.id,
		outside.path_join("stale.drawing")).ok,
		"stale registry cannot export a potentially replaced source")
	var third: AtlasObjectLibrary = AtlasObjectLibrary.new(folder.path_join("Campaign.scn"))
	check(third.load().ok and third.asset_ids().size() == 2,
		"portable registry reload keeps both published identities")
	check(third.instance_info(String(placed.value))["source_id"] == doc.id,
		"portable registry reload preserves linked instance binding")
	var broken: String = outside.path_join("broken.drawing")
	var handle: FileAccess = FileAccess.open(broken, FileAccess.WRITE)
	if handle != null:
		handle.store_string("not json")
		handle.close()
	check(not third.import_portable_source(broken).ok and third.asset_ids().size() == 2,
		"invalid source cannot mutate live registry")
	check(not third.import_portable_source("relative.drawing").ok,
		"relative input paths are refused")
	var missing_id: String = "reserved-object"
	check(DirAccess.make_dir_recursive_absolute(library.root_path.path_join(missing_id)) == OK,
		"create unreferenced reserved Object revision directory")
	var reserved: DrawingDocument = DrawingDocument.new(missing_id, 16)
	var reserved_path: String = outside.path_join("reserved.drawing")
	check(DrawingObjectEditorFile.save(reserved, reserved_path, "Reserved", Vector2i.ZERO,
		Rect2i(), 1).ok, "create reserved-ID portable candidate")
	var refused: DrawingResult = third.import_portable_source(reserved_path)
	check(not refused.ok and refused.code == "DUPLICATE_ID" and third.asset_ids().size() == 2,
		"unindexed revision directory cannot be silently adopted")
	var aborted: DrawingDocument = DrawingDocument.new("rollback-portable", 16)
	var aborted_path: String = outside.path_join("abort.drawing")
	check(DrawingObjectEditorFile.save(aborted, aborted_path, "Rollback", Vector2i.ZERO,
		Rect2i(), 1).ok, "create source for rejected registry publication")
	third.publication_guard = func() -> bool: return false
	var failed_publish: DrawingResult = third.import_portable_source(aborted_path)
	check(not failed_publish.ok and failed_publish.code == "PUBLISH" and
		third.asset_info(aborted.id).is_empty(), "rejected import cannot mutate the registry")
	check(not FileAccess.file_exists(third.root_path.path_join(aborted.id).path_join("v000001.drawing"))
		and not DirAccess.dir_exists_absolute(third.root_path.path_join(aborted.id)),
		"failed import removes its unreferenced staged revision directory")
	third.publication_guard = Callable()
	check(third.import_portable_source(aborted_path).ok and third.asset_exists(aborted.id),
		"a failed import is safely retryable once the publication guard clears")
	var output: String = "T065_PORTABLE_PASSED %d checks, failures=%d" % [checks, failures]
	_erase_tree(folder)
	print(output)
	quit(0 if failures == 0 else 1)
