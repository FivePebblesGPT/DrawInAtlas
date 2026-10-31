extends SceneTree
## T-003: previews inherit board geometry, selected authored LOD and actual bounds.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ALIGNED DETAIL PREVIEW FAILED: " + message)


func _run() -> void:
	var board: AtlasMapDocument = AtlasMapDocument.new("board", "Shared hex canvas")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	board.grid.origin = Vector2(-35, 19)
	board.grid.rotation = deg_to_rad(37.0)
	var overview: AtlasInkLayer = board.floors[0].ink_layer()
	var neighbor_a: Vector2 = board.grid.cell_to_document(Vector2i(0, 0))
	var neighbor_b: Vector2 = board.grid.cell_to_document(Vector2i(1, 0))
	overview.strokes.append(AtlasStroke.new(PackedVector2Array([neighbor_a, neighbor_b]), Color.RED, 8.0))
	var detail: AtlasInkLayer = AtlasInkLayer.new("detail", "Zoomed artwork")
	detail.detail_level = 1
	detail.strokes.append(AtlasStroke.new(PackedVector2Array([Vector2(-258, 0), Vector2(260, 0)]), Color.BLUE, 5.0))
	board.floors[0].layers.append(detail)
	var d0: Rect2 = AtlasPreviewPanel.artwork_bounds(board, board.floors[0], 0)
	var d1: Rect2 = AtlasPreviewPanel.artwork_bounds(board, board.floors[0], 1)
	_check(d0.has_area() and d0.has_point((neighbor_a + neighbor_b) * 0.5), "D0 spans adjacent rotated hexes")
	_check(d1.has_area() and d1.position.x < -256 and d1.end.x > 256, "D1 bounds cross both signed chunk seams")
	_check(d0.size.x < d1.size.x, "framing excludes artwork in unpresented detail levels")
	_check(not AtlasPreviewPanel.artwork_bounds(board, board.floors[0], 2).has_area(), "empty authored detail has no bogus preview footprint")
	var sparse_pixels: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	sparse_pixels.fill(Color.TRANSPARENT)
	sparse_pixels.fill_rect(Rect2i(242, 240, 8, 8), Color.CYAN)
	var sparse: AtlasRasterLayer = AtlasRasterLayer.from_image(sparse_pixels)
	sparse.detail_level = 2
	sparse.transform.origin = Vector2(-257, -256)
	board.floors[0].layers.append(sparse)
	var sparse_bounds: Rect2 = AtlasPreviewPanel.artwork_bounds(board, board.floors[0], 2)
	_check(sparse_bounds.position.distance_to(Vector2(-15, -16)) < 0.001
		and sparse_bounds.size.distance_to(Vector2(8, 8)) < 0.001,
		"preview fit includes only used raster pixels, not the sparse transparent chunk rectangle")
	_check(AtlasPreviewPanel.artwork_bounds(board, board.floors[0], 3) == Rect2(),
		"unpopulated detail level has an empty footprint after sparse raster content")
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 600)
	root.add_child(canvas)
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = board.id
	campaign.add_map(board)
	_check(canvas.set_document(board, campaign), "open exactly one continuous board")
	canvas.active_layer_id = overview.id
	canvas.camera_center = Vector2(20, -10)
	canvas.camera_zoom = 1.8
	var location: Vector2 = Vector2(18, 31)
	var original_screen: Vector2 = canvas.document_to_local(location)
	_check(canvas.local_to_document(original_screen).distance_to(location) < 0.0001, "document transform round-trip")
	_check(canvas.set_presented_detail_level(1) and canvas.active_layer_id == overview.id,
		"preview/detail presentation doesn't retarget editing layer")
	_check(canvas.document_to_local(location) == original_screen, "D0 to D1 preserves actual board registration")
	canvas.camera_center += Vector2(75, -44)
	canvas.camera_zoom *= 1.4
	_check(canvas.local_to_document(canvas.document_to_local(location)).distance_to(location) < 0.0001,
		"registration survives panning and zooming")
	board.grid.rotation += 0.3
	board.grid.cell_size *= 1.2
	_check(canvas.local_to_document(canvas.document_to_local(location)).distance_to(location) < 0.0001,
		"grid rotation and scale do not move preview geometry")
	var placement: AtlasPlacement = AtlasPlacement.new()
	placement.origin = Vector2(70, 25)
	placement.columns = 4
	placement.rows = 3
	placement.rotation = deg_to_rad(37.0)
	placement.parent_units_per_cell = 32.0
	placement.child_units_per_cell = 64.0
	var corners: PackedVector2Array = placement.corners()
	var points: PackedVector2Array = AtlasMapReferences._rect_points(placement.child_bounds())
	var uv: PackedVector2Array = AtlasMapReferences._uvs(points, placement.child_bounds())
	for i: int in range(4):
		_check((placement.child_to_parent() * points[i]).distance_to(corners[i]) < 0.0001,
			"rotated placement maps child artwork corner %d to board" % i)
		_check(uv[i].x >= 0.0 and uv[i].x <= 1.0 and uv[i].y >= 0.0 and uv[i].y <= 1.0,
			"texture UV stays bounded at placement corner %d" % i)
	canvas.free()
	print("ATLAS_ALIGNED_DETAIL_PREVIEWS_PASSED checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
