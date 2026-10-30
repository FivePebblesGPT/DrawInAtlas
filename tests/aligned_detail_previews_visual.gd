extends SceneTree
## T-003 framebuffer witness: alpha compositing and true board-space registration.

var checks: int = 0
var failures: int = 0
var canvas: AtlasCanvas
var references: AtlasMapReferences
var placement: AtlasPlacement
var campaign: AtlasCampaign


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ALIGNED DETAIL PREVIEWS VISUAL FAILED: " + message)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native graphics")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	campaign = _fixture()
	canvas = AtlasCanvas.new()
	canvas.size = Vector2(900, 660)
	canvas.position = Vector2(16, 16)
	root.add_child(canvas)
	_check(canvas.set_document(campaign.get_map("world"), campaign), "same world board owns both hexes")
	canvas.camera_zoom = 2.0
	canvas.camera_center = Vector2.ZERO
	canvas.render_grid = false
	canvas.preview = AtlasCanvas.Preview.MARKERS
	references = AtlasMapReferences.new()
	canvas.add_child(references)
	references.bind(canvas)
	canvas.references = references

	var solid: Vector2 = placement.child_to_parent() * Vector2(128, 96)
	var clear: Vector2 = placement.child_to_parent() * Vector2(42, 140)
	await _frames(5)
	var solid_base: Color = _sample(solid)
	var clear_base: Color = _sample(clear)
	canvas.preview = AtlasCanvas.Preview.OVERLAY
	references.refresh()
	await _frames(20)
	var images: Dictionary = references.get("_children")
	_check(images.has("entrance"), "registered spatial preview captured")
	if images.has("entrance"):
		var source: Image = (images["entrance"].texture as ImageTexture).get_image()
		_check(source.get_pixel(84, 280).a < 0.02, "empty source pixels remain transparent, not opaque board color")
		_check(source.get_pixel(256, 192).b > 0.95 and source.get_pixel(256, 192).a > 0.95,
			"source color and alpha survive the capture")
	_check(_near_color(_sample(clear), clear_base, 0.06), "transparent preview leaves underlying hex artwork visible")
	_check(_sample(solid).b > solid_base.b + 0.4, "opaque preview composites at its registered board point")
	await _save("aligned-transparent-preview.png")

	# A camera transform or changed grid can never detach the registered image.
	canvas.camera_center = Vector2(24, -18)
	canvas.camera_zoom = 3.1
	await _frames(20)
	_check(_near_color(_sample(clear), clear_base, 0.06), "transparent region survives camera pan and zoom")
	_check(_sample(solid).b > solid_base.b + 0.4, "opaque region follows pan/zoom at unchanged document coordinates")
	canvas.map.grid.rotation += deg_to_rad(20)
	canvas.map.grid.cell_size = 58.0
	canvas.queue_redraw()
	await _frames(3)
	_check(_sample(solid).b > solid_base.b + 0.4, "grid rotation and scaling cannot move authored detail")
	await _save("aligned-preview-zoomed.png")

	# Empty D1 and a crossing D1 ink layer remain on the same board, not a new hex document.
	var child: AtlasMapDocument = campaign.get_map("child")
	var capture: AtlasMapCapture = AtlasMapCapture.new()
	canvas.add_child(capture)
	var blank: Image = await capture.capture(campaign, child, "ground", placement.child_bounds(), Vector2i(128, 96), true, 1)
	_check(blank != null and blank.get_pixel(64, 48).a < 0.02, "empty D1 capture stays truly transparent")
	capture.queue_free()
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.camera_center = Vector2(0, 180)
	canvas.camera_zoom = 2.0
	_check(canvas.set_presented_detail_level(1), "manually switch authored artwork group on the same board")
	await _frames(5)
	_check(_sample(Vector2(0, 180)).r > 0.9 and _sample(Vector2(0, 180)).b < 0.2,
		"D1 vector crosses adjacent hexes and chunk seams without per-cell preview images")
	_check(campaign.maps.size() == 2 and canvas.map.id == "world",
		"legacy child link remains distinct and does not create one document per hex")
	canvas.free()
	print("ATLAS_ALIGNED_DETAIL_PREVIEWS_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture() -> AtlasCampaign:
	var result: AtlasCampaign = AtlasCampaign.new()
	result.root_map_id = "world"
	var world: AtlasMapDocument = AtlasMapDocument.new("world", "Continuous world")
	world.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	world.grid.rotation = deg_to_rad(37.0)
	world.grid.visible = false
	var base: Image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	base.fill(Color.GREEN)
	var base_raster: AtlasRasterLayer = AtlasRasterLayer.from_image(base)
	base_raster.transform.origin = Vector2(-256, -256)
	world.floors[0].layers.append(base_raster)
	var d1: AtlasInkLayer = AtlasInkLayer.new("fine-ink", "Continuous detail")
	d1.detail_level = 1
	d1.strokes.append(AtlasStroke.new(PackedVector2Array([
		Vector2(-280, 180), Vector2(280, 180)]), Color.RED, 12.0))
	world.floors[0].layers.append(d1)
	var child: AtlasMapDocument = AtlasMapDocument.new("child", "Legacy linked artwork")
	child.grid.visible = false
	var alpha: Image = Image.create(256, 192, false, Image.FORMAT_RGBA8)
	alpha.fill(Color.TRANSPARENT)
	alpha.fill_rect(Rect2i(120, 88, 16, 16), Color.BLUE)
	child.floors[0].layers.append(AtlasRasterLayer.from_image(alpha))
	result.add_map(world)
	result.add_map(child)
	placement = AtlasPlacement.new()
	placement.id = "placed"
	placement.parent_map_id = "world"
	placement.child_map_id = "child"
	placement.columns = 4
	placement.rows = 3
	placement.origin = Vector2(-60, -50)
	placement.rotation = deg_to_rad(37.0)
	placement.parent_units_per_cell = 30.0
	placement.child_units_per_cell = 64.0
	result.placements.append(placement)
	var link: AtlasMapLink = AtlasMapLink.new()
	link.id = "entrance"
	link.source_map_id = "world"
	link.target_map_id = "child"
	link.placement_id = placement.id
	result.links.append(link)
	return result


func _sample(position: Vector2) -> Color:
	var pixels: Image = root.get_texture().get_image()
	var pixel: Vector2i = Vector2i(canvas.position + canvas.document_to_local(position))
	return pixels.get_pixelv(pixel) if Rect2i(Vector2i.ZERO, pixels.get_size()).has_point(pixel) else Color.TRANSPARENT


func _near_color(actual: Color, expected: Color, tolerance: float) -> bool:
	return absf(actual.r - expected.r) < tolerance and absf(actual.g - expected.g) < tolerance \
		and absf(actual.b - expected.b) < tolerance


func _frames(count: int) -> void:
	for frame: int in range(count):
		await process_frame
	await RenderingServer.frame_post_draw


func _save(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://validation")
	_check(root.get_texture().get_image().save_png("user://validation/" + filename) == OK,
		"native screenshot " + filename)
