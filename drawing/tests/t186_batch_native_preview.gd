extends SceneTree
## T-186: a changed 128px region inside a 256px native tile must not
## recomposite its unchanged 128px neighbors. Preserve warm framebuffer tiles.

var checks: int = 0
var failures: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T186_PREVIEW_FAILED: " + label)


func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw


func framebuffer(canvas: Control, source: Vector2) -> Color:
	var pixel: Vector2i = Vector2i(canvas.global_position + canvas.pixel_to_position(source))
	return root.get_texture().get_image().get_pixelv(pixel)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "graphical framebuffer is required")
		quit(1)
		return
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "native classes registered")
	root.size = Vector2i(1024, 740)
	root.content_scale_size = root.size
	var doc: DrawingDocument = DrawingDocument.new("t186-exact-batch", 256)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Source").value)
	var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04, 0.7, 0.15, 1.0))
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	check(seed.apply_region(Rect2i(-256, 0, 256, 256), image.get_data()).ok and
		seed.commit().ok, "seed full opaque signed storage tile")
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.position = Vector2(10, 10)
	canvas.size = Vector2(1000, 710)
	canvas.camera = Vector2(-128, 128)
	canvas.zoom = 1.4
	canvas.brush_width = 16
	canvas.brush_preset = "hard"
	canvas.color_rgba = 0xffdd3311
	canvas.document = doc
	canvas.layer_id = layer
	root.add_child(canvas)
	for i: int in range(12):
		await frame()
	var neighbor_before: Color = framebuffer(canvas, Vector2(-70, 35))
	check(neighbor_before.g > 0.5, "unmodified neighbor is warm and visible")
	canvas.start_gesture(canvas.pixel_to_position(Vector2(-220, 35)))
	check(canvas.session != null and canvas.session._native_tiles != null,
		"actual native mouse stroke opened")
	canvas.update_gesture(canvas.pixel_to_position(Vector2(-215, 35)))
	for i: int in range(8):
		await frame()
	var edit: DrawingEditSession = canvas.session
	if edit != null:
		var stamps: Dictionary = edit.preview_display_stamps_for_canvas(
			Rect2i(-2, 0, 2, 2), 128)
		check(edit._preview_display_exact and bool(stamps["indexed"]),
			"native dirty batch keeps exact preview index")
		check((stamps["stamps"] as Dictionary).has("-2,0") and
			not (stamps["stamps"] as Dictionary).has("-1,0") and
			not (stamps["stamps"] as Dictionary).has("-2,1"),
			"first batch invalidates only its changed 128px area")
	check(framebuffer(canvas, Vector2(-70, 35)).g > 0.5,
		"unchanged warm neighbor remains visible during native stroke")
	canvas.update_gesture(canvas.pixel_to_position(Vector2(-100, 35)))
	for i: int in range(20):
		await frame()
	edit = canvas.session
	if edit != null:
		var stamps: Dictionary = edit.preview_display_stamps_for_canvas(
			Rect2i(-2, 0, 2, 2), 128)
		check(bool(stamps["indexed"]) and
			(stamps["stamps"] as Dictionary).has("-2,0") and
			(stamps["stamps"] as Dictionary).has("-1,0"),
			"changed neighbor becomes eligible without losing previous tile")
	canvas.finish_gesture(canvas.pixel_to_position(Vector2(-100, 35)))
	for i: int in range(180):
		if canvas.session == null:
			break
		await frame()
	check(canvas.session == null, "native gesture committed")
	check(framebuffer(canvas, Vector2(-70, 100)).g > 0.5,
		"unmodified committed area remains visible")
	var changed: DrawingResult = DrawingRenderer.render(doc, Rect2i(-256, 0, 256, 128))
	check(changed.ok, "committed native source renders")
	if changed.ok:
		var after: PackedByteArray = (changed.value as Image).get_data()
		check(after != image.get_data().slice(0, after.size()),
			"committed native pixels differ from green baseline")
		check(doc.undo().ok, "one-step native undo")
		check(doc.redo().ok, "one-step native redo")
	canvas.queue_free()
	await process_frame
	print("T186_PREVIEW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T186_PREVIEW_PASSED checks=%d failures=0" % checks)
	quit(0 if failures == 0 else 1)
