extends SceneTree
## T-042: assert actual native player framebuffer is filtered before rendering.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FOG VISUAL FAILED: " + label)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(640, 480)
	root.content_scale_size = root.size
	var source: AtlasMapDocument = AtlasMapDocument.new("gm-secret", "Do not publish")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	var pixels: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.RED)
	var paint: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	paint.id = "approved"
	paint.transform.origin = Vector2(-32, -32)
	floor.layers.append(paint)
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-32, -32, 32, 64), true))
	var grants: Array[String] = ["approved"]
	var player: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source, floor.id, 0, grants)
	_check(player != null, "fog-filtered player capture generated")
	var board: AtlasMapDocument = player.get_map(player.root_map_id) if player != null else null
	var renderer: AtlasMapCapture = AtlasMapCapture.new()
	root.add_child(renderer)
	var rect: Rect2 = Rect2(-32, -32, 64, 64)
	var output: Image = await renderer.capture(player, board, board.default_floor_id,
		rect, Vector2i(128, 128)) if board != null else null
	_check(output != null, "native output renders filtered input")
	if output != null:
		var left: Color = output.get_pixel(32, 64)
		var right: Color = output.get_pixel(96, 64)
		_check(left.r > 0.9 and left.g < 0.2, "revealed room visible on player framebuffer")
		_check(right.r < 0.4 and right.g < 0.4, "hidden room absent from player framebuffer")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-32, -32, 32, 64), false))
	player = AtlasPlayerProjection.build_capture_input(source, floor.id, 0, grants)
	board = player.get_map(player.root_map_id) if player != null else null
	output = await renderer.capture(player, board, board.default_floor_id,
		rect, Vector2i(128, 128)) if board != null else null
	_check(output != null and output.get_pixel(32, 64).r < 0.4,
		"re-hide removes formerly revealed pixels from player framebuffer")
	root.remove_child(renderer)
	renderer.free()
	# Fog state changing during asynchronous native window capture must not
	# republish a now-stale frame, even if the image was already sanitized.
	root.gui_embed_subwindows = false
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(session.open_native(Vector2i(320, 180)), "independent player window opens")
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	frame.set_output_size(Vector2i(1280, 720))
	frame.set_view(Vector2.ZERO, 64.0)
	_check(session.update_frame(frame), "player camera matches window aspect")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-32, -32, 64, 64), true))
	floor.set_deferred("fog_enabled", false)
	_check(not await session.publish(source, floor.id, 0, grants),
		"fog revision during capture invalidates in-flight publication")
	_check(session.display.texture == null, "stale fog capture keeps player window blank")
	_check(await session.publish(source, floor.id, 0, grants),
		"new stable state can publish an authorized frame")
	session.invalidate()
	_check(session.display.texture == null, "explicit fog revocation clears frozen imagery")
	session.close_native()
	root.remove_child(session)
	session.free()
	print("ATLAS_FOG_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
