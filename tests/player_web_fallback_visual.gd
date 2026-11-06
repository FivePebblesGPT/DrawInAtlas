extends SceneTree
## T-044 native Compatibility framebuffer proxy, not a Web browser session.
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WEB FALLBACK VISUAL FAILED: " + why)


func _frames(count: int = 4) -> void:
	for index: int in range(count):
		await process_frame


func _solid(id: String, color: Color) -> AtlasRasterLayer:
	var bitmap: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	bitmap.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(bitmap)
	layer.id = id
	layer.transform.origin = Vector2(-32, -32)
	return layer


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_embed_subwindows = false
	var harness: Window = Window.new()
	harness.size = Vector2i(320, 180)
	root.add_child(harness)
	harness.show()
	var host: Control = Control.new()
	host.size = Vector2(320, 180)
	harness.add_child(host)
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(session.open_embedded(host) and session.window == null,
		"fallback uses provided window, creates no player OS subwindow")
	_check(session.display.texture == null, "display is blank before grant")
	await _frames()
	var blank: Color = harness.get_texture().get_image().get_pixel(160, 90)
	_check(blank.r < 0.15 and blank.g < 0.15 and blank.b < 0.15,
		"real framebuffer is opaque black before authorized render")
	var source: AtlasMapDocument = AtlasMapDocument.new("gm-map", "Private title")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	floor.layers.append(_solid("public", Color.RED))
	floor.layers.append(_solid("secret", Color.GREEN))
	var unchanged: Dictionary = source.to_dict().duplicate(true)
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	frame.set_output_size(Vector2i(1280, 720))
	frame.set_view(Vector2.ZERO, 64.0)
	_check(session.update_frame(frame), "matching frame accepted")
	var grants: Array[String] = ["public"]
	_check(await session.publish(source, floor.id, 0, grants), "authorized capture published")
	var pixel: Color = session.display.texture.get_image().get_pixel(160, 90)
	_check(pixel.r > 0.85 and pixel.g < 0.2, "secret green layer absent from texture")
	await _frames()
	var screen: Color = harness.get_texture().get_image().get_pixel(160, 90)
	_check(screen.r > 0.85 and screen.g < 0.2,
		"actual single-window framebuffer contains only granted red")
	_check(session._capture.canvas.map.id == AtlasPlayerProjection.BOARD_ID \
		and source.to_dict() == unchanged,
		"detached board only, original GM data unmodified")
	session.set_follow(false)
	frame.set_view(Vector2(200, 0), 64)
	_check(session.update_frame(frame) and session.camera_center == Vector2.ZERO \
		and session.display.texture != null, "freeze retains last authorized view")
	session.set_follow(true)
	_check(session.update_frame(frame) and session.display.texture == null,
		"follow invalidates frame after movement")
	_check(await session.publish(source, floor.id, 0, grants), "fresh follow frame published")
	session.invalidate()
	await _frames()
	var cleared: Color = harness.get_texture().get_image().get_pixel(160, 90)
	_check(cleared.r < 0.15 and cleared.g < 0.15,
		"revocation clears real on-screen pixels")
	frame.set_view(Vector2.ZERO, 64)
	_check(session.update_frame(frame), "valid camera can recover")
	session.call_deferred("invalidate")
	_check(not await session.publish(source, floor.id, 0, grants) \
		and session.display.texture == null, "mid-readback revoke rejects stale pixels")
	_check(await session.publish(source, floor.id, 0, grants), "fresh capture after cancellation")
	host.size = Vector2(400, 225)
	_check(session.output_size == Vector2i(400, 225) and session.display.texture == null \
		and not session._frame_set, "host resize invalidates old image and camera")
	_check(session.update_frame(frame), "matching frame reauthorized after resizing")
	_check(await session.publish(source, floor.id, 0, grants), "resized output can publish")
	host.size = Vector2(400, 300)
	_check(not session.update_frame(frame) and session.display.texture == null,
		"aspect mismatch fails closed")
	host.hide()
	_check(session.display.texture == null and not session._frame_set,
		"host visibility loss drops pixels and camera")
	host.show()
	_check(session.display.texture == null, "reopening host remains blank")
	session.close_output()
	_check(session.window == null and session.display == null and session._capture == null,
		"closing removes session output resources")
	root.remove_child(session)
	session.free()
	harness.remove_child(host)
	host.free()
	root.remove_child(harness)
	harness.free()
	print("ATLAS_PLAYER_WEB_FALLBACK_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
