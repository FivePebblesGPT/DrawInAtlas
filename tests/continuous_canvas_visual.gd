extends SceneTree
## Native framebuffer witness for T-002: adjacent hexes render as one line,
## and changing presented detail does not replace the authored editing target.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		printerr("CONTINUOUS CANVAS VISUAL FAILED: " + description)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native Xvfb/Mesa framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(820, 620)
	root.content_scale_size = Vector2i(820, 620)
	var board: AtlasMapDocument = AtlasMapDocument.new("hex-world", "Shared hex board")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 48.0)
	board.grid.visible = false
	var floor: AtlasFloor = board.floors[0]
	var overview: AtlasInkLayer = floor.ink_layer()
	var detail: AtlasInkLayer = AtlasInkLayer.new("detail", "Separately authored")
	detail.detail_level = 1
	floor.layers.append(detail)
	var first: Vector2 = board.grid.cell_to_document(Vector2i(-1, 0))
	var last: Vector2 = board.grid.cell_to_document(Vector2i(2, 0))
	var sample: Array[Vector2] = [first, first.lerp(last, 0.5), last]
	var wide: float = 20.0
	overview.strokes.append(AtlasStroke.new(PackedVector2Array([first, last]), Color.RED, wide))
	detail.strokes.append(AtlasStroke.new(PackedVector2Array([first, last]), Color.GREEN, wide))
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 600)
	canvas.position = Vector2(10, 10)
	root.add_child(canvas)
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = board.id
	campaign.add_map(board)
	_check(canvas.set_document(board, campaign), "opens a single shared board")
	canvas.active_layer_id = "ink"
	canvas.camera_center = first.lerp(last, 0.5)
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.render_grid = false
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	for point: Vector2 in sample:
		var pixel: Vector2i = Vector2i(canvas.position + canvas.document_to_local(point))
		_check(pixels.get_pixelv(pixel).is_equal_approx(Color.RED),
			"D0 line is uninterrupted through adjacent hex at %s" % str(point))
	var path: String = "user://validation"
	DirAccess.make_dir_recursive_absolute(path)
	_check(pixels.save_png(path.path_join("continuous-hex-d0.png")) == OK,
		"overview framebuffer witness saved")
	_check(canvas.set_presented_detail_level(1), "switch to authored local detail")
	await process_frame
	await RenderingServer.frame_post_draw
	pixels = root.get_texture().get_image()
	for point: Vector2 in sample:
		var pixel: Vector2i = Vector2i(canvas.position + canvas.document_to_local(point))
		_check(pixels.get_pixelv(pixel).is_equal_approx(Color.GREEN),
			"D1 line uses identical board coordinates at %s" % str(point))
	_check(canvas.active_layer_id == "ink" and not canvas.editing_target_is_presented(),
		"presented detail changed, explicit ink edit target stayed D0")
	_check(pixels.save_png(path.path_join("continuous-hex-d1.png")) == OK,
		"local detail framebuffer witness saved")
	root.remove_child(canvas)
	canvas.free()
	print("ATLAS_CONTINUOUS_CANVAS_VISUAL_%s failures=%d" % [
		"PASSED" if _failures == 0 else "FAILED", _failures])
	quit(0 if _failures == 0 else 1)
