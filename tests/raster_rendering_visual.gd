extends SceneTree
## A one-pixel hard brush edge must not become an interpolated ramp when zoomed.

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(960, 660)
	root.content_scale_size = root.size
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(10):
		await process_frame
	editor.create_board("Crisp pixels", AtlasGrid.new(AtlasGrid.Kind.GRIDLESS, 64))
	var canvas: AtlasCanvas = editor.canvas
	editor.select_layer("raster")
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.show_reference = false
	canvas.camera_center = Vector2.ZERO
	canvas.camera_zoom = 8.0
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(-12.5, 0.5), Vector2(12.5, 0.5)]), Color.WHITE, 1.0), false)
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(canvas.global_position + canvas.size * 0.5)
	for offset: int in range(-4, 12):
		var value: float = image.get_pixelv(center + Vector2i(4, offset)).r
		var expected: float = 1.0 if offset >= 0 and offset < 8 else AtlasCanvas.EMPTY_COLOR.r
		if absf(value - expected) > 0.015:
			failures += 1
			printerr("RASTER EDGE FAILED: offset=%d expected=%f actual=%f" % [offset, expected, value])
	editor.artwork.stroke(AtlasStroke.new(PackedVector2Array([
		Vector2(-8, 4.5), Vector2(8, 4.5)]), Color(1, 1, 1, 0.5), 1.0), false)
	canvas.floor.raster_layer().opacity = 0.5
	canvas.camera_center = Vector2(0, 6)
	var prop: Image = Image.create_empty(32, 16, false, Image.FORMAT_RGBA8)
	prop.fill(Color(1, 1, 1, 0.5))
	editor.artwork.import_prop(prop)
	editor._choose_tool(AtlasCanvas.Tool.WALL_PATH)
	var wall_points: PackedVector2Array = PackedVector2Array()
	for index: int in range(200):
		wall_points.append(Vector2(10, 15) + Vector2.from_angle(float(index) * TAU / 200.0) * 2.0)
	editor.artwork.edit_path(-1, null, AtlasEditablePath.make(wall_points, Color(1, 1, 1, 0.5), 0.5, true))
	canvas.floor.objects_layer().opacity = 0.5
	canvas.queue_redraw()
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	var raster_pixel: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(Vector2(6, 4.5)))
	var object_pixel: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(Vector2(0, 6)))
	var wall_pixel: Vector2i = Vector2i(canvas.global_position + canvas.document_to_local(Vector2(12, 15)))
	var raster_alpha: Color = image.get_pixelv(raster_pixel)
	var object_alpha: Color = image.get_pixelv(object_pixel)
	var wall_alpha: Color = image.get_pixelv(wall_pixel)
	for focused: bool in [false, true]:
		if focused:
			root.focus_entered.emit()
		else:
			root.focus_exited.emit()
		for frame: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
		if image.get_pixelv(raster_pixel) != raster_alpha or image.get_pixelv(object_pixel) != object_alpha \
				or image.get_pixelv(wall_pixel) != wall_alpha:
			failures += 1
			printerr("FOCUS ALPHA FAILED: raster or object opacity changed on focus transition")
	if raster_alpha.r <= AtlasCanvas.EMPTY_COLOR.r or raster_alpha.r >= 0.65 \
			or object_alpha.r <= AtlasCanvas.EMPTY_COLOR.r or object_alpha.r >= 0.65 \
			or wall_alpha.r <= AtlasCanvas.EMPTY_COLOR.r or wall_alpha.r >= 0.65:
		failures += 1
		printerr("FOCUS ALPHA FAILED: source/layer transparency was not preserved")
	canvas.set_document(canvas.map, editor.campaign, canvas.floor.id)
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	image = root.get_texture().get_image()
	if image.get_pixelv(raster_pixel) != raster_alpha or image.get_pixelv(object_pixel) != object_alpha \
			or image.get_pixelv(wall_pixel) != wall_alpha:
		failures += 1
		printerr("CACHE ALPHA FAILED: reopening the same document changed cached artwork")
	root.remove_child(scene)
	scene.free()
	print("ATLAS_RASTER_RENDERING_%s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(0 if failures == 0 else 1)
