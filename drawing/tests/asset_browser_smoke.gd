extends SceneTree
## T-065: read-only portable source discovery plus real dock/tab interaction.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")
const APP: Script = preload("res://addons/drawing/workspace.gd")
var passed: int = 0
var failed: int = 0
var fixture_root: String = ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("T065_ASSET_BROWSER_FAILED: " + description)

func write_source(id: String, label: String, path: String, revision: int = 1) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var document: DrawingDocument = DrawingDocument.new(id)
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not layer.ok:
		return false
	return DrawingObjectEditorFile.save(document, path, label, Vector2i(-5, 12),
		Rect2i(2, 3, 64, 40), revision).ok

func _run() -> void:
	fixture_root = ProjectSettings.globalize_path("user://t065-browser-fixture-" + DrawingDocument.new_id())
	var objects: String = fixture_root.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "create portable Objects folder")
	var castle: String = objects.path_join("asset-castle/v000001.drawing")
	var castle_new: String = objects.path_join("asset-castle/v000002.drawing")
	var tower: String = objects.path_join("tower.drawing")
	check(write_source("asset-castle", "Castle", castle), "publish castle v1")
	check(write_source("asset-castle", "Castle 2", castle_new, 2), "publish castle v2")
	check(write_source("asset-tower", "Tower", tower), "publish standalone tower")
	var browser: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(not browser.scan("relative/Objects").ok, "reject relative path")
	check(not browser.scan(fixture_root).ok, "require explicitly named Objects directory")
	check(browser.scan(objects).ok, "scan portable asset folder")
	check(browser.entries.size() == 2, "scan only latest immutable revision and loose object")
	check(browser.entries[0]["id"] == "asset-castle" and browser.entries[0]["revision"] == 2 and
		browser.entries[0]["path"] == castle_new, "highest published revision chosen")
	check(browser.filtered("tower").size() == 1, "case insensitive name search")
	check(browser.filtered("ASSET-CASTLE").size() == 1, "case insensitive stable ID search")
	check(browser.filtered("NotThere").is_empty(), "no fabricated search matches")
	check(browser.warnings.is_empty(), "clean sources do not produce warnings")
	check(browser.safe_to_open(browser.entries[0]) and browser.safe_to_open(browser.entries[1]),
		"indexed versioned and loose sources pass safe revalidation")
	check(browser.safe_to_open(browser.filtered("castle")[0]),
		"deep-copied filtered index record remains authorized")
	var altered: Dictionary = browser.entries[0].duplicate(true)
	altered["name"] = "Unreviewed label"
	check(not browser.safe_to_open(altered),
		"a modified display record cannot borrow the indexed source authority")
	var unlisted_path: String = objects.path_join("unlisted.drawing")
	check(write_source("unlisted", "Unlisted", unlisted_path),
		"write a real Object source after the index snapshot")
	var unlisted: Dictionary = {"id": "unlisted", "name": "Unlisted", "revision": 1,
		"path": unlisted_path, "sha256": FileAccess.get_sha256(unlisted_path)}
	check(not browser.safe_to_open(unlisted),
		"a hash-valid source created after scan is not authorized by the snapshot")
	check(DirAccess.remove_absolute(unlisted_path) == OK,
		"clean up unlisted source without changing the indexed records")
	# The user can select an absolute path *through* a symlinked campaign
	# ancestor; detecting only Objects/ and its direct children is insufficient.
	var alias_parent: String = fixture_root + "-alias"
	var links: DirAccess = DirAccess.open(fixture_root.get_base_dir())
	check(links.create_link(fixture_root, alias_parent) == OK,
		"create symlinked parent for Objects index")
	check(not browser.scan(alias_parent.path_join("Objects")).ok and
		browser.entries.size() == 2 and browser.root_path == objects,
		"reject symlinked campaign parent without replacing the valid index")
	check(DirAccess.remove_absolute(alias_parent) == OK, "remove parent alias")
	# A previously safe index can become unsafe *after* discovery when a
	# directory in the path is renamed and replaced with a link.
	var guarded_parent: String = fixture_root.path_join("Guarded")
	var guarded_objects: String = guarded_parent.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(guarded_objects) == OK,
		"create nested independent Objects root")
	check(write_source("guarded", "Guarded", guarded_objects.path_join("guarded.drawing")),
		"write source in nested Objects root")
	var guarded: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(guarded.scan(guarded_objects).ok and guarded.entries.size() == 1,
		"scan real nested Objects root")
	var moved_parent: String = fixture_root.path_join("GuardedMoved")
	check(DirAccess.rename_absolute(guarded_parent, moved_parent) == OK and
		links.create_link(moved_parent, guarded_parent) == OK,
		"replace scanned intermediate parent with symlink")
	check(not guarded.safe_to_open(guarded.entries[0]) and
		not guarded.scan(guarded_objects).ok and guarded.entries.size() == 1,
		"stale index cannot open or rescan through a replaced parent")
	check(DirAccess.remove_absolute(guarded_parent) == OK and
		DirAccess.rename_absolute(moved_parent, guarded_parent) == OK and
		guarded.safe_to_open(guarded.entries[0]),
		"restored real path permits exact original source again")
	var app: Control = APP.new() as Control
	app.layout_persistence_enabled = false
	root.add_child(app)
	await process_frame
	await process_frame
	check(app.dock_layout.owner_of("asset_browser") == "", "no guessed Objects folder on startup")
	check(app.show_asset_browser(objects), "user can attach Asset Browser to shared dock")
	await process_frame
	await process_frame
	var panel: DrawingAssetBrowserPanel = app.asset_browser
	check(panel != null and app.dock_layout.owner_of("asset_browser") == "right" and
		app.dock_views["asset_browser"] == panel, "one authoritative dock panel registration")
	check(panel.assets.item_count == 2, "real dock renders both saved sources")
	check(panel.open_button.disabled, "Open is disabled until explicit source selection")
	panel.search.text = "tower"
	panel.search.text_changed.emit("tower")
	check(panel.assets.item_count == 1, "UI filter narrows entries")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	check(panel.selected_asset_id() == "asset-tower" and not panel.open_button.disabled,
		"select exact source without editing Drawing")
	var dirty_before: bool = app.current_document().is_dirty()
	panel.open_selected()
	check(app.tabs.size() == 2 and app.current_object() != null and
		app.current_object().source_id == "asset-tower", "Open opens separate Object Editor tab")
	check(dirty_before == (app.tabs[0]["document"] as DrawingDocument).is_dirty(), "browser selection does not dirty artwork")
	panel.search.text = ""
	panel.search.text_changed.emit("")
	check(panel.assets.item_count == 2, "clearing search restores full list")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	var original_tabs: int = app.tabs.size()
	# Replacing bytes at the same path, even without changing identity, must not
	# silently open a source which was not the one the user inspected.
	check(write_source("asset-tower", "Tower Changed", tower), "external same-ID content replacement")
	panel.search.text = "tower"
	panel.search.text_changed.emit("tower")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	panel.open_selected()
	check(app.tabs.size() == original_tabs and panel.message.text.contains("changed"),
		"same-ID bytes changed since index scan cannot be opened")
	check(write_source("replacement-id", "Tower", tower), "external file replacement creates different identity")
	panel.search.text = "tower"
	panel.search.text_changed.emit("tower")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	panel.open_selected()
	check(app.tabs.size() == original_tabs and panel.message.text.contains("changed"),
		"stale index cannot open a replaced identity")
	panel.refresh_assets()
	check(panel.selected_asset_id() == "" and panel.index.filtered("replacement-id").size() == 1,
		"refresh discovers new ID without preserving stale source selection")
	check(browser.scan(objects).ok and browser.filtered("replacement-id").size() == 1,
		"index refresh sees newly published asset")
	# An exact ID must never silently resolve to one of two different files.
	var duplicate: String = objects.path_join("replacement-copy.drawing")
	check(write_source("replacement-id", "Duplicate", duplicate), "publish duplicate ID fixture")
	check(browser.scan(objects).ok and browser.filtered("replacement-id").is_empty() and
		not browser.warnings.is_empty(), "ambiguous source ID is suppressed and diagnosed")
	var moved_root: String = ProjectSettings.globalize_path("user://t065-browser-moved-" + DrawingDocument.new_id())
	check(DirAccess.rename_absolute(fixture_root, moved_root) == OK, "move complete portable folder")
	check(browser.scan(moved_root.path_join("Objects")).ok and browser.entries.size() == 1,
		"relocated folder preserves unambiguous source IDs")
	check(not browser.scan(fixture_root.path_join("Objects")).ok and browser.entries.size() == 1,
		"failed rescan retains last valid index instead of erasing it")
	var bad_revision: String = moved_root.path_join("Objects/asset-castle/v000003.drawing")
	check(write_source("asset-castle", "Unpublished Castle 3", bad_revision, 2),
		"stage misleading version filename with older embedded revision")
	check(browser.scan(moved_root.path_join("Objects")).ok and browser.entries.is_empty() and
		not browser.warnings.is_empty(),
		"inconsistent revision is rejected, not silently downgraded to prior version")
	# A large version folder must not silently publish an older version chosen
	# from an incomplete directory enumeration. Dummy filenames are deliberately
	# not valid revisions: every directory entry still costs bounded work.
	var crowded: String = moved_root.path_join("Objects/crowded")
	check(write_source("crowded", "Crowded", crowded.path_join("v000001.drawing")),
		"publish a valid revision beneath the candidate budget")
	var populated: bool = true
	for i: int in range(DrawingAssetBrowserIndex.MAX_CANDIDATES):
		var noise: FileAccess = FileAccess.open(crowded.path_join("noise-%04d.tmp" % i), FileAccess.WRITE)
		if noise == null:
			populated = false
			break
		noise.close()
	check(populated, "create over-budget revision directory fixture")
	check(browser.scan(moved_root.path_join("Objects")).ok and
		browser.filtered("crowded").is_empty() and
		"Skipped asset revision directory exceeding candidate limit" in browser.warnings,
		"over-budget revision directory cannot present an incomplete old version")
	for i: int in range(DrawingAssetBrowserIndex.MAX_CANDIDATES):
		DirAccess.remove_absolute(crowded.path_join("noise-%04d.tmp" % i))
	check(browser.scan(moved_root.path_join("Objects")).ok and
		browser.filtered("crowded").size() == 1 and
		browser.safe_to_open(browser.filtered("crowded")[0]),
		"after excess entries are removed, a fresh scan authorizes the full revision")
	# The root budget applies to files *and* directories together. Previously
	# both get_files()/get_directories() allocated unbounded arrays and a
	# truncated listing could still publish the first valid loose source.
	var root_budget: String = moved_root.path_join("RootBudget/Objects")
	check(DirAccess.make_dir_recursive_absolute(root_budget) == OK,
		"create independent root-budget Objects folder")
	var budget_source: String = root_budget.path_join("a-valid.drawing")
	check(write_source("budget-source", "Budget", budget_source),
		"prepare valid first-sorted source for root budget")
	check(DirAccess.make_dir_absolute(root_budget.path_join("empty-folder")) == OK,
		"root budget includes directories, not just files")
	var root_populated: bool = true
	for i: int in range(DrawingAssetBrowserIndex.MAX_CANDIDATES - 2):
		var noise: FileAccess = FileAccess.open(root_budget.path_join("noise-%04d.tmp" % i), FileAccess.WRITE)
		if noise == null:
			root_populated = false
			break
		noise.close()
	check(root_populated, "create root with exactly the combined entry budget")
	var budget_index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(budget_index.scan(root_budget).ok and budget_index.entries.size() == 1 and
		budget_index.safe_to_open(budget_index.entries[0]),
		"root exactly at file-plus-directory budget remains usable")
	var prior_entry: Dictionary = budget_index.entries[0].duplicate(true)
	var beyond: String = root_budget.path_join("zzzz-overflow.tmp")
	var extra: FileAccess = FileAccess.open(beyond, FileAccess.WRITE)
	check(extra != null, "add one unrelated file beyond the root budget")
	if extra != null:
		extra.close()
	var overflowing: DrawingResult = budget_index.scan(root_budget)
	check(not overflowing.ok and overflowing.code == "ASSET_LIMIT" and
		budget_index.root_path == root_budget and budget_index.entries.size() == 1 and
		budget_index.entries[0] == prior_entry,
		"over-budget root fails atomically without publishing a partial index")
	var panel_root_before: String = panel.index.root_path
	check(not panel.set_objects_root(root_budget).ok and
		panel.index.root_path == panel_root_before and
		panel.message.text.contains("candidate limit"),
		"real browser reports the root budget failure without switching roots")
	check(DirAccess.remove_absolute(beyond) == OK and budget_index.scan(root_budget).ok and
		budget_index.entries.size() == 1 and budget_index.safe_to_open(budget_index.entries[0]),
		"removing the excess entry allows a new complete authorized scan")
	# MAX_ASSETS is a source-identity limit, not permission to show only the
	# first 512 files. A late duplicate must still be discovered and suppressed,
	# and a 513th distinct source must fail without replacing the last index.
	var source_limit_root: String = moved_root.path_join("SourceLimit/Objects")
	check(DirAccess.make_dir_recursive_absolute(source_limit_root) == OK,
		"create independent source-count Objects folder")
	var saved_all: bool = true
	for i: int in range(DrawingAssetBrowserIndex.MAX_ASSETS):
		var id: String = "bulk-%04d" % i
		if not write_source(id, "Bulk %04d" % i,
				source_limit_root.path_join(id + ".drawing")):
			saved_all = false
			break
	check(saved_all, "publish exactly the maximum number of independent source IDs")
	var source_cap_index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(source_cap_index.scan(source_limit_root).ok and
		source_cap_index.entries.size() == DrawingAssetBrowserIndex.MAX_ASSETS and
		source_cap_index.warnings.is_empty(),
		"exactly 512 valid source identities form a complete authorized index")
	var authorized_snapshot: Array[Dictionary] = source_cap_index.entries.duplicate(true)
	var duplicate_after_limit: String = source_limit_root.path_join("zz-late-duplicate.drawing")
	check(write_source("bulk-0000", "Duplicate", duplicate_after_limit),
		"add a late duplicate beyond the old source-count cutoff")
	check(source_cap_index.scan(source_limit_root).ok and
		source_cap_index.entries.size() == DrawingAssetBrowserIndex.MAX_ASSETS - 1 and
		source_cap_index.filtered("bulk-0000").is_empty() and
		not source_cap_index.warnings.is_empty(),
		"late duplicate is examined and suppressed instead of hiding behind first 512")
	check(DirAccess.remove_absolute(duplicate_after_limit) == OK and
		source_cap_index.scan(source_limit_root).ok and
		source_cap_index.entries == authorized_snapshot,
		"removing duplicate restores the exact original authorized snapshot")
	var over_source: String = source_limit_root.path_join("zz-new-source.drawing")
	check(write_source("bulk-extra", "Extra", over_source),
		"create 513th distinct valid published source")
	var over_source_scan: DrawingResult = source_cap_index.scan(source_limit_root)
	check(not over_source_scan.ok and over_source_scan.code == "ASSET_LIMIT" and
		source_cap_index.root_path == source_limit_root and
		source_cap_index.entries == authorized_snapshot and
		source_cap_index.warnings.is_empty() and
		source_cap_index.safe_to_open(source_cap_index.entries[0]),
		"source limit fails atomically and retains last authorized index without warnings drift")
	var panel_source_root_before: String = panel.index.root_path
	check(not panel.set_objects_root(source_limit_root).ok and
		panel.index.root_path == panel_source_root_before and
		panel.message.text.contains("source index limit"),
		"visible browser reports over-limit source count without switching its root")
	check(DirAccess.remove_absolute(over_source) == OK and
		source_cap_index.scan(source_limit_root).ok and
		source_cap_index.entries.size() == DrawingAssetBrowserIndex.MAX_ASSETS,
		"removing 513th source allows a complete 512-source rescan")
	# The versioned-source traversal occurs before loose files. Verify its own
	# limit guard, without generating an unrelated second 512-source payload.
	var all_versioned: bool = true
	for i: int in range(DrawingAssetBrowserIndex.MAX_ASSETS):
		var id: String = "bulk-%04d" % i
		var versioned_folder: String = source_limit_root.path_join(id)
		if DirAccess.make_dir_absolute(versioned_folder) != OK or \
				DirAccess.rename_absolute(source_limit_root.path_join(id + ".drawing"),
				versioned_folder.path_join("v000001.drawing")) != OK:
			all_versioned = false
			break
	check(all_versioned, "relocate 512 published sources to canonical versioned directories")
	var versioned_index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(versioned_index.scan(source_limit_root).ok and
		versioned_index.entries.size() == DrawingAssetBrowserIndex.MAX_ASSETS and
		versioned_index.warnings.is_empty(),
		"versioned source traversal also accepts the exact limit")
	var versioned_snapshot: Array[Dictionary] = versioned_index.entries.duplicate(true)
	var versioned_extra: String = source_limit_root.path_join("bulk-versioned/v000001.drawing")
	check(write_source("bulk-versioned", "Versioned overflow", versioned_extra),
		"publish a 513th versioned source")
	var versioned_overflow: DrawingResult = versioned_index.scan(source_limit_root)
	check(not versioned_overflow.ok and versioned_overflow.code == "ASSET_LIMIT" and
		versioned_index.entries == versioned_snapshot and
		versioned_index.warnings.is_empty(),
		"versioned source overflow rejects partial publication atomically")
	check(DirAccess.remove_absolute(versioned_extra) == OK and
		versioned_index.scan(source_limit_root).ok and
		versioned_index.entries.size() == DrawingAssetBrowserIndex.MAX_ASSETS,
		"versioned overflow can recover after removing the extra source")
	app.queue_free()
	print("T065_ASSET_BROWSER: %d passed; %d failed" % [passed, failed])
	if failed == 0:
		print("T065_ASSET_BROWSER_PASSED")
	quit(1 if failed else 0)
