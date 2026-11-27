extends SceneTree
## T-120 standalone and embedded shared File/Open/Object contract; real temporary files.

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T120_MODEL_FAILED: " + description)


func frames(count: int = 3) -> void:
	for _i: int in range(count):
		await process_frame


func menu(top: Control, title: String) -> PopupMenu:
	for button: MenuButton in top._menus:
		if button.text == title:
			return button.get_popup()
	return null


func rgba_at(document: DrawingDocument, bounds: Rect2i, xy: Vector2i) -> Color:
	var image: DrawingResult = DrawingRenderer.render(document, bounds, 0, 0, 256)
	if not image.ok:
		return Color.TRANSPARENT
	return (image.value as Image).get_pixelv(xy)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t120-model-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "fixture folder exists")
	var app: Control = load("res://main.tscn").instantiate()
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	app.start_blank_document = false
	root.add_child(app)
	await frames(5)
	check(app.tabs.size() == 0 and app.current_object() == null, "no implicit document or source")
	var top: Control = app.top_bar
	var file_menu: PopupMenu = menu(top, "File")
	var object_menu: PopupMenu = menu(top, "Object")
	check(file_menu != null and object_menu != null, "real, independent File and Object menus")
	var file_labels: Array[String] = []
	for i: int in range(file_menu.item_count):
		file_labels.append(file_menu.get_item_text(i).split("  ")[0])
	check(file_labels == ["New", "Open…", "Save", "Save As…", "Close Tab", "Export…"],
		"File exposes six current actions and exact wording")
	var object_labels: Array[String] = []
	for i: int in range(object_menu.item_count):
		object_labels.append(object_menu.get_item_text(i))
	check(object_labels == ["New Source", "Open Source…", "Rename Source…",
		"Save Source As…", "Browse Sources…"], "Object owns five source commands")
	check(not file_labels.has("Import Image as Drawing…") and not str(file_labels).contains("Object"),
		"File has no obsolete import or Object-prefixed action")
	check(app.open_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE and
		str(app.open_dialog.filters).contains("*.drawing") and
		str(app.open_dialog.filters).contains("*.png") and
		str(app.open_dialog.filters).contains("*.webp") and
		str(app.open_dialog.filters).contains("*.jpg") and
		str(app.open_dialog.filters).contains("*.jpeg"),
		"one Open chooser advertises all supported extensions")
	file_menu.id_pressed.emit(0)
	check(app.tabs.size() == 1 and app.current_object() == null and
		app.canvas.image_bounds.has_area(), "File New creates an ordinary document")
	var document: DrawingDocument = DrawingDocument.new("t120-saved")
	check(document.create_layer(DrawingLayerNode.RASTER, "Sample").ok, "prepare .drawing")
	var ordinary: String = base.path_join("ordinary.drawing")
	check(DrawingFileIO.save(document, ordinary).ok, "write independent ordinary file")
	var ordinary_before: int = app.tabs.size()
	app.open_dialog.file_selected.emit(ordinary)
	check(app.tabs.size() == ordinary_before + 1 and app.current_document().id == "t120-saved" and
		String(app.tabs[app.active_tab]["path"]) == ordinary and app.current_object() == null,
		"Open chooser dispatches .drawing to its original loader")

	var opaque: Image = Image.create(5, 3, false, Image.FORMAT_RGBA8)
	opaque.fill(Color.TRANSPARENT)
	opaque.set_pixel(1, 2, Color8(13, 45, 209, 255))
	opaque.set_pixel(3, 1, Color8(90, 220, 17, 180))
	var png: String = base.path_join("source.png")
	check(opaque.save_png(png) == OK, "write canonical PNG")
	var png_digest: String = FileAccess.get_sha256(png)
	var count: int = app.tabs.size()
	app.open_dialog.file_selected.emit(png)
	check(app.tabs.size() == count + 1 and app.current_object() == null and
		app.canvas.image_bounds == Rect2i(0, 0, 5, 3), "PNG Open creates framed ordinary Drawing")
	check(app.current_document().layer_count() == 1 and
		String(app.tabs[app.active_tab]["path"]).is_empty() and
		String(app.tabs[app.active_tab]["title"]).contains("source.png") and
		app.current_document().is_dirty(), "PNG tab is editable, unsaved and clearly named")
	var imported: DrawingDocument = app.current_document()
	var imported_id: String = imported.id
	var imported_layer: String = app.current_layer()
	check(imported.read_pixel(imported_layer, 1, 2).ok and
		rgba_at(imported, Rect2i(0, 0, 5, 3), Vector2i(1, 2)).b8 == 209,
		"image pixels map to an editable raster layer without an Object source")
	check(rgba_at(imported, Rect2i(0, 0, 5, 3), Vector2i(3, 1)).a8 == 180,
		"PNG straight-alpha pixel survives canonical import")
	# The raster store uses 0xAABBGGRR straight RGBA8, not the
	# composite renderer's possibly rounded/pre-multiplied display colors.
	var expected_bytes: PackedByteArray = opaque.get_data()
	var exact_png: bool = true
	for y: int in range(3):
		for x: int in range(5):
			var offset: int = (y * 5 + x) * 4
			var expected: int = int(expected_bytes[offset]) | \
				(int(expected_bytes[offset + 1]) << 8) | \
				(int(expected_bytes[offset + 2]) << 16) | \
				(int(expected_bytes[offset + 3]) << 24)
			var actual: DrawingResult = imported.read_pixel(imported_layer, x, y)
			if not actual.ok or int(actual.value) != expected:
				exact_png = false
	check(exact_png, "all 15 PNG canonical straight-RGBA8 pixels match exactly")
	app._save()
	check(app.save_dialog.visible and String(app.tabs[app.active_tab]["path"]).is_empty(),
		"first Save opens .drawing destination picker rather than overwriting image")
	app.save_dialog.hide()
	var saved: String = base.path_join("fresh.drawing")
	app._save_file(saved)
	check(FileAccess.file_exists(saved) and String(app.tabs[app.active_tab]["path"]) == saved and
		FileAccess.get_sha256(png) == png_digest,
		"first Save creates .drawing and preserves source PNG byte-for-byte")
	app._open_file(saved)
	check(app.current_document().id == imported_id and app.canvas.image_bounds == Rect2i(0, 0, 5, 3) and
		rgba_at(app.current_document(), Rect2i(0, 0, 5, 3), Vector2i(1, 2)).b8 == 209,
		"saved imported document reopens with same ID, frame and pixel content")

	var transparent: Image = Image.create(4, 2, false, Image.FORMAT_RGBA8)
	transparent.fill(Color.TRANSPARENT)
	var blank: String = base.path_join("transparent.png")
	check(transparent.save_png(blank) == OK, "create zero-alpha fixture")
	app._open_file(blank)
	check(app.current_object() == null and app.canvas.image_bounds == Rect2i(0, 0, 4, 2) and
		app.current_document().layer_count() == 1 and
		String(app.tabs[app.active_tab]["path"]).is_empty(),
		"fully transparent image still opens as unsaved framed Drawing")

	var webp: String = base.path_join("source.webp")
	var jpeg: String = base.path_join("source.jpeg")
	var jpg: String = base.path_join("source.jpg")
	check(opaque.save_webp(webp, false, 1.0) == OK and opaque.save_jpg(jpeg, 1.0) == OK and
		opaque.save_jpg(jpg, 1.0) == OK, "write WebP and both JPEG suffix fixtures")
	for path: String in [webp, jpeg, jpg]:
		var loaded: Image = Image.load_from_file(path)
		var expected: Color = loaded.get_pixel(1, 2)
		var previous: int = app.tabs.size()
		app._open_file(path)
		var color: Color = rgba_at(app.current_document(), Rect2i(0, 0, 5, 3), Vector2i(1, 2))
		check(app.tabs.size() == previous + 1 and
			app.canvas.image_bounds == Rect2i(0, 0, 5, 3) and
			color.r8 == expected.r8 and color.g8 == expected.g8 and color.b8 == expected.b8,
			"WebP/JPEG format dispatch retains decoded canonical color: " + path.get_extension())

	var failures_before: int = app.tabs.size()
	app._open_file(base.path_join("unsupported.gif"))
	check(app.tabs.size() == failures_before and app.status.text.contains("Unsupported file type"),
		"unsupported extension fails with clear status, no new tab")
	app._open_file(base.path_join("missing.png"))
	check(app.tabs.size() == failures_before and app.status.text.contains("Error:"),
		"missing input cannot create a partial document")
	var broken: String = base.path_join("broken.png")
	var bad_file: FileAccess = FileAccess.open(broken, FileAccess.WRITE)
	bad_file.store_string("not a PNG")
	bad_file.close()
	app._open_file(broken)
	check(app.tabs.size() == failures_before and app.status.text.contains("Image header is invalid"),
		"malformed PNG is rejected before publishing a tab")
	var oversize_image: Image = Image.create(4097, 1, false, Image.FORMAT_RGBA8)
	oversize_image.fill(Color.RED)
	var oversize_path: String = base.path_join("too-wide.png")
	check(oversize_image.save_png(oversize_path) == OK, "create real out-of-bounds image")
	app._open_file(oversize_path)
	check(app.tabs.size() == failures_before and app.status.text.contains("4096px"),
		"4097px geometry is rejected before publishing a tab")
	var oversize_bytes: String = base.path_join("too-big.png")
	var big: FileAccess = FileAccess.open(oversize_bytes, FileAccess.WRITE)
	big.seek(64 * 1024 * 1024)
	big.store_8(0)
	big.close()
	app._open_file(oversize_bytes)
	check(app.tabs.size() == failures_before and app.status.text.contains("64 MiB"),
		"oversized encoded input is rejected without image decoding")

	object_menu.id_pressed.emit(0)
	check(app.current_object() != null and app.tabs.size() == failures_before + 1,
		"Object New Source creates dedicated source session, not an ordinary Open")
	object_menu.id_pressed.emit(4)
	await frames(4)
	check(app.asset_browser != null and app.asset_browser.index.root_path.is_empty(),
		"Object Browse Sources exposes unbound Asset Browser without scanning a root")
	print("T120_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T120_MODEL_PASSED")
	quit(1 if failures else 0)
