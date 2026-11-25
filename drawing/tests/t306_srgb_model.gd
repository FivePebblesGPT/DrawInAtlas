extends "t305_export_model.gd"
## Independent encoded-sRGB byte oracles, not a comparison between two implementations.

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T306_MODEL_FAILED: " + label)


## Independent fixtures: LittleCMS-created linear RGB profile with D65 white,
## sRGB primaries and gamma=1, attached by Pillow to 16x16 RGB(64,128,192).
## A color-managed decode should yield about (137,188,225), not (64,128,192).
## Store fixtures as text to avoid LFS or runtime Pillow/LittleCMS dependencies.
func profile_fixtures() -> Dictionary:
	return {
		"png": (
			"iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAABaGlDQ1BJQ0MgUHJvZmlsZQAAeJx1kb1Lw1AUxU8/pEqLOnRQcOhQ" +
			"nVoQdejgoHXoUqTUCiouyWvaCkkakhQproKOBQdRBL/+B10FFxcnQRHEP8BJEF2kxPOM2CL2PvLuj8M7N+/eBwQzujCc8BxgmK5d" +
			"zGUTK6tricgLohjFINeAIhxrvlDIo2d83CMg811a1up97t+IljVHAIF+8oywbJc8S85vupbkXXJc1JQy+YicsnlB8o3UVZ+fJFd9" +
			"fpVsl4oLQDBMHq52sdrFomYb5Dg5aegN8XMf2UlMM5eXmEf4jaGIHLJIQEUDG9DhIs1s9vBMfnsWUadDcLfQhM3zVdToTFFtwIHG" +
			"XKGuceloypn/naVTmZ7yq8eyQN+z572NA5E9oN3yvM9Tz2ufASH2fmV2/PUTIPNOvdXRksfA0DZwcd3R1H3gcoctPlqKrfy+Bv/t" +
			"z4URktv5A1Da4nPcAgeHwESFtda/AGn+Yu2WKv7+AAAAGUlEQVR4nGN0aDjAQApgIkn1qIZRDUNKAwDIzAGgj7vl2wAAAABJRU5E" +
			"rkJggg=="
		),
		"webp": (
			"UklGRnACAABXRUJQVlA4WAoAAAAgAAAADwAADwAASUNDUDgCAAAAAAI4bGNtcwRAAABtbnRyUkdCIFhZWiAH6gALABkADgAOAAlh" +
			"Y3NwQVBQTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9tYAAQAAAADTLWxjbXMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
			"AAAAAAAAAAAAAAAAAAAAAAAAAAtkZXNjAAABCAAAADRjcHJ0AAABPAAAAEx3dHB0AAABiAAAABRjaGFkAAABnAAAACxyWFlaAAAB" +
			"yAAAABRiWFlaAAAB3AAAABRnWFlaAAAB8AAAABRyVFJDAAACBAAAABBnVFJDAAACBAAAABBiVFJDAAACBAAAABBjaHJtAAACFAAA" +
			"ACRtbHVjAAAAAAAAAAEAAAAMZW5VUwAAABgAAAAcAFIARwBCACAAYgB1AGkAbAB0AC0AaQBubWx1YwAAAAAAAAABAAAADGVuVVMA" +
			"AAAwAAAAHABOAG8AIABjAG8AcAB5AHIAaQBnAGgAdAAsACAAdQBzAGUAIABmAHIAZQBlAGwAeVhZWiAAAAAAAAD21gABAAAAANMt" +
			"c2YzMgAAAAAAAQxCAAAF3v//8yUAAAeTAAD9kP//+6H///2iAAAD3AAAwG5YWVogAAAAAAAAb6AAADj1AAADkFhZWiAAAAAAAAAk" +
			"nwAAD4QAALbDWFlaIAAAAAAAAGKXAAC3hwAAGNlwYXJhAAAAAAAAAAAAAQAAY2hybQAAAAAAAwAAAACj1wAAVHsAAEzNAACZmgAA" +
			"JmYAAA9cVlA4TBEAAAAvD8ADAAdQwAIVuP+BiOh/AAA="
		),
		"jpeg": (
			"/9j/4AAQSkZJRgABAQAAAQABAAD/4gJISUNDX1BST0ZJTEUAAQEAAAI4bGNtcwRAAABtbnRyUkdCIFhZWiAH6gALABkADgAOAAlh" +
			"Y3NwQVBQTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9tYAAQAAAADTLWxjbXMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
			"AAAAAAAAAAAAAAAAAAAAAAAAAAtkZXNjAAABCAAAADRjcHJ0AAABPAAAAEx3dHB0AAABiAAAABRjaGFkAAABnAAAACxyWFlaAAAB" +
			"yAAAABRiWFlaAAAB3AAAABRnWFlaAAAB8AAAABRyVFJDAAACBAAAABBnVFJDAAACBAAAABBiVFJDAAACBAAAABBjaHJtAAACFAAA" +
			"ACRtbHVjAAAAAAAAAAEAAAAMZW5VUwAAABgAAAAcAFIARwBCACAAYgB1AGkAbAB0AC0AaQBubWx1YwAAAAAAAAABAAAADGVuVVMA" +
			"AAAwAAAAHABOAG8AIABjAG8AcAB5AHIAaQBnAGgAdAAsACAAdQBzAGUAIABmAHIAZQBlAGwAeVhZWiAAAAAAAAD21gABAAAAANMt" +
			"c2YzMgAAAAAAAQxCAAAF3v//8yUAAAeTAAD9kP//+6H///2iAAAD3AAAwG5YWVogAAAAAAAAb6AAADj1AAADkFhZWiAAAAAAAAAk" +
			"nwAAD4QAALbDWFlaIAAAAAAAAGKXAAC3hwAAGNlwYXJhAAAAAAAAAAAAAQAAY2hybQAAAAAAAwAAAACj1wAAVHsAAEzNAACZmgAA" +
			"JmYAAA9c/9sAQwABAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
			"/9sAQwEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB/8AAEQgA" +
			"EAAQAwERAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUS" +
			"ITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0" +
			"dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX2" +
			"9/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXET" +
			"IjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKD" +
			"hIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwD" +
			"AQACEQMRAD8A8fr/AFYP81woAKACgD//2Q=="
		),
	}


func check_native_pigments() -> void:
	var preset: String = FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb")
	var samples: PackedFloat32Array = PackedFloat32Array([-4.5, -0.5, 1.0, 0.01, 4.5, -0.5, 1.0, 0.01])
	for rgb: int in [0x000000, 0x010101, 0x0a0a0a, 0x0b0b0b, 0x404040, 0x808080, 0xc0c0c0, 0xfefefe, 0xffffff, 0xc08040, 0x00ff00, 0xff00ff]:
		var engine: Object = ClassDB.instantiate("DrawingNativeBrush")
		var started: Dictionary = engine.call("begin_stroke", "swatch", preset, 8.0, rgb | 0xff000000, 1, Rect2i())
		var handle: int = int(started.get("handle", 0))
		var appended: Dictionary = engine.call("append_samples", handle, 1, samples)
		var preview: Dictionary = engine.call("preview_changes", handle, 1)
		var pixels: PackedInt32Array = preview.get("changes", PackedInt32Array())
		var count: int = 0
		var exact: bool = true
		for i: int in range(2, pixels.size(), 3):
			var rgba: int = pixels[i] & 0xffffffff
			if (rgba >> 24) == 255:
				count += 1
				exact = exact and (rgba & 0xffffff) == rgb
		check(bool(started.get("ok", false)) and bool(appended.get("ok", false)) and bool(preview.get("ok", false)) and count > 0 and exact, "actual native opaque pigment matches %06x" % rgb)
		engine.call("acknowledge_batch", handle, 1, true)
		engine.call("abort_stroke", handle)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and ClassDB.class_exists("DrawingNativeBrush"), "mandatory Rust storage and brush")
	check_native_pigments()
	var raw: PackedByteArray = PackedByteArray()
	# Include transfer-function knee, midtone, saturation, alpha ramp and hidden RGB.
	for i: int in range(256):
		raw.append_array(PackedByteArray([i, 255 - i, 128, i]))
	var image: Image = Image.create_from_data(256, 1, false, Image.FORMAT_RGBA8, raw)
	var original: PackedByteArray = image.save_png_to_buffer()
	var encoded: DrawingResult = DrawingRasterExport.encode(image, "png")
	check(encoded.ok, "PNG encoded")
	if not encoded.ok:
		quit(1)
		return
	var png: PackedByteArray = encoded.value as PackedByteArray
	# PNG sRGB chunk, perceptual intent (0), CRC independently calculated with zlib.
	var tag: PackedByteArray = "000000017352474200aece1ce9".hex_decode()
	check(png.slice(33, 46) == tag, "PNG explicitly declares sRGB after IHDR")
	var png_image: Image = decode(png, "png")
	check(png_image != null and png_image.get_data() == raw, "PNG all 256 encoded channels and alpha exact, including hidden RGB")
	# A valid gAMA=1 PNG (no sRGB declaration). libpng applies a gamma-2.2
	# approximation, not the exact piecewise sRGB transfer. Alpha is untouched.
	var gamma: PackedByteArray = original.slice(0, 33)
	gamma.append_array("0000000467414d41000186a031e8965f".hex_decode())
	gamma.append_array(original.slice(46))
	var assumed: Image = decode(gamma, "png")
	if assumed != null:
		var decoded_gamma: PackedByteArray = assumed.get_data()
		var gamma_ok: bool = true
		for offset: int in range(0, raw.size(), 4):
			for channel: int in range(3):
				var expected: int = roundi(pow(float(raw[offset + channel]) / 255.0, 1.0 / 2.2) * 255.0)
				gamma_ok = gamma_ok and absi(decoded_gamma[offset + channel] - expected) <= 1
			gamma_ok = gamma_ok and decoded_gamma[offset + 3] == raw[offset + 3]
		check(gamma_ok, "PNG gAMA=1 decoder uses power 1/2.2 and retains linear alpha")
	var fixtures: Dictionary = profile_fixtures()
	for format: String in fixtures:
		var fixture: PackedByteArray = Marshalls.base64_to_raw(fixtures[format])
		var profiled: Image = decode(fixture, format)
		if profiled != null:
			var color: Color = profiled.get_pixel(8, 8)
			print("T306_PROFILE ", format, " ", color.to_html())
			check(absi(color.r8 - 64) <= 3 and absi(color.g8 - 128) <= 3 and absi(color.b8 - 192) <= 3 and color.a8 == 255, format + " ICC not transformed: samples assumed sRGB")
	var doc: DrawingDocument = DrawingDocument.new("t306-srgb", 16)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Gradient").value)
	check(DrawingRasterImport.import_image(doc, layer, png_image, -128, -1, doc.revision).ok, "signed gradient imported through canonical storage")
	var same: bool = true
	for i: int in range(256):
		same = same and int(doc.read_pixel(layer, i - 128, -1).value) == raw.decode_u32(i * 4)
	check(same, "native tile bytes match every imported RGB/alpha sample")
	var path: String = OS.get_cache_dir().path_join("t306-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "native save")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok, "native reopen")
	if reopened.ok:
		var restored: DrawingDocument = reopened.value as DrawingDocument
		same = true
		for i: int in range(256):
			same = same and int(restored.read_pixel(layer, i - 128, -1).value) == raw.decode_u32(i * 4)
		check(same, "native file preserves gradient and hidden RGB without transfer conversion")
	DirAccess.remove_absolute(path)
	# Existing non-Brush source-over is in encoded byte space: 50% white over
	# black is 128, not the linear-light result 188; alpha remains linear.
	var bottom: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Black").value)
	var top: String = str(doc.create_layer(DrawingLayerNode.RASTER, "White").value)
	fill(doc, bottom, Rect2i(-2, 2, 2, 1), 0xff000000)
	fill(doc, top, Rect2i(-2, 2, 2, 1), 0x80ffffff)
	var composite: DrawingResult = DrawingRasterExport.render(doc, Rect2i(-2, 2, 2, 1))
	check(composite.ok and (composite.value as Image).get_data().decode_u32(0) == 0xff808080, "encoded sRGB layer source-over: 128, not 188")
	var edit: DrawingEditSession = doc.begin_edit(top, doc.revision).value
	check(edit.paint_polygon(PackedVector2Array([Vector2(-2, 2), Vector2(0, 2), Vector2(0, 3), Vector2(-2, 3)]), 0x80000000, null, 1048576, Rect2i(), true).ok and edit.commit().ok, "native translucent polygon edit")
	check(int(doc.read_pixel(top, -2, 2).value) == 0xc0555555, "native encoded source-over with fractional output alpha: 85/192")
	# Lossless WebP is implicitly sRGB (no ICCP); alpha > 0 is exact. Hidden RGB
	# is a document contract, not a detached visible-composite codec contract.
	var visible: Image = image.duplicate()
	visible.set_pixel(0, 0, Color8(0, 0, 0, 0))
	exact_roundtrip(visible, "webp")
	var flat: Image = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	flat.fill(Color8(64, 128, 192, 255))
	var jpeg: DrawingResult = DrawingRasterExport.encode(flat, "jpeg", false, 1.0)
	check(jpeg.ok, "JPEG encodes known sRGB swatch")
	if jpeg.ok:
		var decoded: Image = decode(jpeg.value as PackedByteArray, "jpeg")
		if decoded != null:
			var c: Color = decoded.get_pixel(16, 16)
			check(absi(c.r8 - 64) <= 3 and absi(c.g8 - 128) <= 3 and absi(c.b8 - 192) <= 3 and c.a8 == 255, "JPEG swatch within lossy tolerance, no gamma shift")
	print("T306_MODEL: %d checks; %d failed" % [checks, failures])
	if failures == 0:
		print("T306_MODEL_PASSED")
	quit(1 if failures else 0)
