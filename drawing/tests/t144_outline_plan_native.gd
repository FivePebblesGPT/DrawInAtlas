extends SceneTree
## Native X11 preview witnesses reuse exact outline eligibility while contour
## generation is deferred across many frames, then rebuild after a camera pan.
var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T144_NATIVE_FAILED: " + message)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int = 2) -> void:
	for i: int in range(n):
		await process_frame

func changed_pixels(a: Image, b: Image, location: Vector2i) -> int:
	var count: int = 0
	for y: int in range(location.y - 7, location.y + 8):
		for x: int in range(location.x - 7, location.x + 8):
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height():
				continue
			var one: Color = a.get_pixel(x, y)
			var two: Color = b.get_pixel(x, y)
			if absf(one.r - two.r) + absf(one.g - two.g) + absf(one.b - two.b) > 0.06:
				count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 display required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var document: DrawingDocument = DrawingDocument.new("t144-outline", 128)
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
	selection.set_rectangle(Rect2i(-4096, -4096, 8192, 8192))
	var pixels: Dictionary[Vector2i, bool] = {}
	for ty: int in range(-24, 24):
		for tx: int in range(-47, 48):
			pixels[Vector2i(tx * 64 + 8, ty * 64 + 8)] = true
	# A 16x16 center island yields reliable screen-space contours at 25% zoom.
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			pixels[Vector2i(x, y)] = true
	selection.set_mask(pixels)
	canvas.set_selection_mask(selection, false)
	await frames(4)
	check(pixels.size() == 4815, "bounded real mask includes 4560 occupied tiles")
	check(canvas._mask_outline_cache.size() > 0 and canvas._mask_outline_cache.size() <= 16,
		"native frames populate contours in groups of at most four")
	check(canvas.get("_mask_outline_plan_build_count") == 1,
		"deferred redraws reuse the same candidate plan")
	var plan: Array[Vector2i] = canvas._mask_outline_tile_candidates(
		Rect2i(-3361, -1921, 6722, 3842).intersection(selection.bounds))
	check(plan.size() == 4096, "native visible plan respects 4096 contour limit")
	var before: int = int(canvas.get("_mask_outline_plan_build_count")) if canvas.get("_mask_outline_plan_build_count") != null else -1
	await frames(2)
	check(canvas.get("_mask_outline_plan_build_count") == before,
		"subsequent contour frames do not rebuild eligible tiles")
	var outline: Image = root.get_texture().get_image()
	var point: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(16, 16)))
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(2)
	var cleared: Image = root.get_texture().get_image()
	var delta: int = changed_pixels(outline, cleared, point)
	check(delta > 0, "cached sparse outline remains visible in real framebuffer")
	check(document.tile_keys(layer).is_empty() and document.revision == 1,
		"outline planning never publishes pixels or history")
	canvas.set_selection_mask(selection, false)
	await frames(3)
	var reenter: int = int(canvas.get("_mask_outline_plan_build_count")) if canvas.get("_mask_outline_plan_build_count") != null else -1
	canvas.camera = Vector2(64, 0)
	canvas.queue_redraw()
	await frames(3)
	check(int(canvas.get("_mask_outline_plan_build_count")) if canvas.get("_mask_outline_plan_build_count") != null else -1 == reenter + 1,
		"camera pan creates one new focal plan, reused across deferred frames")
	check(canvas._mask_outline_cache.size() <= canvas.MAX_MASK_OUTLINE_CACHE,
		"camera pan preserves hard contour cache ceiling")
	print("T144_NATIVE_METRICS " + JSON.stringify({"changed_pixels": delta,
		"plan_builds": canvas.get("_mask_outline_plan_build_count"),
		"cached_contours": canvas._mask_outline_cache.size()}))
	print("T144_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
