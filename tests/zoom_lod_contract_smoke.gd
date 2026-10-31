extends SceneTree
## T-004 reproducible scale audit and bidirectional camera/detail contract.
## This is a design witness, not the automatic-LOD implementation (T-005).

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_sample_scale()
	_test_shared_camera_and_detail()
	print("ATLAS_ZOOM_LOD_CONTRACT_%s checks=%d failures=%d" % [
		"PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _test_sample_scale() -> void:
	var preset: AtlasExampleCampaign = load("res://examples/northern_marches.tres") as AtlasExampleCampaign
	_check(preset != null, "load the bundled Northern Marches / Greyhaven sample")
	if preset == null:
		return
	var world: AtlasMapDocument = preset.world.create_document()
	var city: AtlasMapDocument = preset.city.create_document()
	# The sample grid is spatial metadata, not a painted 13-by-9 tilemap.
	var city_empty_bounds: Rect2 = AtlasPreviewPanel.artwork_bounds(city, city.floors[0])
	var swatch: Image = Image.create(624, 432, false, Image.FORMAT_RGBA8)
	swatch.fill(Color.GREEN)
	var layer: AtlasRasterLayer = AtlasRasterLayer.from_image(swatch)
	layer.id = "scale-witness"
	layer.transform.origin = Vector2(-288, -192)
	city.floors[0].layers.append(layer)
	var city_bounds: Rect2 = AtlasPreviewPanel.artwork_bounds(city, city.floors[0])
	_check(is_equal_approx(world.grid.cell_size, 45.0) and is_equal_approx(city.grid.cell_size, 48.0),
		"sample retains distinct 45-unit world radius and 48-unit city cell size")
	_check(not city_empty_bounds.has_area(), "blank sample content has no implied painted terrain")
	_check(city_bounds.position.is_equal_approx(Vector2(-288, -192))
		and city_bounds.size.is_equal_approx(Vector2(624, 432)),
		"explicit raster artwork covers 624 by 432 independent board units")
	_check(is_equal_approx(city_bounds.size.x / (2.0 * world.grid.cell_size), 624.0 / 90.0),
		"unrelated document camera scales create the approximately 6.93x width mismatch")


func _test_shared_camera_and_detail() -> void:
	var board: AtlasMapDocument = AtlasMapDocument.new("world", "Continuous world")
	board.grid = AtlasGrid.new(AtlasGrid.Kind.HEX_POINTY, 45.0)
	board.grid.origin = Vector2(17, -31)
	board.grid.rotation = deg_to_rad(37.0)
	var center: Vector2 = board.grid.cell_to_document(Vector2i(2, -1))
	var overview: AtlasInkLayer = board.floors[0].ink_layer()
	var local: AtlasInkLayer = AtlasInkLayer.new("local", "Local detail")
	local.detail_level = 1
	board.floors[0].layers.append(local)
	var endpoints: PackedVector2Array = PackedVector2Array([center - Vector2(15, 5), center + Vector2(15, 5)])
	overview.strokes.append(AtlasStroke.new(endpoints, Color.RED, 2.0))
	local.strokes.append(AtlasStroke.new(endpoints, Color.GREEN, 2.0))
	var campaign: AtlasCampaign = AtlasCampaign.new()
	campaign.root_map_id = board.id
	campaign.add_map(board)
	var canvas: AtlasCanvas = AtlasCanvas.new()
	canvas.size = Vector2(800, 600)
	root.add_child(canvas)
	var navigation: AtlasMapNavigator = AtlasMapNavigator.new(canvas)
	navigation.reset(campaign)
	_check(navigation.show_map(board, center), "show shared world board")
	canvas.active_layer_id = overview.id
	var local_pointer: Vector2 = Vector2(310, 260)
	var anchor_before: Vector2 = canvas.local_to_document(local_pointer)

	# Each normal wheel detent preserves the point under the pointer in both directions.
	for index: int in range(6):
		navigation.wheel_step(1, local_pointer)
		_check(canvas.local_to_document(local_pointer).distance_to(anchor_before) < 0.001,
			"zoom-in wheel step %d retains pointer anchor" % index)
	_check(canvas.camera_zoom > 2.98 and canvas.camera_zoom < 3.0,
		"six ordinary wheel steps grow the camera continuously without a jump")
	_check(canvas.map == board and canvas.active_layer_id == overview.id
		and canvas.presented_detail_level == 0, "ordinary geometric zoom never changes maps or editing target")
	for index: int in range(6):
		navigation.wheel_step(-1, local_pointer)
		_check(canvas.local_to_document(local_pointer).distance_to(anchor_before) < 0.001,
			"zoom-out wheel step %d retains pointer anchor" % index)
	_check(absf(canvas.camera_zoom - 1.0) < 0.001,
		"six zoom-out steps reverse six zoom-in steps with no map traversal")

	# A rotated, translated hex has a finite document-space rectangle, independent
	# of which detail group is presented and how far the camera has zoomed.
	var polygon: PackedVector2Array = board.grid.cell_polygon(Vector2i(2, -1))
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	var coverage_at_three: float = maxf(bounds.size.x * 3.0 / canvas.size.x,
		bounds.size.y * 3.0 / canvas.size.y)
	_check(coverage_at_three < 0.6, "historical 3x camera framing left the hex below 60% viewport coverage")
	var fitted_zoom: float = minf(0.8 * canvas.size.x / bounds.size.x,
		0.8 * canvas.size.y / bounds.size.y)
	_check(fitted_zoom > 3.0 and fitted_zoom < AtlasMapNavigator.MAX_ZOOM,
		"expanded navigator range admits the 80% fit beyond the historical 3x cap")
	canvas.camera_center = center
	canvas.camera_zoom = fitted_zoom # Shared-coordinate design witness at the now-reachable local scale.
	_check(canvas.document_to_local(center).distance_to(canvas.size * 0.5) < 0.001,
		"fit target remains at the exact board position despite rotated grid")
	_check(canvas.set_presented_detail_level(1) and not canvas.editing_target_is_presented(),
		"local D1 presentation preserves hidden overview editing target")
	_check(canvas.document_to_local(center).distance_to(canvas.size * 0.5) < 0.001
		and overview.strokes[0].points == local.strokes[0].points,
		"separately authored local detail shares camera and world coordinates")
	canvas.camera_zoom = 1.0
	_check(canvas.set_presented_detail_level(0) and canvas.active_layer_id == overview.id,
		"return to overview restores D0 presentation without changing edited layer")
	_check(canvas.document_to_local(center).distance_to(canvas.size * 0.5) < 0.001,
		"zoom-out through the same board point stays registered")
	_check(canvas.map == board and campaign.maps.size() == 1 and board.floors[0].layers.size() == 3,
		"bidirectional overview/local inspection creates no extra document or artwork")
	canvas.free()
