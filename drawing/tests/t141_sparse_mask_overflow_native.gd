extends SceneTree
## Software-X11 framebuffer check for an over-capacity explicit mask outline.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T141_NATIVE_FAILED: " + label)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 4) -> void:
	for _i: int in range(count):
		await process_frame

func changed_pixels(first: Image, second: Image, position: Vector2i) -> int:
	var changed: int = 0
	for y: int in range(position.y - 5, position.y + 6):
		for x: int in range(position.x - 5, position.x + 6):
			if x < 0 or y < 0 or x >= first.get_width() or y >= first.get_height():
				continue
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				changed += 1
	return changed

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "native X11 is required")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.mode = Window.MODE_WINDOWED
	var document: DrawingDocument = DrawingDocument.new("t141-native", 128)
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
	var before: Image = root.get_texture().get_image()
	var mask: DrawingSelection = DrawingSelection.new()
	var bounds: Rect2i = Rect2i(-3500, -2000, 7000, 4000)
	mask.set_rectangle(bounds)
	var sparse: Dictionary[Vector2i, bool] = {}
	for radius: int in range(50, -1, -1):
		for y: int in range(-27, 28):
			for x: int in range(-50, 51):
				if maxi(absi(x), absi(y)) != radius:
					continue
				sparse[Vector2i(x * 64 + 8, y * 64 + 8)] = true
				if sparse.size() >= 4250:
					break
			if sparse.size() >= 4250:
				break
		if sparse.size() >= 4250:
			break
	var target: Vector2i = Vector2i(38, 0)
	for y: int in range(8, 24):
		for x: int in range(8, 24):
			sparse[target * 64 + Vector2i(x, y)] = true
	mask.set_mask(sparse)
	canvas.set_selection_mask(mask, false)
	await frames(3)  # Establish the selection window before priming retained tiles.
	var candidates: Array[Vector2i] = canvas._mask_outline_tile_candidates(bounds)
	check(sparse.size() > canvas.MAX_MASK_OUTLINE_CACHE, "over-budget explicit mask prepared")
	check(candidates.size() == canvas.MAX_MASK_OUTLINE_CACHE, "candidate budget stays fixed")
	check(candidates.has(target), "far occupied island is in bounded outline plan")
	# Simulate tiles already traced on preceding frames; we still require a
	# real Godot renderer to trace and display the remaining target outline.
	canvas._mask_outline_cache.clear()
	var pending_target: bool = false
	for tile: Vector2i in candidates:
		if tile == target:
			pending_target = true
			break
		canvas._mask_outline_cache[tile] = PackedVector2Array()
	check(pending_target, "target eventually becomes eligible for contour tracing")
	canvas.queue_redraw()
	await frames(4)
	check(canvas._mask_outline_cache.has(target), "remaining target contour is rendered")
	var with_mask: Image = root.get_texture().get_image()
	var pixel: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(
		Vector2(target * 64 + Vector2i(12, 12))))
	var changed: int = changed_pixels(before, with_mask, pixel)
	check(changed > 0, "real framebuffer includes far occupied island outline")
	check(document.tile_keys(layer).is_empty() and document.revision == 1,
		"selection overlay never publishes raster pixels or history")
	canvas.set_selection_mask(DrawingSelection.new(), false)
	await frames(2)
	check(not canvas.selection_mask.enabled and canvas._mask_outline_cache.is_empty(),
		"deselect invalidates cached contours")
	print("T141_NATIVE_METRICS " + JSON.stringify({"far_island_pixel_delta": changed,
		"chosen_tile_count": candidates.size()}))
	print("T141_NATIVE_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
