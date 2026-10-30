extends SceneTree
## T-002: one shared document, grid mask, deterministic raster chunks, authored detail.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = "shared"
	var board: AtlasMapDocument = AtlasMapDocument.new("shared", "Continuous board")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 48.0)
	board.grid.distance_per_cell = 3.0
	board.grid.distance_unit = "mi"
	campaign.add_map(board)
	_check(campaign.maps.size() == 1, "one board owns every hex, including unassigned hexes")
	_test_crossing_ink(board)
	_test_chunk_seams(board)
	_test_pixel_seam_ownership()
	_test_mask_and_geometry(board)
	_test_detail_and_navigation(board, campaign)
	_test_round_trip(campaign)
	print("ATLAS_CONTINUOUS_CANVAS_%s checks=%d failures=%d" % [
		"PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(value: bool, description: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("FAIL: " + description)


func _test_crossing_ink(board: AtlasMapDocument) -> void:
	var ink: AtlasInkLayer = board.floors[0].ink_layer()
	var first: Vector2 = board.grid.cell_to_document(Vector2i(-1, 0))
	var last: Vector2 = board.grid.cell_to_document(Vector2i(2, 0))
	ink.strokes.append(AtlasStroke.new(PackedVector2Array([first, last]), Color.RED, 4.0))
	_check(ink.strokes.size() == 1 and ink.strokes[0].points.size() == 2,
		"cross-hex ink remains one authored stroke, never copied to hex documents")
	_check(board.grid.document_to_cell(first) == Vector2i(-1, 0)
		and board.grid.document_to_cell(last) == Vector2i(2, 0), "ink endpoints occupy adjacent world cells")


func _test_chunk_seams(board: AtlasMapDocument) -> void:
	var layer: AtlasRasterLayer = AtlasRasterLayer.new("seam", "Raster through hex and chunk seams")
	board.floors[0].layers.append(layer)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(-280.0, -120.0), Vector2(280.0, 150.0)])
	var result: AtlasFillResult = AtlasRasterBrush.paint(layer, points, Color.BLUE, 12.0, false)
	_check(result.ok, "raster brush sweeps one continuous gesture across signed chunk boundaries")
	if not result.ok:
		return
	var raster: AtlasRasterLayer = result.layer
	board.floors[0].layers[-1] = raster
	_check(raster.chunks.size() >= 4, "single stroke owns pixels in multiple chunks")
	for point: Vector2i in [Vector2i(-256, -108), Vector2i(-1, 14), Vector2i(0, 15), Vector2i(255, 138), Vector2i(256, 139)]:
		var pixel: Vector2i = point
		var coord: Vector2i = AtlasRasterLayer.pixel_to_chunk(pixel)
		var chunk: AtlasRasterChunk = raster.chunks.get("%d,%d" % [coord.x, coord.y])
		_check(chunk != null, "signed floor chunk owner for %s" % str(pixel))
		if chunk != null:
			_check(chunk.coord == coord and chunk.is_valid(true), "canonical owned raster chunk %s" % str(coord))
	for coord: Vector2i in [Vector2i(-257, -1), Vector2i(-256, -1), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(255, 3), Vector2i(256, 3)]:
		var owner: Vector2i = AtlasRasterLayer.pixel_to_chunk(coord)
		var local: Vector2i = coord - owner * AtlasRasterChunk.SIZE
		_check(local.x >= 0 and local.x < AtlasRasterChunk.SIZE
			and local.y >= 0 and local.y < AtlasRasterChunk.SIZE,
			"every signed pixel has exactly one canonical chunk and local offset")


func _test_pixel_seam_ownership() -> void:
	var raster: AtlasRasterLayer = AtlasRasterLayer.new("pixels", "Signed raster seam")
	var stroke: PackedVector2Array = PackedVector2Array([Vector2(-261, 4), Vector2(261, 4)])
	var result: AtlasFillResult = AtlasRasterBrush.paint(raster, stroke, Color.CYAN, 3.0, false)
	_check(result.ok, "horizontal raster stroke crossing x=-256,0,256 creates owned chunks")
	if not result.ok:
		return
	var painted: AtlasRasterLayer = result.layer
	_check(painted.chunks.size() == 4, "four signed chunks and no duplicated seam chunk")
	for x: int in [-257, -256, -1, 0, 255, 256]:
		var point: Vector2i = Vector2i(x, 4)
		var chunk: AtlasRasterChunk = AtlasFill._existing_chunk(painted, point)
		_check(chunk != null, "stroke covers raster seam pixel %d" % x)
		if chunk != null:
			_check(chunk.image.get_pixelv(AtlasFill._local_pixel(point)) == Color.CYAN,
				"actual raster seam pixel %d has full color" % x)
	var erased: AtlasFillResult = AtlasRasterBrush.paint(painted, stroke, Color.WHITE, 3.0, true)
	_check(erased.ok, "eraser crosses the exact same signed seams")
	if erased.ok:
		for x: int in [-256, -1, 0, 255, 256]:
			var point: Vector2i = Vector2i(x, 4)
			var chunk: AtlasRasterChunk = AtlasFill._existing_chunk(erased.layer, point)
			_check(chunk != null and chunk.image.get_pixelv(AtlasFill._local_pixel(point)).a == 0.0,
				"eraser clears signed seam pixel %d" % x)


func _test_mask_and_geometry(board: AtlasMapDocument) -> void:
	var grid: AtlasGrid = board.grid
	var a: Vector2 = grid.cell_to_document(Vector2i.ZERO)
	var b: Vector2 = grid.cell_to_document(Vector2i(1, 0))
	var unrestricted: AtlasEditScope = AtlasEditScope.new()
	var restricted: AtlasEditScope = AtlasEditScope.new(grid.cell_polygon(Vector2i.ZERO), true)
	var stroke: AtlasStroke = AtlasStroke.new(PackedVector2Array([a, b]), Color.WHITE, 2.0)
	var unrestricted_parts: Array[AtlasStroke] = unrestricted.clip_strokes([stroke])
	var restricted_parts: Array[AtlasStroke] = restricted.clip_strokes([stroke])
	_check(unrestricted_parts.size() == 1 and unrestricted_parts[0].points == stroke.points,
		"disabled mask never changes board coordinates")
	_check(not restricted_parts.is_empty(), "enabled hex mask accepts contained ink")
	for part: AtlasStroke in restricted_parts:
		_check(part.points[-1].distance_to(a) < b.distance_to(a),
			"mask clips ink at the hex border without splitting its document")
	_check(board.floors[0].ink_layer().strokes[0].points.size() == 2,
		"mask modifies edit eligibility, not previously authored crossing ink")
	var original: Vector2 = board.floors[0].ink_layer().strokes[0].points[0]
	grid.origin = Vector2(19.0, -7.0)
	grid.rotation = 0.22
	grid.cell_size = 60.0
	grid.distance_per_cell = 5.0
	grid.distance_unit = "km"
	_check(board.floors[0].ink_layer().strokes[0].points[0] == original,
		"overlay/grid/native measurement changes never rescale authored artwork")


func _test_detail_and_navigation(board: AtlasMapDocument, campaign: AtlasCampaign) -> void:
	var detail: AtlasInkLayer = AtlasInkLayer.new("detail", "Authored local detail")
	detail.detail_level = 1
	detail.strokes.append(AtlasStroke.new(PackedVector2Array([
		Vector2(12.0, 9.0), Vector2(45.0, 22.0)]), Color.YELLOW, 2.0))
	board.floors[0].layers.append(detail)
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 600)
	get_root().add_child(canvas)
	var navigation: AtlasMapNavigator = AtlasMapNavigator.new(canvas)
	navigation.reset(campaign)
	_check(navigation.show_map(board), "open continuous board")
	canvas.active_layer_id = "ink"
	_check(canvas.set_presented_detail_level(1) and canvas.active_layer_id == "ink",
		"switching presented detail never retargets the selected editing layer")
	_check(not canvas.editing_target_is_presented(), "hidden editing target is detected")
	var edits: AtlasEditHistory = AtlasEditHistory.new(campaign)
	edits.active_map_id = board.id
	var artwork: AtlasArtworkEditor = AtlasArtworkEditor.new(canvas, edits)
	var original_count: int = board.floors[0].ink_layer().strokes.size()
	artwork.stroke(AtlasStroke.new(PackedVector2Array([Vector2(1, 1)])), false)
	_check(board.floors[0].ink_layer().strokes.size() == original_count,
		"hidden target rejects new strokes rather than silently retargeting them")
	# Actual editor dispatch uses the same grid polygon mask on the same ink
	# layer; undo restores the original crossing gesture, not a cell copy.
	canvas.set_presented_detail_level(0)
	canvas.has_selected_cell = true
	canvas.selected_cell = Vector2i.ZERO
	artwork.locked_to_cell = true
	artwork.refresh_scope()
	var center: Vector2 = board.grid.cell_to_document(Vector2i.ZERO)
	var adjacent: Vector2 = board.grid.cell_to_document(Vector2i(1, 0))
	artwork.stroke(AtlasStroke.new(PackedVector2Array([center, adjacent]), Color.WHITE, 3.0), false)
	_check(board.floors[0].ink_layer().strokes.size() > original_count,
		"editor paints within selected-hex scope on the original ink layer")
	for index: int in range(original_count, board.floors[0].ink_layer().strokes.size()):
		var clipped: AtlasStroke = board.floors[0].ink_layer().strokes[index]
		_check(clipped.points[-1].distance_to(center) < center.distance_to(adjacent),
			"editor clips crossing ink to active cell, no coordinate rebase")
	_check(edits.undo() and board.floors[0].ink_layer().strokes.size() == original_count,
		"undo restores the shared original layer after cell-mask editing")
	artwork.locked_to_cell = false
	artwork.refresh_scope()
	artwork.select_layer("detail")
	_check(canvas.active_layer_id == "detail" and canvas.presented_detail_level == 1,
		"author explicitly selects a different authored detail layer")
	canvas._draft_stroke = AtlasStroke.new(PackedVector2Array([Vector2(12, 9)]))
	_check(not canvas.set_presented_detail_level(0) and canvas.presented_detail_level == 1,
		"presentation change is deferred while a gesture is active")
	canvas.cancel_edit()
	var old_zoom: float = canvas.camera_zoom
	navigation.wheel_step(1, canvas.size * 0.5)
	_check(canvas.camera_zoom > old_zoom and canvas.active_layer_id == "detail",
		"geometric zoom does not change authored editing target")
	var empty_cell: Vector2i = Vector2i(41, -38)
	canvas.camera_center = board.grid.cell_to_document(empty_cell)
	navigation.wheel_step(1, canvas.size * 0.5)
	_check(canvas.map == board and campaign.maps.size() == 1 and canvas.camera_zoom > old_zoom,
		"empty/unassigned hex can be zoomed into without document creation")
	canvas.queue_redraw()
	canvas.free()


func _test_round_trip(campaign: AtlasCampaign) -> void:
	var plain: Dictionary = campaign.to_dict()
	var loaded: AtlasCampaign = AtlasCampaign.from_dict(plain)
	_check(loaded != null, "canonical campaign handles separately authored detail groups")
	if loaded == null:
		return
	var floor: AtlasFloor = loaded.get_map("shared").floors[0]
	_check(floor.layer_by_id("ink").detail_level == 0 and floor.layer_by_id("detail").detail_level == 1,
		"legacy default and explicit detail levels survive dictionary validation")
	_check(floor.ink_layer().strokes.size() == 1 and floor.layer_by_id("detail") is AtlasInkLayer,
		"cross-hex stroke and local detail survive serialization independently")
	var absent: Dictionary = AtlasInkLayer.new().to_dict()
	absent.erase("detail_level")
	_check(AtlasLayerCodec.from_dict(absent).detail_level == 0,
		"legacy unlabelled layer defaults to shared overview group")
	for bad: Variant in [-1, 33, 0.5, INF, NAN, "1", true]:
		var invalid: Dictionary = AtlasInkLayer.new().to_dict()
		invalid.detail_level = bad
		_check(AtlasLayerCodec.from_dict(invalid) == null, "invalid detail level rejected: %s" % str(bad))
	var path: String = "user://t002_continuous_%d.scn" % Time.get_ticks_usec()
	var saved: Error = AtlasCampaignStore.save_campaign(campaign, path)
	_check(saved == OK, "native packed-scene save of shared detail board")
	if saved == OK:
		var restored: AtlasCampaign = AtlasCampaignStore.load_campaign(path)
		_check(restored != null, "native scene loads with detail groups and raster chunks")
		if restored != null:
			var same: AtlasFloor = restored.get_map("shared").floors[0]
			_check(same.layer_by_id("detail").detail_level == 1 and same.ink_layer().strokes.size() == 1,
				"native save preserves authored detail and crossing artwork")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
