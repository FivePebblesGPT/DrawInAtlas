extends SceneTree
## Real software-X11 framebuffer verification of retained contour tiles on pan.
var checks: int = 0
var failures: int = 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T142_NATIVE_FAILED: " + description)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i: int in range(count):
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
		check(false, "real X11 display required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var document: DrawingDocument = DrawingDocument.new("t142-pan", 128)
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
	mask.set_rectangle(Rect2i(-2880, -1600, 5760, 3200))
	var target: Vector2i = Vector2i(15, 0)
	var pixels: Dictionary[Vector2i, bool] = {}
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			pixels[target * 64 + Vector2i(x, y)] = true
	mask.set_mask(pixels)
	check(mask.combine_rectangle(Rect2i(10000, 10000, 1, 1), "Subtract"),
		"compound mask uses bounded conservative traversal without changing pixels")
	canvas.set_selection_mask(mask, false)
	await frames(3)
	var original_window: Rect2i = canvas._mask_outline_window
	var initial: Array[Vector2i] = canvas._mask_outline_tile_candidates(mask.bounds)
	check(initial.size() == canvas.MAX_MASK_OUTLINE_CACHE,
		"outline window contains more than 4096 candidate tiles")
	check(initial.has(target), "actual selected island is part of focal contour plan")
	# All other candidates are truly empty; seed valid cached empty contours to
	# simulate a settled over-budget frame without 1024 expensive draw callbacks.
	canvas._mask_outline_cache.clear()
	for tile: Vector2i in initial:
		canvas._mask_outline_cache[tile] = PackedVector2Array()
	canvas._mask_outline_cache[target] = mask.contour_segments(
		Rect2i(target * 64, Vector2i(64, 64)))
	check(not canvas._mask_outline_cache[target].is_empty(), "island has real contour edges")
	var initial_count: int = canvas._mask_outline_cache.size()
	canvas.camera = Vector2(64, 0)
	var next: Array[Vector2i] = canvas._mask_outline_tile_candidates(mask.bounds)
	check(next.has(target), "target is eligible both before and after pan")
	canvas.queue_redraw()
	await frames(2)
	check(canvas._mask_outline_window == original_window,
		"camera pans inside unchanged contour tile window")
	check(canvas._mask_outline_cache.has(target),
		"overlapping target contours survive focus change without waiting 100+ frames")
	check(canvas._mask_outline_cache.size() > 3500 and canvas._mask_outline_cache.size() <= initial_count,
		"thousands of eligible contours survive while the 4096 budget holds")
	var outlined: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(
		Vector2(target * 64 + Vector2i(12, 12))))
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(2)
	var cleared: Image = root.get_texture().get_image()
	var delta: int = pixel_delta(outlined, cleared, center)
	check(delta > 0, "retained distant island remains outlined in actual framebuffer after pan")
	check(document.tile_keys(layer).is_empty() and document.revision == 1,
		"cache reuse never publishes selection pixels or document history")
	check(canvas._mask_outline_cache.is_empty(), "deselect clears all retained contours")
	print("T142_NATIVE_METRICS " + JSON.stringify({"retained": initial_count,
		"after_pan": next.size(), "far_pixel_delta": delta}))
	print("T142_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
