extends SceneTree
## T-093 headless model, filesystem and shared-workspace contracts.

const PREFS: String = "user://t093-recent-object-root.json"
var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T093_MODEL_FAILED: " + label)


func frames(n: int = 3) -> void:
	for i: int in range(n):
		await process_frame


func make_source(path: String, id: String, label: String) -> bool:
	var doc: DrawingDocument = DrawingDocument.new(id)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Raster")
	if not layer.ok:
		return false
	var edit: DrawingResult = doc.begin_edit(String(layer.value), doc.revision)
	if not edit.ok:
		return false
	if not (edit.value as DrawingEditSession).apply_region(Rect2i(-2, 3, 1, 1),
			PackedByteArray([19, 82, 143, 230])).ok:
		return false
	if not (edit.value as DrawingEditSession).commit().ok:
		return false
	return DrawingObjectEditorFile.save(doc, path, label, Vector2i(-2, 3),
		Rect2i(-4, 0, 16, 16), 1).ok


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var file_path: String = ProjectSettings.globalize_path(PREFS)
	DirAccess.remove_absolute(file_path)
	DirAccess.remove_absolute(file_path + ".bak")
	check(DrawingObjectRootHistory.read_file(PREFS).is_empty(), "no remembered root at first launch")
	for path: String in ["", "relative/Objects", "/tmp/NotObjects", "/tmp/Objects/../Objects", "/tmp/Objects/../Other"]:
		check(not DrawingObjectRootHistory.valid_path(path), "reject noncanonical or invalid root " + path)
	check(not DrawingObjectRootHistory.save_file(PREFS, "not-an-Objects-root"), "invalid root cannot persist")
	var base: String = ProjectSettings.globalize_path("user://t093-fixture-" + DrawingDocument.new_id())
	var objects: String = base.path_join("Objects")
	check(DirAccess.make_dir_recursive_absolute(objects) == OK, "create fixture Objects root")
	check(DrawingObjectRootHistory.valid_path(objects), "canonical absolute Objects root recognized")
	check(DrawingObjectRootHistory.save_file(PREFS, objects), "persist last explicit choice")
	check(DrawingObjectRootHistory.read_file(PREFS) == objects, "remember exact root without inspecting content")
	var malformed: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	malformed.store_string("[1,2,3]"); malformed.close()
	check(DrawingObjectRootHistory.read_file(PREFS).is_empty(), "wrong schema or type rejected")
	check(DrawingObjectRootHistory.save_file(PREFS, objects), "repair broken preference")
	check(DirAccess.rename_absolute(file_path, file_path + ".bak") == OK, "simulate interrupted preference rename")
	check(DrawingObjectRootHistory.read_file(PREFS) == objects, "backup recovers last validated path")
	check(DrawingObjectRootHistory.save_file(PREFS, objects), "atomic save clears backup")
	check(not FileAccess.file_exists(file_path + ".tmp") and
		not FileAccess.file_exists(file_path + ".bak"), "successful save leaves no transient files")
	var source_path: String = objects.path_join("known.drawing")
	check(make_source(source_path, "t093-source", "Known saved source"), "create signed portable source")
	var digest: String = FileAccess.get_sha256(source_path)
	var corrupt_path: String = objects.path_join("damaged.drawing")
	var bad: FileAccess = FileAccess.open(corrupt_path, FileAccess.WRITE)
	bad.store_string("{bad json}"); bad.close()
	var plain_doc: DrawingDocument = DrawingDocument.new("plain-drawing")
	check(plain_doc.create_layer(DrawingLayerNode.RASTER, "Plain").ok, "build plain drawing")
	var ordinary_path: String = base.path_join("ordinary.drawing")
	check(DrawingFileIO.save(plain_doc, ordinary_path).ok, "save ordinary Drawing outside Objects")
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.recent_objects_root_settings_path = PREFS
	root.add_child(app)
	await frames(5)
	check(app.asset_browser == null, "no guessed or automatic Objects root despite a remembered path")
	var file_menu: PopupMenu = app.top_bar._menus[0].get_popup()
	check(file_menu.get_item_text(1).contains("Open Drawing") and
		file_menu.get_item_text(6).contains("Open source") and
		file_menu.get_item_text(9).contains("Import Image") and
		file_menu.get_item_text(10).contains("Browse saved sources"),
		"File menu distinguishes Drawing, Object source, bitmap and browser commands")
	file_menu.id_pressed.emit(10)
	await frames(3)
	var panel: DrawingAssetBrowserPanel = app.asset_browser
	check(panel != null and panel.index.root_path.is_empty() and panel.assets.item_count == 0,
		"first browser view has no scanned assets")
	check(panel.message.text.contains("No Objects/ folder") and
		panel.root_display.text.contains("Not selected"), "first-use empty state explains root and workflow")
	check(panel.recent_root_button.visible and panel.recent_root == objects,
		"last explicitly chosen root is offered, never auto-activated")
	check(not panel.place_button.visible and panel.open_button.disabled,
		"standalone browser cannot place an Atlas instance or open nonexistent selection")
	check(not app.show_asset_browser(base), "reject project root, require actual Objects directory")
	check(panel.index.root_path.is_empty(), "invalid root does not activate or rebind")
	app._chosen_objects_root(objects)
	await frames(5)
	check(panel.index.root_path == objects and panel.assets.item_count == 1,
		"explicit selection indexes only real valid Object sources")
	check(panel.root_display.text.contains("Objects") and
		panel.root_display.tooltip_text == objects and not panel.copy_root_button.disabled,
		"compact root label and exact-copy/tooltip expose the active absolute path")
	check(not panel.index.safe_to_open({"path": objects.path_join("bad.drawing"),
		"sha256": "x"}), "unlisted or missing source cannot be opened by an unsafe token")
	check(panel.message.text.contains("Skipped") and panel.message.text.contains("invalid"),
		"corrupt source produces specific warning rather than silent omission")
	check(panel.assets.get_item_tooltip(0).contains("t093-source"),
		"source row exposes stable ID and original path")
	panel.search.text = "missing"
	panel.search.text_changed.emit("missing")
	check(panel.assets.item_count == 0 and panel.open_button.disabled,
		"search empty-result cannot enable Open")
	panel.search.text = "t093-source"
	panel.search.text_changed.emit("t093-source")
	check(panel.assets.item_count == 1, "source ID search finds correct saved source")
	panel.assets.select(0)
	panel.assets.item_selected.emit(0)
	panel.open_selected()
	await frames(3)
	check(app.tabs.size() == 2 and app.current_object() != null and
		app.current_object().source_id == "t093-source", "Open creates dedicated Object Editor tab")
	check(FileAccess.get_sha256(source_path) == digest and not app.current_document().is_dirty(),
		"discovery never writes or binds existing source")
	app._open_file(ordinary_path)
	await frames(2)
	check(app.tabs.size() == 3 and app.current_object() == null and
		app.current_document().id == "plain-drawing", "ordinary Open remains independent")
	var before: int = app.tabs.size()
	app._open_file(objects.path_join("damaged.drawing"))
	check(app.tabs.size() == before and app.status.text.contains("Error:"),
		"corrupt ordinary file cannot create a false success tab")
	app._open_object_file(base.path_join("not-there.drawing"))
	check(app.tabs.size() == before and app.status.text.contains("Error:"),
		"missing source fails with actionable status, no false tab")
	app._import_image_file(ordinary_path)
	check(app.tabs.size() == before and app.status.text.contains("Unsupported image type"),
		"wrong import file type gives actionable error")
	var image_path: String = base.path_join("pixels.png")
	var image: Image = Image.create(3, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(1, 1, Color8(21, 92, 203, 255))
	check(image.save_png(image_path) == OK, "create test PNG")
	app._import_image_file(image_path)
	await frames(3)
	check(app.tabs.size() == before + 1 and app.current_object() == null and
		app.canvas.image_bounds == Rect2i(0, 0, 3, 2), "PNG imports as separate framed Drawing")
	var rendered: DrawingResult = DrawingRenderer.render(app.current_document(),
		Rect2i(0, 0, 3, 2), 0, 0, 256)
	check(rendered.ok and (rendered.value as Image).get_pixel(1, 1).b8 == 203 and
		(rendered.value as Image).get_pixel(1, 1).a8 == 255,
		"import preserves exact opaque RGBA8 pixel")
	var saved_path: String = base.path_join("imported.drawing")
	app._save_file(saved_path)
	app._open_file(saved_path)
	check(app.current_document().id == (app.tabs[before]["document"] as DrawingDocument).id and
		app.canvas.image_bounds == Rect2i(0, 0, 3, 2),
		"imported image saves and reopens with stable Drawing identity and frame")
	var blank_path: String = base.path_join("blank.png")
	var blank: Image = Image.create(3, 3, false, Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	check(blank.save_png(blank_path) == OK, "create completely transparent bitmap")
	app._import_image_file(blank_path)
	check(app.canvas.image_bounds == Rect2i(0, 0, 3, 3) and
		app.current_object() == null, "fully transparent bitmap still creates a framed Drawing")
	var before_fail: int = app.tabs.size()
	app._import_image_file(corrupt_path)
	check(app.tabs.size() == before_fail, "wrong-type corrupt source does not create tab")
	# The source itself stays portable; relocation requires a deliberate new root.
	var second_root: String = base.path_join("relocated/Objects")
	check(DirAccess.make_dir_recursive_absolute(second_root) == OK, "create second portable root")
	check(DirAccess.copy_absolute(source_path, second_root.path_join("known.drawing")) == OK,
		"copy portable source without rewriting its stable ID")
	check(panel.index.root_path == objects, "relocation is never followed or selected implicitly")
	app._chosen_objects_root(second_root)
	check(panel.index.root_path == second_root and panel.assets.item_count == 1 and
		String(panel.index.entries[0]["id"]) == "t093-source", "explicit relocation retains source identity")
	check(DrawingObjectRootHistory.read_file(PREFS) == second_root,
		"recent selection updates after successful explicit switch")
	var second_app: Control = load("res://main.tscn").instantiate()
	second_app.layout_persistence_enabled = false
	second_app.recent_objects_root_settings_path = PREFS
	root.add_child(second_app)
	await frames(4)
	check(second_app.asset_browser == null, "relaunch does not silently bind remembered root")
	second_app._show_asset_browser_empty()
	second_app._use_recent_objects_root()
	await frames(3)
	check(second_app.asset_browser.index.root_path == second_root,
		"explicit Use last folder selects relocated Objects root")
	check(second_app.asset_browser.open_button.disabled,
		"reselected root requires explicit source row selection")
	print("T093_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T093_MODEL_PASSED")
	quit(1 if failures else 0)
