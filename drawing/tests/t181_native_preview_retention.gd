extends SceneTree
## Real framebuffer regression for disappearing 128px tiles during native motion.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T181_PREVIEW_FAILED: " + label)


func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func missing_tiles(canvas: Control) -> int:
	var framebuffer: Image = root.get_texture().get_image()
	var missing: int = 0
	for y: int in range(-2, 2):
		for x: int in range(-2, 2):
			var at: Vector2 = Vector2(x * 128 + 64, y * 128 + 64)
			var screen: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(at))
			var color: Color = framebuffer.get_pixelv(screen)
			# Both the green source and blue pigment remain saturated; checker /
			# backdrop colors cannot stand in for a missing source texture.
			if color.r > 0.3 or color.g + color.b < 0.6:
				missing += 1
	return missing


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "requires a real graphical framebuffer")
		quit(1)
		return
	check(ClassDB.class_exists("DrawingNativeBrush") and ClassDB.class_exists("DrawingNativeTiles"),
		"required native classes registered")
	root.size = Vector2i(1000, 720)
	root.content_scale_size = root.size
	var document: DrawingDocument = DrawingDocument.new("t181-preview-retention", 256)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Source").value)
	var image: Image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.7, 0.15, 1.0))
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision).value
	check(seed.apply_region(Rect2i(-256, -256, 512, 512), image.get_data()).ok and seed.commit().ok,
		"sixteen committed display tiles seeded")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(20, 20)
	canvas.size = Vector2(900, 640)
	canvas.zoom = 0.54
	canvas.camera = Vector2.ZERO
	canvas.image_bounds = Rect2i(-256, -256, 512, 512)
	canvas.clip_strokes_to_image_frame = true
	canvas.brush_width = 96.0
	canvas.brush_preset = "hard"
	canvas.color_rgba = 0xffdd3311
	canvas.document = document
	canvas.layer_id = layer
	root.add_child(canvas)
	for i: int in range(12):
		await frame()
	check(missing_tiles(canvas) == 0, "committed source is fully visible before stroke")
	var revision: int = document.revision
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-200, -200), Vector2(200, -200), Vector2(200, 200), Vector2(-200, 200),
		Vector2(-200, -150), Vector2(150, -150), Vector2(150, 150), Vector2(-150, 150),
		Vector2(-150, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)])
	canvas.start_gesture(canvas.pixel_to_position(points[0]))
	check(canvas.session != null and canvas.session._native_tiles != null,
		"pointer gesture uses actual Hokusai native tiles")
	for i: int in range(1, points.size()):
		canvas.update_gesture(canvas.pixel_to_position(points[i]))
		await frame()
		var missing: int = missing_tiles(canvas)
		print("T181_MOVING frame=%d missing=%d metrics=%s" % [i, missing, JSON.stringify(canvas.last_frame_metrics)])
		check(missing == 0, "moving frame %d preserves all committed/preview tiles" % i)
	check(document.revision == revision, "held preview has not published source")
	for i: int in range(8):
		await frame()
	check(missing_tiles(canvas) == 0 and canvas.dragging,
		"stationary held cursor retains complete framebuffer without ending stroke")
	canvas.finish_gesture(canvas.pixel_to_position(points[points.size() - 1]))
	for i: int in range(120):
		if canvas.session == null:
			break
		await frame()
	await frame()
	check(canvas.session == null and document.revision == revision + 1,
		"one complete native gesture commits")
	check(missing_tiles(canvas) == 0, "committed framebuffer remains complete")
	canvas.queue_free()
	await process_frame
	print("T181_PREVIEW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T181_PREVIEW_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
