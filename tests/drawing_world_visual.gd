extends SceneTree
## T-061 native framebuffer witness: deliberately blank D1 does not inherit D0
## artwork; grid and entrance graphics/hit-testing remain independently active.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("T061_VISUAL_FAILED: " + description)


func _frames(count: int = 4) -> void:
	for i: int in range(count):
		await process_frame


func _image_hash() -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(root.get_texture().get_image().get_data())
	return context.finish().hex_encode()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "requires native framebuffer")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(900, 720)
	root.content_scale_size = root.size
	var campaign: AtlasCampaign = AtlasCampaign.sample()
	var board: AtlasMapDocument = campaign.get_map("world")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 550)
	canvas.position = Vector2(12, 12)
	root.add_child(canvas)
	_check(canvas.set_document(board, campaign), "native Atlas map loaded")
	canvas.camera_center = board.grid.cell_to_document(Vector2i.ZERO)
	canvas.camera_zoom = 1.5
	canvas.show_reference = false
	canvas.preview = AtlasCanvas.Preview.OFF
	canvas.render_grid = false
	var origin: Vector2 = canvas.camera_center
	var d0_ink: AtlasObjectsLayer = canvas.floor.objects_layer()
	d0_ink.strokes.append(AtlasStroke.new(PackedVector2Array([origin - Vector2(12, 0),
		origin + Vector2(12, 0)]), Color(1, 0, 0, 1), 15.0))
	canvas.queue_redraw()
	await _frames(8)
	var overview_hash: String = _image_hash()
	_check(canvas.set_presented_detail_level(1), "switch to blank D1 without changing map")
	await _frames(8)
	var detail_hash: String = _image_hash()
	_check(overview_hash != detail_hash, "D0 stroke disappears instead of becoming D1 underlay")
	_check(canvas.map == board and canvas.floor.id == "ground", "same map/floor after detail switch")
	_check(board.grid != null, "grid independent of artwork")
	canvas.render_grid = true
	canvas.queue_redraw()
	await _frames(8)
	var with_grid: String = _image_hash()
	_check(with_grid != detail_hash, "D1 blank view still draws the map grid")
	canvas.render_grid = false
	canvas.queue_redraw()
	await _frames(8)
	_check(_image_hash() == detail_hash, "grid removal does not reveal D0 artwork")
	_check(not campaign.outgoing_links("world", "ground").is_empty(),
		"map entrances remain registered in blank D1")
	var entrance: AtlasMapLink = campaign.outgoing_links("world", "ground")[0]
	_check(entrance != null and campaign.link_by_id(entrance.id) == entrance,
		"navigation retains same stable entrance ID")
	# Test logical navigation directly: D-level only changes the artwork view.
	var matches: Array[AtlasMapLink] = campaign.find_links_at("world", entrance.anchor, "ground")
	_check(matches.has(entrance), "entrance hit-test functions with D1 blank")
	var layer_panel: AtlasLayerPanel = load("res://prefab/layer_panel.tscn").instantiate() as AtlasLayerPanel
	layer_panel.position = Vector2(12, 570)
	layer_panel.size = Vector2(850, 140)
	root.add_child(layer_panel)
	layer_panel.set_floor(canvas.floor, canvas.active_layer_id, 1, false)
	_check(layer_panel.detail_status.text.contains("D1 · empty"),
		"visible UI distinguishes uncreated high detail from lost artwork")
	_check(layer_panel.show_editing_detail.visible, "explicit back-to-editing-detail navigation remains available")
	canvas.render_grid = true
	canvas.queue_redraw()
	await _frames(8)
	var shot: Image = root.get_texture().get_image()
	var output: String = OS.get_cache_dir().path_join("drawinatlas-t061-blank-detail.png")
	_check(shot.save_png(output) == OK, "native blank-detail/overlay screenshot captured")
	print("T061_VISUAL_SCREENSHOT ", output)
	root.remove_child(layer_panel)
	layer_panel.free()
	root.remove_child(canvas)
	canvas.free()
	print("T061_NATIVE_WORLD_VISUAL_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
