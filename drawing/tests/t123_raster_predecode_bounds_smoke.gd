extends SceneTree
## T-123: reject oversized PNG/WebP/JPEG dimensions from captured headers BEFORE codec allocation.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T123_MODEL_FAILED: " + description)


func _u16be(bytes: PackedByteArray, offset: int, number: int) -> void:
	bytes[offset] = (number >> 8) & 255
	bytes[offset + 1] = number & 255


func _u32be(bytes: PackedByteArray, offset: int, number: int) -> void:
	for i: int in range(4):
		bytes[offset + i] = (number >> (24 - i * 8)) & 255


func _u24le(bytes: PackedByteArray, offset: int, number: int) -> void:
	for i: int in range(3):
		bytes[offset + i] = (number >> (i * 8)) & 255


func png_header(width: int, height: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(33)
	for i: int in range(8):
		bytes[i] = [137, 80, 78, 71, 13, 10, 26, 10][i]
	_u32be(bytes, 8, 13)
	for i: int in range(4):
		bytes[12 + i] = "IHDR".to_ascii_buffer()[i]
	_u32be(bytes, 16, width)
	_u32be(bytes, 20, height)
	bytes[24] = 8
	bytes[25] = 6
	return bytes


func webp_header(kind: String, width: int, height: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(30)
	for i: int in range(4):
		bytes[i] = "RIFF".to_ascii_buffer()[i]
		bytes[8 + i] = "WEBP".to_ascii_buffer()[i]
		bytes[12 + i] = kind.to_ascii_buffer()[i]
	# Minimal uncompressed header fixture; intentionally lacks any valid image payload.
	bytes[4] = 22
	bytes[16] = 10
	match kind:
		"VP8 ":
			bytes[23] = 157
			bytes[24] = 1
			bytes[25] = 42
			bytes[26] = width & 255
			bytes[27] = (width >> 8) & 63
			bytes[28] = height & 255
			bytes[29] = (height >> 8) & 63
		"VP8L":
			bytes[20] = 47
			bytes[21] = (width - 1) & 255
			bytes[22] = (((width - 1) >> 8) & 63) | (((height - 1) & 3) << 6)
			bytes[23] = ((height - 1) >> 2) & 255
			bytes[24] = ((height - 1) >> 10) & 15
		"VP8X":
			_u24le(bytes, 24, width - 1)
			_u24le(bytes, 27, height - 1)
	return bytes


func jpeg_header(width: int, height: int) -> PackedByteArray:
	# Skip APP1 by its declared segment length; SOF0 declares actual dimensions.
	var bytes: PackedByteArray = PackedByteArray([
		255, 216, 255, 225, 0, 8, 11, 22, 33, 44, 55, 66,
		255, 192, 0, 17, 8, 0, 0, 0, 0, 3, 1, 17, 0, 2, 17, 0, 3, 17, 0])
	_u16be(bytes, 17, height)
	_u16be(bytes, 19, width)
	return bytes


func run() -> void:
	var cases: Array[Dictionary] = [
		{"name": "PNG width", "bytes": png_header(4097, 1), "kind": "png"},
		{"name": "PNG height", "bytes": png_header(1, 4097), "kind": "PNG"},
		{"name": "PNG huge", "bytes": png_header(2147483647, 2), "kind": "png"},
		{"name": "WebP lossy width", "bytes": webp_header("VP8 ", 4097, 1), "kind": "webp"},
		{"name": "WebP lossless height", "bytes": webp_header("VP8L", 1, 4097), "kind": "webp"},
		{"name": "WebP extended width", "bytes": webp_header("VP8X", 4097, 1), "kind": "webp"},
		{"name": "WebP extended huge", "bytes": webp_header("VP8X", 16777216, 1), "kind": "webp"},
		{"name": "JPEG SOF0 width", "bytes": jpeg_header(4097, 1), "kind": "jpg"},
		{"name": "JPEG SOF0 height", "bytes": jpeg_header(1, 4097), "kind": "jpeg"},
	]
	for fixture: Dictionary in cases:
		var result: DrawingResult = DrawingRasterImport.decode_image_bytes(
			fixture["bytes"] as PackedByteArray, fixture["kind"] as String)
		check(result.code == "IMAGE_LIMIT", String(fixture["name"]) + " fails before decoder")

	# Invalid dimensions and malformed/truncated segment headers also fail closed.
	var zero_png: PackedByteArray = png_header(0, 2)
	check(DrawingRasterImport.decode_image_bytes(zero_png, "png").code == "HEADER",
		"zero-dimension PNG is invalid")
	var bad_png: PackedByteArray = png_header(4097, 1)
	bad_png[12] = 0
	check(DrawingRasterImport.decode_image_bytes(bad_png, "png").code == "HEADER",
		"PNG lacking first IHDR is invalid")
	var bad_webp: PackedByteArray = webp_header("VP8 ", 4097, 1)
	bad_webp[23] = 0
	check(DrawingRasterImport.decode_image_bytes(bad_webp, "webp").code == "HEADER",
		"VP8 invalid signature cannot reach decoder")
	check(DrawingRasterImport.decode_image_bytes(PackedByteArray([
		255, 216, 255, 225, 255, 255]), "jpeg").code == "HEADER",
		"JPEG overflowing APP segment is rejected")
	check(DrawingRasterImport.decode_image_bytes(PackedByteArray([
		255, 216, 255, 192, 0, 1]), "jpg").code == "HEADER",
		"JPEG SOF segment shorter than 2 bytes fails safely")
	check(DrawingRasterImport.decode_image_bytes(jpeg_header(0, 1), "jpg").code == "HEADER",
		"zero-width JPEG is rejected")
	var bad_length_webp: PackedByteArray = webp_header("VP8X", 4097, 1)
	bad_length_webp[16] = 200
	check(DrawingRasterImport.decode_image_bytes(bad_length_webp, "webp").code == "HEADER",
		"oversized WebP chunk length cannot skip beyond captured bytes")
	var truncated_webp: PackedByteArray = webp_header("VP8X", 4097, 1).slice(0, 20)
	check(DrawingRasterImport.decode_image_bytes(truncated_webp, "webp").code == "HEADER",
		"truncated WebP metadata is rejected before decode")
	var hidden_sof: PackedByteArray = jpeg_header(4097, 1)
	hidden_sof.insert(12, 255)
	hidden_sof.insert(13, 1)
	check(DrawingRasterImport.decode_image_bytes(hidden_sof, "jpeg").code == "IMAGE_LIMIT",
		"JPEG TEM marker preceding SOF does not bypass preflight")

	var base: String = ProjectSettings.globalize_path("user://t123-predecode-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(base) == OK, "temporary source directory")
	var app: Control = load("res://main.tscn").instantiate()
	app.start_blank_document = false
	app.layout_persistence_enabled = false
	app.preferences_persistence_enabled = false
	root.add_child(app)
	for _frame: int in range(4):
		await process_frame
	check(app.tabs.size() == 0, "workspace starts empty")
	for fixture: Dictionary in cases:
		var path: String = base.path_join("overlimit." + String(fixture["kind"]).to_lower())
		var saved: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		saved.store_buffer(fixture["bytes"] as PackedByteArray)
		saved.close()
		app._open_file(path)
		check(app.tabs.size() == 0 and app.status.text.begins_with("Error:"),
			String(fixture["name"]) + " rejects without partial workspace document")

	var original: Image = Image.create(7, 5, false, Image.FORMAT_RGBA8)
	original.fill(Color8(21, 42, 63, 255))
	original.set_pixel(3, 2, Color8(113, 47, 186, 255))
	for extension: String in ["png", "webp", "jpg", "jpeg", "webp-lossless"]:
		var path: String = base.path_join("valid." + ("webp" if extension == "webp-lossless" else extension))
		var stored: Error = OK
		match extension:
			"png": stored = original.save_png(path)
			"webp": stored = original.save_webp(path, false, 1.0)
			"webp-lossless": stored = original.save_webp(path, true, 1.0)
			_: stored = original.save_jpg(path, 1.0)
		check(stored == OK, "normal " + extension + " fixture saved")
		var expected: Image = Image.load_from_file(path)
		var decoded: DrawingResult = DrawingRasterImport.load_file_image(path)
		check(decoded.ok and (decoded.value as Image).get_data() == expected.get_data(),
			"normal " + extension + " untouched by header preflight")
	# A thin image at the exact per-side limit stays supported.
	var at_limit: Image = Image.create(4096, 1, false, Image.FORMAT_RGBA8)
	at_limit.fill(Color8(45, 67, 89, 255))
	var at_limit_path: String = base.path_join("at-limit.png")
	check(at_limit.save_png(at_limit_path) == OK, "4096-wide boundary image stored")
	var at_limit_open: DrawingResult = DrawingRasterImport.load_file_image(at_limit_path)
	check(at_limit_open.ok and (at_limit_open.value as Image).get_width() == 4096,
		"4096-wide boundary image remains accepted")

	print("T123_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T123_MODEL_PASSED")
	quit(1 if failures else 0)
