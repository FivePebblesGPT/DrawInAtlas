extends SceneTree
## T-039 native proof: only explicitly granted pixels enter the capture input.
## A projector window is not implemented; output policy still needs approval.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PROJECTION VISUAL FAILED: " + reason)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(640, 480)
	root.content_scale_size = root.size
	var source: AtlasMapDocument = AtlasMapDocument.new("gm-board", "Private source")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	var public: AtlasRasterLayer = _solid("public", Color.RED)
	var secret: AtlasRasterLayer = _solid("secret", Color.GREEN)
	floor.layers.append(public)
	floor.layers.append(secret)
	var granted: Array[String] = ["public"]
	var campaign: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source, floor.id, 0, granted)
	_check(campaign != null, "public-only capture input built")
	if campaign == null:
		quit(1)
		return
	var output: AtlasMapDocument = campaign.get_map(campaign.root_map_id)
	var renderer: AtlasMapCapture = AtlasMapCapture.new()
	root.add_child(renderer)
	var rect: Rect2 = Rect2(-32, -32, 64, 64)
	var size: Vector2i = Vector2i(128, 128)
	var image: Image = await renderer.capture(campaign, output, output.default_floor_id, rect, size)
	_check(image != null, "detached view renders via shared native capture")
	if image != null:
		var pixel: Color = image.get_pixel(64, 64)
		_check(pixel.r > 0.9 and pixel.g < 0.1 and pixel.b < 0.1,
			"player-visible center is public red, never GM-secret green")
	var denied: Array[String] = []
	campaign = AtlasPlayerProjection.build_capture_input(source, floor.id, 0, denied)
	var blank: AtlasMapDocument = campaign.get_map(campaign.root_map_id)
	image = await renderer.capture(campaign, blank, blank.default_floor_id, rect, size)
	_check(image != null, "zero grants still render a blank board")
	if image != null:
		var pixel: Color = image.get_pixel(64, 64)
		_check(pixel.g < 0.4 and pixel.r < 0.4 and pixel.b < 0.4,
			"no grant does not fall back to source artwork")
	root.remove_child(renderer)
	renderer.free()
	print("ATLAS_PLAYER_PROJECTION_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _solid(id: String, color: Color) -> AtlasRasterLayer:
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	layer.id = id
	layer.transform.origin = Vector2(-32, -32)
	return layer
