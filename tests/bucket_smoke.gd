extends SceneTree
## T-023: raster/terrain Bucket boundaries, tolerance, atomic previews and native persistence.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("BUCKET FAILED: " + label)


func _image(width: int, height: int, color: Color) -> Image:
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _pixel(layer: AtlasRasterLayer, point: Vector2i) -> Color:
	var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(point)
	var chunk: AtlasRasterChunk = layer.chunks.get("%d,%d" % [coord.x, coord.y])
	if chunk == null:
		return Color.TRANSPARENT
	return chunk.image.get_pixelv(point - coord * AtlasRasterChunk.SIZE)


func _raster_modes() -> void:
	var image: Image = _image(6, 1, Color(0, 0, 0, 0))
	image.set_pixel(0, 0, Color(1, 0.0, 0.0, 1))
	image.set_pixel(1, 0, Color(0.98, 0, 0, 1))
	image.set_pixel(2, 0, Color(0.7, 0, 0, 1))
	image.set_pixel(3, 0, Color(0, 0, 0, 0))
	image.set_pixel(4, 0, Color(1, 0, 0, 1))
	image.set_pixel(5, 0, Color(1, 0, 0, 0.4))
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(image)
	var original: PackedByteArray = raster.chunks["0,0"].image.get_data()
	var result: AtlasFillResult = AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE)
	_check(result.ok and _pixel(result.layer, Vector2i.ZERO) == Color.BLUE
		and _pixel(result.layer, Vector2i(1, 0)).r > 0.9, "0% contiguous is an exact 4-connected match")
	result = AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 100, 0.03)
	_check(result.ok and _pixel(result.layer, Vector2i(1, 0)) == Color.BLUE
		and _pixel(result.layer, Vector2i(2, 0)).r > 0.6,
		"tolerance compares against the seed without bleeding through dissimilar pixels")
	result = AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 100, 0.0, false)
	_check(result.ok and _pixel(result.layer, Vector2i(4, 0)) == Color.BLUE
		and _pixel(result.layer, Vector2i(2, 0)).r > 0.6,
		"global matches disconnected pixels in active raster only")
	_check(_pixel(result.layer, Vector2i(5, 0)).a < 0.41,
		"premultiplied alpha prevents dissimilar-alpha pixels from matching")
	_check(raster.chunks["0,0"].image.get_data() == original,
		"all flood algorithms preserve original source pixels")
	# Even when the seed already has the replacement color, a positive
	# tolerance can still make a meaningful change to adjacent pixels.
	result = AtlasFill.raster(raster, Vector2(0.5, 0.5), Color(1, 0, 0, 1), null, 100, 0.03)
	_check(result.ok and _pixel(result.layer, Vector2i(1, 0)).r > 0.99,
		"positive tolerance can recolor near matches when seed equals replacement")
	var alpha: Image = _image(3, 1, Color(1, 0, 0, 0))
	alpha.set_pixel(1, 0, Color(0, 1, 0, 0))
	alpha.set_pixel(2, 0, Color(0.7, 0, 1, 0.5))
	var transparent: AtlasRasterLayer = AtlasRasterLayer.from_image(alpha)
	result = AtlasFill.raster(transparent, Vector2(0.5, 0.5), Color(0.1, 0.2, 0.3, 0.6))
	_check(result.ok and absf(_pixel(result.layer, Vector2i(0, 0)).a - 0.6) < 0.005
		and absf(_pixel(result.layer, Vector2i(1, 0)).a - 0.6) < 0.005
		and _pixel(result.layer, Vector2i(2, 0)).a < 0.51,
		"alpha-zero pixels match regardless of hidden RGB, preserving neighboring alpha")
	_check(not AtlasFill.raster(transparent, Vector2(100.0, 0.5), Color.BLUE).ok,
		"unallocated transparent background rejects rather than generating infinite chunks")
	_check(not AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 1, 1.0).ok,
		"limit failures are atomic with tolerant flood")
	_check(not AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 1, 1.0, false).ok,
		"limit failures are atomic with global flood")
	_check(not AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 100, -0.1).ok
		and not AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, null, 100, 1.1).ok,
		"invalid tolerance rejected")
	var boundary: AtlasEditScope = AtlasEditScope.new(PackedVector2Array([
		Vector2.ZERO, Vector2(2, 0), Vector2(2, 1), Vector2(0, 1)]), true)
	result = AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE, boundary, 100, 1.0, false)
	_check(result.ok and _pixel(result.layer, Vector2i(0, 0)) == Color.BLUE
		and _pixel(result.layer, Vector2i(1, 0)) == Color.BLUE
		and _pixel(result.layer, Vector2i(4, 0)).r > 0.9,
		"edit mask bounds global fill by whole pixel quad")
	raster.locked = true
	_check(not AtlasFill.raster(raster, Vector2(0.5, 0.5), Color.BLUE).ok,
		"locked active layer rejects fill")


func _chunk_boundaries() -> void:
	var raster: AtlasRasterLayer = AtlasRasterLayer.new()
	for x: int in [-257, -256, -1, 0, 255, 256]:
		var pixel: Vector2i = Vector2i(x, 0)
		var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(pixel)
		var key: String = "%d,%d" % [coord.x, coord.y]
		if not raster.chunks.has(key):
			raster.chunks[key] = AtlasRasterChunk.new(coord, _image(256, 256, Color.TRANSPARENT))
		raster.chunks[key].image.set_pixelv(pixel - coord * 256, Color.RED)
	var result: AtlasFillResult = AtlasFill.raster(raster, Vector2(-0.5, 0.5), Color.BLUE)
	_check(result.ok and _pixel(result.layer, Vector2i(0, 0)) == Color.BLUE,
		"contiguous raster fill crosses negative/zero chunk seam")
	result = AtlasFill.raster(raster, Vector2(-0.5, 0.5), Color.BLUE, null, 10, 0.0, false)
	_check(result.ok and _pixel(result.layer, Vector2i(-257, 0)) == Color.BLUE
		and _pixel(result.layer, Vector2i(256, 0)) == Color.BLUE,
		"global raster fill crosses signed and partial chunk boundaries")


func _editor_preview() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	var editor: AtlasEditor = scene.get_node("Interface/UI/WorkspaceSplit/Workspace")
	editor.load_saved_on_startup = false
	root.add_child(scene)
	for frame: int in range(6):
		await process_frame
	_check(editor.create_board("Bucket preview", AtlasGrid.new(AtlasGrid.Kind.SQUARE, 8)),
		"isolated board created")
	var canvas: AtlasCanvas = editor.canvas
	var source: Image = _image(3, 2, Color(1, 0, 0, 0.6))
	var added: Array[AtlasLayer] = AtlasLayerCodec.clone_all(canvas.floor.layers)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(source)
	raster.id = "bucket-raster"
	added.append(raster)
	_check(editor.apply_layers(added, raster.id), "raster active layer chosen")
	editor.select_layer(raster.id)
	editor._choose_tool(AtlasCanvas.Tool.FILL)
	_check(editor.inspector._bucket_section.visible and editor.inspector.fill_tolerance_spinner.visible
		and not editor.inspector.brush_width_spinner.visible,
		"Bucket inspector exposes raster tolerance and mode, not stroke width")
	editor.inspector.fill_tolerance_spinner.value = 3.0
	editor.inspector.fill_global_checkbox.button_pressed = true
	_check(absf(canvas.fill_tolerance - 0.03) < 0.001 and canvas.fill_global,
		"UI settings flow to canvas controls")
	var original_bytes: PackedByteArray = (canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer).chunks["0,0"].image.get_data()
	var previous: AtlasEditCommand = editor.edits.get_undo_command()
	editor.artwork.preview_fill(Vector2(0.5, 0.5))
	_check(editor.artwork._pending_fill != null and editor.artwork._pending_fill.ok
		and canvas._preview_layer != null, "press builds visible detached preview")
	_check((canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer).chunks["0,0"].image.get_data() == original_bytes
		and editor.edits.get_undo_command() == previous,
		"preview leaves source and history untouched")
	editor.artwork.cancel_preview_fill()
	_check(canvas._preview_layer == null and editor.artwork._pending_fill == null
		and editor.edits.get_undo_command() == previous, "cancellation discards pending fill")
	editor.artwork.preview_fill(Vector2(0.5, 0.5))
	editor.artwork.commit_preview_fill()
	_check(editor.artwork._pending_fill == null
		and _pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(0, 0)) == canvas.brush_color,
		"release commits complete fill to active raster")
	editor._on_undo()
	_check((canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer).chunks["0,0"].image.get_data() == original_bytes,
		"one undo restores original RGBA pixels")
	editor._on_redo()
	_check(_pixel(canvas.floor.layer_by_id(raster.id) as AtlasRasterLayer, Vector2i(1, 0)) == canvas.brush_color,
		"redo restores complete bucket fill")
	var slot: String = "user://validation/t023-bucket.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://validation"))
	_check(AtlasCampaignStore.save_campaign(editor.campaign, slot) == OK,
		"native save persists committed fill")
	var loaded: AtlasStoreResult = AtlasCampaignStore.load_result(slot)
	var map: AtlasMapDocument = loaded.campaign.get_map(canvas.map.id) if loaded.campaign != null else null
	var floor: AtlasFloor = map.floor_by_id(canvas.floor.id) if map != null else null
	var saved: AtlasRasterLayer = floor.layer_by_id(raster.id) as AtlasRasterLayer if floor != null else null
	_check(saved != null and _pixel(saved, Vector2i(0, 0)) == canvas.brush_color,
		"native save roundtrips filled RGBA bytes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	# Terrain always uses palette adjacency, independently of raster tolerance.
	editor.select_layer(canvas.floor.terrain_layer().id)
	# Keep F selected: the inspector must update when the selected layer changes.
	_check(canvas.tool == AtlasCanvas.Tool.FILL
		and editor.inspector._bucket_section.visible and not editor.inspector.fill_global_checkbox.visible
		and editor.inspector._terrain_section.visible,
		"switching layers while Bucket stays active refreshes terrain-only controls")
	var terrain: AtlasTerrainLayer = canvas.floor.layer_by_id(canvas.active_layer_id) as AtlasTerrainLayer
	var terrain_before: Dictionary = terrain.terrain.duplicate(true)
	var grid: AtlasGrid = terrain.grid if terrain.grid != null else canvas.map.grid
	var point: Vector2 = grid.cell_to_document(Vector2i.ZERO)
	editor.artwork.preview_fill(point)
	_check(editor.artwork._pending_fill != null and not editor.artwork._pending_fill.ok
		and terrain.terrain == terrain_before,
		"unbounded terrain background rejects without mutation")
	editor.artwork.cancel_preview_fill()
	# A finite cell edit scope makes the same empty-area fill safe.
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i.ZERO
	editor._on_scope_toggled(true)
	editor.palette_id = 3
	editor.artwork.preview_fill(point)
	_check(editor.artwork._pending_fill != null and editor.artwork._pending_fill.ok
		and canvas._preview_layer is AtlasTerrainLayer and terrain.terrain == terrain_before,
		"bounded terrain fill produces detached preview")
	editor.artwork.commit_preview_fill()
	_check((canvas.floor.layer_by_id(terrain.id) as AtlasTerrainLayer).terrain.get("0,0") == 3,
		"bounded terrain fill commits one cell with correct palette")
	editor._on_undo()
	_check((canvas.floor.layer_by_id(terrain.id) as AtlasTerrainLayer).terrain == terrain_before,
		"terrain preview commit is atomically undoable")
	root.remove_child(scene)
	scene.free()


func _run() -> void:
	_raster_modes()
	_chunk_boundaries()
	await _editor_preview()
	print("ATLAS_BUCKET_%s (%d checks)" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)
