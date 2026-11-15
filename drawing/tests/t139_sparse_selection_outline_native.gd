extends SceneTree
## Native framebuffer proof of sparse explicit-mask outlines at 25% zoom.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T139_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int = 4) -> void:
	for _i: int in range(n):
		await process_frame

func changed_pixels(first: Image, second: Image, center: Vector2i) -> int:
	var changed: int = 0
	for y: int in range(center.y - 5, center.y + 6):
		for x: int in range(center.x - 5, center.x + 6):
			if x < 0 or y < 0 or x >= first.get_width() or y >= first.get_height():
				continue
			var before: Color = first.get_pixel(x, y)
			var after: Color = second.get_pixel(x, y)
			if absf(before.r - after.r) + absf(before.g - after.g) \
					+ absf(before.b - after.b) > 0.06:
				changed += 1
	return changed

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var doc: DrawingDocument = DrawingDocument.new("t139-native", 128)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(120, 60)
	canvas.size = Vector2(1680, 960)
	canvas.zoom = 0.25
	canvas.tool = "Pan"
	canvas.document = doc
	canvas.layer_id = layer
	var mask: DrawingSelection = DrawingSelection.new()
	mask.set_rectangle(Rect2i(-4000, -2600, 8000, 5200))
	var pixels: Dictionary[Vector2i, bool] = {}
	for y: int in range(16):
		for x: int in range(16):
			pixels[Vector2i(-2800 + x, -1400 + y)] = true
			pixels[Vector2i(2900 + x, 1500 + y)] = true
	mask.set_mask(pixels)
	canvas.set_selection_mask(mask, false)
	root.add_child(canvas)
	canvas.set_process(false)
	await frames(6)
	var tiles: int = canvas._mask_outline_cache.size()
	check(tiles == 2, "two distant selected pixels consume two contour tiles")
	check(canvas._mask_outline_cache.has(Vector2i(-44, -22)),
		"negative island is represented in active selection outline cache")
	check(canvas._mask_outline_cache.has(Vector2i(45, 23)),
		"far positive island remains visible beyond old row-major 4096 cap")
	var picked: Image = root.get_texture().get_image()
	var a: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(-2800, -1400)))
	var b: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(2900, 1500)))
	var revision: int = doc.revision
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(4)
	var cleared: Image = root.get_texture().get_image()
	var first_diff: int = changed_pixels(picked, cleared, a)
	var second_diff: int = changed_pixels(picked, cleared, b)
	check(first_diff > 0, "first distant pixel changes actual framebuffer outline")
	check(second_diff > 0, "far positive pixel changes actual framebuffer outline")
	check(doc.revision == revision and doc.tile_keys(layer).is_empty(),
		"selection overlay does not publish raster content")
	canvas.set_selection_mask(mask, false)
	await frames(4)
	check(canvas._mask_outline_cache.size() == 2,
		"selection re-entry rebuilds only occupied contour tiles")
	print("T139_NATIVE_METRICS " + JSON.stringify({"mask_tiles": tiles,
		"first_pixel_delta": first_diff, "second_pixel_delta": second_diff}))
	print("T139_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
