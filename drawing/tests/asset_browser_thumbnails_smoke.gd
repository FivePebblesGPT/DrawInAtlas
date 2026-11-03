extends SceneTree
## T-065: source pixel preview, bounded lazy cache, refresh and stale rejection.

const INDEX: Script = preload("res://addons/drawing/asset_browser_index.gd")
const PREVIEWS: Script = preload("res://addons/drawing/asset_browser_thumbnails.gd")
const PANEL: Script = preload("res://addons/drawing/asset_browser_panel.gd")

var passed: int = 0
var failed: int = 0


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("T065_THUMB_FAILED: " + label)


func write_source(path: String, id: String, red: int, green: int, blue: int) -> bool:
	var document: DrawingDocument = DrawingDocument.new(id, 16)
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not layer.ok:
		return false
	var begun: DrawingResult = document.begin_edit(layer.value, document.revision)
	if not begun.ok:
		return false
	var edit: DrawingEditSession = begun.value
	if not edit.apply_region(Rect2i(3, 3, 1, 1),
			PackedByteArray([red, green, blue, 255])).ok or not edit.commit().ok:
		return false
	return DrawingObjectEditorFile.save(document, path, "Object " + id,
		Vector2i.ZERO, Rect2i(0, 0, 8, 8), 1).ok


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var root_path: String = ProjectSettings.globalize_path("user://t065-thumb-" + DrawingDocument.new_id())
	var objects: String = root_path.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "create Objects folder")
	var source_path: String = objects.path_join("first.drawing")
	check(write_source(source_path, "source-first", 227, 9, 23), "publish visible red source")
	var index: DrawingAssetBrowserIndex = INDEX.new() as DrawingAssetBrowserIndex
	check(index.scan(objects).ok and index.entries.size() == 1, "index source")
	var cache: DrawingAssetBrowserThumbnails = PREVIEWS.new() as DrawingAssetBrowserThumbnails
	var entry: Dictionary = index.entries[0]
	var render: DrawingResult = cache.preview(index, entry)
	check(render.ok and render.value is Image, "render canonical preview")
	if render.ok:
		var icon: Image = render.value
		check(icon.get_size() == Vector2i(48, 48), "fixed thumbnail dimensions")
		var sample: Color = icon.get_pixel(20, 20)
		check(sample.r8 == 227 and sample.g8 == 9 and sample.b8 == 23 and sample.a8 == 255,
			"canonical pixel survives thumbnail resize")
		check(icon.get_pixel(3, 3).a8 == 0, "transparent canvas preserved")
	check(cache.preview(index, entry).ok and cache.renders == 1,
		"repeat preview served from same digest cache")
	cache.reconcile(index.entries)
	check(cache.count() == 1, "unchanged source stays cached after refresh")
	check(write_source(source_path, "source-first", 1, 181, 15), "publish changed source")
	check(not cache.preview(index, entry).ok and cache.renders == 1,
		"cached pixels rejected when file changes without refresh")
	check(index.scan(objects).ok, "explicit refresh finds new SHA")
	cache.reconcile(index.entries)
	check(cache.count() == 0, "changed SHA invalidates cached thumbnail")
	render = cache.preview(index, index.entries[0])
	check(render.ok and cache.renders == 2 and \
			(render.value as Image).get_pixel(20, 20).g8 == 181,
		"fresh published bytes rendered")
	var panel: DrawingAssetBrowserPanel = PANEL.new() as DrawingAssetBrowserPanel
	root.add_child(panel)
	panel.size = Vector2(340, 440)
	await process_frame
	check(panel.set_objects_root(objects).ok, "panel indexes a portable Object folder")
	await process_frame
	await process_frame
	check(panel.assets.item_count == 1 and panel.assets.get_item_icon(0) != null,
		"visible row renders an image on demand")
	check(panel.thumbnails.count() == 1, "panel holds bounded cache")
	check(write_source(source_path, "source-first", 23, 3, 249), "publish modified source")
	panel.notify_source_published(source_path)
	await process_frame
	await process_frame
	check(panel.thumbnails.renders == 2 and panel.assets.get_item_icon(0) != null,
		"successful Save refreshes visible icon")
	panel.notify_source_published(root_path.path_join("Outside/other.drawing"))
	check(panel.index.root_path == objects, "out-of-folder publication ignored")
	# Exercise the actual shared workspace publication callback, not only the
	# panel's notification API. The source Save must advance metadata and index.
	var app: Control = load("res://addons/drawing/workspace.gd").new() as Control
	app.layout_persistence_enabled = false
	app.initial_asset_browser_root = objects
	root.add_child(app)
	await process_frame
	await process_frame
	var workspace_panel: DrawingAssetBrowserPanel = app.asset_browser
	check(workspace_panel != null and workspace_panel.assets.item_count == 1,
		"workspace owns the same portable source index")
	workspace_panel.assets.select(0)
	workspace_panel.assets.item_selected.emit(0)
	workspace_panel.open_selected()
	check(app.current_object() != null and app.current_object().source_id == "source-first",
		"real browser opens its source in Object Editor")
	var before_hash: String = String(workspace_panel.index.entries[0]["sha256"])
	check(app.current_object().set_name("Source published from Object Editor").ok,
		"edit independent Object source name")
	app._publish_object(false)
	await process_frame
	check(workspace_panel.index.entries.size() == 1 and \
			workspace_panel.index.entries[0]["revision"] == 2 and \
			workspace_panel.index.entries[0]["sha256"] != before_hash,
		"Save increments source revision and refreshes Asset Browser index")
	check(not app.current_object().is_dirty() and workspace_panel.assets.item_count == 1,
		"Save closes dirty state without duplicating the listed source")
	check(workspace_panel.thumbnails.preview(workspace_panel.index,
		workspace_panel.index.entries[0]).ok,
		"newly published source produces a valid preview")
	app.queue_free()
	# Exercise LRU with valid but blank Object files, avoiding large tile allocations.
	for i: int in range(26):
		var item_id: String = "source-%02d" % i
		var document: DrawingDocument = DrawingDocument.new(item_id, 16)
		check(DrawingObjectEditorFile.save(document,
			objects.path_join(item_id + ".drawing"), item_id, Vector2i.ZERO,
			Rect2i(0, 0, 8, 8), 1).ok, "publish LRU fixture %d" % i)
	check(index.scan(objects).ok, "index many Object sources")
	cache.reconcile(index.entries)
	for item: Dictionary in index.entries:
		var preview: DrawingResult = cache.preview(index, item)
		if not preview.ok:
			check(false, "LRU render failed for " + String(item["id"]))
	check(cache.count() == DrawingAssetBrowserThumbnails.CAPACITY,
		"thumbnail count remains within fixed LRU limit")
	# An Atlas page is not a complete source index. Navigating to another page
	# may retain previously rendered previews, but a new SHA for the same ID
	# must invalidate its old cached pixels without evicting other IDs.
	var retained: Array[Dictionary] = []
	for candidate: Dictionary in index.entries:
		if cache.contains(candidate):
			retained.append(candidate)
	check(retained.size() == DrawingAssetBrowserThumbnails.CAPACITY,
		"test cache contains precisely the most recent valid thumbnails")
	if retained.size() >= 2:
		var page_a: Dictionary = retained[retained.size() - 1]
		var page_b: Dictionary = retained[retained.size() - 2]
		var before: int = cache.renders
		cache.reconcile([page_a], false)
		cache.reconcile([page_b], false)
		check(cache.contains(page_a) and cache.contains(page_b),
			"moving between partial Atlas pages keeps bounded off-page previews")
		check(cache.preview(index, page_a).ok and cache.renders == before,
			"revisiting earlier page reuses validated image without rerender")
		var updated: Dictionary = page_a.duplicate(true)
		updated["sha256"] = "f".repeat(64)
		cache.reconcile([updated], false)
		check(not cache.contains(page_a) and cache.contains(page_b),
			"changed source invalidates only that stable ID across partial pages")
		cache.reconcile([page_b])
		check(cache.count() == 1, "complete standalone refresh removes off-index previews")
	# Switching Atlas campaigns may not retain previews, even if IDs match.
	var second_root: String = root_path.path_join("NewCampaign/Objects")
	check(DirAccess.make_dir_recursive_absolute(second_root) == OK,
		"prepare separate campaign root")
	panel.set_published_entries(objects, [index.entries[0]], [], 0, 2, index.entries.size())
	check(panel.thumbnails.preview(panel.index, panel.index.entries[0]).ok,
		"first Atlas page can render its source")
	panel.set_published_entries(second_root, [], [], 0, 1, 0)
	check(panel.thumbnails.count() == 0,
		"campaign switch clears even matching-ID thumbnail cache entries")
	panel.queue_free()
	print("T065_THUMBNAILS: %d passed; %d failed" % [passed, failed])
	if failed == 0:
		print("T065_THUMBNAILS_PASSED")
	quit(1 if failed else 0)
