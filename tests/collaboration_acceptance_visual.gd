extends SceneTree
## T-048: native framebuffer witness rendered ONLY from a JSON-round-tripped
## viewer snapshot. This is an isolated transport consumer, not production UI.

var checks: int = 0
var failures: int = 0
var viewport_window: Window
var picture: TextureRect


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("COLLABORATION ACCEPTANCE VISUAL FAILED: " + description)


func _raster(id: String, color: Color, detail: int = 0) -> AtlasRasterLayer:
	var pixels: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	layer.id = id
	layer.detail_level = detail
	return layer


func _frames(count: int = 5) -> void:
	for index: int in count:
		await process_frame


func _present_wire(snapshot: Dictionary) -> bool:
	# The viewer is given serialized DTO bytes, never a GM map or Token resource.
	picture.texture = null
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	if not parsed is Dictionary or not parsed.has("artwork"):
		return false
	var artwork: Dictionary = parsed["artwork"]
	if not artwork.has("floors"):
		return false
	var layers: Array = artwork["floors"][0]["layers"]
	if layers.size() != 1 or layers[0]["chunks"].size() != 1:
		return false
	var chunk: Dictionary = layers[0]["chunks"][0]
	var image: Image = Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(chunk["png_base64"])) != OK:
		return false
	picture.texture = ImageTexture.create_from_image(image)
	return true


func _screen_color(x: int, y: int) -> Color:
	var output: Image = viewport_window.get_texture().get_image()
	return output.get_pixel(x, y)


func _is_dark(color: Color) -> bool:
	return color.r < 0.3 and color.g < 0.3 and color.b < 0.3


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_embed_subwindows = false
	root.size = Vector2i(640, 400)
	viewport_window = Window.new()
	viewport_window.title = "T-048 isolated serialized viewer"
	viewport_window.size = Vector2i(320, 160)
	viewport_window.unresizable = true
	viewport_window.visible = true
	root.add_child(viewport_window)
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.07, 0.07, 0.07)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_window.add_child(background)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_window.add_child(picture)

	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.display_name = "PRIVATE_NATIVE_CAMPAIGN"
	var document: AtlasMapDocument = AtlasMapDocument.new("private", "PRIVATE_NATIVE_MAP")
	var floor: AtlasFloor = document.floors[0]
	floor.layers.clear()
	floor.layers.append(_raster("approved", Color.RED))
	floor.layers.append(_raster("private-green", Color.GREEN))
	floor.layers.append(_raster("approved-d1", Color.BLUE, 1))
	var tokens: AtlasTokenLayer = AtlasTokenLayer.new("gm-tokens", "PRIVATE_NATIVE_TOKENS")
	tokens.tokens.append(AtlasToken.new("dragon", Vector2.ONE, "PRIVATE_NATIVE_DRAGON"))
	floor.layers.append(tokens)
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 4, 8), true))
	campaign.add_map(document)
	var history: AtlasEditHistory = AtlasEditHistory.new(campaign)
	history.active_map_id = "private"
	var host: AtlasHostSession = AtlasHostSession.new(campaign, history, "visual_epoch",
		"private", floor.id, "gm-tokens")
	var viewer: AtlasSessionClient = host.join_as("viewer", "spectator", ["approved"])
	_check(viewer != null, "trusted host provides only an explicit raster grant")
	if viewer == null:
		quit(1)
		return
	var wire: String = JSON.stringify(host.snapshot_for(viewer))
	_check(not wire.contains("PRIVATE_NATIVE") and not wire.contains("gm-tokens")
		and not wire.contains("private-green"),
		"native viewer's actual serialized input excludes secret source labels")
	_check(_present_wire(host.snapshot_for(viewer)),
		"native surface receives decoded PNG solely from viewer wire payload")
	await _frames()
	var left: Color = _screen_color(80, 80)
	var right: Color = _screen_color(240, 80)
	_check(left.r > 0.8 and left.g < 0.25 and left.b < 0.25,
		"native framebuffer shows authorized revealed red pixels")
	_check(_is_dark(right), "native framebuffer hides unrevealed and secret green pixels")
	_check(host.set_viewer_grants("viewer", []), "host revokes publication")
	_check(not _present_wire(host.snapshot_for(viewer)) and picture.texture == null,
		"revoked serialized snapshot contains no renderable PNG")
	await _frames()
	_check(_is_dark(_screen_color(80, 80)) and _is_dark(_screen_color(240, 80)),
		"native framebuffer clears previously authorized pixels on revocation")
	_check(host.disconnect_peer(viewer) and not _present_wire(host.snapshot_for(viewer)),
		"offline client cannot recover previously rendered content")
	var resumed: AtlasSessionClient = host.reconnect(viewer)
	_check(resumed != null and resumed.artwork_record().is_empty(),
		"reconnecting an offline viewer retains the current blank policy")
	_check(host.set_viewer_grants("viewer", ["approved-d1"], 1),
		"trusted host can reauthorize only the D1 raster")
	_check(_present_wire(host.snapshot_for(resumed)),
		"new D1 viewer bytes can be rendered after explicit host authorization")
	await _frames()
	left = _screen_color(80, 80)
	right = _screen_color(240, 80)
	_check(left.b > 0.8 and left.r < 0.25 and left.g < 0.25,
		"native framebuffer shows newly authorized blue D1 instead of cached D0")
	_check(_is_dark(right), "fog still hides private D1 pixels")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(viewport_window.get_texture().get_image().save_png(
		"user://validation/collaboration-t048-visual.png") == OK,
		"native serialized-viewer evidence screenshot saved")
	host.close()
	_check(not _present_wire(host.snapshot_for(resumed)) and picture.texture == null,
		"closed session cannot retain player publication")
	await _frames()
	_check(_is_dark(_screen_color(80, 80)),
		"native display is blank after session termination")
	root.remove_child(viewport_window)
	viewport_window.free()
	print("ATLAS_COLLABORATION_ACCEPTANCE_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
