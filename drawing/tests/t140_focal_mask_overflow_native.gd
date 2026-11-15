extends SceneTree
## Actual X11 framebuffer evidence for the first cold outline frame near focus.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T140_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 4) -> void:
	for _i: int in range(count):
		await process_frame

func changed_pixels(first: Image, second: Image, point: Vector2i) -> int:
	var changed: int = 0
	for y: int in range(point.y - 5, point.y + 6):
		for x: int in range(point.x - 5, point.x + 6):
			if x < 0 or y < 0 or x >= first.get_width() or y >= first.get_height():
				continue
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
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
	var doc: DrawingDocument = DrawingDocument.new("t140-native", 128)
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
	for y: int in range(-30, 31):
		for x: int in range(-52, 53):
			pixels[Vector2i(x * 64 + 8, y * 64 + 8)] = true
			if pixels.size() > canvas.MAX_MASK_OUTLINE_CACHE + 64:
				break
		if pixels.size() > canvas.MAX_MASK_OUTLINE_CACHE + 64:
			break
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			pixels[Vector2i(x, y)] = true
	mask.set_mask(pixels)
	canvas.set_selection_mask(mask, false)
	root.add_child(canvas)
	canvas.set_process(false)
	await frames(5)
	var first: Array[Vector2i] = canvas._mask_outline_tile_candidates(
		canvas.selected.intersection(Rect2i(-3361, -1921, 6722, 3842)))
	check(first.size() == canvas.MAX_MASK_OUTLINE_CACHE, "over-capacity mask has bounded candidates")
	check(first[0] == Vector2i.ZERO, "initial outline work prioritizes the focal tile")
	check(canvas._mask_outline_cache.size() <= canvas.MASK_OUTLINE_TILES_PER_FRAME * 5,
		"cold outline population respects four new tiles per draw")
	check(canvas._mask_outline_cache.has(Vector2i.ZERO), "focal contour tile is cached promptly")
	var selected_frame: Image = root.get_texture().get_image()
	var focal: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(Vector2(15, 15)))
	var revision: int = doc.revision
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(3)
	var cleared_frame: Image = root.get_texture().get_image()
	var delta: int = changed_pixels(selected_frame, cleared_frame, focal)
	check(delta > 0, "focal selection outline changes the actual framebuffer")
	check(doc.revision == revision and doc.tile_keys(layer).is_empty(),
		"overlay does not change canonical raster or history")
	# A selection wholly inside the viewport keeps the *same* clipped tile
	# window as the camera moves. Even a full old cache must be invalidated
	# when focus changes, otherwise the new focal contour cannot be visited.
	var compact: DrawingSelection = DrawingSelection.new()
	compact.set_rectangle(Rect2i(-2600, -1700, 5200, 3400))
	var dense_tiles: Dictionary[Vector2i, bool] = {}
	for tile_y: int in range(-26, 27):
		for tile_x: int in range(-40, 41):
			dense_tiles[Vector2i(tile_x * 64 + 8, tile_y * 64 + 8)] = true
	compact.set_mask(dense_tiles)
	canvas.set_selection_mask(compact, false)
	canvas.camera = Vector2.ZERO
	canvas.queue_redraw()
	await frames(3)
	var previous_window: Rect2i = canvas._mask_outline_window
	canvas._mask_outline_cache.clear()
	for index: int in range(canvas.MAX_MASK_OUTLINE_CACHE):
		canvas._mask_outline_cache[Vector2i(8000 + index, 8000)] = PackedVector2Array()
	canvas.camera = Vector2(128, 0)
	canvas.queue_redraw()
	await frames(3)
	check(canvas._mask_outline_window == previous_window,
		"panning inside the selection keeps the same outline tile window")
	check(canvas._mask_outline_cache.has(Vector2i(2, 0)),
		"focal change evicts an old full cache and traces the new focal tile")
	check(canvas._mask_outline_cache.size() <= 3 * canvas.MASK_OUTLINE_TILES_PER_FRAME,
		"cache re-entry only populates the current bounded frame budget")
	print("T140_NATIVE_METRICS " + JSON.stringify({"focal_pixel_delta": delta,
		"cached_after_pan": canvas._mask_outline_cache.size()}))
	print("T140_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
