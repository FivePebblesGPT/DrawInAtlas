extends SceneTree
## Native framebuffer proof that an overlapping outline survives window shift.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T145_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 2) -> void:
	for _i: int in range(count):
		await process_frame

func changed_pixels(first: Image, second: Image, center: Vector2i) -> int:
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

func clipped_footprint(canvas: Control, selection: DrawingSelection) -> Rect2i:
	var start: Vector2 = (Vector2.ZERO - canvas.size * 0.5) / canvas.zoom + canvas.camera
	var finish: Vector2 = (canvas.size - canvas.size * 0.5) / canvas.zoom + canvas.camera
	var visible: Rect2i = Rect2i(Vector2i(floori(start.x), floori(start.y)),
		Vector2i(ceili(finish.x) - floori(start.x), ceili(finish.y) - floori(start.y)))
	return selection.bounds.intersection(visible.grow(1))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 renderer required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var document: DrawingDocument = DrawingDocument.new("t145-window-pan", 128)
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
	var selection: DrawingSelection = DrawingSelection.new()
	selection.set_rectangle(Rect2i(-6000, -3000, 12000, 6000))
	var target: Vector2i = Vector2i(15, 0)
	var pixels: Dictionary[Vector2i, bool] = {}
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			pixels[target * 64 + Vector2i(x, y)] = true
	selection.set_mask(pixels)
	check(selection.combine_rectangle(Rect2i(20000, 20000, 1, 1), "Subtract"),
		"compound selection retains exact pixel island")
	canvas.set_selection_mask(selection, false)
	await frames(3)
	var before_window: Rect2i = canvas._mask_outline_window
	var before: Array[Vector2i] = canvas._mask_outline_tile_candidates(clipped_footprint(canvas, selection))
	check(before.size() == 4096 and before.has(target), "saturated plan contains target")
	# Populate a settled plan without taking 1024 software-GPU draw frames.
	canvas._mask_outline_cache.clear()
	for tile: Vector2i in before:
		canvas._mask_outline_cache[tile] = PackedVector2Array()
	canvas._mask_outline_cache[target] = selection.contour_segments(
		Rect2i(target * 64, Vector2i(64, 64)))
	check(not canvas._mask_outline_cache[target].is_empty(), "target has exact source contour")
	canvas.camera = Vector2(64, 0)
	var after: Array[Vector2i] = canvas._mask_outline_tile_candidates(clipped_footprint(canvas, selection))
	check(after.size() == 4096 and after.has(target), "new plan is saturated with target still eligible")
	canvas.queue_redraw()
	await frames(2)
	check(canvas._mask_outline_window != before_window, "panning moved visible contour tile window")
	check(canvas._mask_outline_cache.has(target),
		"shared distant island remains cached after actual window translation")
	check(canvas._mask_outline_cache.size() > 3500 and canvas._mask_outline_cache.size() <= 4096,
		"thousands of shared contours survive within the hard cap")
	var outlined: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(
		Vector2(target * 64 + Vector2i(12, 12))))
	var moved_window: Rect2i = canvas._mask_outline_window
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(2)
	var cleared: Image = root.get_texture().get_image()
	var delta: int = changed_pixels(outlined, cleared, center)
	check(delta > 0, "far island remains visibly outlined in the actual framebuffer")
	check(document.tile_keys(layer).is_empty() and document.revision == 1,
		"outline-cache continuity never changes document pixels or history")
	check(canvas._mask_outline_cache.is_empty(), "deselect still clears old contour cache")
	print("T145_NATIVE_METRICS " + JSON.stringify({"before_window": str(before_window),
		"after_window": str(moved_window), "framebuffer_delta": delta}))
	print("T145_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
