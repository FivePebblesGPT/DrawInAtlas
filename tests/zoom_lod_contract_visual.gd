extends SceneTree
## Historical T-004 native fit witness. Uses the manual presentation setter;
## T-005 separately exercises the live automatic presentation controller.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("ZOOM LOD VISUAL FAILED: " + description)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires X11/native renderer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(820, 620)
	root.content_scale_size = Vector2i(820, 620)
	var board: AtlasMapDocument = AtlasMapDocument.new("world", "Continuous board")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	board.grid.origin = Vector2(17, -31)
	board.grid.rotation = deg_to_rad(37.0)
	board.grid.visible = false
	var center: Vector2 = board.grid.cell_to_document(Vector2i(2, -1))
	var overview: AtlasInkLayer = board.floors[0].ink_layer()
	var detail: AtlasInkLayer = AtlasInkLayer.new("local", "Local authored artwork")
	detail.detail_level = 1
	board.floors[0].layers.append(detail)
	var stroke_points: PackedVector2Array = PackedVector2Array([
		center - Vector2(26, 0), center + Vector2(26, 0)])
	overview.strokes.append(AtlasStroke.new(stroke_points, Color.RED, 10.0))
	detail.strokes.append(AtlasStroke.new(stroke_points, Color.GREEN, 10.0))
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = board.id
	campaign.add_map(board)
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 600)
	canvas.position = Vector2(10, 10)
	root.add_child(canvas)
	_check(canvas.set_document(board, campaign), "open one continuous board")
	canvas.camera_center = center
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.render_grid = false
	canvas.active_layer_id = overview.id
	await _witness(canvas, center, Color.RED, "zoom-lod-overview.png")

	# Reuse the historical fit witness; expanded zoom is implemented under T-005.
	var polygon: PackedVector2Array = board.grid.cell_polygon(Vector2i(2, -1))
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	canvas.camera_zoom = minf(0.8 * canvas.size.x / bounds.size.x,
		0.8 * canvas.size.y / bounds.size.y)
	_check(canvas.camera_zoom > 3.0 and canvas.camera_zoom < AtlasMapNavigator.MAX_ZOOM,
		"local fit is now inside expanded navigator range beyond historical 3x")
	_check(canvas.set_presented_detail_level(1), "explicitly present local authored level")
	await _witness(canvas, center, Color.GREEN, "zoom-lod-local-fit.png")
	_check(canvas.active_layer_id == overview.id and not canvas.editing_target_is_presented(),
		"local inspection does not silently retarget the D0 edit layer")

	canvas.camera_zoom = 1.0
	_check(canvas.set_presented_detail_level(0), "explicitly return to overview")
	await _witness(canvas, center, Color.RED, "zoom-lod-return.png")
	_check(canvas.map == board and campaign.maps.size() == 1,
		"overview/local/overview sequence never changes source board")
	canvas.free()
	print("ATLAS_ZOOM_LOD_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _witness(canvas: AtlasCanvas, point: Vector2, color: Color, filename: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var center: Vector2i = Vector2i(canvas.position + canvas.document_to_local(point))
	_check(pixels.get_pixelv(center).is_equal_approx(color),
		"%s renders authored level at unchanged board position" % filename)
	var folder: String = "user://validation"
	DirAccess.make_dir_recursive_absolute(folder)
	_check(pixels.save_png(folder.path_join(filename)) == OK, "saved %s" % filename)
