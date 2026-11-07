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
	app.queue_free()
	print("T065_ASSET_BROWSER: %d passed; %d failed" % [passed, failed])
	if failed == 0:
		print("T065_ASSET_BROWSER_PASSED")
	quit(1 if failed else 0)
