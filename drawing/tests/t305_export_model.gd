extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T305_MODEL_FAILED: " + label)

func fill(doc: DrawingDocument, layer: String, rect: Rect2i, rgba: int) -> void:
	var edit: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(edit.fill_rect(rect, rgba).ok and edit.commit().ok, "fixture fill commits")

func decode(bytes: PackedByteArray, format: String) -> Image:
	var decoded: DrawingResult = DrawingRasterImport.decode_image_bytes(bytes, format)
	check(decoded.ok, "bounded decoder accepts " + format)
	if not decoded.ok:
		return null
	var image: Image = decoded.value as Image
	image.convert(Image.FORMAT_RGBA8)
	return image

func exact_roundtrip(source: Image, format: String) -> void:
	var encoded: DrawingResult = DrawingRasterExport.encode(source, format)
	check(encoded.ok, format + " encoding succeeds")
	if not encoded.ok:
		return
	var output: Image = decode(encoded.value as PackedByteArray, format)
	check(output != null and output.get_size() == source.get_size() and output.get_data() == source.get_data(), format + " exact composite RGBA8")

func rgb_error(actual: Image, expected: Image) -> float:
	var a: PackedByteArray = actual.get_data()
	var b: PackedByteArray = expected.get_data()
	var error: float = 0.0
	for offset: int in range(0, a.size(), 4):
		for channel: int in range(3):
			error += absi(int(a[offset + channel]) - int(b[offset + channel]))
	return error / float(actual.get_width() * actual.get_height() * 3)

func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "required native extension registered")
	var doc: DrawingDocument = DrawingDocument.new("t305-export", 16)
	var base: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Base").value)
	var top: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Top").value)
	var hidden: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Hidden").value)
	fill(doc, base, Rect2i(-20, -12, 28, 24), 0xff0000ff)
	fill(doc, top, Rect2i(-8, -8, 24, 16), 0x8000ff00)
	fill(doc, hidden, Rect2i(-32, -24, 64, 48), 0xffff0000)
	check(doc.set_visibility(hidden, false).ok, "hidden layer suppressed")
	var bounds: Rect2i = Rect2i(-32, -24, 64, 48)
	var rev: int = doc.revision
	var history: int = doc.history_length()
	var cursor: int = doc.history_position()
	var dirty: bool = doc.is_dirty()
	var rendered: DrawingResult = DrawingRasterExport.render(doc, bounds)
	check(rendered.ok, "signed finite composite succeeds")
	if not rendered.ok:
		quit(1)
		return
	var image: Image = rendered.value as Image
	var expected: Image = Image.create_empty(64, 48, false, Image.FORMAT_RGBA8)
	expected.fill(Color.TRANSPARENT)
	expected.fill_rect(Rect2i(12, 12, 28, 24), Color8(255, 0, 0))
	expected.fill_rect(Rect2i(24, 16, 24, 16), Color8(0, 255, 0, 128))
	expected.fill_rect(Rect2i(24, 16, 16, 16), Color8(127, 128, 0))
	# Godot Color.TRANSPARENT includes white RGB; ensure the expected composite has zero hidden RGB.
	var expected_bytes: PackedByteArray = expected.get_data()
	for i: int in range(0, expected_bytes.size(), 4):
		if expected_bytes[i + 3] == 0:
			expected_bytes.encode_u32(i, 0)
	check(image.get_size() == bounds.size and image.get_data() == expected_bytes, "independent signed, layered, hidden-layer, alpha oracle")
	exact_roundtrip(image, "png")
	exact_roundtrip(image, "webp")
	var crop: DrawingResult = DrawingRasterExport.render(doc, Rect2i(-8, -8, 3, 3))
	check(crop.ok and (crop.value as Image).get_data().decode_u32(0) == 0xff00807f, "frame clips outside content without mutating source")
	check(not DrawingRasterExport.render(doc, Rect2i()).ok, "empty frame rejected")
	check(not DrawingRasterExport.render(doc, Rect2i(0, 0, 4097, 1)).ok, "side budget rejected")
	check(not DrawingRasterExport.render(doc, Rect2i(0, 0, 4096, 4096)).ok, "area budget rejected before allocation")
	check(not DrawingRasterExport.render(doc, Rect2i(1000000000, 0, 1, 1)).ok, "signed edge range rejected")
	var pending: DrawingEditSession = doc.begin_edit(base, doc.revision).value
	check(not DrawingRasterExport.render(doc, bounds).ok, "open edit is rejected without commit")
	pending.cancel()
	check(doc.revision == rev and doc.history_length() == history and doc.history_position() == cursor and doc.is_dirty() == dirty, "render/encode and pending rejection preserve revision, history and savepoint")
	var lazy: DrawingDocument = DrawingDocument.new("t305-lazy", 16)
	var lazy_layer: String = str(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	var tile_bytes: PackedByteArray = PackedByteArray()
	tile_bytes.resize(16 * 16 * 4)
	var tile_digest: String = DrawingRasterTile.digest_rgba8(tile_bytes, 16)
	check(lazy.register_lazy_chunk(lazy_layer, -1, 0, "missing", tile_digest, func(_ref: String) -> Variant: return null).ok, "lazy missing tile registered")
	var lazy_revision: int = lazy.revision
	var missing: DrawingResult = DrawingRasterExport.render(lazy, Rect2i(-16, 0, 16, 16))
	check(not missing.ok and missing.code == "MISSING_TILE" and lazy.revision == lazy_revision, "missing lazy source fails instead of exporting blank pixels")
	var text_doc: DrawingDocument = DrawingDocument.new("t305-text", 16)
	var text: DrawingTextElement = DrawingTextElement.new()
	text.content = "Export"
	text.position = Vector2i(-10, -8)
	text.font_size = 14
	var text_created: DrawingResult = text_doc.commit_text("", text, text_doc.revision)
	check(text_created.ok, "semantic text committed")
	var text_revision: int = text_doc.revision
	var text_render: DrawingResult = DrawingRasterExport.render(text_doc, Rect2i(-16, -16, 96, 48))
	check(text_render.ok and (text_render.value as Image).get_used_rect().has_area() and text_doc.revision == text_revision and text_doc.node_metadata(str(text_created.value))["kind"] == DrawingLayerNode.TEXT, "semantic text renders without rasterizing source")
	var empty: DrawingDocument = DrawingDocument.new("t305-empty", 16)
	var blank: DrawingResult = DrawingRasterExport.render(empty, Rect2i(-10, -10, 5, 6))
	check(blank.ok, "valid blank frame exports")
	if blank.ok:
		check(not (blank.value as Image).get_used_rect().has_area(), "blank frame retains transparent output")
	# Uniform half-alpha JPEG matte and opaque output, independent expected color.
	var semi: Image = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	semi.fill(Color8(200, 100, 20, 128))
	var before: PackedByteArray = semi.get_data()
	var jpg: DrawingResult = DrawingRasterExport.encode(semi, "jpeg", false, 1.0, Color8(40, 60, 100))
	check(jpg.ok, "JPEG matte encodes")
	if jpg.ok:
		var opaque: Image = decode(jpg.value as PackedByteArray, "jpeg")
		if opaque != null:
			var pixel: Color = opaque.get_pixel(32, 32)
			check(opaque.get_size() == semi.get_size() and pixel.a == 1.0 and absi(pixel.r8 - 120) <= 4 and absi(pixel.g8 - 80) <= 4 and absi(pixel.b8 - 60) <= 4, "JPEG expected opaque matte and dimensions")
	check(semi.get_data() == before, "matting never mutates input")
	check(not DrawingRasterExport.encode(semi, "jpeg", true, 0.9, Color(1, 1, 1, 0.5)).ok, "translucent JPEG matte rejected")
	check(not DrawingRasterExport.encode(semi, "webp", false, -1.0).ok, "invalid applicable quality rejected")
	check(not DrawingRasterExport.encode(semi, "gif").ok, "unsupported codec rejected")
	# Quality must affect actual encoder output and error, not just a UI value.
	var detailed: Image = Image.create_empty(96, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(detailed.get_height()):
		for x: int in range(detailed.get_width()):
			var v: int = (x * 19 + y * 13 + ((x * y) % 47)) % 256
			detailed.set_pixel(x, y, Color8(v, v, v, 255))
	for format: String in ["webp", "jpeg"]:
		var low: DrawingResult = DrawingRasterExport.encode(detailed, format, false, 0.1)
		var high: DrawingResult = DrawingRasterExport.encode(detailed, format, false, 0.95)
		check(low.ok and high.ok and low.value != high.value, format + " applicable quality changes bytes")
		if low.ok and high.ok:
			var low_image: Image = decode(low.value as PackedByteArray, format)
			var high_image: Image = decode(high.value as PackedByteArray, format)
			if low_image != null and high_image != null:
				check(low_image.get_size() == detailed.get_size() and high_image.get_size() == detailed.get_size(), format + " lossy dimensions exact")
				check(rgb_error(high_image, detailed) < rgb_error(low_image, detailed), format + " high quality improves representative color error")
	var lossy_alpha: DrawingResult = DrawingRasterExport.encode(image, "webp", false, 0.85)
	check(lossy_alpha.ok, "lossy WebP with alpha encodes")
	if lossy_alpha.ok:
		var lossy: Image = decode(lossy_alpha.value as PackedByteArray, "webp")
		if lossy != null:
			var alpha_ok: bool = true
			var lossy_bytes: PackedByteArray = lossy.get_data()
			var original_bytes: PackedByteArray = image.get_data()
			for i: int in range(3, original_bytes.size(), 4):
				alpha_ok = alpha_ok and lossy_bytes[i] == original_bytes[i]
			check(alpha_ok, "lossy WebP preserves full alpha plane")
	var folder: String = OS.get_cache_dir().path_join("t305-model-" + DrawingDocument.new_id())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "temporary publication directory")
	var dest: String = folder.path_join("export.png")
	var encoded: DrawingResult = DrawingRasterExport.encode(image, "png")
	if encoded.ok:
		var bytes: PackedByteArray = encoded.value as PackedByteArray
		check(DrawingRasterExport.publish(dest, "png", bytes).ok and FileAccess.get_file_as_bytes(dest) == bytes, "atomic new destination exact bytes")
		var hash: String = FileAccess.get_sha256(dest)
		check(not DrawingRasterExport.publish(dest, "png", bytes).ok and FileAccess.get_sha256(dest) == hash, "unconfirmed overwrite rejected")
		check(not DrawingRasterExport.publish(dest, "png", PackedByteArray(), true).ok and FileAccess.get_sha256(dest) == hash, "failed encode cannot truncate existing file")
		check(not DrawingRasterExport.publish(folder.path_join("bad.drawing"), "png", bytes, true).ok, "native extension cannot be overwritten by export")
		check(not DrawingRasterExport.publish(folder.path_join("missing/out.png"), "png", bytes).ok, "unwritable parent rejected")
		var blocking_directory: String = folder.path_join("directory.png")
		DirAccess.make_dir_absolute(blocking_directory)
		check(not DrawingRasterExport.publish(blocking_directory, "png", bytes, true).ok, "directory cannot be replaced")
		var replacement: PackedByteArray = (DrawingRasterExport.encode(semi, "png").value as PackedByteArray)
		check(DrawingRasterExport.publish(dest, "png", replacement, true).ok and FileAccess.get_file_as_bytes(dest) == replacement, "confirmed overwrite publishes complete replacement")
		check(DirAccess.get_files_at(folder).size() == 1, "no temporary output leaked")
		DirAccess.remove_absolute(dest)
		DirAccess.remove_absolute(blocking_directory)
	DirAccess.remove_absolute(folder)
	print("T305_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T305_MODEL_PASSED")
	quit(1 if failures else 0)
