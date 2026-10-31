extends SceneTree
## T-040 native two-window proof. The GM source is never attached to the output.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PLAYER OUTPUT VISUAL FAILED: " + description)


func _solid(id: String, color: Color) -> AtlasRasterLayer:
	var bitmap: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	bitmap.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(bitmap)
	layer.id = id
	layer.transform.origin = Vector2(-32, -32)
	return layer


func _frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(800, 600)
	root.gui_embed_subwindows = false
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(session.open_native(Vector2i(320, 180)), "native output window can open")
	if session.window == null:
		quit(1)
		return
	await _frames(5)
	_check(session.window.visible and session.window.get_window_id() != DisplayServer.INVALID_WINDOW_ID,
		"player has an independent OS window")
	_check(session.display.texture == null, "window is blank before an explicit grant")
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	frame.set_output_size(Vector2i(1280, 720))
	frame.set_view(Vector2.ZERO, 64.0)
	_check(session.update_frame(frame), "camera follows GM frame with matching aspect")
	var source: AtlasMapDocument = AtlasMapDocument.new("gm-map", "Secret campaign")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	floor.layers.append(_solid("public", Color.RED))
	floor.layers.append(_solid("private", Color.GREEN))
	var original: Dictionary = source.to_dict().duplicate(true)
	var grant: Array[String] = ["public"]
	_check(await session.publish(source, floor.id, 0, grant), "authorized layer renders to player window")
	_check(session.display.texture != null, "capture is displayed in the new window")
	if session.display.texture != null:
		var pixel: Color = session.display.texture.get_image().get_pixel(160, 90)
		_check(pixel.r > 0.9 and pixel.g < 0.1, "only authorized red pixels reach player texture")
	await _frames()
	var screen: Image = session.window.get_texture().get_image()
	_check(screen != null and screen.get_size().x > 0, "OS window has a framebuffer")
	if screen != null:
		var center: Color = screen.get_pixel(screen.get_width() / 2, screen.get_height() / 2)
		_check(center.r > 0.85 and center.g < 0.2, "separate window visibly renders only authorized red")
	_check(source.to_dict() == original, "player rendering never mutates GM artwork")
	_check(session._capture.canvas.map.id == AtlasPlayerProjection.BOARD_ID \
		and session._capture.canvas.campaign.root_map_id == AtlasPlayerProjection.BOARD_ID,
		"player renderer owns only the sanitized board, never the GM document")

	session.set_follow(false)
	frame.set_view(Vector2(200, 0), 64)
	_check(session.update_frame(frame) and session.camera_center == Vector2.ZERO,
		"freeze retains previous camera despite GM frame motion")
	_check(session.display.texture != null, "freeze retains last authorized pixels")
	session.set_follow(true)
	_check(session.update_frame(frame) and session.camera_center == Vector2(200, 0),
		"follow resumes explicitly and updates independent player camera")
	_check(session.display.texture == null, "moving camera invalidates previous player image")
	_check(await session.publish(source, floor.id, 0, grant), "new frame renders after following")
	if session.display.texture != null:
		var shifted: Color = session.display.texture.get_image().get_pixel(160, 90)
		_check(shifted.r < 0.4 and shifted.g < 0.4, "new camera does not retain out-of-frame old pixels")

	# Unapproved grants and revocation must blank even when frozen.
	session.set_follow(false)
	var bad: Array[String] = ["nonexistent"]
	_check(not await session.publish(source, floor.id, 0, bad), "stale publication grant rejected")
	_check(session.display.texture == null, "invalid grant clears frozen output")
	_check(await session.publish(source, floor.id, 0, grant), "valid grant can resume after denial")
	session.invalidate()
	_check(session.display.texture == null, "revocation blanks authorized image synchronously")
	frame.set_view(Vector2.ZERO, 64.0)
	session.set_follow(true)
	session.update_frame(frame)
	session.call_deferred("invalidate")
	_check(not await session.publish(source, floor.id, 0, grant), "mid-render revocation rejects in-flight image")
	_check(session.display.texture == null, "in-flight capture cannot republish revoked pixels")
	var wrong_aspect: AtlasProjectorFrame = AtlasProjectorFrame.new()
	wrong_aspect.set_output_size(Vector2i(1000, 1000))
	_check(not session.update_frame(wrong_aspect) and session.display.texture == null,
		"aspect mismatch fails closed rather than stretching output")
	_check(not await session.publish(source, floor.id, 0, grant),
		"a rejected frame cannot silently reuse an older authorized camera")
	# Revocation removes actual screen pixels, not only a resource reference.
	_check(session.update_frame(frame), "authorized camera can recover after rejected aspect")
	_check(await session.publish(source, floor.id, 0, grant), "granted frame can be shown before revocation")
	await _frames()
	session.invalidate()
	await _frames(4)
	var cleared: Image = session.window.get_texture().get_image()
	var clear_pixel: Color = cleared.get_pixel(cleared.get_width() / 2, cleared.get_height() / 2)
	_check(clear_pixel.r < 0.8 and clear_pixel.g < 0.8, "revocation visibly removes old public frame from OS window")
	# Resizing changes render resolution, not physical calibration or frame size.
	var measured: bool = session.calibration.set_measurements(700.0, 25.0)
	var width_before: float = session.camera_width
	session.window.size = Vector2i(480, 270)
	await _frames(6)
	_check(measured and session.output_size == Vector2i(480, 270) \
		and session.camera_width == width_before and session.display.texture == null,
		"native resize invalidates pixels without altering camera span or physical calibration")
	_check(session.update_frame(frame), "same aspect can reauthorize at new output resolution")
	_check(await session.publish(source, floor.id, 0, grant), "resized window can republish sanitized art")
	session.window.size = Vector2i(480, 300)
	await _frames(6)
	_check(not session.update_frame(frame) and session.display.texture == null,
		"different window aspect requires an explicit frame aspect change")
	session.close_native()
	_check(session.window == null and session.display == null, "closing output releases published surface")
	root.remove_child(session)
	session.free()
	print("ATLAS_PLAYER_OUTPUT_SESSION_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
