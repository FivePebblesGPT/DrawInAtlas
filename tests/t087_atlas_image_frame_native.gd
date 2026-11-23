extends SceneTree
## T-087: a real Atlas detail's Drawing frame is visual guidance, not a
## clipping policy or a replacement for the host's canonical raster source.

var checks: int = 0
var failures: int = 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T087_ATLAS_FAILED: " + description)


func frames(count: int = 4) -> void:
	for _index: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func sample(canvas: Control, source: Vector2) -> Color:
	var image: Image = root.get_texture().get_image()
	var target: Vector2i = Vector2i(root.get_final_transform() * (canvas.global_position + canvas.pixel_to_position(source)))
	if target.x < 0 or target.y < 0 or target.x >= image.get_width() or target.y >= image.get_height():
		return Color(-1, -1, -1)
	return image.get_pixelv(target)


func difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "X11 software framebuffer required")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(780, 540)
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var registry: AtlasDrawingRegistry = AtlasDrawingRegistry.new()
	check(registry.attach_campaign(campaign).ok, "real Atlas campaign registry attaches")
	check(registry.ensure_detail("world", "ground", 1, 2, 1, 64).ok,
		"independent high-detail Atlas Drawing document exists")
	var document: DrawingDocument = registry.document_at("world", "ground", 1, true).value as DrawingDocument
	check(document != null, "document comes from Atlas rather than standalone file")
	if document == null:
		quit(1)
		return
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Art").value)
	var tile_data: PackedByteArray = PackedByteArray()
	tile_data.resize(64 * 64 * 4)
	# One colored pixel inside the guide and one *outside* it; the outside
	# pixel is part of the authoritative sparse Atlas source, not a crop.
	tile_data.encode_u32((1 * 64 + 1) * 4, 0xff00aa44)
	tile_data.encode_u32((1 * 64 + 30) * 4, 0xff0000ff)
	var tile: DrawingRasterTile = DrawingRasterTile.from_rgba8(64, tile_data)
	document._nodes[layer].tiles["0,0"] = tile
	var original: PackedByteArray = (document.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8()
	var revision: int = document.revision
	var history: int = document.history_length()
	var canvas: Control = Control.new()
	canvas.set_script(load("res://addons/drawing/canvas.gd"))
	canvas.size = Vector2(620, 470)
	canvas.position = Vector2(30, 20)
	root.add_child(canvas)
	canvas.document = document
	canvas.layer_id = layer
	canvas.image_bounds = Rect2i(-12, -12, 24, 24)
	canvas.clip_strokes_to_image_frame = false
	canvas.zoom = 3.0
	canvas.camera = Vector2.ZERO
	canvas.show_grid = false
	canvas.snap_to_grid = false
	await frames(8)
	var inside: Color = sample(canvas, Vector2(0.5, 0.5))
	var outside: Color = sample(canvas, Vector2(30.5, 1.5))
	check(inside.a > 0.99 and inside.r > 0.3 and inside.r < 0.9,
		"embedded Atlas canvas draws fixed-pixel checker inside the image frame")
	check(outside.r > 0.8 and outside.g < 0.25 and outside.b < 0.25,
		"Atlas pixels outside finite image frame still appear in framebuffer")
	var grid_before: Color = sample(canvas, Vector2(9.0, 5.0))
	canvas.show_grid = true
	canvas.grid_spacing = 12
	canvas.grid_origin = Vector2i(-3, 5)
	canvas.queue_redraw()
	await frames()
	check(difference(grid_before, sample(canvas, Vector2(9.0, 5.0))) > 0.015,
		"Atlas renderer shows source-aligned grid without changing raster bytes")
	check(difference(outside, sample(canvas, Vector2(30.5, 1.5))) < 0.025,
		"drawing grid cannot tint Atlas artwork outside the frame")
	var candidate: Vector2 = canvas.pixel_to_position(Vector2(8.3, 8.2))
	check(canvas.position_to_pixel(candidate) == Vector2i(8, 8),
		"Show grid does not enable snapping for Atlas input")
	canvas.snap_to_grid = true
	check(canvas.position_to_pixel(candidate) == Vector2i(9, 5),
		"explicit snap uses same signed grid intersections as standalone Drawing")
	canvas.show_grid = false
	check(canvas.position_to_pixel(candidate) == Vector2i(9, 5),
		"hiding guide lines leaves snapping enabled")
	canvas.image_bounds = Rect2i(-8, -8, 16, 16)
	canvas.zoom = 2.0
	canvas.queue_redraw()
	await frames()
	check(sample(canvas, Vector2(30.5, 1.5)).r > 0.8,
		"moving/resizing guide never crops existing Atlas raster display")
	root.size = Vector2i(1180, 780)
	canvas.queue_redraw()
	await frames(5)
	check(sample(canvas, Vector2(30.5, 1.5)).r > 0.8,
		"Atlas view scales from compact to full desktop with source display unchanged")
	canvas.camera = Vector2(4, -3)
	canvas.queue_redraw()
	await frames(4)
	check(sample(canvas, Vector2(30.5, 1.5)).r > 0.8,
		"Atlas camera pan does not crop off-guide source artwork")
	check(document.revision == revision and document.history_length() == history and
		(document.request_chunk(layer, "0,0").value as DrawingRasterTile).to_rgba8() == original,
		"frame, grid, snap and camera view changes preserve Atlas RGBA8/history")
	check(not canvas.clip_strokes_to_image_frame,
		"Atlas can explicitly keep unbounded source editing while guide is present")
	print("T087_ATLAS: %d checks; %d failures" % [checks, failures])
	if failures == 0:
		print("T087_ATLAS_PASSED")
	quit(1 if failures else 0)
