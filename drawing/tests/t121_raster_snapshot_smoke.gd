extends SceneTree
## T-121: size/header/decoder consume exactly the same captured raster bytes.

var checks: int = 0
var failures: int = 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T121_MODEL_FAILED: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var base: String = ProjectSettings.globalize_path("user://t121-snapshot-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "temporary source directory")
	var image_a: Image = Image.create(5, 3, false, Image.FORMAT_RGBA8)
	image_a.fill(Color.TRANSPARENT)
	image_a.set_pixel(1, 1, Color8(23, 71, 199, 129))
	var image_b: Image = Image.create(5, 3, false, Image.FORMAT_RGBA8)
	image_b.fill(Color8(17, 220, 53, 255))
	var path: String = base.path_join("replace.PNG")
	check(image_a.save_png(path) == OK, "PNG fixture stored with uppercase extension")
	var snapshot: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var decoded_a: DrawingResult = DrawingRasterImport.decode_image_bytes(snapshot, "PNG")
	check(decoded_a.ok and (decoded_a.value as Image).get_data() == image_a.get_data(),
		"captured PNG bytes decode exactly without a path")
	check(image_b.save_png(path) == OK, "atomic-swap proxy replaces disk file after capture")
	var decoded_again: DrawingResult = DrawingRasterImport.decode_image_bytes(snapshot, "png")
	check(decoded_again.ok and (decoded_again.value as Image).get_data() == image_a.get_data(),
		"captured bytes retain original pixels even when path now names different content")
	var live: DrawingResult = DrawingRasterImport.load_file_image(path)
	check(live.ok and (live.value as Image).get_data() == image_b.get_data(),
		"new request reads current bytes, case-insensitive PNG extension")
	check(DrawingRasterImport.decode_image_bytes(snapshot, "jpg").code == "HEADER",
		"cross-format spoof is rejected before decode")
	check(DrawingRasterImport.decode_image_bytes(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]),
		"png").code == "HEADER", "header-only PNG cannot reach the decoder")
	check(DrawingRasterImport.decode_image_bytes(snapshot, "gif").code == "FORMAT",
		"unknown codec cannot be selected through buffer API")

	for extension: String in ["webp", "jpg", "jpeg"]:
		var other: String = base.path_join("source." + extension)
		var saved: Error = image_a.save_webp(other, false, 1.0) if extension == "webp" else \
			image_a.save_jpg(other, 1.0)
		check(saved == OK, extension + " fixture saved")
		var from_file: Image = Image.load_from_file(other)
		var opened: DrawingResult = DrawingRasterImport.load_file_image(other)
		check(opened.ok and (opened.value as Image).get_data() == from_file.get_data(),
			extension + " buffer decode matches prior file-based decoder")

	var wide: Image = Image.create(4097, 1, false, Image.FORMAT_RGBA8)
	wide.fill(Color8(1, 2, 3, 255))
	var wide_path: String = base.path_join("wide.png")
	check(wide.save_png(wide_path) == OK, "overwide fixture saved")
	check(DrawingRasterImport.load_file_image(wide_path).code == "IMAGE_LIMIT",
		"overwide decoded image rejected before source document mutation")
	var oversized: String = base.path_join("too-large.png")
	var stream: FileAccess = FileAccess.open(oversized, FileAccess.WRITE)
	stream.seek(64 * 1024 * 1024)
	stream.store_8(0)
	stream.close()
	check(DrawingRasterImport.load_file_image(oversized).code == "READ_LIMIT",
		"encoded image larger than 64 MiB fails before allocating source buffer")
	check(DrawingRasterImport.load_file_image(base.path_join("missing.png")).code == "READ",
		"nonexistent path fails without partial image")
	check(DrawingRasterImport.load_file_image(base.path_join("unknown.gif")).code == "FORMAT",
		"unknown file extension fails before touching disk")

	var app: Control = load("res://main.tscn").instantiate()
	app.start_blank_document = false
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	for _frame: int in range(4):
		await process_frame
	check(app.tabs.size() == 0, "empty application before raster Open")
	app._open_file(path)
	check(app.tabs.size() == 1 and app.current_object() == null and \
		app.canvas.image_bounds == Rect2i(0, 0, 5, 3),
		"real Open remains an ordinary framed document, not an Object")
	check((app.current_document().read_pixel(app.current_layer(), 1, 1).value as int) == \
		(17 | (220 << 8) | (53 << 16) | (255 << 24)),
		"real Open uses the replacement snapshot's exact straight RGBA8 bytes")
	var previous: int = app.tabs.size()
	app._open_file(wide_path)
	app._open_file(oversized)
	app._open_file(base.path_join("missing.png"))
	check(app.tabs.size() == previous and app.status.text.begins_with("Error:"),
		"all failure paths are transactional and leave the existing tab intact")
	print("T121_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T121_MODEL_PASSED")
	quit(1 if failures else 0)
