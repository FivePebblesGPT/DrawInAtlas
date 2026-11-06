extends SceneTree
## T-043 native GM/player witness. Inspect player texture AND the OS framebuffer.
## The renderer receives only the isolated, sanitized projection campaign.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PLAYER PRIVACY VISUAL FAILED: " + description)


func _solid(id: String, color: Color, detail: int = 0) -> AtlasRasterLayer:
	var pixels: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	layer.id = id
	layer.detail_level = detail
	layer.transform.origin = Vector2(-32, -32)
	return layer


func _frames(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame


func _is_red(pixel: Color) -> bool:
	return pixel.r > 0.8 and pixel.g < 0.25 and pixel.b < 0.25


func _is_blue(pixel: Color) -> bool:
	return pixel.b > 0.75 and pixel.g < 0.3 and pixel.r < 0.3


func _is_hidden(pixel: Color) -> bool:
	return pixel.r < 0.45 and pixel.g < 0.45 and pixel.b < 0.45


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(800, 600)
	root.gui_embed_subwindows = false
	var session: AtlasPlayerOutputSession = AtlasPlayerOutputSession.new()
	root.add_child(session)
	_check(session.open_native(Vector2i(320, 180)), "independent player OS window created")
	if session.window == null:
		quit(1)
		return
	var frame: AtlasProjectorFrame = AtlasProjectorFrame.new()
	frame.set_output_size(Vector2i(1280, 720))
	frame.set_view(Vector2.ZERO, 64.0)
	_check(session.update_frame(frame), "matching frame explicitly authorized")
	var source: AtlasMapDocument = AtlasMapDocument.new("gm-private", "Secret GM map")
	var floor: AtlasFloor = source.floors[0]
	floor.layers.clear()
	var public: AtlasRasterLayer = _solid("public", Color.RED)
	floor.layers.append(public)
	floor.layers.append(_solid("private-green", Color.GREEN))
	var detailed: AtlasRasterLayer = _solid("public-d1", Color.BLUE, 1)
	floor.layers.append(detailed)
	floor.layers.append(_solid("private-d1-green", Color.GREEN, 1))
	var tokens: AtlasTokenLayer = AtlasTokenLayer.new("gm-token", "Secret tokens")
	tokens.tokens.append(AtlasToken.new("dragon", Vector2(-10, 0), "SECRET DRAGON"))
	floor.layers.append(tokens)
	var notes: AtlasObjectsLayer = AtlasObjectsLayer.new("gm-note", "Secret labels")
	var label: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2(-10, 0)]), Color.WHITE, 16)
	label.text = "SECRET PASSWORD"
	notes.strokes.append(label)
	floor.layers.append(notes)
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-32, -32, 32, 64), true))
	var grants: Array[String] = ["public"]
	_check(await session.publish(source, floor.id, 0, grants), "public D0 capture publishes")
	_check(session.display.texture != null, "player received a texture")
	if session.display.texture != null:
		var result: Image = session.display.texture.get_image()
		_check(_is_red(result.get_pixel(80, 90)), "revealed D0 red pixel visible")
		_check(_is_hidden(result.get_pixel(240, 90)), "unrevealed room hidden in output image")
		_check(session._capture.canvas.map.id == AtlasPlayerProjection.BOARD_ID \
			and session._capture.canvas.campaign.get_map("gm-private") == null,
			"renderer owns only detached player map")
		_check(not JSON.stringify(session._capture.canvas.campaign.to_dict()).contains("SECRET"),
			"renderer input excludes secret token/label text")
	await _frames(4)
	var screen: Image = session.window.get_texture().get_image()
	_check(screen != null and screen.get_width() > 0, "independent OS framebuffer accessible")
	if screen != null:
		_check(_is_red(screen.get_pixel(screen.get_width() / 4, screen.get_height() / 2)),
			"actual player OS framebuffer reveals only public room")
		_check(_is_hidden(screen.get_pixel(screen.get_width() * 3 / 4, screen.get_height() / 2)),
			"actual player OS framebuffer hides secret room")
		var image_path: String = "user://validation/player-privacy-t043.png"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
		_check(screen.save_png(image_path) == OK, "native privacy witness screenshot saved")
	var d1_grants: Array[String] = ["public-d1"]
	_check(await session.publish(source, floor.id, 1, d1_grants), "D1 produces separately sanitized output")
	if session.display.texture != null:
		var image: Image = session.display.texture.get_image()
		_check(_is_blue(image.get_pixel(80, 90)) and _is_hidden(image.get_pixel(240, 90)),
			"D1 cannot reveal its private alternative or bypass fog")
	var denied: Array[String] = ["public-d1", "gm-note"]
	_check(not await session.publish(source, floor.id, 1, denied),
		"fogged text/label grant denies entire frame")
	_check(session.display.texture == null, "denial blanks prior D1 image")
	denied = ["gm-token"]
	_check(not await session.publish(source, floor.id, 0, denied), "GM token grant is denied")
	session.set_follow(false)
	_check(await session.publish(source, floor.id, 0, grants), "freeze holds a valid authorized frame")
	frame.set_view(Vector2(300, 0), 64)
	_check(session.update_frame(frame) and session.camera_center == Vector2.ZERO,
		"frozen player camera remains independent of moving GM frame")
	_check(session.display.texture != null, "frozen authorized image remains visible")
	session.invalidate()
	_check(session.display.texture == null, "policy revocation blanks frozen image immediately")
	await _frames(4)
	screen = session.window.get_texture().get_image()
	_check(_is_hidden(screen.get_pixel(screen.get_width() / 4, screen.get_height() / 2)),
		"revocation removes secret-capable image from actual OS framebuffer")
	# Re-authorization requires a new explicit publish, never a cache fallback.
	session.set_follow(true)
	frame.set_view(Vector2.ZERO, 64)
	_check(session.update_frame(frame), "camera can be reauthorized explicitly")
	_check(await session.publish(source, floor.id, 0, grants), "fresh authorized pixels can republish")
	# Mutation runs after capture begins, before readback completes. Old D0 red
	# pixels must never reappear if the authorized raster has changed in place.
	var pixel_edit: Callable = func() -> void:
		public.chunks["0,0"].image.fill(Color.YELLOW)
	pixel_edit.call_deferred()
	_check(not await session.publish(source, floor.id, 0, grants),
		"mid-capture in-place pixel revision rejects stale publication")
	_check(session.display.texture == null, "pixel revision leaves player blank")
	var visibility_edit: Callable = func() -> void:
		public.visible = false
	visibility_edit.call_deferred()
	_check(not await session.publish(source, floor.id, 0, grants),
		"mid-capture layer visibility revocation rejects stale publication")
	_check(session.display.texture == null, "visibility revocation leaves player blank")
	public.visible = true
	public.chunks["0,0"].image.fill(Color.RED)
	var lod_edit: Callable = func() -> void:
		public.detail_level = 1
	lod_edit.call_deferred()
	_check(not await session.publish(source, floor.id, 0, grants),
		"mid-capture detail-level revision rejects stale publication")
	public.detail_level = 0
	var replaced_floor: AtlasFloor = AtlasFloor.new()
	replaced_floor.id = floor.id
	var floor_edit: Callable = func() -> void:
		source.floors[0] = replaced_floor
	floor_edit.call_deferred()
	_check(not await session.publish(source, floor.id, 0, grants),
		"floor replacement with reused ID rejects stale publication")
	_check(session.display.texture == null, "floor replacement keeps player blank")
	source.floors[0] = floor
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(-32, -32, 32, 64), false))
	_check(await session.publish(source, floor.id, 0, grants), "fresh fog policy can publish blanked artwork")
	if session.display.texture != null:
		_check(_is_hidden(session.display.texture.get_image().get_pixel(80, 90)),
			"a later fog hide removes formerly public room from player output")
	session.close_native()
	_check(session.window == null and session.display == null,
		"closing player session destroys its output surface")
	root.remove_child(session)
	session.free()
	print("ATLAS_PLAYER_PRIVACY_ACCEPTANCE_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
