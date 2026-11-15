extends SceneTree
## Real X11 framebuffer: a sub-tile pan swaps one selected edge island while
## the selection tile window and focal tile remain unchanged.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T143_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 2) -> void:
	for _i: int in range(count):
		await process_frame

func pixel_delta(first: Image, second: Image, center: Vector2i) -> int:
	var changed: int = 0
	for y: int in range(center.y - 6, center.y + 7):
		for x: int in range(center.x - 6, center.x + 7):
			if x < 0 or y < 0 or x >= first.get_width() or y >= first.get_height():
				continue
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				changed += 1
	return changed

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 display required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var document: DrawingDocument = DrawingDocument.new("t143-clip", 128)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(120, 60)
	canvas.size = Vector2(1680, 960)
	canvas.zoom = 0.25
	canvas.tool = "Pan"
	canvas.document = document
	canvas.layer_id = layer
	root.add_child(canvas)
	canvas.set_process(false)
	await frames(3)
	var mask: DrawingSelection = DrawingSelection.new()
	mask.set_rectangle(Rect2i(-3500, -2000, 7000, 4000))
	var pixels: Dictionary[Vector2i, bool] = {}
	for ty: int in range(-26, 27):
		for tx: int in range(-39, 40):
			if pixels.size() >= 4095:
				break
			pixels[Vector2i(tx * 64 + 8, ty * 64 + 8)] = true
		if pixels.size() >= 4095:
			break
	for y: int in range(8, 24):
		for x: int in range(-3359, -3354):
			pixels[Vector2i(x, y)] = true
		for x: int in range(3362, 3368):
			pixels[Vector2i(x, y)] = true
	mask.set_mask(pixels)
	canvas.set_selection_mask(mask, false)
	await frames(3)
	var before_window: Rect2i = canvas._mask_outline_window
	var before_focus: Vector2i = canvas._mask_outline_focus
	var before: Array[Vector2i] = canvas._mask_outline_tile_candidates(
		Rect2i(-3361, -1921, 6722, 3842).intersection(mask.bounds))
	var old_tile: Vector2i = Vector2i(-53, 0)
	var new_tile: Vector2i = Vector2i(52, 0)
	check(before.size() == canvas.MAX_MASK_OUTLINE_CACHE, "baseline clipped plan saturated")
	check(before.has(old_tile) and not before.has(new_tile), "only old edge is initially visible")
	canvas._mask_outline_cache.clear()
	for tile: Vector2i in before:
		canvas._mask_outline_cache[tile] = PackedVector2Array()
	canvas.camera = Vector2(8, 0)
	var after: Array[Vector2i] = canvas._mask_outline_tile_candidates(
		Rect2i(-3353, -1921, 6722, 3842).intersection(mask.bounds))
	check(after.size() == canvas.MAX_MASK_OUTLINE_CACHE, "new clipped plan saturated")
	check(after.has(new_tile) and not after.has(old_tile), "edge islands trade visibility")
	canvas.queue_redraw()
	await frames(3)
	check(canvas._mask_outline_window == before_window and canvas._mask_outline_focus == before_focus,
		"camera remains within the same contour window and focal cell")
	check(canvas._mask_outline_cache.has(new_tile), "newly visible edge tile gets traced")
	check(not canvas._mask_outline_cache.has(old_tile), "old edge tile evicted to make room")
	check(canvas._mask_outline_cache.size() <= canvas.MAX_MASK_OUTLINE_CACHE,
		"contour cache never exceeds 4096 tiles")
	var outlined: Image = root.get_texture().get_image()
	var pixel: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(3364, 12)))
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(2)
	var clear: Image = root.get_texture().get_image()
	var delta: int = pixel_delta(outlined, clear, pixel)
	check(delta > 0, "new edge island has a visible outline in the real framebuffer")
	check(document.tile_keys(layer).is_empty() and document.revision == 1,
		"selection overlay never modifies raster pixels or history")
	print("T143_NATIVE_METRICS " + JSON.stringify({"edge_pixel_delta": delta,
		"old_plan": before.size(), "new_plan": after.size()}))
	print("T143_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
