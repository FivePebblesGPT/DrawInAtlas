extends SceneTree
## T-065: explicit safe file copy only, without Atlas library registration.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")
const TRANSFERS: Script = preload("res://addons/drawing/asset_browser_transfer.gd")
const PANEL: Script = preload("res://addons/drawing/asset_browser_panel.gd")

var passed: int = 0
var failed: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("T065_TRANSFER_FAILED: " + label)


func write_source(path: String, id: String, label: String) -> bool:
	var document: DrawingDocument = DrawingDocument.new(id, 16)
	return DrawingObjectEditorFile.save(document, path, label,
		Vector2i(-3, 2), Rect2i(0, 0, 8, 8), 1).ok


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t065-transfer-" + DrawingDocument.new_id())
	var objects: String = base.path_join("Campaign/Objects")
	var input_folder: String = base.path_join("Incoming")
	var output_folder: String = base.path_join("Exported")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK and
		DirAccess.make_dir_recursive_absolute(input_folder) == OK and
		DirAccess.make_dir_recursive_absolute(output_folder) == OK, "create isolated folders")
	var source: String = input_folder.path_join("renamed-on-disk.drawing")
	check(write_source(source, "asset-portable", "Hero"), "publish valid external portable source")
	var index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(index.scan(objects).ok and index.entries.is_empty(), "start with empty Objects index")
	var links: DirAccess = DirAccess.open(base)
	var input_alias: String = base.path_join("InputAlias")
	var output_alias: String = base.path_join("OutputAlias")
	var campaign_alias: String = base.path_join("CampaignAlias")
	check(links.create_link(input_folder, input_alias) == OK and
		links.create_link(output_folder, output_alias) == OK and
		links.create_link(base.path_join("Campaign"), campaign_alias) == OK,
		"create aliases to real external source, export directory and campaign")
	check(not index.scan(campaign_alias.path_join("Objects")).ok and
		index.root_path == objects, "reject symlinked campaign root during re-scan")
	# Reset the fixture if the vulnerable index accepted the alias, so that a
	# negative-control failure cannot cascade into unrelated copy assertions.
	index.scan(objects)
	var alias_import: DrawingResult = TRANSFERS.import_file(index,
		input_alias.path_join("renamed-on-disk.drawing"))
	check(not alias_import.ok and
		not FileAccess.file_exists(objects.path_join("asset-portable.drawing")),
		"Import refuses source whose parent is a symlink")
	if FileAccess.file_exists(objects.path_join("asset-portable.drawing")):
		DirAccess.remove_absolute(objects.path_join("asset-portable.drawing"))
	index.scan(objects)
	var imported: DrawingResult = TRANSFERS.import_file(index, source)
	var destination: String = objects.path_join("asset-portable.drawing")
	check(imported.ok and imported.value == destination and FileAccess.file_exists(destination),
		"Import names file after stable identity, not incoming basename")
	check(FileAccess.get_sha256(destination) == FileAccess.get_sha256(source),
		"Import is byte-for-byte lossless and leaves external source intact")
	check(index.scan(objects).ok and index.entries.size() == 1 and
		index.entries[0]["id"] == "asset-portable", "fresh index sees copied stable source")
	# A caller may supply a correct filesystem hash for a source created after
	# the user's index snapshot. Export must not treat that as selected authority.
	var forged_path: String = objects.path_join("unlisted.drawing")
	check(write_source(forged_path, "unlisted", "Unreviewed"),
		"create source after the latest displayed index snapshot")
	var forged: Dictionary = {"id": "unlisted", "name": "Unreviewed", "revision": 1,
		"path": forged_path, "sha256": FileAccess.get_sha256(forged_path)}
	var forged_export: String = output_folder.path_join("forged-export.drawing")
	check(not TRANSFERS.export_file(index, forged, forged_export).ok and
		not FileAccess.file_exists(forged_export),
		"Export rejects a real byte-valid source that was not in the selected index")
	check(DirAccess.remove_absolute(forged_path) == OK,
		"clean up unindexed source without changing the authorized export")
	check(not TRANSFERS.import_file(index, source).ok,
		"duplicate source ID import is forbidden, even with different filename")
	check(not TRANSFERS.import_file(index, destination).ok,
		"cannot import another file from its own Objects folder")
	var exported_path: String = output_folder.path_join("portable-export.drawing")
	var exported: DrawingResult = TRANSFERS.export_file(index, index.entries[0], exported_path)
	check(exported.ok and FileAccess.get_sha256(exported_path) == index.entries[0]["sha256"],
		"Export produces exactly the indexed source's bytes")
	check(not TRANSFERS.export_file(index, index.entries[0],
		output_alias.path_join("through-link.drawing")).ok and
		not FileAccess.file_exists(output_folder.path_join("through-link.drawing")),
		"Export refuses an output directory reached through a symlinked parent")
	check(DirAccess.remove_absolute(input_alias) == OK and
		DirAccess.remove_absolute(output_alias) == OK and
		DirAccess.remove_absolute(campaign_alias) == OK,
		"remove aliases without touching original asset bytes")
	check(FileAccess.file_exists(destination) and FileAccess.file_exists(source),
		"Export never moves or deletes the indexed source")
	check(not TRANSFERS.export_file(index, index.entries[0], exported_path).ok,
		"Export must not overwrite an existing file")
	check(not TRANSFERS.export_file(index, index.entries[0],
		objects.path_join("another.drawing")).ok,
		"Export cannot quietly create a second copy in the source index")
	check(not TRANSFERS.export_file(index, index.entries[0], "relative.drawing").ok,
		"Export must name an absolute .drawing destination")
	var invalid: String = input_folder.path_join("not-a-source.drawing")
	var writer: FileAccess = FileAccess.open(invalid, FileAccess.WRITE)
	writer.store_string("not a Drawing Object source")
	writer.close()
	check(not TRANSFERS.import_file(index, invalid).ok,
		"Import rejects invalid standalone file metadata")
	var other: String = input_folder.path_join("another-name.drawing")
	check(write_source(other, "asset-portable", "Duplicate Hero"),
		"prepare same-ID new file")
	check(not TRANSFERS.import_file(index, other).ok,
		"Import never picks a same-named object over a stable ID collision")
	var reserved_directory: String = objects.path_join("other-source")
	check(DirAccess.make_dir_recursive_absolute(reserved_directory) == OK,
		"create existing revision reservation folder")
	var reserved: String = input_folder.path_join("reserved.drawing")
	check(write_source(reserved, "other-source", "Reserved"), "write reserved source")
	check(not TRANSFERS.import_file(index, reserved).ok,
		"existing versioned-source directory prevents a second loose identity")
	var managed_source: String = input_folder.path_join("managed.drawing")
	check(write_source(managed_source, "asset-managed", "Managed"),
		"write candidate Atlas-managed source")
	var managed_index: String = objects.path_join("Campaign.scn.atlas-object-index.json")
	var registry_file: FileAccess = FileAccess.open(managed_index, FileAccess.WRITE)
	registry_file.store_string("{}")
	registry_file.close()
	check(TRANSFERS.import_file(index, managed_source).code == "ATLAS_REGISTRY" and
		not FileAccess.file_exists(objects.path_join("asset-managed.drawing")),
		"refuse standalone import into an Atlas registry without registration")
	DirAccess.remove_absolute(managed_index)
	check(write_source(destination, "asset-portable", "Changed outside app"),
		"replace selected source externally")
	check(not TRANSFERS.export_file(index, index.entries[0],
		output_folder.path_join("stale.drawing")).ok,
		"Export rejects an exact source hash that became stale")
	check(not FileAccess.file_exists(output_folder.path_join("stale.drawing")),
		"rejected stale source creates no destination")
	var panel: DrawingAssetBrowserPanel = PANEL.new() as DrawingAssetBrowserPanel
	root.add_child(panel)
	panel.size = Vector2(340, 440)
	await process_frame
	check(panel.set_objects_root(objects).ok and panel.assets.item_count == 1,
		"real panel has imported source")
	var another_source: String = input_folder.path_join("new.drawing")
	check(write_source(another_source, "asset-new", "New"), "publish independent source for import")
	panel._import_file(another_source)
	check(panel.index.entries.size() == 2 and panel.message.text.contains("Imported"),
		"Import button callback performs checked copy and refreshes the browser")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	panel._ask_export()
	check(not panel._pending_export.is_empty(),
		"Export freezes an exact selected source while file dialog is open")
	panel._export_file(output_folder.path_join("via-panel.drawing"))
	check(FileAccess.file_exists(output_folder.path_join("via-panel.drawing")) and
		panel.message.text.contains("Exported"), "Export callback creates a portable file")
	# Revalidate the Objects path after discovery: a renamed parent may now
	# point outside the campaign even when each indexed filename is unchanged.
	var redirect_source: String = input_folder.path_join("redirect-test.drawing")
	check(write_source(redirect_source, "asset-redirect-test", "Redirect probe"),
		"prepare source with unused ID for post-scan root substitution")
	var campaign_root: String = base.path_join("Campaign")
	var campaign_moved: String = base.path_join("CampaignMoved")
	check(DirAccess.rename_absolute(campaign_root, campaign_moved) == OK and
		links.create_link(campaign_moved, campaign_root) == OK,
		"replace scanned campaign parent with a symlink")
	check(not panel.index.safe_to_open(panel.index.entries[0]),
		"already-indexed source fails closed after campaign parent replacement")
	check(not TRANSFERS.import_file(panel.index, redirect_source).ok and
		not FileAccess.file_exists(campaign_moved.path_join("Objects/asset-redirect-test.drawing")),
		"Import refuses a previously indexed Objects root redirected by link")
	check(not TRANSFERS.export_file(panel.index, panel.index.entries[0],
		output_folder.path_join("post-link.drawing")).ok and
		not FileAccess.file_exists(output_folder.path_join("post-link.drawing")),
		"Export refuses a previously indexed source after parent replacement")
	check(DirAccess.remove_absolute(campaign_root) == OK and
		DirAccess.rename_absolute(campaign_moved, campaign_root) == OK and
		panel.index.safe_to_open(panel.index.entries[0]),
		"restoring real campaign path restores authorized source access")
	panel.queue_free()
	print("T065_TRANSFERS: %d passed; %d failed" % [passed, failed])
	if failed == 0:
		print("T065_TRANSFERS_PASSED")
	quit(1 if failed else 0)
