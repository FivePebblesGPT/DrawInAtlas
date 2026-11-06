extends SceneTree
## T-043 acceptance matrix for the isolated, explicitly granted player boundary.
## It deliberately does NOT treat a cache audience name as authorization.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_multifloor_detail_fog_and_metadata()
	_test_secret_objects_and_cache()
	print("ATLAS_PLAYER_PRIVACY_ACCEPTANCE_%s checks=%d failures=%d" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("PLAYER PRIVACY FAILED: " + label)


func _raster(id: String, color: Color, detail: int = 0) -> AtlasRasterLayer:
	var pixels: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	pixels.fill(color)
	var raster: AtlasRasterLayer = AtlasRasterLayer.from_image(pixels)
	raster.id = id
	raster.display_name = "GM named " + id
	raster.detail_level = detail
	return raster


func _source() -> AtlasMapDocument:
	var map: AtlasMapDocument = AtlasMapDocument.new("gm-secret-map", "GM ONLY: dragon lair")
	map.tags.append("UNPUBLISHED-PASSAGE")
	map.grid.distance_unit = "GM SECRET UNIT"
	var floor: AtlasFloor = map.floors[0]
	floor.display_name = "SECRET BASEMENT"
	floor.layers.clear()
	floor.layers.append(_raster("public-d0", Color.RED))
	floor.layers.append(_raster("secret-d0", Color.GREEN))
	floor.layers.append(_raster("public-d1", Color.BLUE, 1))
	floor.layers.append(_raster("secret-d1", Color.GREEN, 1))
	var notes: AtlasObjectsLayer = AtlasObjectsLayer.new("gm-labels", "GM private labels")
	var secret: AtlasStroke = AtlasStroke.new(PackedVector2Array([Vector2(12, 12)]),
		Color.WHITE, 14.0)
	secret.text = "SECRET PASSWORD"
	notes.strokes.append(secret)
	floor.layers.append(notes)
	var tokens: AtlasTokenLayer = AtlasTokenLayer.new("private-tokens", "GM private tokens")
	tokens.tokens.append(AtlasToken.new("dragon", Vector2(8, 8), "HIDDEN DRAGON"))
	floor.layers.append(tokens)
	var another: AtlasFloor = AtlasFloor.new()
	another.id = "upper-secret-floor"
	another.display_name = "SECRET ROOF"
	another.layers.clear()
	another.layers.append(_raster("upper-secret", Color.YELLOW))
	map.floors.append(another)
	return map


func _test_multifloor_detail_fog_and_metadata() -> void:
	var source: AtlasMapDocument = _source()
	var floor: AtlasFloor = source.floors[0]
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 32, 64), true))
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(16, 0, 16, 64), false))
	var gm_before: Dictionary = source.to_dict().duplicate(true)
	for detail: int in [0, 1]:
		var public_id: String = "public-d%d" % detail
		var grants: Array[String] = [public_id]
		var campaign: AtlasCampaign = AtlasPlayerProjection.build_capture_input(
			source, floor.id, detail, grants)
		_check(campaign != null, "D%d authorized sanitized capture exists" % detail)
		if campaign == null:
			continue
		var board: AtlasMapDocument = campaign.get_map(campaign.root_map_id)
		_check(campaign.maps.size() == 1 and campaign.links.is_empty() \
			and campaign.placements.is_empty() and board.floors.size() == 1,
			"D%d has no private document graph or other floors" % detail)
		_check(board.id != source.id and board.tags.is_empty() \
			and board.display_name != source.display_name \
			and board.floors[0].display_name != floor.display_name \
			and board.grid.distance_unit == "unit" and not board.grid.visible,
			"D%d scrubs GM map/floor/grid metadata" % detail)
		_check(board.floors[0].layers.size() == 1 \
			and board.floors[0].layers[0] is AtlasRasterLayer,
			"D%d admits only one explicitly granted raster layer" % detail)
		var raster: AtlasRasterLayer = board.floors[0].layers[0] as AtlasRasterLayer
		if raster == null:
			continue
		var chunk: AtlasRasterChunk = raster.chunks.get("0,0") as AtlasRasterChunk
		_check(chunk != null, "D%d has a sanitized raster chunk" % detail)
		if chunk == null:
			continue
		var allowed: Color = Color.RED if detail == 0 else Color.BLUE
		_check(chunk.image.get_pixel(4, 32).is_equal_approx(allowed),
			"D%d keeps only the revealed paint" % detail)
		_check(chunk.image.get_pixel(24, 32).a == 0.0 \
			and chunk.image.get_pixel(48, 32).a == 0.0,
			"D%d removes re-hidden and never-revealed pixel data" % detail)
		_check(chunk.image != floor.layer_by_id(public_id).chunks["0,0"].image,
			"D%d capture cannot alias editable source pixels" % detail)
		var serialized: String = JSON.stringify(campaign.to_dict())
		_check(not serialized.contains("SECRET") and not serialized.contains("HIDDEN DRAGON") \
			and not serialized.contains("gm-secret-map") and not serialized.contains("secret-d"),
			"D%d detached capture has no private metadata or labels" % detail)
		var source_hash: String = (floor.layer_by_id(public_id) as AtlasRasterLayer).chunks["0,0"].asset_id
		_check(not serialized.contains(source_hash),
			"D%d hidden original raster asset address is not exported" % detail)
		chunk.image.fill(Color.BLACK)
		_check(floor.layer_by_id(public_id).chunks["0,0"].image.get_pixel(4, 32).a == 1.0,
			"D%d mutating the capture cannot alter GM art" % detail)
	_check(source.to_dict() == gm_before, "building and editing captures leaves source document unchanged")
	var bad_detail: Array[String] = ["public-d1"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, bad_detail) == null,
		"cannot grant another authored detail level under D0")
	var invalid_floor: Array[String] = ["upper-secret"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, invalid_floor) == null,
		"cannot grant layer on another floor using its ID")
	var no_grants: Array[String] = []
	var blank: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source, floor.id, 0, no_grants)
	_check(blank != null and blank.get_map(blank.root_map_id).floors[0].layers.is_empty(),
		"no grants means blank artwork, not editor fallback")
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 16, 64), false))
	var view: AtlasMapDocument = AtlasPlayerProjection.build_artwork_view(source,
		floor.id, 0, ["public-d0"])
	_check(view != null and (view.floors[0].layers[0] as AtlasRasterLayer).chunks.is_empty(),
		"subsequent fog hide revokes the final visible room")


func _test_secret_objects_and_cache() -> void:
	var source: AtlasMapDocument = _source()
	var floor: AtlasFloor = source.floors[0]
	floor.fog_enabled = true
	floor.fog_regions.append(AtlasFogRegion.new(Rect2(0, 0, 32, 64), true))
	var token_grant: Array[String] = ["private-tokens"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, token_grant) == null,
		"explicit GM-token grant always fails closed")
	var label_grant: Array[String] = ["gm-labels"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, label_grant) == null,
		"fogged semantic labels cannot bypass pixel clipping")
	var mixed: Array[String] = ["public-d0", "gm-labels"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, mixed) == null,
		"mixed public+forbidden grant denies the entire capture")
	var stale: Array[String] = ["public-d0", "deleted-id"]
	_check(AtlasPlayerProjection.build_capture_input(source, floor.id, 0, stale) == null,
		"stale grants cannot partially succeed")
	var cache: AtlasPreviewCache = AtlasPreviewCache.new()
	var poisoned: Image = Image.create(192, 128, false, Image.FORMAT_RGBA8)
	poisoned.fill(Color.GREEN)
	cache.put_image(source, floor.id, Vector2i(192, 128), poisoned, "player")
	var cached: Image = cache.get_image(source, floor.id, Vector2i(192, 128), "player")
	_check(cached != null and cached.get_pixel(0, 0).g > 0.9,
		"preview cache audience string is explicitly NOT an authorization filter")
	var public_grant: Array[String] = ["public-d0"]
	var projected: AtlasCampaign = AtlasPlayerProjection.build_capture_input(source,
		floor.id, 0, public_grant)
	var raster: AtlasRasterLayer = projected.get_map(projected.root_map_id).floors[0].layers[0] as AtlasRasterLayer
	_check(raster.chunks["0,0"].image.get_pixel(4, 32).r > 0.9 \
		and raster.chunks["0,0"].image.get_pixel(4, 32).g < 0.1,
		"poisoned player-audience preview cannot enter sanitized output")
	cache.invalidate(source.id)
	_check(cache.get_image(source, floor.id, Vector2i(192, 128), "player") == null \
		and raster.chunks["0,0"].image.get_pixel(4, 32).r > 0.9,
		"editor preview invalidation is independent of detached player input")
