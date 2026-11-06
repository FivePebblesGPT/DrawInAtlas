extends SceneTree
## T-065: large published Object catalogs remain searchable beyond the old
## 512-source cutoff, with bounded decoded pages and valid placement tokens.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T065_PAGING_FAILED: " + description)


func _erase_tree(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for child: String in directory.get_directories():
		_erase_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func _run() -> void:
	var source: Array[Dictionary] = []
	for i: int in range(1301):
		source.append({"id": "asset-%04d" % i,
			"name": "Portable %04d" % i})
	var all_ids: Dictionary = {}
	for page: int in range(21):
		var selected: Dictionary = AtlasObjectBrowserPages.select_page(source, "", page)
		_check(int(selected["total"]) == 1301 and int(selected["pages"]) == 21 and
			int(selected["page"]) == page, "large catalog page %d metadata" % page)
		var records: Array = selected["records"]
		_check(records.size() == (21 if page == 20 else 64),
			"page %d bounded to 64 source summaries" % page)
		for item: Dictionary in records:
			var stable_id: String = String(item["id"])
			_check(not all_ids.has(stable_id), "source appears on exactly one page: " + stable_id)
			all_ids[stable_id] = true
	_check(all_ids.size() == 1301, "all sources remain reachable, including beyond index 512")
	var last: Dictionary = AtlasObjectBrowserPages.select_page(source, "portable 1300", 19)
	_check(int(last["total"]) == 1 and int(last["page"]) == 0 and
		String(last["records"][0]["id"]) == "asset-1300",
		"case-insensitive global search reaches final page and clamps page")
	var by_id: Dictionary = AtlasObjectBrowserPages.select_page(source, "ASSET-0999", 0)
	_check(int(by_id["total"]) == 1 and String(by_id["records"][0]["id"]) == "asset-0999",
		"search by stable ID beyond the old 512-source cap")
	var missing: Dictionary = AtlasObjectBrowserPages.select_page(source, "not-present", 1000000)
	_check(int(missing["total"]) == 0 and int(missing["page"]) == 0 and
		int(missing["pages"]) == 1 and (missing["records"] as Array).is_empty(),
		"empty query result retains a bounded, safe empty page")
	var first: Dictionary = AtlasObjectBrowserPages.select_page(source, "", -100)
	_check(int(first["page"]) == 0 and String(first["records"][0]["id"]) == "asset-0000",
		"negative requested page clamps to first page")
	var last_clamped: Dictionary = AtlasObjectBrowserPages.select_page(source, "", 9999)
	_check(int(last_clamped["page"]) == 20 and
		String(last_clamped["records"][-1]["id"]) == "asset-1300",
		"stale high page clamps to last page")
	# Atlas permits up to ten thousand registry entries. Search remains metadata-
	# only, and even that maximum never opens more than one 64-source page.
	var maximum_catalog: Array[Dictionary] = []
	for i: int in range(10000):
		maximum_catalog.append({"id": "max-%05d" % i, "name": "Catalog %05d" % i})
	var start_time: int = Time.get_ticks_msec()
	var maximum: Dictionary = AtlasObjectBrowserPages.select_page(maximum_catalog, "", 156)
	var duration_ms: int = Time.get_ticks_msec() - start_time
	_check(int(maximum["total"]) == 10000 and int(maximum["pages"]) == 157 and
		(maximum["records"] as Array).size() == 16,
		"maximum allowed registry size uses 157 bounded pages")
	var final_source: Dictionary = AtlasObjectBrowserPages.select_page(maximum_catalog, "MAX-09999", 0)
	_check(int(final_source["total"]) == 1 and
		String(final_source["records"][0]["id"]) == "max-09999",
		"max-registry search reaches final ID without opening document bytes")
	print("T065_PAGING_MAX_METADATA_MS %d" % duration_ms)
	var tied: Array[Dictionary] = [{"id": "third", "name": "z"},
		{"id": "second", "name": "Same"}, {"id": "first", "name": "same"}]
	var sorted: Dictionary = AtlasObjectBrowserPages.select_page(tied, "", 0)
	_check(String(sorted["records"][0]["id"]) == "first" and
		String(sorted["records"][1]["id"]) == "second",
		"equal case-folded names use stable ID as deterministic tiebreaker")

	# End-to-end registry and UI: later pages cannot use a stale or forged
	# drag token simply because the first page was authenticated earlier.
	var directory: String = OS.get_cache_dir().path_join("t065-page-" + DrawingDocument.new_id())
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create temporary campaign")
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	editor.save_path = directory.path_join("Campaign.scn")
	editor.use_system_clipboard = false
	root.add_child(scene)
	for frame: int in range(3):
		await process_frame
	var library: AtlasObjectLibrary = editor.drawing_composition.library
	var initial: DrawingDocument = DrawingDocument.new("source-for-pagination", 16)
	var created: DrawingResult = library.create_asset(initial, "Very late specimen")
	_check(created.ok, "create real published test source")
	# 65 additional published sources cross the production 64-row page bound.
	# The test goes through real registry commits and immutable Object files.
	for i: int in range(65):
		var document: DrawingDocument = DrawingDocument.new("bulk-%03d" % i, 16)
		var added: DrawingResult = library.create_asset(document, "Bulk source %03d" % i)
		_check(added.ok, "publish distinct source %d" % i)
	var browser: DrawingAssetBrowserPanel = editor.asset_browser_panel
	editor.sidebar.select_view(&"Layers")
	editor.asset_browser_toggle.pressed.emit()
	await process_frame
	_check(browser.index.entries.size() == 64 and browser._matched_count == 66 and
		browser.page_status.text == "1 / 2" and browser.previous_page.disabled and
		not browser.next_page.disabled,
		"first production page contains at most 64 registered Object sources")
	browser.next_page.pressed.emit()
	_check(browser.index.entries.size() == 2 and browser.page_status.text == "2 / 2" and
		not browser.previous_page.disabled and browser.next_page.disabled,
		"second production page makes later published sources reachable")
	var late_row: int = -1
	for i: int in range(browser._visible_entries.size()):
		if browser._visible_entries[i]["id"] == String(created.value):
			late_row = i
	_check(late_row >= 0, "published source beyond first page has its own row")
	if late_row >= 0:
		var late_token: Dictionary = browser._drag_entry_for_row(late_row)
		_check(editor._valid_browser_source(late_token),
			"second-page drag uses a fresh, registry-verified source token")
	browser.search.text = "VERY LATE"
	browser.query_changed.emit("VERY LATE")
	_check(browser.index.entries.size() == 1 and int(browser._matched_count) == 1 and
		browser.page_status.text == "1 / 1" and
		String(browser._visible_entries[0]["id"]) == String(created.value),
		"search spans all registry metadata, not the currently opened page")
	browser.search.text = "missing"
	browser.query_changed.emit("missing")
	_check(browser.index.entries.is_empty() and int(browser._matched_count) == 0 and
		browser.previous_page.disabled and browser.next_page.disabled,
		"no matches cannot activate stale page controls or row selection")
	browser.search.text = ""
	browser.query_changed.emit("")
	_check(browser.page_status.text == "1 / 2" and browser.index.entries.size() == 64,
		"clearing a search restores a bounded first page")
	var token: Dictionary = browser._drag_entry_for_row(0)
	_check(editor._valid_browser_source(token), "current source remains placeable after search")
	var stale: Dictionary = token.duplicate(true)
	stale["revision"] = 123456
	_check(not editor._valid_browser_source(stale), "invalid revision rejected after paging")
	scene.queue_free()
	await process_frame
	_erase_tree(directory)
	print("T065_PAGING_PASSED %d checks, failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
